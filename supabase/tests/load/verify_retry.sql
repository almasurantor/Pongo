\set ON_ERROR_STOP on

DO $$
BEGIN
  IF (SELECT COUNT(*) FROM public.beaver_queue_members
      WHERE status IN('waiting','called','king','playing'))<>50 THEN
    RAISE EXCEPTION 'Idempotent retries changed the active queue size';
  END IF;
  IF EXISTS(
    SELECT 1
    FROM public.beaver_queue_members member
    JOIN public.queue_load_position_snapshot snapshot USING(user_id)
    WHERE member.queue_position<>snapshot.queue_position
  ) THEN
    RAISE EXCEPTION 'Idempotent join retry changed a queue position';
  END IF;
END;
$$;
