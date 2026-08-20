#!/usr/bin/env bash
#
# Assert that a module's installed version actually moved.
#
# Odoo will finish an upgrade, report no error, and leave a module at its previous
# version. Usually because the manifest version was not bumped, occasionally because
# the upgrade silently failed. Either way the deploy "succeeded" and the change is
# not live, and you find out days later when a field is missing.
#
# Usage:  assert_version.sh <module> <expected_version>
# Exit 0 when the installed version matches. Non-zero otherwise, loudly.

set -euo pipefail

MODULE="${1:?module name required}"
EXPECTED="${2:?expected version required}"
DB_NAME="${DB_NAME:?DB_NAME must be set}"

installed="$(docker compose exec -T db psql -U "${DB_USER}" -d "${DB_NAME}" -tAc \
  "SELECT latest_version FROM ir_module_module WHERE name = '${MODULE}' AND state = 'installed'")"

if [[ -z "${installed}" ]]; then
  echo "FAIL: module '${MODULE}' is not installed at all" >&2
  exit 2
fi

if [[ "${installed}" != "${EXPECTED}" ]]; then
  echo "FAIL: '${MODULE}' is at ${installed}, expected ${EXPECTED}" >&2
  echo "      The upgrade reported success and did not apply. Rolling back." >&2
  exit 1
fi

echo "OK: ${MODULE} at ${installed}"
