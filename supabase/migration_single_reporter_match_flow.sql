-- Single-reporter match lifecycle. Safe to run against the previous Pongo schema.
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS reported_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS reported_at TIMESTAMPTZ;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS confirmed_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS disputed_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS disputed_at TIMESTAMPTZ;
ALTER TABLE public.matches ADD COLUMN IF NOT EXISTS dispute_reason TEXT;

ALTER TABLE public.matches DROP CONSTRAINT IF EXISTS matches_status_check;
ALTER TABLE public.matches ADD CONSTRAINT matches_status_check
  CHECK (status IN ('active', 'pending_confirmation', 'disputed', 'confirmed', 'auto_expired'));

-- Preserve completed history. Convert usable pending rows; reset incomplete legacy submissions.
UPDATE public.matches
SET reported_by = player_one_id,
    reported_at = COALESCE(created_at, NOW())
WHERE status = 'pending_confirmation'
  AND player_one_score IS NOT NULL
  AND player_two_score IS NOT NULL
  AND reported_by IS NULL;

UPDATE public.matches
SET player_one_score = NULL,
    player_two_score = NULL,
    status = 'active',
    expires_at = NULL
WHERE status IN ('active', 'pending_confirmation')
  AND (player_one_score IS NULL OR player_two_score IS NULL);

ALTER TABLE public.matches DROP COLUMN IF EXISTS player_one_submission;
ALTER TABLE public.matches DROP COLUMN IF EXISTS player_two_submission;

CREATE OR REPLACE FUNCTION public.is_valid_match_score(p_one INTEGER, p_two INTEGER)
RETURNS BOOLEAN AS $$
  SELECT COALESCE(p_one >= 0 AND p_two >= 0 AND p_one <> p_two
    AND GREATEST(p_one, p_two) >= 11
    AND ABS(p_one - p_two) >= 2
    AND NOT (GREATEST(p_one, p_two) > 11 AND (LEAST(p_one, p_two) < 10 OR ABS(p_one - p_two) <> 2)), FALSE);
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION public.report_match_result(
  p_match_id UUID,
  p_player_one_score INTEGER,
  p_player_two_score INTEGER
) RETURNS public.matches AS $$
DECLARE
  m public.matches;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF auth.uid() IS NULL OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  IF m.status NOT IN ('active', 'disputed') THEN RAISE EXCEPTION 'This result cannot be reported now'; END IF;
  IF m.status = 'disputed' AND m.reported_by <> auth.uid() THEN
    RAISE EXCEPTION 'Only the original reporter can revise a disputed result';
  END IF;
  IF NOT public.is_valid_match_score(p_player_one_score, p_player_two_score) THEN
    RAISE EXCEPTION 'Invalid score';
  END IF;

  UPDATE public.matches SET
    player_one_score = p_player_one_score,
    player_two_score = p_player_two_score,
    reported_by = COALESCE(reported_by, auth.uid()),
    reported_at = NOW(),
    status = 'pending_confirmation',
    confirmed_by = NULL,
    disputed_by = NULL,
    disputed_at = NULL,
    dispute_reason = NULL,
    expires_at = NOW() + INTERVAL '24 hours'
  WHERE id = p_match_id
  RETURNING * INTO m;
  RETURN m;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.dispute_match_result(p_match_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS public.matches AS $$
DECLARE
  m public.matches;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status <> 'pending_confirmation' THEN RAISE EXCEPTION 'This result is not awaiting confirmation'; END IF;
  IF auth.uid() IS NULL OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) OR auth.uid() = m.reported_by THEN
    RAISE EXCEPTION 'Only the reporting player''s opponent can dispute this result';
  END IF;

  UPDATE public.matches SET
    status = 'disputed',
    disputed_by = auth.uid(),
    disputed_at = NOW(),
    dispute_reason = NULLIF(LEFT(TRIM(p_reason), 500), ''),
    expires_at = NOW() + INTERVAL '24 hours'
  WHERE id = p_match_id
  RETURNING * INTO m;
  RETURN m;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.confirm_match_result(p_match_id UUID)
RETURNS JSONB AS $$
DECLARE
  m public.matches;
  p1 public.profiles;
  p2 public.profiles;
  expected_one NUMERIC;
  margin NUMERIC;
  actual_one NUMERIC;
  change_one INTEGER;
  change_two INTEGER;
