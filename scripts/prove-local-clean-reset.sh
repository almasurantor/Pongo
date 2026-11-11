#!/usr/bin/env bash
set -euo pipefail

if [[ "${PONGO_ALLOW_LOCAL_RESET_PROOF:-}" != "YES_RESET_LOCAL_PONGO" ]]; then
  echo "Refusing to reset the local stack. Set PONGO_ALLOW_LOCAL_RESET_PROOF=YES_RESET_LOCAL_PONGO." >&2
  exit 1
fi

db_container="${SUPABASE_DB_CONTAINER:-supabase_db_pongo}"
cli_version="${PONGO_CLI_VERSION:-3.0.0}"

if [[ "$(find supabase/migrations -type f -name '*.sql' | wc -l | tr -d ' ')" != "33" ]]; then
  echo "Expected exactly 33 local migrations." >&2
  exit 1
fi

npx --yes "supabase@${cli_version}" db reset --no-seed

docker cp supabase/seed.testing.sql "$db_container:/tmp/pongo-seed.testing.sql"
docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -f /tmp/pongo-seed.testing.sql >/dev/null

dirty_counts="$(docker exec "$db_container" psql -X -At -v ON_ERROR_STOP=1 \
  -U postgres -d postgres -c \
  "SELECT COUNT(*)||','||(SELECT COUNT(*) FROM public.profiles)||','||(SELECT COUNT(*) FROM public.matches) FROM auth.users;")"
if [[ "$dirty_counts" != "14,14,19" ]]; then
  echo "Fixture did not create the expected dirty state: $dirty_counts" >&2
  exit 1
fi

npx --yes "supabase@${cli_version}" db reset --no-seed

clean_result="$(docker exec "$db_container" psql -X -At -v ON_ERROR_STOP=1 \
  -U postgres -d postgres -c \
  "SELECT
    (SELECT COUNT(*) FROM auth.users)=0
    AND (SELECT COUNT(*) FROM public.profiles)=0
    AND (SELECT COUNT(*) FROM public.matches)=0
    AND (SELECT COUNT(*) FROM public.beaver_queue_members)=0
    AND (SELECT COUNT(*) FROM supabase_migrations.schema_migrations)=33
    AND EXISTS(SELECT 1 FROM public.ranking_config WHERE id AND daily_ranked_player_limit=10 AND daily_ranked_pair_limit=3)
    AND EXISTS(SELECT 1 FROM public.beaver_queue_table WHERE id=1 AND phase='idle' AND king_id IS NULL AND challenger_id IS NULL);")"
if [[ "$clean_result" != "t" ]]; then
  echo "Clean reset assertions failed." >&2
  exit 1
fi

# Local Supabase does not enable pg_cron by default. Enable it only inside the
# isolated stack, then rerun the idempotent final migration to exercise its
# hosted scheduling branch.
docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c 'CREATE EXTENSION IF NOT EXISTS pg_cron;' >/dev/null
docker cp supabase/migrations/20261104100000_queue_maintenance_worker.sql \
  "$db_container:/tmp/20261104100000_queue_maintenance_worker.sql"
docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -f /tmp/20261104100000_queue_maintenance_worker.sql >/dev/null

sleep 12
docker exec "$db_container" psql -X -At -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c 'SELECT public.run_pongo_ranked_maintenance_v1();' >/dev/null
docker cp supabase/production/04_clean_reset_readonly_verify.sql \
  "$db_container:/tmp/04_clean_reset_readonly_verify.sql"
docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -f /tmp/04_clean_reset_readonly_verify.sql

echo "Local dirty-to-clean reset, schema, and Cron-installation proof passed."
echo "The ranked wrapper was invoked directly; confirm its scheduled run after the next five-minute boundary."
