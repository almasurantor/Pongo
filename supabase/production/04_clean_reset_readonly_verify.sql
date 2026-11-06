-- READ ONLY. Final clean-reset gate for project dqkmtbrzhqearrqpmlwd.
-- Run as the database owner after the schema reset, permanent Auth deletion,
-- and at least one scheduled execution of both maintenance workers.

SELECT now() AS verified_at,current_database() AS database_name,current_user AS database_user;

WITH expected(version) AS (VALUES
  ('20260930000000'),('20261001010000'),('20261001020000'),('20261001030000'),
  ('20261025010000'),('20261030010000'),('20261030020000'),('20261031010000'),
  ('20261031020000'),('20261031030000'),('20261031040000'),('20261031050000'),
  ('20261031060000'),('20261101010000'),('20261101020000'),('20261102010000'),
  ('20261103010000'),('20261103020000'),('20261103030000'),('20261103040000'),
  ('20261103050000'),('20261104010000'),('20261104020000'),('20261104030000'),
  ('20261104040000'),('20261104050000'),('20261104060000'),('20261104070000'),
  ('20261104080000'),('20261104090000'),('20261104100000'),('20261106010000')
), actual AS (
  SELECT node::TEXT AS version
  FROM unnest(CASE
    WHEN to_regclass('supabase_migrations.schema_migrations') IS NULL
      THEN ARRAY[]::XML[]
    ELSE xpath(
      '/table/row/version/text()',
      query_to_xml(
        'SELECT version::TEXT AS version FROM supabase_migrations.schema_migrations ORDER BY version',
        TRUE,FALSE,''
      )
    )
  END) node
), differences AS (
  SELECT 'missing'::TEXT AS problem,version FROM expected
  EXCEPT SELECT 'missing',version FROM actual
  UNION ALL
  SELECT 'unexpected',version FROM actual
  EXCEPT SELECT 'unexpected',version FROM expected
)
SELECT 'exact_32_migration_ledger' AS check_name,
       (SELECT COUNT(*) FROM actual)=32 AND NOT EXISTS(SELECT 1 FROM differences) AS passed,
       (SELECT COUNT(*) FROM actual) AS actual_count,
       COALESCE((SELECT jsonb_agg(differences ORDER BY problem,version) FROM differences),'[]'::JSONB) AS differences;

WITH expected(table_name) AS (VALUES
  ('profiles'),('challenges'),('matches'),('ranking_config'),('user_roles'),
  ('player_integrity'),('profile_stat_baselines'),('seasons'),('rating_events'),
  ('weekly_player_stats'),('player_season_stats'),('match_submissions'),('disputes'),
  ('match_revisions'),('domain_events'),('notifications'),('integrity_flags'),
  ('match_cancellation_requests'),('competitive_rank_tiers'),('beaver_queue_members'),
  ('beaver_queue_table'),('beaver_queue_games'),('beaver_queue_swap_requests'),
  ('beaver_queue_game_corrections'),('beaver_queue_ranked_requests'),
  ('pongo_maintenance_state')
), actual AS (
  SELECT c.relname AS table_name,c.relrowsecurity
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN('r','p')
)
SELECT expected.table_name,
       actual.table_name IS NOT NULL AS exists,
       COALESCE(actual.relrowsecurity,FALSE) AS rls_enabled
FROM expected LEFT JOIN actual USING(table_name)
ORDER BY expected.table_name;

SELECT 'auth_signup_trigger' AS check_name,
       COUNT(*)=1 AS passed,COUNT(*) AS trigger_count
FROM pg_trigger trigger
JOIN pg_class relation ON relation.oid=trigger.tgrelid
JOIN pg_namespace schema ON schema.oid=relation.relnamespace
WHERE schema.nspname='auth' AND relation.relname='users'
  AND trigger.tgname='on_auth_user_created' AND NOT trigger.tgisinternal;

SELECT 'all_public_constraints_validated' AS check_name,
       COUNT(*)=0 AS passed,COUNT(*) AS invalid_constraints
FROM pg_constraint constraint_row
JOIN pg_class relation ON relation.oid=constraint_row.conrelid
JOIN pg_namespace schema ON schema.oid=relation.relnamespace
WHERE schema.nspname='public' AND NOT constraint_row.convalidated;

