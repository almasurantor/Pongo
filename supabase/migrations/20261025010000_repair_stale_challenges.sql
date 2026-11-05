-- Keep challenge actions healthy even when the external expiration worker is
-- delayed or unavailable. Expired pending rows otherwise remain visible and
-- also continue to occupy the unique pending-pair index.
BEGIN;

UPDATE public.challenges
SET status = 'expired'
WHERE status = 'pending'
  AND expires_at <= NOW();

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

  IF NOT public.check_daily_match_limit(auth.uid(), p_opponent) THEN
    RAISE EXCEPTION 'Daily ranked match limit reached';
  END IF;

  -- Release the pending-pair uniqueness slot without relying on a scheduler.
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
  mode TEXT;
BEGIN
  SELECT * INTO c FROM public.challenges WHERE id = p_challenge FOR UPDATE;

  IF NOT FOUND OR c.opponent_id <> auth.uid() OR c.status <> 'pending' THEN
    RAISE EXCEPTION 'Challenge is not actionable';
  END IF;

  -- Return instead of raising so the expiration update is committed.
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

  IF NOT public.check_daily_match_limit(c.challenger_id, c.opponent_id) THEN
    RAISE EXCEPTION 'Daily ranked match limit reached';
  END IF;

  SELECT CASE WHEN EXISTS(
    SELECT 1
    FROM public.player_integrity
    WHERE player_id IN (c.challenger_id, c.opponent_id)
      AND verification_level = 'dual_verification'
  ) THEN 'dual' ELSE 'normal' END
  INTO mode;

  INSERT INTO public.matches(
    challenge_id, player_one_id, player_two_id, status, source,
    verification_mode, season_id
  )
  VALUES(
    c.id, c.challenger_id, c.opponent_id, 'ready', 'challenge', mode,
    (SELECT id FROM public.seasons WHERE is_active LIMIT 1)
  )
  RETURNING * INTO m;

  UPDATE public.challenges SET status = 'accepted' WHERE id = c.id;
  PERFORM public.emit_domain_event(
    'challenge.accepted', auth.uid(), m.id, c.id, '{}',
    ARRAY[c.challenger_id, c.opponent_id]
  );

  RETURN jsonb_build_object(
    'challenge_id', c.id, 'status', 'accepted', 'match_id', m.id
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_challenge_v2(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.respond_challenge_v2(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_challenge_v2(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_challenge_v2(UUID, TEXT) TO authenticated;

COMMIT;
