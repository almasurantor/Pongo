-- Browser-independent queue/ranked maintenance and observable scheduler freshness.
-- Supabase Cron is enabled separately in the hosted project; when the cron
-- schema already exists this migration installs the 10-second job as well.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.beaver_queue_advance_expired_v1()') IS NULL
     OR to_regprocedure('public.expire_mobile_ranking_items_v2()') IS NULL THEN
    RAISE EXCEPTION 'Missing maintenance dependency: apply ranked and queue migrations through 20261104_08 first';
  END IF;
END;
$dependencies$;

CREATE TABLE IF NOT EXISTS public.pongo_maintenance_state(
  task TEXT PRIMARY KEY CHECK(task IN('queue','ranked')),
  last_succeeded_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO public.pongo_maintenance_state(task) VALUES('queue'),('ranked')
ON CONFLICT(task) DO NOTHING;

ALTER TABLE public.pongo_maintenance_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pongo_maintenance_state FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.run_pongo_queue_maintenance_v1()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  completed_at TIMESTAMPTZ;
BEGIN
  PERFORM public.beaver_queue_advance_expired_v1();
  completed_at:=clock_timestamp();
  UPDATE public.pongo_maintenance_state
  SET last_succeeded_at=completed_at,updated_at=completed_at
  WHERE task='queue';
  RETURN jsonb_build_object('ok',TRUE,'completed_at',completed_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.run_pongo_ranked_maintenance_v1()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  completed_at TIMESTAMPTZ;
BEGIN
  PERFORM public.expire_mobile_ranking_items_v2();
  completed_at:=clock_timestamp();
  UPDATE public.pongo_maintenance_state
  SET last_succeeded_at=completed_at,updated_at=completed_at
  WHERE task='ranked';
  RETURN jsonb_build_object('ok',TRUE,'completed_at',completed_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.pongo_queue_maintenance_health_v1()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT jsonb_build_object(
    'healthy',state.last_succeeded_at IS NOT NULL
      AND state.last_succeeded_at>clock_timestamp()-INTERVAL '30 seconds',
    'last_succeeded_at',state.last_succeeded_at,
    'seconds_since_success',CASE WHEN state.last_succeeded_at IS NULL THEN NULL
      ELSE EXTRACT(EPOCH FROM clock_timestamp()-state.last_succeeded_at)::INTEGER END,
    'overdue_queue_deadline',EXISTS(
      SELECT 1 FROM public.beaver_queue_table queue
      WHERE queue.id=1 AND (
        queue.solo_expires_at<=clock_timestamp()
        OR queue.call_expires_at<=clock_timestamp()
        OR queue.game_expires_at<=clock_timestamp()
        OR queue.afk_expires_at<=clock_timestamp()
      )
    )
  )
  FROM public.pongo_maintenance_state state
  WHERE state.task='queue'
$$;

CREATE OR REPLACE FUNCTION public.pongo_ranked_maintenance_health_v1()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT jsonb_build_object(
    'healthy',state.last_succeeded_at IS NOT NULL
      AND state.last_succeeded_at>clock_timestamp()-INTERVAL '10 minutes',
    'last_succeeded_at',state.last_succeeded_at,
    'seconds_since_success',CASE WHEN state.last_succeeded_at IS NULL THEN NULL
      ELSE EXTRACT(EPOCH FROM clock_timestamp()-state.last_succeeded_at)::INTEGER END
  )
  FROM public.pongo_maintenance_state state
  WHERE state.task='ranked'
$$;

REVOKE ALL ON FUNCTION public.run_pongo_queue_maintenance_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.run_pongo_ranked_maintenance_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pongo_queue_maintenance_health_v1()
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pongo_ranked_maintenance_health_v1()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.run_pongo_queue_maintenance_v1() TO service_role;
GRANT EXECUTE ON FUNCTION public.run_pongo_ranked_maintenance_v1() TO service_role;
GRANT EXECUTE ON FUNCTION public.pongo_queue_maintenance_health_v1()
  TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pongo_ranked_maintenance_health_v1()
  TO authenticated,service_role;

-- Hosted projects expose cron.schedule after the Cron integration is enabled.
-- Dynamic SQL keeps clean local Supabase resets working when pg_cron is absent.
DO $schedule_if_available$
DECLARE
  conflict_count INTEGER;
  installed_count INTEGER;
BEGIN
  IF to_regprocedure('cron.schedule(text,text,text)') IS NOT NULL THEN
    -- A same-name call by the same owner updates the existing job. Refuse any
    -- differently named copy or same-name job owned by another role so this
    -- migration can never create parallel maintenance workers accidentally.
    EXECUTE $conflicts$
      SELECT COUNT(*)::INTEGER
      FROM cron.job
      WHERE (
        jobname IN(
          'pongo-queue-expiration-v1',
          'pongo-ranked-expiration-v1',
          'pongo-cron-history-cleanup-v1'
        )
        AND username<>current_user
      ) OR (
        COALESCE(jobname,'') NOT IN(
          'pongo-queue-expiration-v1',
          'pongo-ranked-expiration-v1',
          'pongo-cron-history-cleanup-v1'
        )
        AND command IN(
          'SELECT public.run_pongo_queue_maintenance_v1()',
          'SELECT public.run_pongo_ranked_maintenance_v1()'
        )
      )
    $conflicts$ INTO conflict_count;
    IF conflict_count<>0 THEN
      RAISE EXCEPTION 'Conflicting Pongo Cron job exists; inspect cron.job before applying this migration';
    END IF;

    EXECUTE format(
      'SELECT cron.schedule(%L,%L,%L)',
      'pongo-queue-expiration-v1',
      '10 seconds',
      'SELECT public.run_pongo_queue_maintenance_v1()'
    );
    EXECUTE format(
      'SELECT cron.schedule(%L,%L,%L)',
      'pongo-ranked-expiration-v1',
      '*/5 * * * *',
      'SELECT public.run_pongo_ranked_maintenance_v1()'
    );
    EXECUTE format(
      'SELECT cron.schedule(%L,%L,%L)',
      'pongo-cron-history-cleanup-v1',
      '0 3 * * *',
      $cleanup$DELETE FROM cron.job_run_details
        WHERE end_time<clock_timestamp()-INTERVAL '7 days'$cleanup$
    );

    EXECUTE $installed$
      SELECT COUNT(*)::INTEGER
      FROM cron.job
      WHERE username=current_user
        AND active
        AND (
          (jobname='pongo-queue-expiration-v1'
            AND schedule='10 seconds'
            AND command='SELECT public.run_pongo_queue_maintenance_v1()')
          OR (jobname='pongo-ranked-expiration-v1'
            AND schedule='*/5 * * * *'
            AND command='SELECT public.run_pongo_ranked_maintenance_v1()')
          OR (jobname='pongo-cron-history-cleanup-v1'
            AND schedule='0 3 * * *')
        )
    $installed$ INTO installed_count;
    IF installed_count<>3 THEN
      RAISE EXCEPTION 'Pongo Cron jobs were not installed with the expected owner, schedules, and commands';
    END IF;
  END IF;
END;
$schedule_if_available$;

NOTIFY pgrst,'reload schema';
COMMIT;
