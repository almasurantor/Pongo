-- Pongo V3 Phase 1: challenge-only ranked matches with first-report
-- finalization, concurrency-safe active limits, cancellation, and expiration.
BEGIN;

UPDATE public.ranking_config
SET k_factor = 32,
    daily_ranked_pair_limit = 20,
    challenge_expiry_hours = 24,
    result_expiry_hours = 24,
    updated_at = NOW()
WHERE id;

-- The product decision for this rollout is to close every unfinished V2 match
-- without applying a result. Confirmed history and all audit rows are retained.
UPDATE public.matches
SET status = 'expired',
    finalized_at = COALESCE(finalized_at, NOW())
WHERE status NOT IN ('confirmed', 'expired', 'voided');

UPDATE public.disputes
SET status = 'voided',
    resolution = 'voided',
    admin_notes = COALESCE(admin_notes, 'Closed by the Phase 1 lifecycle migration.'),
    resolved_at = COALESCE(resolved_at, NOW())
WHERE status IN ('proposed', 'admin_review');

ALTER TABLE public.matches DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE public.matches ADD CONSTRAINT matches_status_check CHECK (status IN (
  -- result_reported exists only inside the score-submission transaction so the
  -- existing audited finalizer can validate and finalize the stored result.
  'ready', 'result_reported', 'confirmed', 'expired', 'canceled', 'voided'
));

CREATE TABLE public.match_cancellation_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  match_id UUID NOT NULL REFERENCES public.matches(id) ON DELETE RESTRICT,
  requested_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  responded_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'declined', 'expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  responded_at TIMESTAMPTZ,
  CONSTRAINT cancellation_response_consistent CHECK (
    (status = 'pending' AND responded_by IS NULL AND responded_at IS NULL)
    OR (status <> 'pending' AND responded_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX one_pending_cancellation_per_match
  ON public.match_cancellation_requests(match_id) WHERE status = 'pending';
CREATE INDEX match_cancellation_requests_match_created
  ON public.match_cancellation_requests(match_id, created_at DESC);

-- A database invariant backs the RPC checks for one unfinished ranked match
-- per unordered player pair.
CREATE UNIQUE INDEX one_ready_ranked_match_per_pair
  ON public.matches (
    LEAST(player_one_id, player_two_id),
    GREATEST(player_one_id, player_two_id)
  )
  WHERE ranked AND status = 'ready';

ALTER TABLE public.match_cancellation_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Participants and admins read cancellation requests"
  ON public.match_cancellation_requests FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id = match_id
        AND auth.uid() IN (m.player_one_id, m.player_two_id)
    )
  );
