-- Queue lifecycle, outcome, deadline, v4 forward-swap, audit, and security coverage.
-- Run only against a disposable database after all migrations. Everything rolls back.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  to_regprocedure('public.beaver_queue_health_v3()') IS NOT NULL
  AND has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_respond_swap_v1(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.beaver_queue_report_v1(uuid,integer,integer)','EXECUTE')
  AND NOT has_function_privilege('anon','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE'),
  'v3 RPC grants must expose outcome and swap actions only to authenticated users'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('fc000000-0000-4000-8000-000000000001'::UUID,'queue-v3-a@example.test','Queue V3 A'),
  ('fc000000-0000-4000-8000-000000000002'::UUID,'queue-v3-b@example.test','Queue V3 B'),
  ('fc000000-0000-4000-8000-000000000003'::UUID,'queue-v3-c@example.test','Queue V3 C'),
  ('fc000000-0000-4000-8000-000000000004'::UUID,'queue-v3-d@example.test','Queue V3 D'),
  ('fc000000-0000-4000-8000-000000000005'::UUID,'queue-v3-e@example.test','Queue V3 E'),
  ('fc000000-0000-4000-8000-000000000006'::UUID,'queue-v3-admin@example.test','Queue V3 Admin')
) fixtures(id,email,name);

INSERT INTO public.user_roles(user_id,role)
VALUES('fc000000-0000-4000-8000-000000000006','admin')
ON CONFLICT(user_id) DO UPDATE SET role='admin';

DELETE FROM public.beaver_queue_game_corrections;
DELETE FROM public.beaver_queue_swap_requests;
DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET phase='idle',king_id=NULL,challenger_id=NULL,
  call_expires_at=NULL,game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW() WHERE id=1;
SELECT setval('public.beaver_queue_position_seq',1,FALSE);

CREATE TEMP TABLE queue_v3_baseline AS
SELECT (SELECT COUNT(*) FROM public.matches) matches,
       (SELECT COUNT(*) FROM public.rating_events) rating_events,
       (SELECT COUNT(*) FROM public.challenges) challenges;

-- Historical scored rows remain valid and readable after scores became nullable.
INSERT INTO public.beaver_queue_games(
  id,king_id,challenger_id,king_name,challenger_name,king_score,challenger_score,
  winner_id,loser_id,reported_by,status,completed_at
) VALUES(
  'fc100000-0000-4000-8000-000000000001',
  'fc000000-0000-4000-8000-000000000001','fc000000-0000-4000-8000-000000000002',
  'Queue V3 A','Queue V3 B',11,8,'fc000000-0000-4000-8000-000000000001',
  'fc000000-0000-4000-8000-000000000002','fc000000-0000-4000-8000-000000000001',
  'completed',NOW()-INTERVAL '1 day'
);
SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.beaver_queue_games WHERE id='fc100000-0000-4000-8000-000000000001'
    AND king_score=11 AND challenger_score=8 AND loser_id='fc000000-0000-4000-8000-000000000002'),
  'historical scored queue results must remain readable'
);
DO $$
BEGIN
  INSERT INTO public.beaver_queue_games(
    id,king_id,challenger_id,king_name,challenger_name,king_score,challenger_score,
    winner_id,loser_id,reported_by,status
  ) VALUES(
    'fc100000-0000-4000-8000-000000000002',
    'fc000000-0000-4000-8000-000000000001','fc000000-0000-4000-8000-000000000002',
    'Queue V3 A','Queue V3 B',11,NULL,'fc000000-0000-4000-8000-000000000001',
    'fc000000-0000-4000-8000-000000000002','fc000000-0000-4000-8000-000000000001','completed'
  );
  RAISE EXCEPTION 'Expected partial-score constraint rejection';
EXCEPTION WHEN check_violation THEN NULL;
END;
$$;

-- A holds, B is called, and C/D wait.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000003',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000004',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_confirm_v1();
RESET ROLE;

CREATE TEMP TABLE queue_v3_game_one AS SELECT game_id id FROM public.beaver_queue_table WHERE id=1;
GRANT SELECT ON queue_v3_game_one TO authenticated;
SELECT pg_temp.assert_true(
  (SELECT phase='playing' AND king_id='fc000000-0000-4000-8000-000000000001'
    AND challenger_id='fc000000-0000-4000-8000-000000000002' FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT COUNT(*)=2 FROM public.beaver_queue_members WHERE status='playing'),
  'check-in must start one game for two different accounts'
);

