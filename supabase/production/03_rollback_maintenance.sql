-- DO NOT RUN during normal deployment. This is the targeted rollback for
-- migration 20261104100000 only. Review job ownership and take a backup first.
BEGIN;

DO $rollback_jobs$
DECLARE
  target TEXT;
BEGIN
  IF to_regprocedure('cron.unschedule(text)') IS NOT NULL THEN
    FOREACH target IN ARRAY ARRAY[
      'pongo-queue-expiration-v1',
      'pongo-ranked-expiration-v1',
      'pongo-cron-history-cleanup-v1'
    ]
    LOOP
      IF EXISTS(SELECT 1 FROM cron.job WHERE jobname=target AND username=current_user) THEN
        PERFORM cron.unschedule(target);
      END IF;
    END LOOP;
  END IF;
END;
$rollback_jobs$;

DROP FUNCTION IF EXISTS public.pongo_ranked_maintenance_health_v1();
DROP FUNCTION IF EXISTS public.pongo_queue_maintenance_health_v1();
DROP FUNCTION IF EXISTS public.run_pongo_ranked_maintenance_v1();
DROP FUNCTION IF EXISTS public.run_pongo_queue_maintenance_v1();
DROP TABLE IF EXISTS public.pongo_maintenance_state;

COMMIT;
