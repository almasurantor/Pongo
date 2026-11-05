#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:-supabase_db_pongo}"
load_dir="/tmp/pongo-queue-load"

docker exec "$db_container" sh -lc "mkdir -p '$load_dir'"
docker cp supabase/tests/load/. "$db_container:$load_dir"

docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -f "$load_dir/setup.sql" >/dev/null

echo "50 simultaneous queue joins"
docker exec "$db_container" pgbench -n -r -c 50 -j 10 -t 1 \
  -U postgres -d postgres -f "$load_dir/join.pgbench"
docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -f "$load_dir/verify_initial.sql"

echo "100 concurrent authenticated queue-state readers"
eval "$(npx --yes supabase@latest status -o env 2>/dev/null)"
export API_URL JWT_SECRET ANON_KEY
node scripts/queue-http-load.mjs

echo "50 simultaneous idempotent join retries"
docker exec "$db_container" pgbench -n -r -c 50 -j 10 -t 1 \
  -U postgres -d postgres -f "$load_dir/join.pgbench"
docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -f "$load_dir/verify_retry.sql"

echo "30 clients performing join/leave churn with concurrent expiry workers"
docker exec "$db_container" pgbench -n -r -c 30 -j 10 -t 20 \
  -U postgres -d postgres \
  -f "$load_dir/churn.pgbench@9" -f "$load_dir/expire.pgbench@1"
docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -f "$load_dir/verify_invariants.sql"

docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -f "$load_dir/cleanup.sql" >/dev/null

echo "Queue load invariants passed."