-- A nonparticipant cannot report; A reporting "lost" derives B as winner.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000005',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_report_outcome_v2((SELECT id FROM queue_v3_game_one),'won');
  RAISE EXCEPTION 'Expected nonparticipant rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected nonparticipant rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%only players%' THEN RAISE; END IF;
END;
$$;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_report_outcome_v2((SELECT id FROM queue_v3_game_one),'lost');
-- Identical network retry is idempotent.
SELECT pg_temp.assert_true(
  public.beaver_queue_report_outcome_v2((SELECT id FROM queue_v3_game_one),'lost')->>'idempotent'='true',
  'an identical outcome retry must be idempotent'
);
DO $$
BEGIN
  PERFORM public.beaver_queue_report_outcome_v2((SELECT id FROM queue_v3_game_one),'won');
  RAISE EXCEPTION 'Expected conflicting retry rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected conflicting retry rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%administrator%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=1 FROM public.beaver_queue_games WHERE id=(SELECT id FROM queue_v3_game_one)
    AND status='completed' AND winner_id='fc000000-0000-4000-8000-000000000002'
    AND loser_id='fc000000-0000-4000-8000-000000000001'
    AND king_score IS NULL AND challenger_score IS NULL)
  AND (SELECT phase='called' AND king_id='fc000000-0000-4000-8000-000000000002'
    AND challenger_id='fc000000-0000-4000-8000-000000000003' FROM public.beaver_queue_table WHERE id=1),
  'lost must derive the other participant as winner and immediately call the next player'
);

-- Challenger C reporting "won" derives C as winner.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000003',TRUE);
SELECT public.beaver_queue_confirm_v1();
SELECT public.beaver_queue_report_outcome_v2((SELECT game_id FROM public.beaver_queue_table WHERE id=1),'won');
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT king_id='fc000000-0000-4000-8000-000000000003'
    AND challenger_id='fc000000-0000-4000-8000-000000000004' AND phase='called'
    FROM public.beaver_queue_table WHERE id=1),
  'won must derive the reporting challenger as winner and preserve winner-stays rotation'
);

SELECT pg_temp.assert_true(
  (SELECT COUNT(*) FROM public.matches)=(SELECT matches FROM queue_v3_baseline)
  AND (SELECT COUNT(*) FROM public.rating_events)=(SELECT rating_events FROM queue_v3_baseline)
  AND (SELECT COUNT(*) FROM public.challenges)=(SELECT challenges FROM queue_v3_baseline),
  'queue outcomes must not touch ranked matches, ratings, challenges, or limits'
);

-- Build a stable called table with three waiting users for swap coverage.
DELETE FROM public.beaver_queue_swap_requests;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET phase='idle',king_id=NULL,challenger_id=NULL,
  call_expires_at=NULL,game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW() WHERE id=1;
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fc000000-0000-4000-8000-000000000001','Queue V3 A','king',101,NOW(),NOW()),
 ('fc000000-0000-4000-8000-000000000002','Queue V3 B','called',102,NOW(),NOW()),
 ('fc000000-0000-4000-8000-000000000003','Queue V3 C','waiting',103,NOW(),NOW()),
 ('fc000000-0000-4000-8000-000000000004','Queue V3 D','waiting',104,NOW(),NOW()),
 ('fc000000-0000-4000-8000-000000000005','Queue V3 E','waiting',105,NOW(),NOW());
UPDATE public.beaver_queue_table SET phase='called',king_id='fc000000-0000-4000-8000-000000000001',
  challenger_id='fc000000-0000-4000-8000-000000000002',call_expires_at=NOW()+INTERVAL '1 minute',
  updated_at=NOW() WHERE id=1;

SET LOCAL ROLE authenticated;
-- A player behind cannot initiate a swap with someone ahead.
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000005',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_request_swap_v1('fc000000-0000-4000-8000-000000000003');
  RAISE EXCEPTION 'Expected reverse swap rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected reverse swap rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%behind you%' THEN RAISE; END IF;
END;
$$;
DO $$
BEGIN
  PERFORM public.beaver_queue_request_swap_v1('fc000000-0000-4000-8000-000000000005');
  RAISE EXCEPTION 'Expected self-swap rejection';