BEGIN
  SELECT * INTO m FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match not found'; END IF;
  IF m.status <> 'pending_confirmation' THEN RAISE EXCEPTION 'This result is not awaiting confirmation'; END IF;
  IF auth.uid() IS NULL OR auth.uid() NOT IN (m.player_one_id, m.player_two_id) OR auth.uid() = m.reported_by THEN
    RAISE EXCEPTION 'Only the reporting player''s opponent can confirm this result';
  END IF;
  IF NOT public.is_valid_match_score(m.player_one_score, m.player_two_score) THEN
    RAISE EXCEPTION 'Invalid score';
  END IF;

  -- Lock both profiles in stable order before calculating and applying ratings.
  PERFORM id FROM public.profiles
    WHERE id IN (m.player_one_id, m.player_two_id)
    ORDER BY id FOR UPDATE;
  SELECT * INTO p1 FROM public.profiles WHERE id = m.player_one_id;
  SELECT * INTO p2 FROM public.profiles WHERE id = m.player_two_id;

  expected_one := 1.0 / (1.0 + POWER(10.0, (p2.current_elo - p1.current_elo) / 400.0));
  actual_one := CASE WHEN m.player_one_score > m.player_two_score THEN 1.0 ELSE 0.0 END;
  margin := CASE
    WHEN ABS(m.player_one_score - m.player_two_score) <= 2 THEN 1.0
    WHEN ABS(m.player_one_score - m.player_two_score) <= 5 THEN 1.1
    WHEN ABS(m.player_one_score - m.player_two_score) <= 8 THEN 1.2
    ELSE 1.25
  END;
  -- FLOOR(x + .5) matches JavaScript Math.round, including negative half-values.
  change_one := FLOOR(32 * margin * (actual_one - expected_one) + 0.5);
  change_two := FLOOR(32 * margin * ((1 - actual_one) - (1 - expected_one)) + 0.5);

  UPDATE public.profiles SET
    current_elo = current_elo + change_one,
    total_wins = total_wins + CASE WHEN actual_one = 1 THEN 1 ELSE 0 END,
    total_losses = total_losses + CASE WHEN actual_one = 1 THEN 0 ELSE 1 END,
    weekly_wins = weekly_wins + CASE WHEN actual_one = 1 THEN 1 ELSE 0 END,
    weekly_losses = weekly_losses + CASE WHEN actual_one = 1 THEN 0 ELSE 1 END,
    updated_at = NOW()
  WHERE id = m.player_one_id;

  UPDATE public.profiles SET
    current_elo = current_elo + change_two,
    total_wins = total_wins + CASE WHEN actual_one = 0 THEN 1 ELSE 0 END,
    total_losses = total_losses + CASE WHEN actual_one = 0 THEN 0 ELSE 1 END,
    weekly_wins = weekly_wins + CASE WHEN actual_one = 0 THEN 1 ELSE 0 END,
    weekly_losses = weekly_losses + CASE WHEN actual_one = 0 THEN 0 ELSE 1 END,
    updated_at = NOW()
  WHERE id = m.player_two_id;

  UPDATE public.matches SET
    status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = NOW(), expires_at = NULL,
    player_one_elo_before = p1.current_elo, player_two_elo_before = p2.current_elo,
    player_one_elo_change = change_one, player_two_elo_change = change_two
  WHERE id = p_match_id;

  IF m.challenge_id IS NOT NULL THEN
    UPDATE public.challenges SET status = 'completed' WHERE id = m.challenge_id;
  END IF;

  RETURN jsonb_build_object(
    'eloChanges', jsonb_build_object(
      'player_one', change_one, 'player_two', change_two,
      'player_one_new', p1.current_elo + change_one,
      'player_two_new', p2.current_elo + change_two
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.expire_unconfirmed_matches()
RETURNS void AS $$
BEGIN
  UPDATE public.matches
  SET status = 'auto_expired'
  WHERE status IN ('pending_confirmation', 'disputed')
    AND expires_at IS NOT NULL AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Keep existing cron jobs safe while they are moved to expire_unconfirmed_matches().
CREATE OR REPLACE FUNCTION public.expire_pending_confirmation_matches()
RETURNS void AS $$
BEGIN
  UPDATE public.matches SET status = 'auto_expired'
  WHERE status IN ('pending_confirmation', 'disputed')
    AND expires_at IS NOT NULL AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.expire_unsubmitted_matches()
RETURNS void AS $$
BEGIN
  UPDATE public.matches SET status = 'auto_expired'
  WHERE status IN ('pending_confirmation', 'disputed')
    AND expires_at IS NOT NULL AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Result changes must go through the role-aware functions above.
DROP POLICY IF EXISTS "Users can update matches they're involved in" ON public.matches;
DROP POLICY IF EXISTS "Users can create matches" ON public.matches;
CREATE POLICY "Users can create active matches"
  ON public.matches FOR INSERT
  WITH CHECK (
    (auth.uid() = player_one_id OR auth.uid() = player_two_id)
    AND status = 'active' AND player_one_score IS NULL AND player_two_score IS NULL
    AND reported_by IS NULL AND confirmed_by IS NULL AND disputed_by IS NULL
    AND reported_at IS NULL AND confirmed_at IS NULL AND disputed_at IS NULL
    AND player_one_elo_change IS NULL AND player_two_elo_change IS NULL
  );
REVOKE EXECUTE ON FUNCTION public.report_match_result(UUID, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dispute_match_result(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.confirm_match_result(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_unconfirmed_matches() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_match_stats(UUID, UUID, UUID, INTEGER, INTEGER, BOOLEAN) FROM PUBLIC, authenticated;
REVOKE UPDATE ON TABLE public.profiles FROM authenticated;
GRANT UPDATE (display_name) ON TABLE public.profiles TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_match_result(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispute_match_result(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_match_result(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_unconfirmed_matches() TO authenticated;
