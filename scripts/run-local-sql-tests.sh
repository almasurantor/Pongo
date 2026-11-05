#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:-supabase_db_pongo}"
test_dir="/tmp/pongo-sql-tests"

docker exec "$db_container" sh -lc "mkdir -p '$test_dir'"
docker cp supabase/tests/. "$db_container:$test_dir"

passed=0
for test_file in supabase/tests/*.test.sql; do
  test_name="$(basename "$test_file")"
  docker exec "$db_container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
    -f "$test_dir/$test_name" >/dev/null
  echo "PASS $test_name"
  passed=$((passed + 1))
done

echo "Passed $passed SQL integration files."