EXCEPTION WHEN OTHERS THEN IF SQLERRM='Expected self-swap rejection' THEN RAISE; END IF; END;
$$;

-- C is ahead and can offer E a swap; conflicting requests are rejected.
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000003',TRUE);
SELECT public.beaver_queue_request_swap_v1('fc000000-0000-4000-8000-000000000005');
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000004',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_request_swap_v1('fc000000-0000-4000-8000-000000000005');
  RAISE EXCEPTION 'Expected conflicting swap rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected conflicting swap rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%pending swap%' THEN RAISE; END IF;
END;
$$;
-- Only target E accepts, atomically exchanging 103 and 105.
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000005',TRUE);
SELECT public.beaver_queue_respond_swap_v1(
  (SELECT id FROM public.beaver_queue_swap_requests WHERE status='pending'),'accept'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT queue_position=105 FROM public.beaver_queue_members WHERE user_id='fc000000-0000-4000-8000-000000000003')
  AND (SELECT queue_position=103 FROM public.beaver_queue_members WHERE user_id='fc000000-0000-4000-8000-000000000005')
  AND (SELECT COUNT(*)=COUNT(DISTINCT queue_position) FROM public.beaver_queue_members),
  'accepted swaps must exchange positions atomically without duplicates'
);

-- Decline and expiry preserve positions.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000004',TRUE);
SELECT public.beaver_queue_request_swap_v1('fc000000-0000-4000-8000-000000000003');
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000003',TRUE);
SELECT public.beaver_queue_respond_swap_v1(
  (SELECT id FROM public.beaver_queue_swap_requests WHERE status='pending'),'decline'
);
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000004',TRUE);
SELECT public.beaver_queue_request_swap_v1('fc000000-0000-4000-8000-000000000003');
RESET ROLE;
UPDATE public.beaver_queue_swap_requests SET expires_at=NOW()-INTERVAL '1 second' WHERE status='pending';
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  NOT EXISTS(SELECT 1 FROM public.beaver_queue_swap_requests WHERE status='pending')
  AND EXISTS(SELECT 1 FROM public.beaver_queue_swap_requests WHERE status='declined')
  AND EXISTS(SELECT 1 FROM public.beaver_queue_swap_requests WHERE status='expired'),
  'declined and expired swaps must leave no pending request'
);

-- Leaving cancels related pending requests.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000005',TRUE);
SELECT public.beaver_queue_request_swap_v1('fc000000-0000-4000-8000-000000000004');
SELECT public.beaver_queue_leave_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  NOT EXISTS(SELECT 1 FROM public.beaver_queue_swap_requests WHERE status='pending'
    AND 'fc000000-0000-4000-8000-000000000005' IN(requester_id,target_id)),
  'leaving the waiting list must cancel related swap requests'
);

-- A 10-minute game is abandoned, both players leave, and waiting players advance.
DELETE FROM public.beaver_queue_swap_requests;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET phase='idle',king_id=NULL,challenger_id=NULL,
  call_expires_at=NULL,game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,updated_at=NOW() WHERE id=1;
INSERT INTO public.beaver_queue_members(user_id,display_name,status,queue_position,joined_at,updated_at) VALUES
 ('fc000000-0000-4000-8000-000000000001','Queue V3 A','playing',201,NOW(),NOW()),
 ('fc000000-0000-4000-8000-000000000002','Queue V3 B','playing',202,NOW(),NOW()),
 ('fc000000-0000-4000-8000-000000000003','Queue V3 C','waiting',203,NOW(),NOW()),
 ('fc000000-0000-4000-8000-000000000004','Queue V3 D','waiting',204,NOW(),NOW());
