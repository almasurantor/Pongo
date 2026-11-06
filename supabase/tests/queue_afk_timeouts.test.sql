-- Queue V5 solo timeout and in-game AFK coverage.
-- Run only against a disposable database after all migrations. Everything rolls back.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  to_regprocedure('public.beaver_queue_health_v5()') IS NOT NULL
  AND has_function_privilege('authenticated','public.beaver_queue_report_afk_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_confirm_presence_v1()','EXECUTE')
  AND NOT has_function_privilege('anon','public.beaver_queue_report_afk_v1()','EXECUTE'),
  'v5 must expose AFK actions only to authenticated users'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('fd000000-0000-4000-8000-000000000001'::UUID,'queue-v5-a@example.test','Queue V5 A'),
  ('fd000000-0000-4000-8000-000000000002'::UUID,'queue-v5-b@example.test','Queue V5 B'),
  ('fd000000-0000-4000-8000-000000000003'::UUID,'queue-v5-c@example.test','Queue V5 C')
) fixtures(id,email,name);

DELETE FROM public.beaver_queue_swap_requests;
DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;

CREATE TEMP TABLE queue_v5_ranked_baseline AS
SELECT (SELECT COUNT(*) FROM public.matches) matches,
       (SELECT COUNT(*) FROM public.rating_events) rating_events;

-- A solo holder gets exactly one server deadline, independent of heartbeats.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fd000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_join_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND king_id='fd000000-0000-4000-8000-000000000001'
    AND solo_expires_at IS NOT NULL FROM public.beaver_queue_table WHERE id=1),
  'joining alone must start a 60-second server deadline'
);
UPDATE public.beaver_queue_members SET updated_at=clock_timestamp()
WHERE user_id='fd000000-0000-4000-8000-000000000001';
UPDATE public.beaver_queue_table SET solo_expires_at=clock_timestamp()-INTERVAL '1 second'
WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT king_id IS NULL AND solo_expires_at IS NULL FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fd000000-0000-4000-8000-000000000001'),
  'the trusted worker must remove a solo holder even when their heartbeat is fresh'
);

-- Build an active match with C waiting.
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fd000000-0000-4000-8000-000000000001','Queue V5 A','playing',301,NOW(),NOW()),
 ('fd000000-0000-4000-8000-000000000002','Queue V5 B','playing',302,NOW(),NOW()),
 ('fd000000-0000-4000-8000-000000000003','Queue V5 C','waiting',303,NOW(),NOW());
UPDATE public.beaver_queue_table SET
  phase='playing',king_id='fd000000-0000-4000-8000-000000000001',
  challenger_id='fd000000-0000-4000-8000-000000000002',
  game_id='fd100000-0000-4000-8000-000000000001',game_started_at=NOW(),
  game_expires_at=NOW()+INTERVAL '10 minutes',updated_at=NOW()
WHERE id=1;

-- Only a participant can report, and the target can clear the check.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fd000000-0000-4000-8000-000000000003',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_report_afk_v1();
  RAISE EXCEPTION 'Expected nonparticipant AFK rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected nonparticipant AFK rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%active match participant%' THEN RAISE; END IF;
END;
$$;
SELECT set_config('request.jwt.claim.sub','fd000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_report_afk_v1();
DO $$
BEGIN
  PERFORM public.beaver_queue_report_afk_v1();
  RAISE EXCEPTION 'Expected duplicate AFK rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected duplicate AFK rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%already pending%' THEN RAISE; END IF;
END;
$$;
SELECT set_config('request.jwt.claim.sub','fd000000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_confirm_presence_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='playing' AND afk_reporter_id IS NULL AND afk_target_id IS NULL
    AND afk_expires_at IS NULL FROM public.beaver_queue_table WHERE id=1),
  'the reported opponent must be able to confirm presence without ending the game'
);

-- An unanswered report removes only the target and records no winner or loser.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fd000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_report_afk_v1();
RESET ROLE;
UPDATE public.beaver_queue_table SET afk_expires_at=clock_timestamp()-INTERVAL '1 second'
WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.beaver_queue_games
    WHERE id='fd100000-0000-4000-8000-000000000001' AND status='abandoned'
      AND winner_id IS NULL AND loser_id IS NULL AND reported_by IS NULL)
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fd000000-0000-4000-8000-000000000002')
  AND (SELECT phase='called' AND king_id='fd000000-0000-4000-8000-000000000001'
    AND challenger_id='fd000000-0000-4000-8000-000000000003'
    AND afk_reporter_id IS NULL AND afk_target_id IS NULL AND afk_expires_at IS NULL
    FROM public.beaver_queue_table WHERE id=1),
  'AFK expiry must keep the reporter, remove the target, clear the report, and call next'
);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*) FROM public.matches)=(SELECT matches FROM queue_v5_ranked_baseline)
  AND (SELECT COUNT(*) FROM public.rating_events)=(SELECT rating_events FROM queue_v5_ranked_baseline),
  'solo and AFK expiry must not affect ranked match or rating history'
);

-- If the game deadline elapsed before an AFK deadline, a delayed worker must
-- abandon both players instead of treating the later AFK check as decisive.
DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fd000000-0000-4000-8000-000000000001','Queue V5 A','playing',401,NOW(),NOW()),
 ('fd000000-0000-4000-8000-000000000002','Queue V5 B','playing',402,NOW(),NOW()),
 ('fd000000-0000-4000-8000-000000000003','Queue V5 C','waiting',403,NOW(),NOW());
UPDATE public.beaver_queue_table SET
  phase='playing',king_id='fd000000-0000-4000-8000-000000000001',
  challenger_id='fd000000-0000-4000-8000-000000000002',
  game_id='fd100000-0000-4000-8000-000000000002',
  game_started_at=clock_timestamp()-INTERVAL '12 minutes',
  game_expires_at=clock_timestamp()-INTERVAL '2 minutes',
  afk_reporter_id='fd000000-0000-4000-8000-000000000001',
  afk_target_id='fd000000-0000-4000-8000-000000000002',
  afk_expires_at=clock_timestamp()-INTERVAL '1 second',updated_at=NOW()
WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fd000000-0000-4000-8000-000000000001',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_report_outcome_v2(
    'fd100000-0000-4000-8000-000000000002','won'
  );
  RAISE EXCEPTION 'Expected expired outcome rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected expired outcome rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%deadline has expired%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.beaver_queue_games
    WHERE id='fd100000-0000-4000-8000-000000000002' AND status='abandoned')
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fd000000-0000-4000-8000-000000000001')
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fd000000-0000-4000-8000-000000000002')
  AND (SELECT king_id='fd000000-0000-4000-8000-000000000003'
    AND challenger_id IS NULL FROM public.beaver_queue_table WHERE id=1),
  'the earliest elapsed deadline must determine how an overdue game advances'
);

ROLLBACK;
