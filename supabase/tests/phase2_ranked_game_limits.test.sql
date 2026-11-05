-- Run only against a disposable Supabase database after all migrations.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN, message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value, FALSE) THEN RAISE EXCEPTION 'Assertion failed: %', message; END IF;
END;
$$;

INSERT INTO auth.users(id, email, raw_user_meta_data, created_at, updated_at)
SELECT id, email, jsonb_build_object('display_name', name), NOW(), NOW()
FROM (VALUES
  ('f2000000-0000-0000-0000-000000000001'::UUID, 'phase2-a@example.test', 'Phase Two A'),
  ('f2000000-0000-0000-0000-000000000002'::UUID, 'phase2-b@example.test', 'Phase Two B'),
  ('f2000000-0000-0000-0000-000000000003'::UUID, 'phase2-c@example.test', 'Phase Two C'),
  ('f2000000-0000-0000-0000-000000000004'::UUID, 'phase2-d@example.test', 'Phase Two D'),
  ('f2000000-0000-0000-0000-000000000005'::UUID, 'phase2-e@example.test', 'Phase Two E'),
  ('f2000000-0000-0000-0000-000000000006'::UUID, 'phase2-f@example.test', 'Phase Two F'),
  ('f2000000-0000-0000-0000-000000000007'::UUID, 'phase2-g@example.test', 'Phase Two G'),
  ('f2000000-0000-0000-0000-000000000008'::UUID, 'phase2-h@example.test', 'Phase Two H'),
  ('f2000000-0000-0000-0000-000000000009'::UUID, 'phase2-i@example.test', 'Phase Two I'),
  ('f2000000-0000-0000-0000-00000000000a'::UUID, 'phase2-j@example.test', 'Phase Two J'),
  ('f2000000-0000-0000-0000-00000000000b'::UUID, 'phase2-k@example.test', 'Phase Two K'),
  ('f2000000-0000-0000-0000-00000000000c'::UUID, 'phase2-l@example.test', 'Phase Two L'),
  ('f2000000-0000-0000-0000-00000000000d'::UUID, 'phase2-m@example.test', 'Phase Two M'),
  ('f2000000-0000-0000-0000-00000000000e'::UUID, 'phase2-n@example.test', 'Phase Two N'),
  ('f2000000-0000-0000-0000-00000000000f'::UUID, 'phase2-o@example.test', 'Phase Two O'),
  ('f2000000-0000-0000-0000-000000000010'::UUID, 'phase2-p@example.test', 'Phase Two P')
) AS fixtures(id, email, name);

-- Nine completed reservations for A today, each against a different opponent.
INSERT INTO public.matches(
  player_one_id, player_two_id, status, source, ranked, ranked_day,
  winner_id, player_one_score, player_two_score, confirmed_at, finalized_at
)
SELECT 'f2000000-0000-0000-0000-000000000001', opponent, 'confirmed', 'challenge', TRUE,
  public.club_ranked_day_v3(), 'f2000000-0000-0000-0000-000000000001', 11, 9, NOW(), NOW()
FROM unnest(ARRAY[
  'f2000000-0000-0000-0000-000000000002'::UUID,
  'f2000000-0000-0000-0000-000000000003'::UUID,
  'f2000000-0000-0000-0000-000000000004'::UUID,
  'f2000000-0000-0000-0000-000000000005'::UUID,
  'f2000000-0000-0000-0000-000000000006'::UUID,
  'f2000000-0000-0000-0000-000000000007'::UUID,
  'f2000000-0000-0000-0000-000000000008'::UUID,
  'f2000000-0000-0000-0000-000000000009'::UUID,
  'f2000000-0000-0000-0000-00000000000a'::UUID
]) AS opponent;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000001', TRUE);
SELECT pg_temp.assert_true(
  (public.get_my_ranked_usage_v3()->>'daily_used')::INTEGER = 9,
  'completed matches must consume daily capacity'
);
RESET ROLE;

