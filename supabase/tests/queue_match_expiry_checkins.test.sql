-- Queue V6 explicit deadline and challenger check-in coverage.
-- Run only against a disposable database after all migrations. Everything rolls back.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  to_regprocedure('public.beaver_queue_health_v7()') IS NOT NULL
  AND EXISTS(SELECT 1 FROM pg_catalog.pg_trigger trigger_row
    WHERE trigger_row.tgrelid='public.beaver_queue_table'::regclass
      AND trigger_row.tgname='beaver_queue_autoconfirm_holder_v1'
      AND NOT trigger_row.tgisinternal)
  AND has_function_privilege('authenticated','public.beaver_queue_tick_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_confirm_v1()','EXECUTE')
  AND NOT has_function_privilege('anon','public.beaver_queue_confirm_v1()','EXECUTE'),
  'v6 must expose check-in and client synchronization only to authenticated users'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('fc000000-0000-4000-8000-000000000001'::UUID,'queue-v6-a@example.test','Queue V6 A'),
  ('fc000000-0000-4000-8000-000000000002'::UUID,'queue-v6-b@example.test','Queue V6 B'),
  ('fc000000-0000-4000-8000-000000000003'::UUID,'queue-v6-c@example.test','Queue V6 C')
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

CREATE TEMP TABLE queue_v6_ranked_baseline AS
SELECT (SELECT COUNT(*) FROM public.matches) matches,
       (SELECT COUNT(*) FROM public.rating_events) rating_events;

-- Assign A and B. The holder is already present; only the challenger checks in.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_join_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='called' AND king_id='fc000000-0000-4000-8000-000000000001'
    AND challenger_id='fc000000-0000-4000-8000-000000000002'
    AND call_expires_at IS NOT NULL AND king_confirmed_at IS NOT NULL
    AND challenger_confirmed_at IS NULL
    FROM public.beaver_queue_table WHERE id=1),
  'assigning a pair must start one server deadline with only the challenger pending'
);

-- The V7 trigger must repair any function that tries to clear holder presence.
UPDATE public.beaver_queue_table SET king_confirmed_at=NULL WHERE id=1;
SELECT pg_temp.assert_true(
  (SELECT king_confirmed_at IS NOT NULL FROM public.beaver_queue_table WHERE id=1),
  'a called table must never require the existing holder to check in again'
);

-- A holder confirmation is unnecessary and must not alter or extend the call.
CREATE TEMP TABLE queue_v6_call_deadline AS
SELECT call_expires_at FROM public.beaver_queue_table WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_confirm_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='called' AND king_confirmed_at IS NOT NULL
    AND challenger_confirmed_at IS NULL AND game_id IS NULL
    AND call_expires_at=(SELECT call_expires_at FROM queue_v6_call_deadline)
    FROM public.beaver_queue_table WHERE id=1),
  'the holder must remain present without changing the challenger deadline'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_confirm_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='playing' AND game_id IS NOT NULL
    AND game_expires_at>game_started_at
    AND game_expires_at=game_started_at+INTERVAL '10 minutes'
    AND king_confirmed_at IS NULL AND challenger_confirmed_at IS NULL
    FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='playing' FROM public.beaver_queue_members
    WHERE user_id='fc000000-0000-4000-8000-000000000001')
  AND (SELECT status='playing' FROM public.beaver_queue_members
    WHERE user_id='fc000000-0000-4000-8000-000000000002'),
  'the match must start when the incoming challenger confirms'
);

-- Add a waiting player, then expire the active game exactly at its deadline.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000003',TRUE);
SELECT public.beaver_queue_join_v1();
RESET ROLE;
CREATE TEMP TABLE queue_v6_game AS
SELECT game_id FROM public.beaver_queue_table WHERE id=1;
GRANT SELECT ON queue_v6_game TO authenticated;
UPDATE public.beaver_queue_table SET
  game_expires_at=clock_timestamp()-INTERVAL '60 seconds',
  overtime_prompt_expires_at=clock_timestamp()
WHERE id=1;

-- A result at/after the authoritative deadline is rejected under the same row lock.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000001',TRUE);
DO $$
DECLARE expired_game UUID;
BEGIN
  SELECT game_id INTO expired_game FROM queue_v6_game;
  PERFORM public.beaver_queue_report_outcome_v2(expired_game,'won');
  RAISE EXCEPTION 'Expected deadline rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected deadline rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%deadline has expired%' THEN RAISE; END IF;
END;
$$;
SELECT public.beaver_queue_tick_v1();
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND king_id='fc000000-0000-4000-8000-000000000003'
    AND challenger_id IS NULL AND game_id IS NULL AND game_expires_at IS NULL
    FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fc000000-0000-4000-8000-000000000001')
  AND (SELECT status='left' FROM public.beaver_queue_members
    WHERE user_id='fc000000-0000-4000-8000-000000000002')
  AND EXISTS(SELECT 1 FROM public.beaver_queue_games game CROSS JOIN queue_v6_game snapshot
    WHERE game.id=snapshot.game_id AND game.status='abandoned'
      AND game.winner_id IS NULL AND game.loser_id IS NULL AND game.reported_by IS NULL),
  'deadline expiry must remove both players, record no outcome, and advance the waiting player'
);

-- Repeated workers are idempotent and cannot remove the newly advanced holder.
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND king_id='fc000000-0000-4000-8000-000000000003'
    FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT COUNT(*)=1 FROM public.beaver_queue_games game CROSS JOIN queue_v6_game snapshot
    WHERE game.id=snapshot.game_id),
  'simultaneous or repeated expiration requests must be idempotent'
);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*) FROM public.matches)=(SELECT matches FROM queue_v6_ranked_baseline)
  AND (SELECT COUNT(*) FROM public.rating_events)=(SELECT rating_events FROM queue_v6_ranked_baseline),
  'queue expiration must not alter ranked matches, ratings, or statistics'
);

-- A confirmed player survives check-in timeout; the unconfirmed player does not.
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW()
WHERE id=1;
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fc000000-0000-4000-8000-000000000001','Queue V6 A','king',601,NOW(),NOW()),
 ('fc000000-0000-4000-8000-000000000002','Queue V6 B','called',602,NOW(),NOW());
UPDATE public.beaver_queue_table SET
  phase='called',king_id='fc000000-0000-4000-8000-000000000001',
  challenger_id='fc000000-0000-4000-8000-000000000002',
  call_expires_at=clock_timestamp()+INTERVAL '60 seconds',
  king_confirmed_at=clock_timestamp(),challenger_confirmed_at=NULL
WHERE id=1;
UPDATE public.beaver_queue_table SET call_expires_at=clock_timestamp() WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND king_id='fc000000-0000-4000-8000-000000000001'
    AND king_confirmed_at IS NULL AND challenger_confirmed_at IS NULL
    FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='king' FROM public.beaver_queue_members
    WHERE user_id='fc000000-0000-4000-8000-000000000001')
  AND (SELECT status='no_show' FROM public.beaver_queue_members
    WHERE user_id='fc000000-0000-4000-8000-000000000002'),
  'check-in timeout must remove only the unconfirmed assigned player'
);

ROLLBACK;
