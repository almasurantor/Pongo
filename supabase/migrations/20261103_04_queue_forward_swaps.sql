-- Queue V4: only a waiting player ahead in line may offer a position swap to
-- a waiting player behind them. Apply after 20261103_03.
BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.beaver_queue_health_v3()') IS NULL
     OR to_regclass('public.beaver_queue_swap_requests') IS NULL THEN
    RAISE EXCEPTION 'Missing dependency: apply 20261103_03_queue_outcomes_swaps.sql first';
  END IF;
END;
$dependencies$;

-- Requests created under V3 point in the opposite direction. Cancel any that
-- have not been answered so nobody can accept a request under changed rules.
UPDATE public.beaver_queue_swap_requests
SET status='canceled',responded_at=clock_timestamp()
WHERE status='pending';

ALTER TABLE public.beaver_queue_swap_requests
  DROP CONSTRAINT IF EXISTS beaver_queue_swap_direction;
ALTER TABLE public.beaver_queue_swap_requests
  ADD CONSTRAINT beaver_queue_swap_direction CHECK(
    status<>'pending' OR target_position>requester_position
  );

CREATE OR REPLACE FUNCTION public.beaver_queue_request_swap_v1(p_target UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  requester public.beaver_queue_members%ROWTYPE;
  target public.beaver_queue_members%ROWTYPE;
  request_id UUID;
  requester_rank BIGINT;
  target_rank BIGINT;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF p_target IS NULL OR p_target=player_id THEN RAISE EXCEPTION 'Choose another waiting player'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO requester FROM public.beaver_queue_members WHERE user_id=player_id;
  SELECT * INTO target FROM public.beaver_queue_members WHERE user_id=p_target;
  IF requester.status IS DISTINCT FROM 'waiting' OR target.status IS DISTINCT FROM 'waiting' THEN
    RAISE EXCEPTION 'Both players must still be waiting';
  END IF;
  IF target.queue_position<=requester.queue_position THEN
    RAISE EXCEPTION 'You can only request a swap with a player behind you';
  END IF;
  IF EXISTS(SELECT 1 FROM public.beaver_queue_swap_requests request
    WHERE request.status='pending' AND request.expires_at>clock_timestamp()
      AND (player_id IN(request.requester_id,request.target_id)
        OR p_target IN(request.requester_id,request.target_id))) THEN
    RAISE EXCEPTION 'One of these players already has a pending swap request';
  END IF;
  SELECT COUNT(*)+1 INTO requester_rank FROM public.beaver_queue_members member
  WHERE member.status='waiting' AND member.queue_position<requester.queue_position;
  SELECT COUNT(*)+1 INTO target_rank FROM public.beaver_queue_members member
  WHERE member.status='waiting' AND member.queue_position<target.queue_position;
  INSERT INTO public.beaver_queue_swap_requests(
    requester_id,target_id,requester_position,target_position,expires_at
  ) VALUES(player_id,p_target,requester_rank,target_rank,
    clock_timestamp()+INTERVAL '60 seconds') RETURNING id INTO request_id;
  RETURN jsonb_build_object('request_id',request_id,'status','pending');
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_respond_swap_v1(p_request UUID,p_action TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  player_id UUID:=auth.uid();
  normalized_action TEXT:=LOWER(BTRIM(COALESCE(p_action,'')));
  request public.beaver_queue_swap_requests%ROWTYPE;
  requester public.beaver_queue_members%ROWTYPE;
  target public.beaver_queue_members%ROWTYPE;
  temporary_position BIGINT;
BEGIN
  IF player_id IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  IF normalized_action NOT IN('accept','decline') THEN RAISE EXCEPTION 'Action must be accept or decline'; END IF;
  PERFORM 1 FROM public.beaver_queue_table WHERE id=1 FOR UPDATE;
  PERFORM public.beaver_queue_advance_internal_v1();
  SELECT * INTO request FROM public.beaver_queue_swap_requests WHERE id=p_request FOR UPDATE;
  IF NOT FOUND OR request.target_id<>player_id THEN RAISE EXCEPTION 'Swap request is not available'; END IF;
  IF request.status<>'pending' THEN RAISE EXCEPTION 'Swap request is no longer available'; END IF;
  IF request.expires_at<=clock_timestamp() THEN
    UPDATE public.beaver_queue_swap_requests SET status='expired',responded_at=clock_timestamp() WHERE id=request.id;
    RAISE EXCEPTION 'Swap request has expired';
  END IF;

  SELECT * INTO requester FROM public.beaver_queue_members WHERE user_id=request.requester_id;
  SELECT * INTO target FROM public.beaver_queue_members WHERE user_id=request.target_id;
  IF requester.status IS DISTINCT FROM 'waiting' OR target.status IS DISTINCT FROM 'waiting' THEN
    UPDATE public.beaver_queue_swap_requests SET status='canceled',responded_at=clock_timestamp()
    WHERE id=request.id;
    RAISE EXCEPTION 'Both players must still be waiting';
  END IF;
  IF target.queue_position<=requester.queue_position THEN
    UPDATE public.beaver_queue_swap_requests SET status='canceled',responded_at=clock_timestamp()
    WHERE id=request.id;
    RAISE EXCEPTION 'Queue positions changed; request another swap';
  END IF;
  IF EXISTS(SELECT 1 FROM public.beaver_queue_swap_requests other
    WHERE other.id<>request.id AND other.status='pending' AND other.expires_at>clock_timestamp()
      AND (request.requester_id IN(other.requester_id,other.target_id)
        OR request.target_id IN(other.requester_id,other.target_id))) THEN
    RAISE EXCEPTION 'A conflicting swap request is pending';
  END IF;
  IF normalized_action='decline' THEN
    UPDATE public.beaver_queue_swap_requests SET status='declined',responded_at=clock_timestamp()
    WHERE id=request.id;
    RETURN jsonb_build_object('request_id',request.id,'status','declined');
  END IF;

  temporary_position:=-nextval('public.beaver_queue_position_seq');
  UPDATE public.beaver_queue_members SET queue_position=temporary_position,updated_at=clock_timestamp()
  WHERE user_id=request.requester_id;
  UPDATE public.beaver_queue_members SET queue_position=requester.queue_position,updated_at=clock_timestamp()
  WHERE user_id=request.target_id;
  UPDATE public.beaver_queue_members SET queue_position=target.queue_position,updated_at=clock_timestamp()
  WHERE user_id=request.requester_id;
  UPDATE public.beaver_queue_swap_requests SET status='accepted',responded_at=clock_timestamp()
  WHERE id=request.id;
  RETURN jsonb_build_object('request_id',request.id,'status','accepted');
END;
$$;

CREATE OR REPLACE FUNCTION public.beaver_queue_health_v4()
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
    'version','20261103_04','initialized',state.id=1,'phase',state.phase,
    'member_status',my_status,
    'heartbeat_granted',has_function_privilege('authenticated','public.beaver_queue_heartbeat_v1()','EXECUTE'),
    'join_granted',has_function_privilege('authenticated','public.beaver_queue_join_v1()','EXECUTE'),
    'outcome_granted',has_function_privilege('authenticated','public.beaver_queue_report_outcome_v2(uuid,text)','EXECUTE'),
    'swap_request_granted',has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE'),
    'swap_response_granted',has_function_privilege('authenticated','public.beaver_queue_respond_swap_v1(uuid,text)','EXECUTE'),
    'swap_granted',
      has_function_privilege('authenticated','public.beaver_queue_request_swap_v1(uuid)','EXECUTE')
      AND has_function_privilege('authenticated','public.beaver_queue_respond_swap_v1(uuid,text)','EXECUTE')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.beaver_queue_request_swap_v1(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_respond_swap_v1(UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.beaver_queue_health_v4() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.beaver_queue_request_swap_v1(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_respond_swap_v1(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.beaver_queue_health_v4() TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
