-- Queue V7: a current table holder is inherently present for the next match.
-- Apply after 20261104_02_queue_match_expiry_checkins.sql.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.beaver_queue_health_v6()') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply 20261104_02_queue_match_expiry_checkins.sql first';
  END IF;
END;
$dependencies$;

-- Enforce the invariant at the table boundary so it also fixes databases that
-- installed the first V6 function before holder auto-presence was added.
CREATE OR REPLACE FUNCTION public.beaver_queue_autoconfirm_holder_v1()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path=''
AS $$
BEGIN
  IF NEW.phase='called' AND NEW.king_id IS NOT NULL AND NEW.king_confirmed_at IS NULL THEN
    NEW.king_confirmed_at:=clock_timestamp();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS beaver_queue_autoconfirm_holder_v1 ON public.beaver_queue_table;
CREATE TRIGGER beaver_queue_autoconfirm_holder_v1
BEFORE INSERT OR UPDATE OF phase,king_id,challenger_id,king_confirmed_at
ON public.beaver_queue_table
FOR EACH ROW
EXECUTE FUNCTION public.beaver_queue_autoconfirm_holder_v1();

-- Unstick an active call immediately. This covers the exact reported failure:
-- the challenger confirmed under the earlier V6 function, but the holder's
-- confirmation was null so the match remained in the called phase.
UPDATE public.beaver_queue_table
SET king_confirmed_at=COALESCE(king_confirmed_at,clock_timestamp()),
    updated_at=clock_timestamp()
WHERE id=1 AND phase='called' AND king_id IS NOT NULL;

DO $repair_active_call$
DECLARE
  state public.beaver_queue_table%ROWTYPE;
  match_started_at TIMESTAMPTZ;
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  IF state.phase='called'
     AND state.king_confirmed_at IS NOT NULL
     AND state.challenger_confirmed_at IS NOT NULL THEN
    match_started_at:=clock_timestamp();
    UPDATE public.beaver_queue_members
    SET status='playing',updated_at=clock_timestamp()
    WHERE user_id IN(state.king_id,state.challenger_id)
      AND status IN('king','called');
    UPDATE public.beaver_queue_table SET
      phase='playing',game_id=gen_random_uuid(),game_started_at=match_started_at,
      game_expires_at=match_started_at+INTERVAL '10 minutes',call_expires_at=NULL,
      king_confirmed_at=NULL,challenger_confirmed_at=NULL,solo_expires_at=NULL,
      afk_reporter_id=NULL,afk_target_id=NULL,afk_expires_at=NULL,
      updated_at=clock_timestamp()
    WHERE id=1 AND phase='called';
  END IF;
END;
$repair_active_call$;

CREATE OR REPLACE FUNCTION public.beaver_queue_health_v7()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  state public.beaver_queue_table%ROWTYPE;
  my_status TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  SELECT status INTO my_status FROM public.beaver_queue_members WHERE user_id=auth.uid();
  RETURN jsonb_build_object(
    'version','20261104_03','initialized',state.id=1,'phase',state.phase,
    'member_status',my_status,
    'heartbeat_granted',has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE'),
    'join_granted',has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE'),
    'tick_granted',has_function_privilege('authenticated','public.beaver_queue_tick_v1()','EXECUTE'),
    'outcome_granted',has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE'),
    'swap_granted',has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_respond_swap_v1(uuid,text)','EXECUTE'),
    'afk_granted',has_function_privilege('authenticated','public.beaver_queue_report_afk_v1()','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_confirm_presence_v1()','EXECUTE'),
    'holder_presence_trigger',EXISTS(
      SELECT 1 FROM pg_catalog.pg_trigger trigger_row
      WHERE trigger_row.tgrelid='public.beaver_queue_table'::regclass
        AND trigger_row.tgname='beaver_queue_autoconfirm_holder_v1'
        AND NOT trigger_row.tgisinternal
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.beaver_queue_autoconfirm_holder_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_health_v7() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_health_v7() TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
