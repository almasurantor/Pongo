-- Supabase Cron schedules the trusted wrapper installed by migration
-- 20261104100000 every five minutes:
--
--   */5 * * * *
--
-- It expires pending challenges, accepted matches, pending cancellation
-- requests, and escalates overdue result disputes. The function is installed
-- by the ordered migration chain.

-- Manual service-role invocation and health verification:
SELECT public.run_pongo_ranked_maintenance_v1();
SELECT public.pongo_ranked_maintenance_health_v1();
