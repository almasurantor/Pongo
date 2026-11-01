-- Run only against a disposable database after applying all migrations.
-- Every fixture is rolled back, and any failed assertion aborts the script.
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
  ('f1000000-0000-0000-0000-000000000001'::UUID, 'phase1-a@example.test', 'Phase One A'),
  ('f1000000-0000-0000-0000-000000000002'::UUID, 'phase1-b@example.test', 'Phase One B'),
  ('f1000000-0000-0000-0000-000000000003'::UUID, 'phase1-c@example.test', 'Phase One C'),
  ('f1000000-0000-0000-0000-000000000004'::UUID, 'phase1-d@example.test', 'Phase One D'),
  ('f1000000-0000-0000-0000-000000000005'::UUID, 'phase1-e@example.test', 'Phase One E'),
  ('f1000000-0000-0000-0000-000000000006'::UUID, 'phase1-f@example.test', 'Phase One F')
) AS fixtures(id, email, name);

-- Accept three matches involving A.
INSERT INTO public.challenges(challenger_id, opponent_id, status, expires_at)
SELECT 'f1000000-0000-0000-0000-000000000001', opponent, 'pending', NOW() + INTERVAL '24 hours'
FROM unnest(ARRAY[
  'f1000000-0000-0000-0000-000000000002'::UUID,
  'f1000000-0000-0000-0000-000000000003'::UUID,
  'f1000000-0000-0000-0000-000000000004'::UUID
]) AS opponent;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000004', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT COUNT(*) = 3 FROM public.matches WHERE status='ready' AND 'f1000000-0000-0000-0000-000000000001' IN(player_one_id,player_two_id)),
  'three active matches should be accepted'
);

-- A fourth acceptance must fail and leave its challenge pending.
INSERT INTO public.challenges(challenger_id, opponent_id, status, expires_at)
VALUES('f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000005','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000005', TRUE);
DO $$
BEGIN
  PERFORM public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
  RAISE EXCEPTION 'Expected the fourth active match to be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'Expected the fourth active match to be rejected' THEN RAISE; END IF;
  IF SQLERRM NOT LIKE '%3 active ranked matches%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

-- Decline then re-request and approve cancellation for A/B.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', TRUE);
SELECT public.request_match_cancellation_v2((SELECT id FROM public.matches WHERE status='ready' AND player_two_id='f1000000-0000-0000-0000-000000000002'));
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', TRUE);
SELECT public.respond_match_cancellation_v2((SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid()), FALSE);
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', TRUE);
SELECT public.request_match_cancellation_v2((SELECT id FROM public.matches WHERE status='ready' AND player_two_id='f1000000-0000-0000-0000-000000000002'));
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', TRUE);
SELECT public.respond_match_cancellation_v2((SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid()), TRUE);
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT status='canceled' FROM public.matches WHERE player_one_id='f1000000-0000-0000-0000-000000000001' AND player_two_id='f1000000-0000-0000-0000-000000000002'),
  'mutually approved cancellation should cancel the match'
);
SELECT pg_temp.assert_true(
  (SELECT current_elo=1000 AND total_wins=0 AND total_losses=0 FROM public.profiles WHERE id='f1000000-0000-0000-0000-000000000001'),
  'cancellation must not change ratings or records'
);

-- First report finalizes A/C. A conflicting second report is idempotent.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', TRUE);
SELECT public.submit_match_report_v2(
  (SELECT id FROM public.matches WHERE status='ready' AND player_two_id='f1000000-0000-0000-0000-000000000003'),
  'f1000000-0000-0000-0000-000000000001', 11, 9
);
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', TRUE);
SELECT public.submit_match_report_v2(
  (SELECT id FROM public.matches WHERE status='confirmed' AND player_two_id=auth.uid()),
  'f1000000-0000-0000-0000-000000000003', 11, 0
);
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT winner_id='f1000000-0000-0000-0000-000000000001' AND player_one_score=11 AND player_two_score=9
   FROM public.matches WHERE status='confirmed' AND player_two_id='f1000000-0000-0000-0000-000000000003'),
  'the first valid report must remain authoritative'
);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=2 FROM public.rating_events
   WHERE match_id=(SELECT id FROM public.matches WHERE status='confirmed' AND player_two_id='f1000000-0000-0000-0000-000000000003')),
  'finalization must create exactly two rating events'
);
SELECT pg_temp.assert_true(
  (SELECT player_one_elo_change + player_two_elo_change = 0 FROM public.matches
   WHERE status='confirmed' AND player_two_id='f1000000-0000-0000-0000-000000000003'),
  'rating changes must remain zero-sum'
);

