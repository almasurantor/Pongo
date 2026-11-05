-- Production-readiness security repairs that must remain deployable after the
-- already-applied gameplay migrations.
BEGIN;

-- The original policy used an unqualified `id` inside the notifications
-- subquery. PostgreSQL resolved that name to notifications.id, so intended
-- recipients could not read the associated domain event. Qualify the outer
-- row explicitly while preserving actor and administrator access.
DROP POLICY IF EXISTS "Users read relevant events" ON public.domain_events;
CREATE POLICY "Users read relevant events"
  ON public.domain_events FOR SELECT TO authenticated
  USING(
    actor_id=auth.uid()
    OR EXISTS(
      SELECT 1
      FROM public.notifications recipient_notification
      WHERE recipient_notification.event_id=domain_events.id
        AND recipient_notification.user_id=auth.uid()
    )
    OR public.is_admin()
  );

COMMIT;
