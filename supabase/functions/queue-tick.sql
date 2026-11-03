-- Invoke this RPC with the service role from a trusted recurring worker.
-- Run it frequently (for example every 5-15 seconds) for prompt no-show
-- rotation even when no queue page is open. It is safe and idempotent.
SELECT public.beaver_queue_advance_expired_v1();
