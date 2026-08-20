#!/usr/bin/env bash
#
# restic backup, run every six hours from cron or a systemd timer.
#
# Two things worth noting. The filestore is backed up alongside the database: a
# database dump on its own loses every attachment, which is the single most common
# way a self-managed Odoo backup turns out to be useless.
#
# And the restic repository password is held by the customer. If the contractor can
# decrypt the backups unilaterally, the customer does not really have backups, they
# have someone else's copy of their data.

set -euo pipefail

DB_NAME="${DB_NAME:?DB_NAME must be set}"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

echo "==> dumping ${DB_NAME}"
docker compose exec -T db pg_dump -U "${DB_USER}" -Fc "${DB_NAME}" > "${STAGING}/${DB_NAME}.dump"

echo "==> copying filestore"
docker compose cp odoo:/var/lib/odoo "${STAGING}/filestore"

echo "==> restic backup"
restic backup "${STAGING}" \
  --tag odoo \
  --tag "db:${DB_NAME}" \
  --host "$(hostname)"

echo "==> pruning"
restic forget \
  --keep-hourly 24 \
  --keep-daily 14 \
  --keep-weekly 8 \
  --keep-monthly 12 \
  --prune

echo "==> done"
