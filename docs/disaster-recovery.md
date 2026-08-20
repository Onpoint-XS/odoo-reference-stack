# Disaster recovery

Numbers here are the ones the drill actually produces, not the ones anybody hoped for.
Update them when the drill output changes.

## Objectives

| | Target | How it is met |
|---|---|---|
| RPO, how much data you can lose | 6 hours | restic runs every six hours |
| RTO, how long to get back | Measured, not assumed | See the drill timing below |

RTO is deliberately not a promise. It is whatever the last restore drill measured, and
that number moves as the database grows. A DR document stating an RTO nobody has timed is
a work of fiction.

## What is backed up

- The PostgreSQL database, `pg_dump -Fc`
- **The filestore**, `/var/lib/odoo`

The second one is the one people lose. Every attachment, every uploaded document, every
generated PDF lives there and not in the database. A database-only backup restores into an
Odoo where every attachment is a broken link, and the failure is not visible until
somebody opens an old invoice.

## Who holds the key

The restic repository password is held by the customer. Not by the contractor, not in the
repository, not in the CI secrets store beyond what is needed to write new snapshots.

This is a deliberate constraint and it cuts both ways. It means the customer can recover
their data without the contractor, and it means the contractor cannot unilaterally decrypt
it. If the person who set up your backups can read them all on their own, you do not
really have backups.

## The drill

`scripts/restore_drill.sh`, weekly, via `.github/workflows/restore-drill.yml`.

It restores the most recent snapshot into a throwaway database, counts rows in tables that
should never be empty, prints the elapsed time, and drops the database. A restore that
completes into an empty database succeeds at the command line and fails at the only thing
that matters, so the row counts are the real assertion.

Record each run:

| Date | Snapshot | Restore time | Result |
|---|---|---|---|
| | | | |

## Scenarios

**Deploy broke production.** Automatic. The pipeline restores the pre-deploy snapshot and
checks out the previous commit together. Minutes.

**Database corrupted, or data deleted in error.** Restore the most recent six-hourly
snapshot. Recovery time is the drill timing. Data loss is whatever happened since the last
snapshot.

**The host is gone.** Provision a new one, install Docker, clone the repository, populate
`.env`, restore from restic, `docker compose up -d`. Everything except the secrets and the
data is in version control, which is the entire reason for pinning images by digest: a
rebuild six months later produces the same stack rather than a similar one.

**The backup repository is gone.** This is the one nobody plans for. Replicate the restic
repository to a second provider and confirm both are receiving snapshots. One copy in one
place is not a backup strategy.
