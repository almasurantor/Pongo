\set ON_ERROR_STOP on

DO $$
DECLARE
  state public.beaver_queue_table%ROWTYPE;
BEGIN
  SELECT * INTO state FROM public.beaver_queue_table WHERE id=1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue singleton is missing'; END IF;
  IF (SELECT COUNT(*) FROM public.beaver_queue_members WHERE status='king')>1 THEN
    RAISE EXCEPTION 'More than one table holder exists';
  END IF;
  IF (SELECT COUNT(*) FROM public.beaver_queue_members WHERE status='called')>1 THEN
    RAISE EXCEPTION 'More than one called player exists';
  END IF;
  IF (SELECT COUNT(*) FROM public.beaver_queue_members
      WHERE status IN('waiting','called','king','playing'))>50 THEN
    RAISE EXCEPTION 'Churn duplicated active members';
  END IF;
  IF state.phase='called' AND (
    NOT EXISTS(SELECT 1 FROM public.beaver_queue_members
      WHERE user_id=state.king_id AND status='king')
    OR NOT EXISTS(SELECT 1 FROM public.beaver_queue_members
      WHERE user_id=state.challenger_id AND status='called')
  ) THEN
    RAISE EXCEPTION 'Called state is inconsistent with member statuses';
  END IF;
  IF state.phase='idle' AND state.king_id IS NOT NULL
     AND NOT EXISTS(SELECT 1 FROM public.beaver_queue_members
       WHERE user_id=state.king_id AND status='king') THEN
    RAISE EXCEPTION 'Idle holder is inconsistent with member status';
  END IF;
  IF EXISTS(
    SELECT queue_position FROM public.beaver_queue_members
    GROUP BY queue_position HAVING COUNT(*)>1
  ) THEN
    RAISE EXCEPTION 'Churn produced duplicate positions';
  END IF;
END;
$$;

SELECT phase,COUNT(*) FILTER(WHERE status IN('waiting','called','king','playing')) AS active_members
FROM public.beaver_queue_table CROSS JOIN public.beaver_queue_members
WHERE id=1
GROUP BY phase;