REVOKE INSERT, UPDATE, DELETE ON public.match_cancellation_requests FROM authenticated;
GRANT SELECT ON public.match_cancellation_requests TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_challenge_v2(p_challenge UUID)
RETURNS public.challenges
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c public.challenges;
BEGIN
  SELECT * INTO c FROM public.challenges WHERE id = p_challenge FOR UPDATE;
  IF NOT FOUND OR c.challenger_id <> auth.uid() OR c.status <> 'pending' THEN
    RAISE EXCEPTION 'Challenge cannot be canceled';
  END IF;
  IF c.expires_at <= NOW() THEN
    UPDATE public.challenges SET status = 'expired' WHERE id = c.id RETURNING * INTO c;
    RETURN c;
  END IF;
  UPDATE public.challenges SET status = 'declined' WHERE id = c.id RETURNING * INTO c;
  PERFORM public.emit_domain_event(
    'challenge.cancelled', auth.uid(), NULL, c.id, '{}', ARRAY[c.opponent_id]
  );
  RETURN c;
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_challenge_v2(p_challenge UUID, p_action TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c public.challenges;
  m public.matches;
  cfg public.ranking_config;
  player_active_count INTEGER;
BEGIN
  SELECT * INTO c FROM public.challenges WHERE id = p_challenge FOR UPDATE;

  IF NOT FOUND OR c.opponent_id <> auth.uid() OR c.status <> 'pending' THEN
    RAISE EXCEPTION 'Challenge is not actionable';
  END IF;

  IF c.expires_at <= NOW() THEN
    UPDATE public.challenges SET status = 'expired' WHERE id = c.id;
    RETURN jsonb_build_object('challenge_id', c.id, 'status', 'expired');
  END IF;

  IF p_action = 'decline' THEN
    UPDATE public.challenges SET status = 'declined' WHERE id = c.id;
    PERFORM public.emit_domain_event(
      'challenge.declined', auth.uid(), NULL, c.id, '{}', ARRAY[c.challenger_id]
    );
    RETURN jsonb_build_object('challenge_id', c.id, 'status', 'declined');
  ELSIF p_action <> 'accept' THEN
    RAISE EXCEPTION 'Invalid challenge action';
  END IF;

  PERFORM public.assert_ranked_access(c.challenger_id);
  PERFORM public.assert_ranked_access(c.opponent_id);

  -- A delayed worker must not let stale matches occupy an active slot or the
  -- unique pair index. Do this before profile locking to preserve the same
  -- match-then-profile lock order used by result finalization.
  WITH expired_matches AS (
    UPDATE public.matches
    SET status = 'expired', finalized_at = NOW()
    WHERE status = 'ready'
      AND expires_at IS NOT NULL
      AND expires_at <= NOW()
      AND (
        player_one_id IN (c.challenger_id, c.opponent_id)
        OR player_two_id IN (c.challenger_id, c.opponent_id)
      )
    RETURNING id
  )
  UPDATE public.match_cancellation_requests r
  SET status = 'expired', responded_at = NOW()
  FROM expired_matches stale
  WHERE r.match_id = stale.id AND r.status = 'pending';

  -- Every acceptance involving either player takes the same stable pair of
  -- profile locks, preventing concurrent accepts from exceeding the cap.
  PERFORM id FROM public.profiles
  WHERE id IN (c.challenger_id, c.opponent_id)
  ORDER BY id
  FOR UPDATE;

  SELECT COUNT(*) INTO player_active_count
  FROM public.matches
  WHERE ranked AND status = 'ready'
    AND (player_one_id = c.challenger_id OR player_two_id = c.challenger_id);
  IF player_active_count >= 3 THEN
    RAISE EXCEPTION 'The challenger already has 3 active ranked matches';
  END IF;

  SELECT COUNT(*) INTO player_active_count
  FROM public.matches
  WHERE ranked AND status = 'ready'
    AND (player_one_id = c.opponent_id OR player_two_id = c.opponent_id);
  IF player_active_count >= 3 THEN
    RAISE EXCEPTION 'You already have 3 active ranked matches';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.matches
    WHERE ranked AND status = 'ready'
      AND LEAST(player_one_id, player_two_id) = LEAST(c.challenger_id, c.opponent_id)
      AND GREATEST(player_one_id, player_two_id) = GREATEST(c.challenger_id, c.opponent_id)
  ) THEN
    RAISE EXCEPTION 'You already have an unfinished ranked match with this opponent';
  END IF;

  -- Preserve the existing temporary 20-confirmed-games-per-pair/day guard.
  IF NOT public.check_daily_match_limit(c.challenger_id, c.opponent_id) THEN
    RAISE EXCEPTION 'Daily ranked match limit reached';
  END IF;

  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  INSERT INTO public.matches(
    challenge_id, player_one_id, player_two_id, status, source, ranked,
    verification_mode, season_id, expires_at
  )
  VALUES(
    c.id, c.challenger_id, c.opponent_id, 'ready', 'challenge', TRUE,
    'normal', (SELECT id FROM public.seasons WHERE is_active LIMIT 1),
    NOW() + make_interval(hours => cfg.result_expiry_hours)
  )
  RETURNING * INTO m;

  UPDATE public.challenges SET status = 'accepted' WHERE id = c.id;
  PERFORM public.emit_domain_event(
    'challenge.accepted', auth.uid(), m.id, c.id,
    jsonb_build_object('expires_at', m.expires_at),
    ARRAY[c.challenger_id, c.opponent_id]
  );

  RETURN jsonb_build_object(
    'challenge_id', c.id,
    'status', 'accepted',
    'match_id', m.id,
    'expires_at', m.expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_match_report_v2(
  p_match UUID,
  p_winner UUID,
  p_winner_score INTEGER,
  p_loser_score INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.matches;
  p1s INTEGER;
  p2s INTEGER;
  result JSONB;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) THEN
    RAISE EXCEPTION 'Match not found';
  END IF;

  -- A repeated or racing request observes the stored result and never writes
  -- another score or applies another rating event.
  IF m.status = 'confirmed' THEN
    RETURN jsonb_build_object(
      'match_id', m.id,
      'status', 'confirmed',
      'already_finalized', TRUE,
      'player_one_change', m.player_one_elo_change,
      'player_two_change', m.player_two_elo_change,
      'player_one_new', m.player_one_elo_before + m.player_one_elo_change,
      'player_two_new', m.player_two_elo_before + m.player_two_elo_change
    );
  END IF;

  IF m.status <> 'ready' THEN
    RAISE EXCEPTION 'Match is already closed';
  END IF;

  IF m.expires_at IS NOT NULL AND m.expires_at <= NOW() THEN
    UPDATE public.match_cancellation_requests
    SET status = 'expired', responded_at = NOW()
    WHERE match_id = m.id AND status = 'pending';
    UPDATE public.matches
    SET status = 'expired', finalized_at = NOW()
    WHERE id = m.id;
    RETURN jsonb_build_object('match_id', m.id, 'status', 'expired');
  END IF;

  IF p_winner NOT IN (m.player_one_id, m.player_two_id) THEN
    RAISE EXCEPTION 'Winner must be a participant';
  END IF;
  IF p_winner_score IS NULL OR p_loser_score IS NULL OR p_winner_score <= p_loser_score THEN
    RAISE EXCEPTION 'Winner score must be higher';
  END IF;

  p1s := CASE WHEN p_winner = m.player_one_id THEN p_winner_score ELSE p_loser_score END;
  p2s := CASE WHEN p_winner = m.player_two_id THEN p_winner_score ELSE p_loser_score END;
  IF NOT public.is_valid_match_score_v2(p1s, p2s) THEN
    RAISE EXCEPTION 'Invalid table tennis score';
  END IF;

  PERFORM public.assert_ranked_access(m.player_one_id);
  PERFORM public.assert_ranked_access(m.player_two_id);

  UPDATE public.matches
  SET winner_id = p_winner,
      player_one_score = p1s,
      player_two_score = p2s,
      reported_by = auth.uid(),
      reported_at = NOW(),
      status = 'result_reported'
  WHERE id = m.id;

  -- A score is allowed while cancellation is pending. If it wins the row-lock
  -- race, close the request as expired before finalizing the match.
  UPDATE public.match_cancellation_requests
  SET status = 'expired', responded_at = NOW()
  WHERE match_id = m.id AND status = 'pending';

  SELECT public.finalize_match_v2(m.id, auth.uid()) INTO result;
  RETURN result || jsonb_build_object('status', 'confirmed');
END;
$$;

CREATE OR REPLACE FUNCTION public.request_match_cancellation_v2(p_match UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.matches;
  request_row public.match_cancellation_requests;
  opponent UUID;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) THEN
    RAISE EXCEPTION 'Match not found';
  END IF;
  IF m.status <> 'ready' THEN
    RAISE EXCEPTION 'Only an active match can be canceled';
  END IF;

  IF m.expires_at IS NOT NULL AND m.expires_at <= NOW() THEN
    UPDATE public.match_cancellation_requests
    SET status = 'expired', responded_at = NOW()
    WHERE match_id = m.id AND status = 'pending';
    UPDATE public.matches SET status = 'expired', finalized_at = NOW() WHERE id = m.id;
    RETURN jsonb_build_object('match_id', m.id, 'status', 'expired');
  END IF;

  SELECT * INTO request_row
  FROM public.match_cancellation_requests
  WHERE match_id = m.id AND status = 'pending'
  FOR UPDATE;

  IF FOUND AND request_row.requested_by = auth.uid() THEN
    RETURN jsonb_build_object(
      'match_id', m.id,
      'status', 'pending',
      'request_id', request_row.id,
      'idempotent', TRUE
    );
  ELSIF FOUND THEN
    UPDATE public.match_cancellation_requests
    SET status = 'approved', responded_by = auth.uid(), responded_at = NOW()
    WHERE id = request_row.id;
    UPDATE public.matches SET status = 'canceled', finalized_at = NOW() WHERE id = m.id;
    PERFORM public.emit_domain_event(
      'match.canceled', auth.uid(), m.id, m.challenge_id,
      jsonb_build_object('request_id', request_row.id),
      ARRAY[m.player_one_id, m.player_two_id]
    );
    RETURN jsonb_build_object(
      'match_id', m.id,
      'status', 'canceled',
      'request_id', request_row.id
    );
  END IF;

  INSERT INTO public.match_cancellation_requests(match_id, requested_by)
  VALUES(m.id, auth.uid())
  RETURNING * INTO request_row;
  opponent := CASE WHEN auth.uid() = m.player_one_id THEN m.player_two_id ELSE m.player_one_id END;
  PERFORM public.emit_domain_event(
    'match.cancellation_requested', auth.uid(), m.id, m.challenge_id,
    jsonb_build_object('request_id', request_row.id), ARRAY[opponent]
  );
  RETURN jsonb_build_object(
    'match_id', m.id,
    'status', 'pending',
    'request_id', request_row.id,
    'idempotent', FALSE
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_match_cancellation_v2(
  p_match UUID,
  p_approve BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.matches;
  request_row public.match_cancellation_requests;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) THEN
    RAISE EXCEPTION 'Match not found';
  END IF;
  IF m.status <> 'ready' THEN
    RAISE EXCEPTION 'Only an active match can be canceled';
  END IF;
  IF p_approve IS NULL THEN
    RAISE EXCEPTION 'Cancellation response is required';
  END IF;

  IF m.expires_at IS NOT NULL AND m.expires_at <= NOW() THEN
    UPDATE public.match_cancellation_requests
    SET status = 'expired', responded_at = NOW()
    WHERE match_id = m.id AND status = 'pending';
    UPDATE public.matches SET status = 'expired', finalized_at = NOW() WHERE id = m.id;
    RETURN jsonb_build_object('match_id', m.id, 'status', 'expired');
  END IF;

  SELECT * INTO request_row
  FROM public.match_cancellation_requests
  WHERE match_id = m.id AND status = 'pending'
  FOR UPDATE;
  IF NOT FOUND OR request_row.requested_by = auth.uid() THEN
    RAISE EXCEPTION 'Only the other player can respond to this cancellation request';
  END IF;

  IF p_approve THEN
    UPDATE public.match_cancellation_requests
    SET status = 'approved', responded_by = auth.uid(), responded_at = NOW()
    WHERE id = request_row.id;
    UPDATE public.matches SET status = 'canceled', finalized_at = NOW() WHERE id = m.id;
    PERFORM public.emit_domain_event(
      'match.canceled', auth.uid(), m.id, m.challenge_id,
      jsonb_build_object('request_id', request_row.id),
      ARRAY[m.player_one_id, m.player_two_id]
    );
    RETURN jsonb_build_object('match_id', m.id, 'status', 'canceled', 'request_id', request_row.id);
  END IF;

  UPDATE public.match_cancellation_requests
  SET status = 'declined', responded_by = auth.uid(), responded_at = NOW()
  WHERE id = request_row.id;
  PERFORM public.emit_domain_event(
    'match.cancellation_declined', auth.uid(), m.id, m.challenge_id,
    jsonb_build_object('request_id', request_row.id), ARRAY[request_row.requested_by]
  );
  RETURN jsonb_build_object('match_id', m.id, 'status', 'ready', 'request_id', request_row.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_mobile_ranking_items_v2()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  challenge_count INTEGER;
  match_count INTEGER;
  cancellation_count INTEGER;
BEGIN
  UPDATE public.challenges
  SET status = 'expired'
  WHERE status = 'pending' AND expires_at <= NOW();
  GET DIAGNOSTICS challenge_count = ROW_COUNT;

  WITH expired_matches AS (
    UPDATE public.matches
    SET status = 'expired', finalized_at = NOW()
    WHERE status = 'ready'
      AND expires_at IS NOT NULL
      AND expires_at <= NOW()
    RETURNING id
  ), expired_requests AS (
    UPDATE public.match_cancellation_requests r
    SET status = 'expired', responded_at = NOW()
    FROM expired_matches m
    WHERE r.match_id = m.id AND r.status = 'pending'
    RETURNING r.id
  )
  SELECT
    (SELECT COUNT(*) FROM expired_matches),
    (SELECT COUNT(*) FROM expired_requests)
  INTO match_count, cancellation_count;

  RETURN jsonb_build_object(
    'expired_challenges', challenge_count,
    'expired_matches', match_count,
    'expired_cancellation_requests', cancellation_count
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_spontaneous_match_v2(UUID, UUID, INTEGER, INTEGER, UUID, BOOLEAN)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.confirm_match_result_v2(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.propose_match_correction_v2(UUID, TEXT, UUID, INTEGER, INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.respond_match_correction_v2(UUID, BOOLEAN)
  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.request_match_cancellation_v2(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.respond_match_cancellation_v2(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_match_cancellation_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_match_cancellation_v2(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_challenge_v2(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_match_report_v2(UUID, UUID, INTEGER, INTEGER) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.expire_mobile_ranking_items_v2() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_mobile_ranking_items_v2() TO service_role;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.match_cancellation_requests;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMIT;
