-- Beaver Smash V3 Phase 2: acceptance-day reservations and ranked game limits.
BEGIN;

ALTER TABLE public.ranking_config
  ADD COLUMN IF NOT EXISTS daily_ranked_player_limit INTEGER NOT NULL DEFAULT 10
    CHECK (daily_ranked_player_limit > 0),
  ADD COLUMN IF NOT EXISTS active_ranked_match_limit INTEGER NOT NULL DEFAULT 3
    CHECK (active_ranked_match_limit > 0);

UPDATE public.ranking_config
SET daily_ranked_player_limit = 10,
    daily_ranked_pair_limit = 3,
    active_ranked_match_limit = 3,
    challenge_expiry_hours = 24,
    result_expiry_hours = 24,
    updated_at = NOW()
WHERE id;

CREATE OR REPLACE FUNCTION public.club_ranked_day_v3(p_at TIMESTAMPTZ DEFAULT NOW())
RETURNS DATE
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT (p_at AT TIME ZONE 'America/New_York')::DATE;
$$;

ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS ranked_day DATE;
UPDATE public.matches
SET ranked_day = public.club_ranked_day_v3(created_at)
WHERE ranked AND ranked_day IS NULL;
ALTER TABLE public.matches ADD CONSTRAINT ranked_matches_have_day
  CHECK (NOT ranked OR ranked_day IS NOT NULL) NOT VALID;
ALTER TABLE public.matches VALIDATE CONSTRAINT ranked_matches_have_day;

CREATE INDEX IF NOT EXISTS idx_matches_ranked_day_status
  ON public.matches(ranked_day, status) WHERE ranked;
CREATE INDEX IF NOT EXISTS idx_matches_ranked_day_player_one
  ON public.matches(ranked_day, player_one_id, status) WHERE ranked;
CREATE INDEX IF NOT EXISTS idx_matches_ranked_day_player_two
  ON public.matches(ranked_day, player_two_id, status) WHERE ranked;

-- Reservations are represented by accepted/finalizing/confirmed match rows.
-- Canceled, expired, and voided rows remain historical but consume no capacity.
CREATE OR REPLACE FUNCTION public.check_daily_match_limit(
  p_player_one_id UUID,
  p_player_two_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH cfg AS (
    SELECT daily_ranked_player_limit AS player_limit,
           daily_ranked_pair_limit AS pair_limit
    FROM public.ranking_config WHERE id
  ), usage AS (
    SELECT
      COUNT(*) FILTER (
        WHERE p_player_one_id IN (m.player_one_id, m.player_two_id)
      ) AS player_one_used,
      COUNT(*) FILTER (
        WHERE p_player_two_id IN (m.player_one_id, m.player_two_id)
      ) AS player_two_used,
      COUNT(*) FILTER (
        WHERE LEAST(m.player_one_id, m.player_two_id) = LEAST(p_player_one_id, p_player_two_id)
          AND GREATEST(m.player_one_id, m.player_two_id) = GREATEST(p_player_one_id, p_player_two_id)
      ) AS pair_used
    FROM public.matches m
    WHERE m.ranked
      AND m.ranked_day = public.club_ranked_day_v3()
      AND m.status IN ('ready', 'result_reported', 'confirmed')
  )
  SELECT
    -- The Phase 1 finalizer calls this after changing its already-reserved row
    -- to result_reported. That reservation is valid and must be finalizable.
    EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.ranked AND m.status = 'result_reported'
        AND LEAST(m.player_one_id, m.player_two_id) = LEAST(p_player_one_id, p_player_two_id)
        AND GREATEST(m.player_one_id, m.player_two_id) = GREATEST(p_player_one_id, p_player_two_id)
    )
    OR (
      usage.player_one_used < cfg.player_limit
      AND usage.player_two_used < cfg.player_limit
      AND usage.pair_used < cfg.pair_limit
    )
  FROM cfg CROSS JOIN usage;
