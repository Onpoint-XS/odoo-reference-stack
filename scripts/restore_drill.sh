#!/usr/bin/env bash
#
# Restore the most recent snapshot into a throwaway database, count rows, print a
# timing, then drop it.
#
# This is the script that separates having backups from having recovery. Almost
# everyone has the first. The number of production Odoo instances where somebody has
# actually restored a backup into a clean environment and timed it is small.
#
# Run it weekly. When it fails, you have found out on a Tuesday afternoon rather than
# during an outage.

set -euo pipefail

# Guarded because rollback.sh guards it and this script did not. Under set -u an
# unset DB_USER fails at first use with a bare bash error; this fails immediately
# and says which variable is missing.
DB_USER="${DB_USER:?DB_USER must be set}"

DRILL_DB="odoo_drill_$(date +%Y%m%d_%H%M%S)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
STARTED=$(date +%s)

SNAPSHOT="$(restic snapshots --tag odoo --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1]["short_id"])')"
echo "==> restoring snapshot ${SNAPSHOT} into ${DRILL_DB}"

restic restore "${SNAPSHOT}" --target "${WORKDIR}"
DUMP="$(find "${WORKDIR}" -name '*.dump' | head -n1)"

docker compose exec -T db psql -U "${DB_USER}" -d postgres -c \
  "CREATE DATABASE ${DRILL_DB} OWNER ${DB_USER}"
docker compose exec -T db pg_restore -U "${DB_USER}" -d "${DRILL_DB}" --no-owner < "${DUMP}"

ELAPSED=$(( $(date +%s) - STARTED ))
printf '==> restore completed in %dm%02ds\n' $(( ELAPSED / 60 )) $(( ELAPSED % 60 ))

# Row counts on tables that should never be empty. A restore that produces an empty
# database succeeds at the command line and fails at the only thing that matters.
FAILED=0
for table in res_partner account_move ir_module_module; do
  count="$(docker compose exec -T db psql -U "${DB_USER}" -d "${DRILL_DB}" -tAc \
    "SELECT count(*) FROM ${table}" 2>/dev/null || echo 0)"
  printf '==> %-20s %s rows\n' "${table}" "${count}"
  if [[ "${count}" -eq 0 ]]; then
    echo "    WARNING: ${table} is empty" >&2
    FAILED=1
  fi
done

docker compose exec -T db psql -U "${DB_USER}" -d postgres -c \
  "DROP DATABASE ${DRILL_DB} WITH (FORCE)" >/dev/null

if [[ "${FAILED}" -eq 1 ]]; then
  echo "==> drill FAILED"
  exit 1
fi

echo "==> drill PASSED, dropped ${DRILL_DB}"
