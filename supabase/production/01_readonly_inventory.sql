-- READ ONLY. Run before any production migration and save the complete output.
-- Compatible with psql and the Supabase SQL Editor.

SELECT now() AS captured_at,current_database() AS database_name,current_user AS database_user,
       current_setting('server_version') AS postgres_version;

SELECT extname,extversion
FROM pg_extension
ORDER BY extname;

-- Inventory every non-system schema before a remote reset. Review anything
-- outside the normal Supabase-managed schemas and public before proceeding.
SELECT namespace.nspname AS schema_name,
       COUNT(object.oid) FILTER(WHERE object.relkind IN('r','p')) AS tables,
       COUNT(object.oid) FILTER(WHERE object.relkind='v') AS views,
       COUNT(object.oid) FILTER(WHERE object.relkind='S') AS sequences
FROM pg_namespace namespace
LEFT JOIN pg_class object ON object.relnamespace=namespace.oid
WHERE namespace.nspname NOT LIKE 'pg\_%' ESCAPE '\'
  AND namespace.nspname<>'information_schema'
GROUP BY namespace.nspname
ORDER BY namespace.nspname;

SELECT role.rolname,role.rolcanlogin,role.rolsuper,role.rolcreatedb,
       role.rolcreaterole
FROM pg_roles role
WHERE role.rolname NOT LIKE 'pg\_%' ESCAPE '\'
ORDER BY role.rolname;

SELECT publication.pubname,publication.puballtables,
       pg_get_userbyid(publication.pubowner) AS owner
FROM pg_publication publication
ORDER BY publication.pubname;

SELECT wrapper.fdwname,server.srvname,server.srvoptions
FROM pg_foreign_server server
JOIN pg_foreign_data_wrapper wrapper ON wrapper.oid=server.srvfdw
ORDER BY wrapper.fdwname,server.srvname;

SELECT trigger.evtname,trigger.evtevent,trigger.evtenabled,
       trigger.evtfoid::regprocedure AS function_name
FROM pg_event_trigger trigger
ORDER BY trigger.evtname;

SELECT 'auth_users' AS resource,COUNT(*) AS row_count FROM auth.users
UNION ALL
SELECT 'storage_buckets',COUNT(*) FROM storage.buckets
UNION ALL
SELECT 'storage_objects',COUNT(*) FROM storage.objects
ORDER BY resource;

SELECT schema.nspname AS table_schema,relation.relname AS table_name,
       trigger.tgname AS trigger_name,trigger.tgenabled,
       trigger.tgfoid::regprocedure AS function_name
FROM pg_trigger trigger
JOIN pg_class relation ON relation.oid=trigger.tgrelid
JOIN pg_namespace schema ON schema.oid=relation.relnamespace
WHERE NOT trigger.tgisinternal
ORDER BY schema.nspname,relation.relname,trigger.tgname;

SELECT current_setting('cron.database_name',TRUE) AS cron_database_name,
       current_setting('cron.launch_active_jobs',TRUE) AS cron_launch_active_jobs,
       current_setting('cron.use_background_workers',TRUE) AS cron_use_background_workers;

-- The ledger can legitimately be absent when historical SQL was applied
-- manually. Dynamic execution avoids parse-time failure on that state.
SELECT to_regclass('supabase_migrations.schema_migrations') IS NOT NULL AS ledger_exists,
       CASE
         WHEN to_regclass('supabase_migrations.schema_migrations') IS NULL
           THEN '[]'::JSONB
         ELSE COALESCE(
           ((xpath(
             '/table/row/payload/text()',
             query_to_xml(
               $migration_query$
                 SELECT COALESCE(
                   jsonb_agg(to_jsonb(item) ORDER BY item.version),
                   '[]'::JSONB
                 )::TEXT AS payload
                 FROM (
                   SELECT version::TEXT,name::TEXT
                   FROM supabase_migrations.schema_migrations
                 ) item
               $migration_query$,
               TRUE,FALSE,''
             )
           ))[1]::TEXT)::JSONB,
           '[]'::JSONB
         )
       END AS ledger_rows;