-- Exact-deadline reporting expires A/D without applying a result.
UPDATE public.matches SET expires_at=NOW()
WHERE status='ready' AND player_two_id='f1000000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000004', TRUE);
SELECT public.submit_match_report_v2(
  (SELECT id FROM public.matches WHERE status='ready' AND player_two_id=auth.uid()),
  auth.uid(), 11, 9
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT status='expired' AND winner_id IS NULL FROM public.matches WHERE player_two_id='f1000000-0000-0000-0000-000000000004'),
  'a report at the deadline must expire without a result'
);

-- A new match for the same unordered pair cannot be accepted while one is ready.
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE challenger_id='f1000000-0000-0000-0000-000000000001' AND opponent_id=auth.uid() AND status='pending'), 'accept');
RESET ROLE;
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000001','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', TRUE);
DO $$
BEGIN
  PERFORM public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
  RAISE EXCEPTION 'Expected the duplicate opponent match to be rejected';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM = 'Expected the duplicate opponent match to be rejected' THEN RAISE; END IF;
  IF SQLERRM NOT LIKE '%unfinished ranked match%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=1 FROM public.matches WHERE status='ready'
   AND LEAST(player_one_id,player_two_id)='f1000000-0000-0000-0000-000000000001'
   AND GREATEST(player_one_id,player_two_id)='f1000000-0000-0000-0000-000000000002'),
  'only one ready match may exist per unordered opponent pair'
);

-- Scheduled cleanup expires accepted matches, their pending cancellation, and challenges.
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f1000000-0000-0000-0000-000000000005','f1000000-0000-0000-0000-000000000006','pending',NOW()+INTERVAL '24 hours');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000006', TRUE);
SELECT public.respond_challenge_v2((SELECT id FROM public.challenges WHERE opponent_id=auth.uid() AND status='pending'), 'accept');
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000005', TRUE);
SELECT public.request_match_cancellation_v2((SELECT id FROM public.matches WHERE status='ready' AND player_one_id=auth.uid() AND player_two_id='f1000000-0000-0000-0000-000000000006'));
RESET ROLE;
UPDATE public.matches SET expires_at=NOW() WHERE status='ready' AND player_one_id='f1000000-0000-0000-0000-000000000005';
INSERT INTO public.challenges(challenger_id,opponent_id,status,expires_at)
VALUES('f1000000-0000-0000-0000-000000000005','f1000000-0000-0000-0000-000000000004','pending',NOW());
SELECT public.expire_mobile_ranking_items_v2();
SELECT pg_temp.assert_true(
  (SELECT status='expired' FROM public.matches WHERE player_one_id='f1000000-0000-0000-0000-000000000005' AND player_two_id='f1000000-0000-0000-0000-000000000006'),
  'scheduled cleanup must expire accepted matches at the deadline'
);
SELECT pg_temp.assert_true(
  (SELECT status='expired' FROM public.match_cancellation_requests WHERE requested_by='f1000000-0000-0000-0000-000000000005'),
  'scheduled cleanup must expire pending cancellation requests'
);
SELECT pg_temp.assert_true(
  (SELECT status='expired' FROM public.challenges WHERE challenger_id='f1000000-0000-0000-0000-000000000005' AND opponent_id='f1000000-0000-0000-0000-000000000004'),
  'scheduled cleanup must expire unanswered challenges'
);

-- The current pair limit remains enforced after finalization.
INSERT INTO public.matches(player_one_id,player_two_id,status,source,ranked,ranked_day,winner_id,player_one_score,player_two_score,confirmed_at,finalized_at)
SELECT 'f1000000-0000-0000-0000-000000000005','f1000000-0000-0000-0000-000000000006',
  'confirmed','challenge',TRUE,public.club_ranked_day_v3(),'f1000000-0000-0000-0000-000000000005',11,9,NOW(),NOW()
FROM generate_series(1,3);
SELECT pg_temp.assert_true(
  NOT public.check_daily_match_limit('f1000000-0000-0000-0000-000000000005','f1000000-0000-0000-0000-000000000006'),
  'the daily pair cap must reject match 4'
);

-- An unrelated authenticated user cannot read cancellation history.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', TRUE);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=0 FROM public.match_cancellation_requests),
  'RLS must hide cancellation requests from non-participants'
);
RESET ROLE;

ROLLBACK;
