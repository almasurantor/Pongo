\set ON_ERROR_STOP on

DO $$
BEGIN
  IF (SELECT COUNT(*) FROM public.beaver_queue_members
      WHERE status IN('waiting','called','king','playing'))<>50 THEN
    RAISE EXCEPTION 'Expected exactly 50 active queue members after concurrent joins';
  END IF;
  IF (SELECT COUNT(DISTINCT queue_position) FROM public.beaver_queue_members)<>50 THEN
    RAISE EXCEPTION 'Concurrent joins produced duplicate queue positions';
  END IF;
END;
$$;

INSERT INTO public.queue_load_position_snapshot(user_id,queue_position)
SELECT user_id,queue_position FROM public.beaver_queue_members;