SELECT dependency,installed
FROM (VALUES
  ('beaver_queue_health_v10',to_regprocedure('public.beaver_queue_health_v10()') IS NOT NULL),
  ('beaver_queue_overtime_v1',to_regprocedure('public.beaver_queue_overtime_v1(uuid,text)') IS NOT NULL),
  ('beaver_queue_advance_expired_v1',to_regprocedure('public.beaver_queue_advance_expired_v1()') IS NOT NULL),
  ('assert_ranked_match_eligibility_v4',to_regprocedure('public.assert_ranked_match_eligibility_v4(uuid,uuid)') IS NOT NULL),
  ('expire_mobile_ranking_items_v2',to_regprocedure('public.expire_mobile_ranking_items_v2()') IS NOT NULL),
  ('run_pongo_queue_maintenance_v1',to_regprocedure('public.run_pongo_queue_maintenance_v1()') IS NOT NULL),
  ('run_pongo_ranked_maintenance_v1',to_regprocedure('public.run_pongo_ranked_maintenance_v1()') IS NOT NULL),
  ('queue_maintenance_health',to_regprocedure('public.pongo_queue_maintenance_health_v1()') IS NOT NULL),
  ('ranked_maintenance_health',to_regprocedure('public.pongo_ranked_maintenance_health_v1()') IS NOT NULL)
) AS checks(dependency,installed)
ORDER BY dependency;

-- Schema fingerprints are required because the legacy date-only ledger cannot
-- distinguish multiple SQL files that shared the same date prefix.
SELECT stage,fingerprint_present
FROM (VALUES
  ('ranking expansion',to_regclass('public.ranking_config') IS NOT NULL),
  ('challenge repair',to_regprocedure('public.create_challenge_v2(uuid)') IS NOT NULL),
  ('ranked lifecycle',to_regclass('public.match_cancellation_requests') IS NOT NULL),
  ('New York daily limits',to_regprocedure('public.club_ranked_day_v3(timestamp with time zone)') IS NOT NULL),
  ('weighted ELO',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='rating_events' AND column_name='calculation')),
  ('competitive ranks',to_regclass('public.competitive_rank_tiers') IS NOT NULL),
  ('unified leaderboards',to_regprocedure('public.get_leaderboard_v3(text,date)') IS NOT NULL),
  ('dispute corrections',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='disputes' AND column_name='requested_resolution')),
  ('security ledger protection',to_regprocedure('public.protect_rating_event_ledger_v3()') IS NOT NULL),
  ('live queue',to_regclass('public.beaver_queue_members') IS NOT NULL AND to_regprocedure('public.beaver_queue_tick_v1()') IS NOT NULL),
  ('profile settings',to_regprocedure('public.update_my_profile_settings_v4(text,boolean,boolean)') IS NOT NULL),
  ('queue outcomes and swaps',to_regclass('public.beaver_queue_swap_requests') IS NOT NULL),
  ('queue match overtime',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='beaver_queue_table' AND column_name='overtime_prompt_expires_at') AND to_regprocedure('public.beaver_queue_overtime_v1(uuid,text)') IS NOT NULL),
  ('queue ranked conversion',to_regclass('public.beaver_queue_ranked_requests') IS NOT NULL AND to_regprocedure('public.beaver_queue_health_v10()') IS NOT NULL),
  ('avatar configuration',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='avatar_config'))
) AS fingerprints(stage,fingerprint_present)
ORDER BY stage;

SELECT id,active_ranked_match_limit,daily_ranked_player_limit,daily_ranked_pair_limit,updated_at
FROM public.ranking_config;

SELECT p.oid::regprocedure AS function_name,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef AS security_definer,
       p.proconfig AS function_settings
FROM pg_proc p
WHERE p.oid IN(
  to_regprocedure('public.beaver_queue_advance_expired_v1()'),
  to_regprocedure('public.expire_mobile_ranking_items_v2()'),
  to_regprocedure('public.run_pongo_queue_maintenance_v1()'),
  to_regprocedure('public.run_pongo_ranked_maintenance_v1()')
)
ORDER BY 1;

