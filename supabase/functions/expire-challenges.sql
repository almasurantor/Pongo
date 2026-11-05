-- Schedule this trusted cleanup RPC through a Supabase Edge Function or an
-- equivalent service-role worker every five minutes:
--
--   */5 * * * *
--
-- It expires pending challenges, accepted matches, pending cancellation
-- requests, and escalates overdue result disputes. The function is installed
-- by the incremental Pongo V3 migrations, not schema.sql.

-- Manual service-role invocation for operational verification:
SELECT public.expire_mobile_ranking_items_v2();
