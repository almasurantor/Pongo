-- One read-only final gate for `supabase db query --read-only --file ...`.
-- `ready` must be true and every check must pass before Vercel production opens.
WITH expected_versions(version) AS (VALUES
  ('20260930000000'),('20261001010000'),('20261001020000'),('20261001030000'),
  ('20261025010000'),('20261030010000'),('20261030020000'),('20261031010000'),
  ('20261031020000'),('20261031030000'),('20261031040000'),('20261031050000'),
  ('20261031060000'),('20261101010000'),('20261101020000'),('20261102010000'),
  ('20261103010000'),('20261103020000'),('20261103030000'),('20261103040000'),
  ('20261103050000'),('20261104010000'),('20261104020000'),('20261104030000'),
  ('20261104040000'),('20261104050000'),('20261104060000'),('20261104070000'),
  ('20261104080000'),('20261104090000'),('20261104100000'),('20261106010000'),
  ('20261111010000')
), actual_versions AS (
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
), version_differences AS (
  SELECT 'missing'::TEXT AS problem,version FROM expected_versions
  EXCEPT SELECT 'missing',version FROM actual_versions
  UNION ALL
  SELECT 'unexpected',version FROM actual_versions
  EXCEPT SELECT 'unexpected',version FROM expected_versions
), empty_counts(table_name,row_count) AS (
  SELECT 'auth.users',COUNT(*) FROM auth.users UNION ALL
  SELECT 'auth.identities',COUNT(*) FROM auth.identities UNION ALL
  SELECT 'auth.sessions',COUNT(*) FROM auth.sessions UNION ALL
  SELECT 'profiles',COUNT(*) FROM public.profiles UNION ALL
  SELECT 'challenges',COUNT(*) FROM public.challenges UNION ALL
  SELECT 'matches',COUNT(*) FROM public.matches UNION ALL
  SELECT 'rating_events',COUNT(*) FROM public.rating_events UNION ALL
  SELECT 'match_submissions',COUNT(*) FROM public.match_submissions UNION ALL
  SELECT 'disputes',COUNT(*) FROM public.disputes UNION ALL
  SELECT 'notifications',COUNT(*) FROM public.notifications UNION ALL
  SELECT 'integrity_flags',COUNT(*) FROM public.integrity_flags UNION ALL
  SELECT 'queue_members',COUNT(*) FROM public.beaver_queue_members UNION ALL
  SELECT 'queue_games',COUNT(*) FROM public.beaver_queue_games UNION ALL
  SELECT 'queue_swaps',COUNT(*) FROM public.beaver_queue_swap_requests UNION ALL
  SELECT 'queue_corrections',COUNT(*) FROM public.beaver_queue_game_corrections UNION ALL
  SELECT 'queue_ranked_requests',COUNT(*) FROM public.beaver_queue_ranked_requests
), expected_rls(table_name) AS (VALUES
  ('profiles'),('challenges'),('matches'),('ranking_config'),('user_roles'),
  ('player_integrity'),('profile_stat_baselines'),('seasons'),('rating_events'),
  ('weekly_player_stats'),('player_season_stats'),('match_submissions'),('disputes'),
  ('match_revisions'),('domain_events'),('notifications'),('integrity_flags'),
  ('match_cancellation_requests'),('competitive_rank_tiers'),('beaver_queue_members'),
  ('beaver_queue_table'),('beaver_queue_games'),('beaver_queue_swap_requests'),
  ('beaver_queue_game_corrections'),('beaver_queue_ranked_requests'),
  ('pongo_maintenance_state')
), expected_realtime(table_name) AS (VALUES
  ('profiles'),('challenges'),('matches'),('rating_events'),('disputes'),
  ('match_cancellation_requests'),('beaver_queue_table'),('beaver_queue_members'),
  ('beaver_queue_games'),('beaver_queue_swap_requests'),('beaver_queue_ranked_requests')
), expected_functions(signature) AS (VALUES
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
), expected_jobs(jobname,schedule,command) AS (VALUES
  ('pongo-queue-expiration-v1','10 seconds','SELECT public.run_pongo_queue_maintenance_v1()'),
  ('pongo-ranked-expiration-v1','*/5 * * * *','SELECT public.run_pongo_ranked_maintenance_v1()'),
  ('pongo-cron-history-cleanup-v1','0 3 * * *',NULL::TEXT)
), health AS (
  -- The Supabase CLI executes `db query --read-only` as
  -- supabase_read_only_user. That role can inspect the underlying state but
  -- intentionally cannot execute application RPCs. Reproduce the health RPC
  -- predicates here instead of widening either function's EXECUTE grants.
  SELECT
    (
      SELECT jsonb_build_object(
        'healthy',state.last_succeeded_at IS NOT NULL
          AND state.last_succeeded_at>clock_timestamp()-INTERVAL '30 seconds',
        'last_succeeded_at',state.last_succeeded_at,
        'seconds_since_success',CASE
          WHEN state.last_succeeded_at IS NULL THEN NULL
          ELSE EXTRACT(EPOCH FROM clock_timestamp()-state.last_succeeded_at)::INTEGER
        END,
        'overdue_queue_deadline',EXISTS(
          SELECT 1
          FROM public.beaver_queue_table queue
          WHERE queue.id=1 AND (
            queue.solo_expires_at<=clock_timestamp()
            OR queue.call_expires_at<=clock_timestamp()
            OR (queue.phase='playing' AND queue.overtime_used
                AND queue.game_expires_at<=clock_timestamp())
            OR (queue.phase='playing' AND NOT queue.overtime_used
                AND queue.overtime_prompt_expires_at<=clock_timestamp())
            OR queue.afk_expires_at<=clock_timestamp()
          )
        )
      )
      FROM public.pongo_maintenance_state state
      WHERE state.task='queue'
    ) AS queue,
    (
      SELECT jsonb_build_object(
        'healthy',state.last_succeeded_at IS NOT NULL
          AND state.last_succeeded_at>clock_timestamp()-INTERVAL '10 minutes',
        'last_succeeded_at',state.last_succeeded_at,
        'seconds_since_success',CASE
          WHEN state.last_succeeded_at IS NULL THEN NULL
          ELSE EXTRACT(EPOCH FROM clock_timestamp()-state.last_succeeded_at)::INTEGER
        END
      )
      FROM public.pongo_maintenance_state state
      WHERE state.task='ranked'
    ) AS ranked
), checks(check_name,passed,details) AS (
  SELECT 'migration_ledger',
         (SELECT COUNT(*) FROM actual_versions)=33
           AND NOT EXISTS(SELECT 1 FROM version_differences),
         jsonb_build_object(
           'count',(SELECT COUNT(*) FROM actual_versions),
           'differences',COALESCE((SELECT jsonb_agg(to_jsonb(item)) FROM version_differences item),'[]'::JSONB)
         )
  UNION ALL
  SELECT 'all_auth_and_gameplay_data_empty',
         NOT EXISTS(SELECT 1 FROM empty_counts WHERE row_count<>0),
         (SELECT jsonb_object_agg(table_name,row_count) FROM empty_counts)
  UNION ALL
  SELECT 'required_seed_rows',
         (SELECT COUNT(*) FROM public.ranking_config)=1
           AND (SELECT COUNT(*) FROM public.competitive_rank_tiers)=7
           AND (SELECT COUNT(*) FROM public.pongo_maintenance_state)=2,
         jsonb_build_object(
           'ranking_config',(SELECT COUNT(*) FROM public.ranking_config),
           'rank_tiers',(SELECT COUNT(*) FROM public.competitive_rank_tiers),
           'maintenance_state',(SELECT COUNT(*) FROM public.pongo_maintenance_state)
         )
  UNION ALL
  SELECT 'ranked_limits_10_total_3_pair',
         (SELECT COUNT(*)=1 FROM public.ranking_config
          WHERE id AND daily_ranked_player_limit=10 AND daily_ranked_pair_limit=3),
         COALESCE((SELECT to_jsonb(item) FROM (
           SELECT daily_ranked_player_limit,daily_ranked_pair_limit
           FROM public.ranking_config WHERE id
         ) item),'{}'::JSONB)
  UNION ALL
  SELECT 'idle_queue_singleton',
         (SELECT COUNT(*)=1 FROM public.beaver_queue_table
          WHERE id=1 AND phase='idle' AND king_id IS NULL AND challenger_id IS NULL
            AND call_expires_at IS NULL AND game_id IS NULL AND game_started_at IS NULL
            AND game_expires_at IS NULL AND solo_expires_at IS NULL
            AND overtime_prompt_expires_at IS NULL AND overtime_used=FALSE
            AND afk_reporter_id IS NULL AND afk_target_id IS NULL AND afk_expires_at IS NULL),
         COALESCE((SELECT to_jsonb(item) FROM (
           SELECT id,phase,king_id,challenger_id,game_id FROM public.beaver_queue_table
         ) item),'{}'::JSONB)
  UNION ALL
  SELECT 'required_functions',
         NOT EXISTS(SELECT 1 FROM expected_functions WHERE to_regprocedure(signature) IS NULL),
         (SELECT jsonb_object_agg(signature,to_regprocedure(signature) IS NOT NULL) FROM expected_functions)
  UNION ALL
  SELECT 'rls_on_all_26_tables',
         NOT EXISTS(
           SELECT 1 FROM expected_rls expected
           LEFT JOIN pg_class relation ON relation.relname=expected.table_name
           LEFT JOIN pg_namespace schema ON schema.oid=relation.relnamespace AND schema.nspname='public'
           WHERE schema.oid IS NULL OR NOT relation.relrowsecurity
         ),
         jsonb_build_object('expected_tables',26)
  UNION ALL
  SELECT 'auth_signup_trigger',
         (SELECT COUNT(*)=1 FROM pg_trigger trigger
          JOIN pg_class relation ON relation.oid=trigger.tgrelid
          JOIN pg_namespace schema ON schema.oid=relation.relnamespace
          WHERE schema.nspname='auth' AND relation.relname='users'
            AND trigger.tgname='on_auth_user_created' AND NOT trigger.tgisinternal),
         '{}'::JSONB
  UNION ALL
  SELECT 'realtime_11_tables',
         NOT EXISTS(
           SELECT 1 FROM expected_realtime expected
           LEFT JOIN pg_publication_tables publication
             ON publication.pubname='supabase_realtime'
            AND publication.schemaname='public'
            AND publication.tablename=expected.table_name
           WHERE publication.tablename IS NULL
         ),
         jsonb_build_object('expected_tables',11)
  UNION ALL
  SELECT 'cron_jobs_exact',
         NOT EXISTS(
           SELECT 1 FROM expected_jobs expected
           LEFT JOIN cron.job job ON job.jobname=expected.jobname
             AND job.schedule=expected.schedule AND job.active
             AND (expected.command IS NULL OR job.command=expected.command)
           GROUP BY expected.jobname HAVING COUNT(job.jobid)<>1
         ) AND (SELECT COUNT(*) FROM cron.job WHERE command IN(
           'SELECT public.run_pongo_queue_maintenance_v1()',
           'SELECT public.run_pongo_ranked_maintenance_v1()'
         ))=2,
         (SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.jobname),'[]'::JSONB)
          FROM (SELECT jobname,schedule,command,active FROM cron.job WHERE jobname LIKE 'pongo-%') item)
  UNION ALL
  SELECT 'recent_scheduled_runs',
         (SELECT COUNT(*)=2 FROM cron.job job
          WHERE job.jobname IN('pongo-queue-expiration-v1','pongo-ranked-expiration-v1')
            AND EXISTS(SELECT 1 FROM cron.job_run_details run
              WHERE run.jobid=job.jobid AND run.status='succeeded'
                AND run.start_time>clock_timestamp()-INTERVAL '15 minutes')),
         (SELECT COALESCE(jsonb_object_agg(job.jobname,(
           SELECT MAX(run.start_time) FROM cron.job_run_details run
           WHERE run.jobid=job.jobid AND run.status='succeeded'
         )),'{}'::JSONB) FROM cron.job job
          WHERE job.jobname IN('pongo-queue-expiration-v1','pongo-ranked-expiration-v1'))
  UNION ALL
  SELECT 'maintenance_health',
         COALESCE((health.queue->>'healthy')::BOOLEAN,FALSE)
           AND COALESCE((health.ranked->>'healthy')::BOOLEAN,FALSE),
         jsonb_build_object('queue',health.queue,'ranked',health.ranked)
  FROM health
  UNION ALL
  SELECT 'maintenance_permissions',
         NOT has_function_privilege('anon','public.run_pongo_queue_maintenance_v1()','EXECUTE')
           AND NOT has_function_privilege('authenticated','public.run_pongo_queue_maintenance_v1()','EXECUTE')
           AND has_function_privilege('service_role','public.run_pongo_queue_maintenance_v1()','EXECUTE')
           AND NOT has_function_privilege('anon','public.run_pongo_ranked_maintenance_v1()','EXECUTE')
           AND NOT has_function_privilege('authenticated','public.run_pongo_ranked_maintenance_v1()','EXECUTE')
           AND has_function_privilege('service_role','public.run_pongo_ranked_maintenance_v1()','EXECUTE'),
         '{}'::JSONB
)
SELECT jsonb_pretty(jsonb_build_object(
  'ready',BOOL_AND(passed),
  'checked_at',clock_timestamp(),
  'checks',jsonb_object_agg(check_name,jsonb_build_object('passed',passed,'details',details))
))
FROM checks;
