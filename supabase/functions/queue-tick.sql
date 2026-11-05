-- First enable Supabase Cron under Dashboard -> Integrations -> Cron. Hosted
-- Postgres versions 15.1.1.61+ support second-based schedules. The named job
-- is overwritten safely when this statement is rerun.
SELECT cron.schedule(
  'pongo-queue-expiration-v1',
  '10 seconds',
  'SELECT public.run_pongo_queue_maintenance_v1()'
);

-- Verify the job and the last successful database-side reconciliation.
SELECT jobid,jobname,schedule,active
FROM cron.job
WHERE jobname='pongo-queue-expiration-v1';
SELECT public.pongo_queue_maintenance_health_v1();

-- The production-readiness migration also schedules ranked/challenge expiry
-- every five minutes and trims Cron history daily. Verify all three jobs:
SELECT jobid,jobname,schedule,active
FROM cron.job
WHERE jobname IN(
  'pongo-queue-expiration-v1',
  'pongo-ranked-expiration-v1',
  'pongo-cron-history-cleanup-v1'
)
ORDER BY jobname;
SELECT public.pongo_ranked_maintenance_health_v1();