WITH required(signature) AS (VALUES
  ('public.assert_ranked_match_eligibility_v4(uuid,uuid)'),
  ('public.beaver_queue_request_ranked_v1()'),
  ('public.beaver_queue_overtime_v1(uuid,text)'),
  ('public.beaver_queue_health_v10()'),
  ('public.beaver_queue_advance_expired_v1()'),
  ('public.expire_mobile_ranking_items_v2()'),
  ('public.run_pongo_queue_maintenance_v1()'),
  ('public.run_pongo_ranked_maintenance_v1()'),
  ('public.pongo_queue_maintenance_health_v1()'),
  ('public.pongo_ranked_maintenance_health_v1()')
)
SELECT signature,to_regprocedure(signature) IS NOT NULL AS passed
FROM required ORDER BY signature;

SELECT 'ranked_limits_10_total_3_pair' AS check_name,
       COUNT(*)=1 AS passed,
       COUNT(*) AS matching_rows
FROM public.ranking_config
WHERE id AND daily_ranked_player_limit=10 AND daily_ranked_pair_limit=3;

WITH counts(table_name,row_count) AS (
  SELECT 'auth.users',COUNT(*) FROM auth.users UNION ALL
  SELECT 'auth.identities',COUNT(*) FROM auth.identities UNION ALL
  SELECT 'auth.sessions',COUNT(*) FROM auth.sessions UNION ALL
  SELECT 'public.profiles',COUNT(*) FROM public.profiles UNION ALL
  SELECT 'public.challenges',COUNT(*) FROM public.challenges UNION ALL
  SELECT 'public.matches',COUNT(*) FROM public.matches UNION ALL
  SELECT 'public.user_roles',COUNT(*) FROM public.user_roles UNION ALL
  SELECT 'public.player_integrity',COUNT(*) FROM public.player_integrity UNION ALL
  SELECT 'public.profile_stat_baselines',COUNT(*) FROM public.profile_stat_baselines UNION ALL
  SELECT 'public.rating_events',COUNT(*) FROM public.rating_events UNION ALL
  SELECT 'public.weekly_player_stats',COUNT(*) FROM public.weekly_player_stats UNION ALL
  SELECT 'public.player_season_stats',COUNT(*) FROM public.player_season_stats UNION ALL
  SELECT 'public.match_submissions',COUNT(*) FROM public.match_submissions UNION ALL
  SELECT 'public.disputes',COUNT(*) FROM public.disputes UNION ALL
  SELECT 'public.match_revisions',COUNT(*) FROM public.match_revisions UNION ALL
  SELECT 'public.domain_events',COUNT(*) FROM public.domain_events UNION ALL
  SELECT 'public.notifications',COUNT(*) FROM public.notifications UNION ALL
  SELECT 'public.integrity_flags',COUNT(*) FROM public.integrity_flags UNION ALL
  SELECT 'public.match_cancellation_requests',COUNT(*) FROM public.match_cancellation_requests UNION ALL
  SELECT 'public.beaver_queue_members',COUNT(*) FROM public.beaver_queue_members UNION ALL
  SELECT 'public.beaver_queue_games',COUNT(*) FROM public.beaver_queue_games UNION ALL
  SELECT 'public.beaver_queue_swap_requests',COUNT(*) FROM public.beaver_queue_swap_requests UNION ALL
  SELECT 'public.beaver_queue_game_corrections',COUNT(*) FROM public.beaver_queue_game_corrections UNION ALL
  SELECT 'public.beaver_queue_ranked_requests',COUNT(*) FROM public.beaver_queue_ranked_requests
)
SELECT table_name,row_count=0 AS passed,row_count
FROM counts ORDER BY table_name;

SELECT 'required_seed_rows' AS check_name,
       (SELECT COUNT(*) FROM public.ranking_config)=1
       AND (SELECT COUNT(*) FROM public.competitive_rank_tiers)=7
       AND (SELECT COUNT(*) FROM public.pongo_maintenance_state)=2 AS passed,
       (SELECT COUNT(*) FROM public.ranking_config) AS ranking_config_rows,
       (SELECT COUNT(*) FROM public.competitive_rank_tiers) AS rank_tier_rows,
       (SELECT COUNT(*) FROM public.pongo_maintenance_state) AS maintenance_state_rows;

SELECT 'idle_queue_singleton' AS check_name,
       COUNT(*)=1 AS passed,COUNT(*) AS matching_rows
