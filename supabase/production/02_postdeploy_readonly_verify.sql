-- READ ONLY. Run after applying the approved delta. A production launch still
-- requires the HTTP/RLS and closed-browser expiry checks documented separately.

SELECT 'ranked_limits_10_total_3_pair' AS check_name,
       EXISTS(
         SELECT 1 FROM public.ranking_config
         WHERE id AND daily_ranked_player_limit=10 AND daily_ranked_pair_limit=3
       ) AS passed;
SELECT 'maintenance_functions_and_privileges' AS check_name,
       to_regprocedure('public.run_pongo_queue_maintenance_v1()') IS NOT NULL
       AND to_regprocedure('public.run_pongo_ranked_maintenance_v1()') IS NOT NULL
       AND has_function_privilege('service_role','public.run_pongo_queue_maintenance_v1()','EXECUTE')
       AND has_function_privilege('service_role','public.run_pongo_ranked_maintenance_v1()','EXECUTE')
       AND NOT has_function_privilege('authenticated','public.run_pongo_queue_maintenance_v1()','EXECUTE')
       AND NOT has_function_privilege('authenticated','public.run_pongo_ranked_maintenance_v1()','EXECUTE')
       AND NOT has_function_privilege('anon','public.run_pongo_queue_maintenance_v1()','EXECUTE')
       AND NOT has_function_privilege('anon','public.run_pongo_ranked_maintenance_v1()','EXECUTE') AS passed;

WITH expected(jobname,schedule,command) AS (VALUES
  ('pongo-queue-expiration-v1','10 seconds','SELECT public.run_pongo_queue_maintenance_v1()'),
  ('pongo-ranked-expiration-v1','*/5 * * * *','SELECT public.run_pongo_ranked_maintenance_v1()'),
  ('pongo-cron-history-cleanup-v1','0 3 * * *',NULL::TEXT)
), actual AS (
  SELECT expected.jobname,COUNT(job.jobid) AS matching_jobs
  FROM expected
  LEFT JOIN cron.job job
    ON job.jobname=expected.jobname
   AND job.schedule=expected.schedule
   AND job.active
   AND (expected.command IS NULL OR job.command=expected.command)
  GROUP BY expected.jobname
)
SELECT jobname,matching_jobs=1 AS passed,matching_jobs
FROM actual
ORDER BY jobname;

SELECT 'no_duplicate_maintenance_commands' AS check_name,
       COUNT(*)=2 AS passed,
       COUNT(*) AS matching_command_jobs
FROM cron.job
WHERE command IN(
  'SELECT public.run_pongo_queue_maintenance_v1()',
  'SELECT public.run_pongo_ranked_maintenance_v1()'
);

SELECT public.pongo_queue_maintenance_health_v1() AS queue_maintenance_health;
SELECT public.pongo_ranked_maintenance_health_v1() AS ranked_maintenance_health;

SELECT job.jobname,run.status,run.return_message,run.start_time,run.end_time
FROM cron.job job
LEFT JOIN LATERAL(
  SELECT detail.status,detail.return_message,detail.start_time,detail.end_time
  FROM cron.job_run_details detail
  WHERE detail.jobid=job.jobid
  ORDER BY detail.start_time DESC
  LIMIT 1
) run ON TRUE
WHERE job.jobname IN('pongo-queue-expiration-v1','pongo-ranked-expiration-v1')
ORDER BY job.jobname;

SELECT job.jobname,
       COUNT(*) FILTER(WHERE run.status='succeeded') AS succeeded_runs,
       COUNT(*) FILTER(WHERE run.status<>'succeeded') AS non_succeeded_runs,
       MAX(run.end_time) FILTER(WHERE run.status='succeeded') AS last_success
FROM cron.job job
LEFT JOIN cron.job_run_details run
  ON run.jobid=job.jobid
 AND run.start_time>clock_timestamp()-INTERVAL '15 minutes'
WHERE job.jobname IN('pongo-queue-expiration-v1','pongo-ranked-expiration-v1')
GROUP BY job.jobname
ORDER BY job.jobname;

WITH expected(tablename) AS (VALUES
  ('profiles'),('challenges'),('matches'),('rating_events'),('disputes'),
  ('match_cancellation_requests'),('beaver_queue_table'),
  ('beaver_queue_members'),('beaver_queue_games'),
  ('beaver_queue_swap_requests'),('beaver_queue_ranked_requests')
)
SELECT expected.tablename,
       publication.tablename IS NOT NULL AS passed
FROM expected
LEFT JOIN pg_publication_tables publication
  ON publication.pubname='supabase_realtime'
 AND publication.schemaname='public'
 AND publication.tablename=expected.tablename
ORDER BY expected.tablename;

SELECT 'domain_event_recipient_policy_repaired' AS check_name,
       EXISTS(
         SELECT 1 FROM pg_policies
         WHERE schemaname='public' AND tablename='domain_events'
           AND policyname='Users read relevant events'
           AND qual LIKE '%recipient_notification.event_id = domain_events.id%'
       ) AS passed;
-- End of read-only verification.