$$;

CREATE OR REPLACE FUNCTION public.get_my_ranked_usage_v3()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cfg public.ranking_config;
  day DATE := public.club_ranked_day_v3();
  daily_used INTEGER;
  active_used INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  SELECT COUNT(*) INTO daily_used
  FROM public.matches
  WHERE ranked AND ranked_day = day
    AND status IN ('ready', 'result_reported', 'confirmed')
    AND (status <> 'ready' OR expires_at > NOW())
    AND auth.uid() IN (player_one_id, player_two_id);
  SELECT COUNT(*) INTO active_used
  FROM public.matches
  WHERE ranked AND status = 'ready'
    AND expires_at > NOW()
    AND auth.uid() IN (player_one_id, player_two_id);
  RETURN jsonb_build_object(
    'ranked_day', day,
    'daily_used', daily_used,
    'daily_limit', cfg.daily_ranked_player_limit,
    'daily_remaining', GREATEST(cfg.daily_ranked_player_limit - daily_used, 0),
    'active_used', active_used,
    'active_limit', cfg.active_ranked_match_limit,
    'active_remaining', GREATEST(cfg.active_ranked_match_limit - active_used, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_opponent_ranked_usage_v3()
RETURNS TABLE(
  opponent_id UUID,
  games_used INTEGER,
  games_limit INTEGER,
  games_remaining INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  RETURN QUERY
  WITH cfg AS (
    SELECT daily_ranked_pair_limit AS pair_limit
    FROM public.ranking_config WHERE id
  ), usage AS (
    SELECT
      CASE WHEN m.player_one_id = auth.uid() THEN m.player_two_id ELSE m.player_one_id END AS opponent,
      COUNT(*)::INTEGER AS used
    FROM public.matches m
    WHERE m.ranked
      AND m.ranked_day = public.club_ranked_day_v3()
      AND m.status IN ('ready', 'result_reported', 'confirmed')
      AND (m.status <> 'ready' OR m.expires_at > NOW())
      AND auth.uid() IN (m.player_one_id, m.player_two_id)
    GROUP BY 1
  )
  SELECT p.id,
         COALESCE(u.used, 0)::INTEGER,
         cfg.pair_limit,
         GREATEST(cfg.pair_limit - COALESCE(u.used, 0), 0)::INTEGER
  FROM public.profiles p
  CROSS JOIN cfg
  LEFT JOIN usage u ON u.opponent = p.id
  WHERE p.id <> auth.uid();
END;
$$;

-- Sending a challenge does not reserve capacity. A pending challenge may be
-- accepted after the New York calendar day resets, so limits are checked only
-- when the opponent accepts.
CREATE OR REPLACE FUNCTION public.create_challenge_v2(p_opponent UUID)
RETURNS public.challenges
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c public.challenges;
  cfg public.ranking_config;
BEGIN
  IF auth.uid() IS NULL OR p_opponent = auth.uid() THEN
    RAISE EXCEPTION 'Invalid opponent';
  END IF;
  PERFORM public.assert_ranked_access(auth.uid());
  PERFORM public.assert_ranked_access(p_opponent);

  UPDATE public.challenges
  SET status = 'expired'
  WHERE status = 'pending'
    AND expires_at <= NOW()
    AND LEAST(challenger_id, opponent_id) = LEAST(auth.uid(), p_opponent)
    AND GREATEST(challenger_id, opponent_id) = GREATEST(auth.uid(), p_opponent);

  SELECT * INTO cfg FROM public.ranking_config WHERE id;
  INSERT INTO public.challenges(challenger_id, opponent_id, status, expires_at)
  VALUES(auth.uid(), p_opponent, 'pending', NOW() + make_interval(hours => cfg.challenge_expiry_hours))
  RETURNING * INTO c;
  PERFORM public.emit_domain_event(
    'challenge.received', auth.uid(), NULL, c.id, '{}', ARRAY[p_opponent]
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
  day DATE := public.club_ranked_day_v3();
  usage_count INTEGER;
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

  PERFORM id FROM public.profiles
  WHERE id IN (c.challenger_id, c.opponent_id)
  ORDER BY id
  FOR UPDATE;
  SELECT * INTO cfg FROM public.ranking_config WHERE id;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND status = 'ready'
    AND c.challenger_id IN (player_one_id, player_two_id);
  IF usage_count >= cfg.active_ranked_match_limit THEN
    RAISE EXCEPTION 'The challenger has reached the 3 active ranked match limit';
  END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND status = 'ready'
    AND c.opponent_id IN (player_one_id, player_two_id);
  IF usage_count >= cfg.active_ranked_match_limit THEN
    RAISE EXCEPTION 'You have reached the 3 active ranked match limit';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.matches
    WHERE ranked AND status = 'ready'
      AND LEAST(player_one_id, player_two_id) = LEAST(c.challenger_id, c.opponent_id)
      AND GREATEST(player_one_id, player_two_id) = GREATEST(c.challenger_id, c.opponent_id)
  ) THEN
    RAISE EXCEPTION 'You already have an unfinished ranked match with this opponent';
  END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND ranked_day = day
    AND status IN ('ready', 'result_reported', 'confirmed')
    AND c.challenger_id IN (player_one_id, player_two_id);
  IF usage_count >= cfg.daily_ranked_player_limit THEN
    RAISE EXCEPTION 'The challenger has reached the 10 ranked games per day limit';
  END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND ranked_day = day
    AND status IN ('ready', 'result_reported', 'confirmed')
    AND c.opponent_id IN (player_one_id, player_two_id);
  IF usage_count >= cfg.daily_ranked_player_limit THEN
    RAISE EXCEPTION 'You have reached the 10 ranked games per day limit';
  END IF;

  SELECT COUNT(*) INTO usage_count
  FROM public.matches
  WHERE ranked AND ranked_day = day
    AND status IN ('ready', 'result_reported', 'confirmed')
    AND LEAST(player_one_id, player_two_id) = LEAST(c.challenger_id, c.opponent_id)
    AND GREATEST(player_one_id, player_two_id) = GREATEST(c.challenger_id, c.opponent_id);
  IF usage_count >= cfg.daily_ranked_pair_limit THEN
    RAISE EXCEPTION 'You have reached the daily limit of 3 ranked games against this opponent';
  END IF;

  INSERT INTO public.matches(
    challenge_id, player_one_id, player_two_id, status, source, ranked,
    verification_mode, season_id, expires_at, ranked_day
  )
  VALUES(
    c.id, c.challenger_id, c.opponent_id, 'ready', 'challenge', TRUE,
    'normal', (SELECT id FROM public.seasons WHERE is_active LIMIT 1),
    NOW() + make_interval(hours => cfg.result_expiry_hours), day
  )
  RETURNING * INTO m;

  UPDATE public.challenges SET status = 'accepted' WHERE id = c.id;
  PERFORM public.emit_domain_event(
    'challenge.accepted', auth.uid(), m.id, c.id,
    jsonb_build_object('expires_at', m.expires_at, 'ranked_day', m.ranked_day),
    ARRAY[c.challenger_id, c.opponent_id]
  );
  RETURN jsonb_build_object(
    'challenge_id', c.id,
    'status', 'accepted',
    'match_id', m.id,
    'expires_at', m.expires_at,
    'ranked_day', m.ranked_day
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_ranked_usage_v3() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_my_opponent_ranked_usage_v3() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.club_ranked_day_v3(TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_ranked_usage_v3() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_opponent_ranked_usage_v3() TO authenticated;
GRANT EXECUTE ON FUNCTION public.club_ranked_day_v3(TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_challenge_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_challenge_v2(UUID, TEXT) TO authenticated;

COMMIT;
