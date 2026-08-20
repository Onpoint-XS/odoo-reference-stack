#!/usr/bin/env bash
#
# Roll the database and the code back together.
#
# This is the whole point of the script. Rolling back code alone leaves old code
# running against a migrated schema, which is a worse failure than the one you were
# recovering from, and it is what happens when a deploy pipeline treats "revert the
# commit" as a rollback.
#
# Usage:  rollback.sh <snapshot_file> <previous_commit_sha>

set -euo pipefail

SNAPSHOT="${1:?snapshot file required}"
PREV_SHA="${2:?previous commit sha required}"
DB_NAME="${DB_NAME:?DB_NAME must be set}"

echo "==> stopping odoo so nothing writes during the restore"
docker compose stop odoo

echo "==> dropping and recreating ${DB_NAME}"
docker compose exec -T db psql -U "${DB_USER}" -d postgres -c \
  "DROP DATABASE IF EXISTS ${DB_NAME} WITH (FORCE)"
docker compose exec -T db psql -U "${DB_USER}" -d postgres -c \
  "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}"

echo "==> restoring ${SNAPSHOT}"
docker compose exec -T db pg_restore -U "${DB_USER}" -d "${DB_NAME}" --no-owner < "${SNAPSHOT}"

echo "==> checking out ${PREV_SHA}"
git checkout --quiet "${PREV_SHA}"

echo "==> bringing the stack back up on the previous code"
docker compose up -d

echo "==> waiting for odoo to report healthy"
for _ in $(seq 1 30); do
  if curl -fsS http://localhost:8069/web/health >/dev/null 2>&1; then
    echo "==> rollback complete, database and code both at ${PREV_SHA}"
    exit 0
  fi
  sleep 5
done

echo "FAIL: rolled back but Odoo did not come up healthy. Manual intervention needed." >&2
exit 1
