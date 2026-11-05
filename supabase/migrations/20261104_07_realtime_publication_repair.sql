-- Pongo realtime publication repair.
-- Safe and idempotent: it changes no application data or business rules.
BEGIN;

DO $realtime$
DECLARE
  table_name TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    RAISE EXCEPTION 'Missing Supabase Realtime publication';
  END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'profiles',
    'challenges',
    'matches',
    'rating_events',
    'disputes',
    'match_cancellation_requests',
    'beaver_queue_table',
    'beaver_queue_members',
    'beaver_queue_games',
    'beaver_queue_swap_requests',
    'beaver_queue_ranked_requests'
  ]
  LOOP
    IF to_regclass(format('public.%I', table_name)) IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM pg_catalog.pg_publication_tables
         WHERE pubname = 'supabase_realtime'
           AND schemaname = 'public'
           AND tablename = table_name
       ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
    END IF;
  END LOOP;
END;
$realtime$;

COMMIT;