SELECT p.oid::regprocedure AS function_name,
       md5(pg_get_functiondef(p.oid)) AS definition_md5,
       pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
WHERE p.oid IN(
  to_regprocedure('public.assert_ranked_match_eligibility_v4(uuid,uuid)'),
  to_regprocedure('public.beaver_queue_request_ranked_v1()'),
  to_regprocedure('public.beaver_queue_advance_expired_v1()'),
  to_regprocedure('public.expire_mobile_ranking_items_v2()')
)
ORDER BY 1;

SELECT role_name,function_name,can_execute
FROM (VALUES
  ('anon','run_pongo_queue_maintenance_v1',CASE WHEN to_regprocedure('public.run_pongo_queue_maintenance_v1()') IS NULL THEN NULL ELSE has_function_privilege('anon',to_regprocedure('public.run_pongo_queue_maintenance_v1()'),'EXECUTE') END),
  ('authenticated','run_pongo_queue_maintenance_v1',CASE WHEN to_regprocedure('public.run_pongo_queue_maintenance_v1()') IS NULL THEN NULL ELSE has_function_privilege('authenticated',to_regprocedure('public.run_pongo_queue_maintenance_v1()'),'EXECUTE') END),
  ('service_role','run_pongo_queue_maintenance_v1',CASE WHEN to_regprocedure('public.run_pongo_queue_maintenance_v1()') IS NULL THEN NULL ELSE has_function_privilege('service_role',to_regprocedure('public.run_pongo_queue_maintenance_v1()'),'EXECUTE') END),
  ('anon','run_pongo_ranked_maintenance_v1',CASE WHEN to_regprocedure('public.run_pongo_ranked_maintenance_v1()') IS NULL THEN NULL ELSE has_function_privilege('anon',to_regprocedure('public.run_pongo_ranked_maintenance_v1()'),'EXECUTE') END),
  ('authenticated','run_pongo_ranked_maintenance_v1',CASE WHEN to_regprocedure('public.run_pongo_ranked_maintenance_v1()') IS NULL THEN NULL ELSE has_function_privilege('authenticated',to_regprocedure('public.run_pongo_ranked_maintenance_v1()'),'EXECUTE') END),
  ('service_role','run_pongo_ranked_maintenance_v1',CASE WHEN to_regprocedure('public.run_pongo_ranked_maintenance_v1()') IS NULL THEN NULL ELSE has_function_privilege('service_role',to_regprocedure('public.run_pongo_ranked_maintenance_v1()'),'EXECUTE') END)
) AS privileges(role_name,function_name,can_execute)
ORDER BY function_name,role_name;

SELECT jobid,jobname,schedule,command,database,username,active
FROM cron.job
ORDER BY jobname,jobid;

SELECT jobid,runid,status,return_message,start_time,end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 50;

WITH expected(tablename) AS (VALUES
  ('profiles'),('challenges'),('matches'),('rating_events'),('disputes'),
  ('match_cancellation_requests'),('beaver_queue_table'),
  ('beaver_queue_members'),('beaver_queue_games'),
  ('beaver_queue_swap_requests'),('beaver_queue_ranked_requests')
)
SELECT expected.tablename,
       publication.tablename IS NOT NULL AS in_supabase_realtime
FROM expected
LEFT JOIN pg_publication_tables publication
  ON publication.pubname='supabase_realtime'
 AND publication.schemaname='public'
 AND publication.tablename=expected.tablename
ORDER BY expected.tablename;

SELECT c.relname AS table_name,c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname IN(
    'profiles','challenges','matches','rating_events','disputes','notifications',
    'domain_events','match_submissions','beaver_queue_table',
    'beaver_queue_members','pongo_maintenance_state'
  )
ORDER BY c.relname;

SELECT schemaname,tablename,policyname,roles,cmd,qual,with_check
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN('domain_events','notifications','match_submissions','pongo_maintenance_state')
ORDER BY tablename,policyname;
