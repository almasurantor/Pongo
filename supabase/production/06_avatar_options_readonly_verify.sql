-- Read-only post-migration proof for the additive avatar vocabulary release.
SELECT jsonb_build_object(
  'migration_applied',EXISTS(
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version='20261111010000' AND name='expand_avatar_options'
  ),
  'migration_count',(SELECT COUNT(*) FROM supabase_migrations.schema_migrations),
  'v2_constraint_validated',EXISTS(
    SELECT 1
    FROM pg_catalog.pg_constraint constraint_row
    JOIN pg_catalog.pg_class relation ON relation.oid=constraint_row.conrelid
    JOIN pg_catalog.pg_namespace schema ON schema.oid=relation.relnamespace
    WHERE schema.nspname='public' AND relation.relname='profiles'
      AND constraint_row.conname='profiles_avatar_config_v2_check'
      AND constraint_row.convalidated
  ),
  'v1_constraint_removed',NOT EXISTS(
    SELECT 1
    FROM pg_catalog.pg_constraint constraint_row
    JOIN pg_catalog.pg_class relation ON relation.oid=constraint_row.conrelid
    JOIN pg_catalog.pg_namespace schema ON schema.oid=relation.relnamespace
    WHERE schema.nspname='public' AND relation.relname='profiles'
      AND constraint_row.conname='profiles_avatar_config_v1_check'
  ),
  'save_rpc_present',to_regprocedure('public.update_my_avatar_v1(jsonb)') IS NOT NULL,
  'save_rpc_authenticated',has_function_privilege(
    'authenticated','public.update_my_avatar_v1(jsonb)','EXECUTE'
  ),
  'invalid_public_constraints',(
    SELECT COUNT(*)
    FROM pg_catalog.pg_constraint constraint_row
    JOIN pg_catalog.pg_class relation ON relation.oid=constraint_row.conrelid
    JOIN pg_catalog.pg_namespace schema ON schema.oid=relation.relnamespace
    WHERE schema.nspname='public' AND NOT constraint_row.convalidated
  ),
  'avatar_rows',(SELECT COUNT(*) FROM public.profiles WHERE avatar_config IS NOT NULL),
  'auth_users',(SELECT COUNT(*) FROM auth.users),
  'auth_sessions',(SELECT COUNT(*) FROM auth.sessions),
  'queue_maintenance_healthy',(
    SELECT state.last_succeeded_at IS NOT NULL
      AND state.last_succeeded_at>clock_timestamp()-INTERVAL '30 seconds'
    FROM public.pongo_maintenance_state state WHERE state.task='queue'
  ),
  'ranked_maintenance_healthy',(
    SELECT state.last_succeeded_at IS NOT NULL
      AND state.last_succeeded_at>clock_timestamp()-INTERVAL '10 minutes'
    FROM public.pongo_maintenance_state state WHERE state.task='ranked'
  )
);
