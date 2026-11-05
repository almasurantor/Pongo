#!/usr/bin/env bash
set -euo pipefail

: "${PONGO_PRODUCTION_DATABASE_URL:?Set PONGO_PRODUCTION_DATABASE_URL to the direct or session-pooler connection string}"

# The database itself enforces read-only mode for every statement in the files.
export PGOPTIONS="${PGOPTIONS:-} -c default_transaction_read_only=on -c statement_timeout=30000"

psql "$PONGO_PRODUCTION_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -f supabase/production/01_readonly_inventory.sql

if [[ "${1:-}" == "--postdeploy" ]]; then
  psql "$PONGO_PRODUCTION_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
    -f supabase/production/02_postdeploy_readonly_verify.sql
fi