-- Accepting A/K creates reservation 10. A/L is then rejected.
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f2000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-00000000000b','pending',NOW()+INTERVAL '24 hours'),
      ('f2000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-00000000000c','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-00000000000b', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-00000000000c', TRUE);
DO $$
BEGIN
  PERFORM public.respond_challenge_v2((SELECT id FROM public.challenges
    WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
  RAISE EXCEPTION 'Expected daily player cap rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'Expected daily player cap rejection' THEN RAISE; END IF;
  IF SQLERRM NOT LIKE '%10 ranked games per day%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

-- Cancellation releases A/K, allowing A/L to reserve the tenth slot.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000001', TRUE);
SELECT public.request_match_cancellation_v2((SELECT id FROM public.matches WHERE status='ready' AND player_two_id='f2000000-0000-0000-0000-00000000000b'));
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-00000000000b', TRUE);
SELECT public.respond_match_cancellation_v2((SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid()), TRUE);
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-00000000000c', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000001', TRUE);
SELECT pg_temp.assert_true(
  (public.get_my_ranked_usage_v3()->>'daily_used')::INTEGER = 10,
  'canceled reservations must be released and reusable'
);
SELECT pg_temp.assert_true(
  (SELECT games_used=1 AND games_remaining=2 FROM public.get_my_opponent_ranked_usage_v3() WHERE opponent_id='f2000000-0000-0000-0000-00000000000c'),
  'opponent usage must include accepted reservations'
);
-- Sending is still allowed at the cap because acceptance may occur tomorrow.
SELECT public.create_challenge_v2('f2000000-0000-0000-0000-00000000000d');
RESET ROLE;

-- A match accepted yesterday is charged to yesterday, not the result day.
INSERT INTO public.matches(
  player_one_id,player_two_id,status,source,ranked,ranked_day,
  winner_id,player_one_score,player_two_score,confirmed_at,finalized_at
)
VALUES(
  'f2000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-00000000000d',
  'confirmed','challenge',TRUE,public.club_ranked_day_v3()-1,
  'f2000000-0000-0000-0000-000000000001',11,9,NOW(),NOW()
);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000001', TRUE);
SELECT pg_temp.assert_true(
  (public.get_my_ranked_usage_v3()->>'daily_used')::INTEGER = 10,
  'yesterday acceptance must not consume today capacity'
);
RESET ROLE;

-- Two completed M/N games plus one accepted result reach the three-game pair cap.
INSERT INTO public.matches(
  player_one_id,player_two_id,status,source,ranked,ranked_day,
  winner_id,player_one_score,player_two_score,confirmed_at,finalized_at
)
SELECT 'f2000000-0000-0000-0000-00000000000d','f2000000-0000-0000-0000-00000000000e',
  'confirmed','challenge',TRUE,public.club_ranked_day_v3(),
  'f2000000-0000-0000-0000-00000000000d',11,9,NOW(),NOW()
FROM generate_series(1,2);
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f2000000-0000-0000-0000-00000000000d','f2000000-0000-0000-0000-00000000000e','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-00000000000e', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
SELECT public.submit_match_report_v2(
  (SELECT id FROM public.matches WHERE status='ready' AND player_one_id='f2000000-0000-0000-0000-00000000000d' AND player_two_id=auth.uid()),
  'f2000000-0000-0000-0000-00000000000d', 11, 9
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-00000000000d', TRUE);
SELECT pg_temp.assert_true(
  (SELECT games_used=3 AND games_remaining=0
    FROM public.get_my_opponent_ranked_usage_v3()
    WHERE opponent_id='f2000000-0000-0000-0000-00000000000e'),
  'the first three completed games against an opponent must consume all three slots'
);
RESET ROLE;
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f2000000-0000-0000-0000-00000000000e','f2000000-0000-0000-0000-00000000000d','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-00000000000d', TRUE);
DO $$
BEGIN
  PERFORM public.respond_challenge_v2((SELECT id FROM public.challenges
    WHERE challenger_id='f2000000-0000-0000-0000-00000000000e'
      AND opponent_id=auth.uid() AND status='pending'), 'accept');
  RAISE EXCEPTION 'Expected daily opponent cap rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'Expected daily opponent cap rejection' THEN RAISE; END IF;
  IF SQLERRM NOT LIKE '%limit of 3 ranked games against this opponent%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;
-- Expiration also releases a reservation.
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f2000000-0000-0000-0000-00000000000f','f2000000-0000-0000-0000-000000000010','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000010', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
RESET ROLE;
UPDATE public.matches SET expires_at=NOW()
WHERE status='ready' AND player_one_id='f2000000-0000-0000-0000-00000000000f' AND player_two_id='f2000000-0000-0000-0000-000000000010';
SELECT public.expire_mobile_ranking_items_v2();
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-00000000000f', TRUE);
SELECT pg_temp.assert_true(
  (public.get_my_ranked_usage_v3()->>'daily_used')::INTEGER = 0,
  'expired reservations must not consume capacity'
);
RESET ROLE;

-- New York calendar boundaries, including both DST transition dates.
SELECT pg_temp.assert_true(
  public.club_ranked_day_v3('2026-03-08 04:59:59+00') = DATE '2026-03-07'
  AND public.club_ranked_day_v3('2026-03-08 05:00:00+00') = DATE '2026-03-08',
  'spring DST date boundary must use America/New_York midnight'
);
SELECT pg_temp.assert_true(
  public.club_ranked_day_v3('2026-11-01 03:59:59+00') = DATE '2026-10-31'
  AND public.club_ranked_day_v3('2026-11-01 04:00:00+00') = DATE '2026-11-01',
  'fall DST date boundary must use America/New_York midnight'
);

ROLLBACK;
