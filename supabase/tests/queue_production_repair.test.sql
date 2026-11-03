-- Run against a disposable database after every migration. All changes roll back.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  to_regprocedure('public.beaver_queue_health_v2()') IS NOT NULL
  AND has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE')
  AND NOT has_function_privilege('anon','public.beaver_queue_join_v1()','EXECUTE'),
  'repair migration and least-privilege RPC grants must be installed'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
VALUES
  ('fb000000-0000-4000-8000-000000000001','queue-repair-a@example.test',jsonb_build_object('display_name','Repair Alpha'),NOW(),NOW()),
  ('fb000000-0000-4000-8000-000000000002','queue-repair-b@example.test',jsonb_build_object('display_name','Repair Beta'),NOW(),NOW());

DELETE FROM public.beaver_queue_games;
DELETE FROM public.beaver_queue_members;
UPDATE public.beaver_queue_table SET phase='idle',king_id=NULL,challenger_id=NULL,
  call_expires_at=NULL,game_id=NULL,game_started_at=NULL,updated_at=NOW() WHERE id=1;

-- A heartbeat for an authenticated non-member is a successful no-op.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_heartbeat_v1();
SELECT public.beaver_queue_join_v1();
SELECT public.beaver_queue_join_v1();
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT COUNT(*)=1 FROM public.beaver_queue_members WHERE user_id='fb000000-0000-4000-8000-000000000001')
  AND (SELECT status='king' FROM public.beaver_queue_members WHERE user_id='fb000000-0000-4000-8000-000000000001')
  AND (SELECT king_id='fb000000-0000-4000-8000-000000000001' AND phase='idle' FROM public.beaver_queue_table WHERE id=1),
  'joining twice must be idempotent and seat exactly one holder'
);

UPDATE public.beaver_queue_members SET updated_at=NOW()-INTERVAL '30 seconds'
WHERE user_id='fb000000-0000-4000-8000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000001',TRUE);
SELECT public.beaver_queue_heartbeat_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT updated_at>NOW()-INTERVAL '5 seconds' FROM public.beaver_queue_members WHERE user_id='fb000000-0000-4000-8000-000000000001'),
  'heartbeat must refresh an active member timestamp'
);

-- A second distinct player is called; the singleton lock and PK prevent self
-- matches and duplicate claims.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000002',TRUE);
SELECT public.beaver_queue_join_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='called'
      AND king_id='fb000000-0000-4000-8000-000000000001'
      AND challenger_id='fb000000-0000-4000-8000-000000000002'
      AND king_id<>challenger_id
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT COUNT(*)=2 FROM public.beaver_queue_members WHERE status IN ('king','called')),
  'two accounts must match into one holder and one distinct called player'
);

-- Direct writes stay blocked by grants/RLS.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000002',TRUE);
DO $$
BEGIN
  UPDATE public.beaver_queue_members SET status='king'
  WHERE user_id='fb000000-0000-4000-8000-000000000002';
  RAISE EXCEPTION 'Expected direct queue write rejection';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END;
$$;
SELECT public.beaver_queue_leave_v1();
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND king_id='fb000000-0000-4000-8000-000000000001'
      AND challenger_id IS NULL FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='left' FROM public.beaver_queue_members WHERE user_id='fb000000-0000-4000-8000-000000000002'),
  'leaving a called spot must preserve a valid reusable queue'
);

-- A holder with no heartbeat is removed by the trusted worker.
UPDATE public.beaver_queue_members SET updated_at=NOW()-INTERVAL '3 minutes'
WHERE user_id='fb000000-0000-4000-8000-000000000001';
SET LOCAL ROLE service_role;
SELECT public.beaver_queue_advance_expired_v1();
RESET ROLE;
SELECT pg_temp.assert_true(
  (SELECT phase='idle' AND king_id IS NULL AND challenger_id IS NULL FROM public.beaver_queue_table WHERE id=1)
  AND NOT EXISTS(SELECT 1 FROM public.beaver_queue_members WHERE status IN ('waiting','called','king','playing')),
  'stale non-playing entries must be cleaned without creating an invalid match'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fb000000-0000-4000-8000-000000000001',TRUE);
SELECT pg_temp.assert_true(
  public.beaver_queue_health_v2() @> jsonb_build_object(
    'version','20261103_02','initialized',TRUE,
    'heartbeat_granted',TRUE,'join_granted',TRUE
  ),
  'health RPC must identify the deployed repair version and grants'
);
RESET ROLE;

SELECT pg_temp.assert_true(
  NOT EXISTS(
    SELECT 1 FROM public.matches
    WHERE player_one_id::TEXT LIKE 'fb000000-%' OR player_two_id::TEXT LIKE 'fb000000-%'
  ),
  'queue repair must remain isolated from ranked matches and challenge limits'
);

ROLLBACK;
