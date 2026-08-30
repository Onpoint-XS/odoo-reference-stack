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
DB_USER="${DB_USER:?DB_USER must be set}"

# Validate before destroying anything.
#
# This script used to drop the database first and find out whether the snapshot was
# any good afterwards. If pg_restore then failed there was nothing to go back to, at
# the exact moment something had already gone wrong. restore_drill.sh has always
# restored into a throwaway database and checked it before dropping; this script did
# not, and the repository already contained the pattern it should have used.
#
# pg_restore --list reads the archive table of contents without touching a database,
# so it costs nothing and catches truncation, corruption and zero-byte files. The
# deploy workflow creates the dump with a shell redirect, which means the file exists
# before pg_dump writes to it, so a dump that died halfway leaves something that looks
# perfectly normal on disk.
echo "==> validating ${SNAPSHOT} before touching the database"

if [[ ! -s "${SNAPSHOT}" ]]; then
  echo "FAIL: ${SNAPSHOT} is missing or empty. Refusing to drop the database." >&2
  exit 1
fi

if ! docker compose exec -T db pg_restore --list >/dev/null 2>&1 < "${SNAPSHOT}"; then
  echo "FAIL: ${SNAPSHOT} is not a readable pg_dump archive. Refusing to drop the database." >&2
  exit 1
fi

echo "==> snapshot is readable, proceeding"

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