UPDATE public.beaver_queue_table SET phase='playing',king_id='fc000000-0000-4000-8000-000000000001',
  challenger_id='fc000000-0000-4000-8000-000000000002',call_expires_at=NULL,
  game_id='fc200000-0000-4000-8000-000000000001',game_started_at=NOW()-INTERVAL '11 minutes 1 second',
  game_expires_at=NOW()-INTERVAL '1 minute 1 second',
  updated_at=NOW() WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.beaver_queue_games WHERE id='fc200000-0000-4000-8000-000000000001'
    AND status='abandoned' AND winner_id IS NULL AND loser_id IS NULL AND reported_by IS NULL)
  AND (SELECT status='left' FROM public.beaver_queue_members WHERE user_id='fc000000-0000-4000-8000-000000000001')
  AND (SELECT status='left' FROM public.beaver_queue_members WHERE user_id='fc000000-0000-4000-8000-000000000002')
  AND (SELECT phase='called' AND king_id='fc000000-0000-4000-8000-000000000003'
    AND challenger_id='fc000000-0000-4000-8000-000000000004' FROM public.beaver_queue_table WHERE id=1),
  'the trusted worker must audit a 10-minute game and advance both waiting players'
);

-- Non-admin clients cannot see abandoned audit rows.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000003',TRUE);
SELECT pg_temp.assert_true(
  NOT EXISTS(SELECT 1 FROM public.beaver_queue_games WHERE id='fc200000-0000-4000-8000-000000000001'),
  'abandoned games must be hidden from ordinary queue activity readers'
);
RESET ROLE;

-- Admin correction writes an immutable audit record without touching live/ranked state.
CREATE TEMP TABLE queue_v3_live_before AS SELECT row_to_json(t)::JSONB value FROM public.beaver_queue_table t WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000003',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_admin_correct_game_v1(
    (SELECT id FROM queue_v3_game_one),'fc000000-0000-4000-8000-000000000001','not an admin'
  );
  RAISE EXCEPTION 'Expected non-admin correction rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected non-admin correction rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%administrator%' THEN RAISE; END IF;
END;
$$;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000006',TRUE);
SELECT public.beaver_queue_admin_correct_game_v1(
  (SELECT id FROM queue_v3_game_one),'fc000000-0000-4000-8000-000000000001','Verified report was reversed'
);
DO $$
BEGIN
  PERFORM public.beaver_queue_admin_correct_game_v1(
    'fc200000-0000-4000-8000-000000000001','fc000000-0000-4000-8000-000000000001','cannot correct abandonment'
  );
  RAISE EXCEPTION 'Expected abandoned correction rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected abandoned correction rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%abandoned%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;

SELECT pg_temp.assert_true(
  EXISTS(SELECT 1 FROM public.beaver_queue_games WHERE id=(SELECT id FROM queue_v3_game_one)
    AND winner_id='fc000000-0000-4000-8000-000000000001'
    AND loser_id='fc000000-0000-4000-8000-000000000002' AND corrected_at IS NOT NULL)
  AND EXISTS(SELECT 1 FROM public.beaver_queue_game_corrections WHERE game_id=(SELECT id FROM queue_v3_game_one)
    AND old_winner_id='fc000000-0000-4000-8000-000000000002'
    AND new_winner_id='fc000000-0000-4000-8000-000000000001'
    AND reason='Verified report was reversed')
  AND (SELECT row_to_json(t)::JSONB FROM public.beaver_queue_table t WHERE id=1)=(SELECT value FROM queue_v3_live_before)
  AND (SELECT COUNT(*) FROM public.matches)=(SELECT matches FROM queue_v3_baseline)
  AND (SELECT COUNT(*) FROM public.rating_events)=(SELECT rating_events FROM queue_v3_baseline),
  'admin correction must update history and audit only, never live queue or ranked data'
);

-- Direct writes remain denied.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fc000000-0000-4000-8000-000000000003',TRUE);
DO $$
BEGIN
  UPDATE public.beaver_queue_members SET queue_position=999 WHERE user_id='fc000000-0000-4000-8000-000000000003';
  RAISE EXCEPTION 'Expected direct queue write rejection';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END;
$$;
DO $$
BEGIN
  INSERT INTO public.beaver_queue_swap_requests(requester_id,target_id,requester_position,target_position)
  VALUES('fc000000-0000-4000-8000-000000000003','fc000000-0000-4000-8000-000000000004',203,204);
  RAISE EXCEPTION 'Expected direct swap write rejection';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END;
$$;
SELECT pg_temp.assert_true(
  public.beaver_queue_health_v4() @> jsonb_build_object(
    'version','20261103_04','initialized',TRUE,'outcome_granted',TRUE,'swap_granted',TRUE
  ),
  'health v4 must report migration version and action grants'
);
RESET ROLE;

ROLLBACK;