FROM public.beaver_queue_table
WHERE id=1 AND phase='idle'
  AND king_id IS NULL AND challenger_id IS NULL AND call_expires_at IS NULL
  AND game_id IS NULL AND game_started_at IS NULL AND game_expires_at IS NULL
  AND overtime_prompt_expires_at IS NULL AND overtime_used=FALSE
  AND solo_expires_at IS NULL AND afk_reporter_id IS NULL
  AND afk_target_id IS NULL AND afk_expires_at IS NULL
  AND king_confirmed_at IS NULL AND challenger_confirmed_at IS NULL;

WITH expected(jobname,schedule,command) AS (VALUES
  ('pongo-queue-expiration-v1','10 seconds','SELECT public.run_pongo_queue_maintenance_v1()'),
  ('pongo-ranked-expiration-v1','*/5 * * * *','SELECT public.run_pongo_ranked_maintenance_v1()'),
  ('pongo-cron-history-cleanup-v1','0 3 * * *',NULL::TEXT)
), actual AS (
  SELECT expected.jobname,COUNT(job.jobid) AS matching_jobs
  FROM expected LEFT JOIN cron.job job
    ON job.jobname=expected.jobname AND job.schedule=expected.schedule AND job.active
   AND (expected.command IS NULL OR job.command=expected.command)
  GROUP BY expected.jobname
)
SELECT jobname,matching_jobs=1 AS passed,matching_jobs
FROM actual ORDER BY jobname;

SELECT 'no_duplicate_maintenance_commands' AS check_name,
       COUNT(*)=2 AS passed,COUNT(*) AS command_jobs
FROM cron.job
WHERE command IN(
  'SELECT public.run_pongo_queue_maintenance_v1()',
  'SELECT public.run_pongo_ranked_maintenance_v1()'
);

SELECT public.pongo_queue_maintenance_health_v1() AS queue_maintenance_health;
SELECT public.pongo_ranked_maintenance_health_v1() AS ranked_maintenance_health;

WITH expected(tablename) AS (VALUES
  ('profiles'),('challenges'),('matches'),('rating_events'),('disputes'),
  ('match_cancellation_requests'),('beaver_queue_table'),
  ('beaver_queue_members'),('beaver_queue_games'),
  ('beaver_queue_swap_requests'),('beaver_queue_ranked_requests')
)
SELECT expected.tablename,publication.tablename IS NOT NULL AS passed
FROM expected LEFT JOIN pg_publication_tables publication
  ON publication.pubname='supabase_realtime'
 AND publication.schemaname='public'
 AND publication.tablename=expected.tablename
ORDER BY expected.tablename;

SELECT role_name,function_name,can_execute
FROM (VALUES
  ('anon','queue_worker',has_function_privilege('anon','public.run_pongo_queue_maintenance_v1()','EXECUTE')),
  ('authenticated','queue_worker',has_function_privilege('authenticated','public.run_pongo_queue_maintenance_v1()','EXECUTE')),
  ('service_role','queue_worker',has_function_privilege('service_role','public.run_pongo_queue_maintenance_v1()','EXECUTE')),
  ('anon','ranked_worker',has_function_privilege('anon','public.run_pongo_ranked_maintenance_v1()','EXECUTE')),
  ('authenticated','ranked_worker',has_function_privilege('authenticated','public.run_pongo_ranked_maintenance_v1()','EXECUTE')),
  ('service_role','ranked_worker',has_function_privilege('service_role','public.run_pongo_ranked_maintenance_v1()','EXECUTE'))
) AS privileges(role_name,function_name,can_execute)
ORDER BY function_name,role_name;

SELECT job.jobname,run.status,run.return_message,run.start_time,run.end_time
FROM cron.job job
LEFT JOIN LATERAL(
  SELECT detail.status,detail.return_message,detail.start_time,detail.end_time
  FROM cron.job_run_details detail
  WHERE detail.jobid=job.jobid ORDER BY detail.start_time DESC LIMIT 1
) run ON TRUE
WHERE job.jobname IN('pongo-queue-expiration-v1','pongo-ranked-expiration-v1')
ORDER BY job.jobname;

SELECT job.jobname,
       EXISTS(
         SELECT 1 FROM cron.job_run_details run
         WHERE run.jobid=job.jobid AND run.status='succeeded'
           AND run.start_time>clock_timestamp()-INTERVAL '15 minutes'
       ) AS passed_recent_scheduled_run
FROM cron.job job
WHERE job.jobname IN('pongo-queue-expiration-v1','pongo-ranked-expiration-v1')
ORDER BY job.jobname;
