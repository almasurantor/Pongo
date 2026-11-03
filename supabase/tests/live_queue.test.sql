-- Run only against a disposable Supabase database after all migrations.
-- Fixtures and queue state changes are rolled back at the end.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
SELECT id,email,jsonb_build_object('display_name',name),NOW(),NOW()
FROM (VALUES
  ('fa000000-0000-0000-0000-000000000001'::UUID,'queue-a@example.test','Queue A'),
  ('fa000000-0000-0000-0000-000000000002'::UUID,'queue-b@example.test','Queue B'),
  ('fa000000-0000-0000-0000-000000000003'::UUID,'queue-c@example.test','Queue C'),
  ('fa000000-0000-0000-0000-000000000004'::UUID,'queue-d@example.test','Queue D'),
  ('fa000000-0000-0000-0000-000000000005'::UUID,'queue-e@example.test','Queue E')
) fixtures(id,email,name);

DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,updated_at=NOW()
WHERE id=1;
SELECT setval('public.beaver_queue_position_seq',1,FALSE);
CREATE TEMP TABLE queue_test_ids(id UUID PRIMARY KEY) ON COMMIT DROP;
GRANT SELECT ON queue_test_ids TO authenticated;

-- A is immediately seated. Rejoining is idempotent and cannot move their turn.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000001',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT public.beaver_queue_join_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT king_id='fa000000-0000-0000-0000-000000000001' AND phase='idle'
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT COUNT(*)=1 AND MIN(queue_position)=1 FROM public.beaver_queue_members),
  'the first player must hold the table and duplicate join must be idempotent'
);

-- B is called and C waits behind B in FIFO order.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000002',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000003',TRUE);
SELECT public.beaver_queue_join_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='called'
      AND challenger_id='fa000000-0000-0000-0000-000000000002'
      AND call_expires_at>NOW()
      AND call_expires_at<=NOW()+INTERVAL '61 seconds'
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='waiting' FROM public.beaver_queue_members
       WHERE user_id='fa000000-0000-0000-0000-000000000003'),
  'the first challenger must receive a server-timed call while later players wait'
);

-- B checks in. Only either active participant may report an outcome.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000002',TRUE);
SELECT public.beaver_queue_confirm_v1();
RESET ROLE;
INSERT INTO queue_test_ids SELECT game_id FROM public.beaver_queue_table WHERE id=1;
SELECT pg_temp.assert_true(
  (SELECT phase='playing' AND game_id IS NOT NULL AND call_expires_at IS NULL
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT COUNT(*)=2 FROM public.beaver_queue_members WHERE status='playing'),
  'confirmation must start one game with both participants marked playing'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000004',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_report_outcome_v2((SELECT id FROM queue_test_ids),'won');
  RAISE EXCEPTION 'Expected unrelated outcome reporter rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected unrelated outcome reporter rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%only players%' THEN RAISE; END IF;
END;
$$;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000001',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_report_outcome_v2((SELECT id FROM queue_test_ids),'maybe');
  RAISE EXCEPTION 'Expected invalid outcome rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected invalid outcome rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%outcome must be%' THEN RAISE; END IF;
END;
$$;
SELECT public.beaver_queue_report_outcome_v2((SELECT id FROM queue_test_ids),'won');
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT phase='called'
      AND king_id='fa000000-0000-0000-0000-000000000001'
      AND challenger_id='fa000000-0000-0000-0000-000000000003'
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='left' FROM public.beaver_queue_members
       WHERE user_id='fa000000-0000-0000-0000-000000000002')
  AND (SELECT COUNT(*)=1 FROM public.beaver_queue_games)
  AND EXISTS(SELECT 1 FROM public.beaver_queue_games
       WHERE winner_id='fa000000-0000-0000-0000-000000000001'),
  'the winner must stay, the loser leave, and the next FIFO player be called'
);

-- The finalized game cannot be submitted twice, even by its other participant.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000002',TRUE);
DO $$
BEGIN
  PERFORM public.beaver_queue_report_outcome_v2((SELECT id FROM queue_test_ids),'won');
  RAISE EXCEPTION 'Expected duplicate finalization rejection';
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Expected duplicate finalization rejection' THEN RAISE; END IF;
  IF SQLERRM NOT ILIKE '%administrator%' THEN RAISE; END IF;
END;
$$;
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=1 FROM public.beaver_queue_games),
  'a finalized game must retain exactly one result'
);

