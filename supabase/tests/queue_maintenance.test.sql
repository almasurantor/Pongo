-- Browser-independent queue maintenance and scheduler health coverage.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(value BOOLEAN,message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(value,FALSE) THEN RAISE EXCEPTION 'Assertion failed: %',message; END IF;
END;
$$;

SELECT pg_temp.assert_true(
  to_regprocedure('public.run_pongo_queue_maintenance_v1()') IS NOT NULL
  AND to_regprocedure('public.run_pongo_ranked_maintenance_v1()') IS NOT NULL
  AND has_function_privilege('service_role','public.run_pongo_queue_maintenance_v1()','EXECUTE')
  AND has_function_privilege('service_role','public.run_pongo_ranked_maintenance_v1()','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.run_pongo_queue_maintenance_v1()','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.run_pongo_ranked_maintenance_v1()','EXECUTE')
  AND NOT has_function_privilege('anon','public.run_pongo_queue_maintenance_v1()','EXECUTE')
  AND NOT has_function_privilege('anon','public.run_pongo_ranked_maintenance_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.pongo_queue_maintenance_health_v1()','EXECUTE')
  AND has_function_privilege('authenticated','public.pongo_ranked_maintenance_health_v1()','EXECUTE')
  AND NOT has_function_privilege('anon','public.pongo_queue_maintenance_health_v1()','EXECUTE')
  AND NOT has_function_privilege('anon','public.pongo_ranked_maintenance_health_v1()','EXECUTE')
  AND NOT has_table_privilege('authenticated','public.pongo_maintenance_state','SELECT')
  AND NOT has_table_privilege('anon','public.pongo_maintenance_state','SELECT'),
  'only the trusted worker may run maintenance'
);

INSERT INTO auth.users(id,email,raw_user_meta_data,created_at,updated_at)
VALUES(
  'f9100000-0000-4000-8000-000000000001','queue-worker@example.test',
  '{"display_name":"Queue Worker Test"}'::JSONB,clock_timestamp(),clock_timestamp()
);

UPDATE public.beaver_queue_table SET
  phase='idle',king_id=NULL,challenger_id=NULL,call_expires_at=NULL,
  game_id=NULL,game_started_at=NULL,game_expires_at=NULL,
  king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
  afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
  updated_at=clock_timestamp()
WHERE id=1;
DELETE FROM public.beaver_queue_members;
INSERT INTO public.beaver_queue_members(
  user_id,display_name,status,queue_position,joined_at,updated_at
) VALUES(
  'f9100000-0000-4000-8000-000000000001','Queue Worker Test','king',991001,
  clock_timestamp(),clock_timestamp()
);
UPDATE public.beaver_queue_table SET
  king_id='f9100000-0000-4000-8000-000000000001',
  solo_expires_at=clock_timestamp()-INTERVAL '1 second'
WHERE id=1;

SET LOCAL ROLE service_role;
SELECT public.run_pongo_queue_maintenance_v1();
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT king_id IS NULL AND solo_expires_at IS NULL
   FROM public.beaver_queue_table WHERE id=1)
  AND (SELECT status='left' FROM public.beaver_queue_members
       WHERE user_id='f9100000-0000-4000-8000-000000000001')
  AND (SELECT last_succeeded_at>clock_timestamp()-INTERVAL '5 seconds'
       FROM public.pongo_maintenance_state WHERE task='queue'),
  'trusted maintenance must reconcile an expired queue without a browser'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','f9100000-0000-4000-8000-000000000001',TRUE);
SELECT pg_temp.assert_true(
  public.pongo_queue_maintenance_health_v1() @> jsonb_build_object(
    'healthy',TRUE,'overdue_queue_deadline',FALSE
  ),
  'authenticated health checks must report fresh successful maintenance'
);
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT public.run_pongo_ranked_maintenance_v1();
RESET ROLE;

SELECT pg_temp.assert_true(
  (SELECT last_succeeded_at>clock_timestamp()-INTERVAL '5 seconds'
   FROM public.pongo_maintenance_state WHERE task='ranked'),
  'trusted ranked maintenance must record a successful run'
);

ROLLBACK;
