-- One read-only statement for `supabase db query --read-only --file ...`.
-- Review every array before authorizing a remote reset. No secret values are read.
SELECT jsonb_pretty(jsonb_build_object(
  'captured_at',clock_timestamp(),
  'database',current_database(),
  'database_user',current_user,
  'extensions',(
    SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.extname),'[]'::JSONB)
    FROM (SELECT extname,extversion FROM pg_extension) item
  ),
  'non_system_schemas',(
    SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.schema_name),'[]'::JSONB)
    FROM (
      SELECT namespace.nspname AS schema_name,
             COUNT(object.oid) FILTER(WHERE object.relkind IN('r','p')) AS tables,
             COUNT(object.oid) FILTER(WHERE object.relkind='v') AS views,
             COUNT(object.oid) FILTER(WHERE object.relkind='S') AS sequences
      FROM pg_namespace namespace
      LEFT JOIN pg_class object ON object.relnamespace=namespace.oid
      WHERE namespace.nspname NOT LIKE 'pg\_%' ESCAPE '\'
        AND namespace.nspname<>'information_schema'
      GROUP BY namespace.nspname
    ) item
  ),
  'non_system_roles',(
    SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.rolname),'[]'::JSONB)
    FROM (
      SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole
      FROM pg_roles WHERE rolname NOT LIKE 'pg\_%' ESCAPE '\'
    ) item
  ),
  'migration_ledger',jsonb_build_object(
    'exists',to_regclass('supabase_migrations.schema_migrations') IS NOT NULL,
    'rows',CASE
      WHEN to_regclass('supabase_migrations.schema_migrations') IS NULL
        THEN '[]'::JSONB
      ELSE COALESCE(
        ((xpath(
          '/table/row/payload/text()',
          query_to_xml(
            $migration_query$
              SELECT COALESCE(
                jsonb_agg(to_jsonb(item) ORDER BY item.version),
                '[]'::JSONB
              )::TEXT AS payload
              FROM (
                SELECT version::TEXT,name::TEXT
                FROM supabase_migrations.schema_migrations
              ) item
            $migration_query$,
            TRUE,FALSE,''
          )
        ))[1]::TEXT)::JSONB,
        '[]'::JSONB
      )
    END
  ),
  'cron_jobs',jsonb_build_object(
    'exists',to_regclass('cron.job') IS NOT NULL,
    'rows',CASE
      WHEN to_regclass('cron.job') IS NULL THEN '[]'::JSONB
      ELSE COALESCE(
        ((xpath(
          '/table/row/payload/text()',
          query_to_xml(
            $cron_query$
              SELECT COALESCE(
                jsonb_agg(to_jsonb(item) ORDER BY item.jobname,item.jobid),
                '[]'::JSONB
              )::TEXT AS payload
              FROM (
                SELECT jobid,jobname,schedule,command,database,username,active
                FROM cron.job
              ) item
            $cron_query$,
            TRUE,FALSE,''
          )
        ))[1]::TEXT)::JSONB,
        '[]'::JSONB
      )
    END
  ),
  'publications',(
    SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.pubname),'[]'::JSONB)
    FROM (
      SELECT pubname,puballtables,pg_get_userbyid(pubowner) AS owner
      FROM pg_publication
    ) item
  ),
  'event_triggers',(
    SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.evtname),'[]'::JSONB)
    FROM (
      SELECT evtname,evtevent,evtenabled,evtfoid::regprocedure::TEXT AS function_name
      FROM pg_event_trigger
    ) item
  ),
  'foreign_servers',(
    SELECT COALESCE(jsonb_agg(to_jsonb(item) ORDER BY item.fdwname,item.srvname),'[]'::JSONB)
    FROM (
      SELECT wrapper.fdwname,server.srvname,server.srvoptions
      FROM pg_foreign_server server
      JOIN pg_foreign_data_wrapper wrapper ON wrapper.oid=server.srvfdw
    ) item
  ),
  'managed_resources',(
    SELECT jsonb_object_agg(expected.resource,jsonb_build_object(
      'exists',relation.oid IS NOT NULL,
      'estimated_rows',CASE WHEN relation.oid IS NULL THEN NULL
        ELSE GREATEST(relation.reltuples,0)::BIGINT END
    ))
    FROM (VALUES
      ('auth_users','auth','users'),
      ('storage_buckets','storage','buckets'),
      ('storage_objects','storage','objects')
    ) expected(resource,schema_name,table_name)
    LEFT JOIN pg_namespace namespace ON namespace.nspname=expected.schema_name
    LEFT JOIN pg_class relation
      ON relation.relnamespace=namespace.oid AND relation.relname=expected.table_name
  ),
  'application_relations',(
    SELECT jsonb_object_agg(expected.resource,jsonb_build_object(
      'exists',relation.oid IS NOT NULL,
      'estimated_rows',CASE WHEN relation.oid IS NULL THEN NULL
        ELSE GREATEST(relation.reltuples,0)::BIGINT END
    ))
    FROM (VALUES
      ('profiles','profiles'),('challenges','challenges'),('matches','matches'),
      ('rating_events','rating_events'),('queue_members','beaver_queue_members'),
      ('queue_games','beaver_queue_games'),
      ('queue_ranked_requests','beaver_queue_ranked_requests')
    ) expected(resource,table_name)
    LEFT JOIN pg_namespace namespace ON namespace.nspname='public'
    LEFT JOIN pg_class relation
      ON relation.relnamespace=namespace.oid AND relation.relname=expected.table_name
  ),
  'ranking_config',jsonb_build_object(
    'exists',to_regclass('public.ranking_config') IS NOT NULL,
    'rows',CASE
      WHEN to_regclass('public.ranking_config') IS NULL THEN '[]'::JSONB
      ELSE COALESCE(
        ((xpath(
          '/table/row/payload/text()',
          query_to_xml(
            $ranking_query$
              SELECT COALESCE(jsonb_agg(to_jsonb(item)),'[]'::JSONB)::TEXT AS payload
              FROM (
                SELECT id,daily_ranked_player_limit,daily_ranked_pair_limit,
                       active_ranked_match_limit,updated_at
                FROM public.ranking_config
              ) item
            $ranking_query$,
            TRUE,FALSE,''
          )
        ))[1]::TEXT)::JSONB,
        '[]'::JSONB
      )
    END
  ),
  'reset_dependencies',jsonb_build_object(
    'pg_cron',EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron'),
    'cron_schedule',to_regprocedure('cron.schedule(text,text,text)') IS NOT NULL,
    'queue_advance',to_regprocedure('public.beaver_queue_advance_expired_v1()') IS NOT NULL,
    'queue_overtime',to_regprocedure('public.beaver_queue_overtime_v1(uuid,text)') IS NOT NULL,
    'ranked_expire',to_regprocedure('public.expire_mobile_ranking_items_v2()') IS NOT NULL
  )
));