-- A trusted tick advances a deadline with every browser closed.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000004',TRUE);
SELECT public.beaver_queue_join_v1();
RESET ROLE;
UPDATE public.beaver_queue_table SET call_expires_at=NOW()-INTERVAL '1 second'
WHERE id=1;
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='called' AND king_id='fa000000-0000-0000-0000-000000000001'
      AND challenger_id='fa000000-0000-0000-0000-000000000004'
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='no_show' FROM public.beaver_queue_members
       WHERE user_id='fa000000-0000-0000-0000-000000000003'),
  'the server-side worker must skip an expired call and call the next player without a browser'
);

-- A called player can leave, then rejoin at the back and win the next game.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000004',TRUE);
SELECT public.beaver_queue_leave_v1();
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000002',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT public.beaver_queue_confirm_v1();
SELECT public.beaver_queue_report_outcome_v2(
  (SELECT game_id FROM public.beaver_queue_table WHERE id=1),'won'
);
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND king_id='fa000000-0000-0000-0000-000000000002'
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='left' FROM public.beaver_queue_members
       WHERE user_id='fa000000-0000-0000-0000-000000000001'),
  'a rejoined loser must go to the back and can become the next table holder by winning'
);

-- If the holder leaves between games, the called challenger becomes holder and
-- the next waiting player is called. A separate waiting player may leave safely.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000003',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000001',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000005',TRUE);
SELECT public.beaver_queue_join_v1();
SELECT public.beaver_queue_leave_v1();
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000002',TRUE);
SELECT public.beaver_queue_leave_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='called'
      AND king_id='fa000000-0000-0000-0000-000000000003'
      AND challenger_id='fa000000-0000-0000-0000-000000000001'
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='left' FROM public.beaver_queue_members
       WHERE user_id='fa000000-0000-0000-0000-000000000005'),
  'holder and waiting-player departures must preserve the remaining FIFO rotation'
);

-- Leaving the called seat and then the holder can make the queue completely empty.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000001',TRUE);
SELECT public.beaver_queue_leave_v1();
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000003',TRUE);
SELECT public.beaver_queue_leave_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND king_id IS NULL AND challenger_id IS NULL
      AND game_id IS NULL FROM public.beaver_queue_table WHERE id=1)
  AND NOT EXISTS(
    SELECT 1 FROM public.beaver_queue_members
    WHERE status IN ('waiting','called','king','playing')
  ),
  'all voluntary departures must leave a reusable empty queue'
);

-- Queue play is isolated from ranked matches, rating events, and profile stats.
SELECT pg_temp.assert_true(
  NOT EXISTS(
    SELECT 1 FROM public.matches
    WHERE player_one_id::TEXT LIKE 'fa000000-%' OR player_two_id::TEXT LIKE 'fa000000-%'
  )
  AND NOT EXISTS(
    SELECT 1 FROM public.rating_events WHERE player_id::TEXT LIKE 'fa000000-%'
  )
  AND NOT EXISTS(
    SELECT 1 FROM public.profiles
    WHERE id::TEXT LIKE 'fa000000-%'
      AND (current_elo<>500 OR total_wins<>0 OR total_losses<>0)
  ),
  'queue games must never touch ranked history, ELO, or ranked statistics'
);

-- Authenticated clients read public queue state but cannot mutate tables.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa000000-0000-0000-0000-000000000004',TRUE);
SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=5 FROM public.beaver_queue_members)
  AND (SELECT COUNT(*)=2 FROM public.beaver_queue_games),
  'authenticated reconnects must be able to rebuild queue and recent-game state'
);
DO $$
BEGIN
  UPDATE public.beaver_queue_table SET phase='idle' WHERE id=1;
  RAISE EXCEPTION 'Expected direct queue mutation rejection';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END;
$$;
RESET ROLE;

SELECT pg_temp.assert_true(
  has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_leave_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_confirm_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.beaver_queue_report_v1(uuid,integer,integer)','EXECUTE')
  AND NOT has_function_privilege('anon','public.beaver_queue_join_v1()','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.beaver_queue_advance_internal_v1()','EXECUTE')
  AND has_function_privilege('service_role','public.beaver_queue_advance_expired_v1()','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.beaver_queue_advance_expired_v1()','EXECUTE'),
  'queue RPC grants must expose only participant actions and the trusted expiry entry point'
);

ROLLBACK;
