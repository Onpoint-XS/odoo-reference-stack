# Runbook

What to do when it is 2am and something is wrong. Written for someone who did not build
this, because that is who is usually reading it.

## First, decide which of three things is happening

```
Is Odoo answering?          curl -fsS localhost:8069/web/health
Is the ORM answering?       curl -fsS localhost:8069/reference/health
Is PostgreSQL answering?    docker compose exec db pg_isready -U "$DB_USER"
```

A container that is running is not the same as an Odoo that is serving. The first check
can pass while the second fails, which means the process is up and the database
connection is gone.

## Odoo is up but everything is slow

Resist the urge to resize the server. It is almost never the server.

```sql
-- What is actually running right now, longest first
SELECT pid, now() - query_start AS duration, state, left(query, 120)
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY duration DESC;

-- What has cost the most time overall
SELECT calls, round(total_exec_time::numeric, 0) AS total_ms,
       round(mean_exec_time::numeric, 1) AS mean_ms, left(query, 120)
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;

-- Bloat. A two year old Odoo database with default autovacuum will show this.
SELECT relname, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC LIMIT 20;
```

The usual culprits, in the order they actually occur:

1. A scheduled action holding a lock during business hours. Check `ir_cron`.
2. An unstored computed field being read in a list view.
3. A report iterating records one at a time instead of reading in bulk.
4. Autovacuum never tuned, so tables bloated quietly over two years.
5. Workers configured for a machine you no longer run on.

Genuinely needing more hardware is sixth on that list, not first.

## A deploy failed

It has already rolled back. The deploy workflow restores the database and checks out the
previous commit together, so you should be on the previous release with the previous
schema. Confirm rather than assume:

```bash
git rev-parse HEAD
./scripts/assert_version.sh reference_health <previous_version>
```

If the rollback itself failed, the pre-deploy snapshot is in `/var/backups/` named by
timestamp. Restore it manually with `scripts/rollback.sh`.

## Somebody needs a database restore

Do not practise on production.

```bash
./scripts/restore_drill.sh
```

That restores the latest snapshot into a throwaway database and drops it afterwards. Read
the timing it prints, because that number is your actual recovery time, and it is the
only honest answer to how long it would take to get back.

## A module upgrade half-applied

Symptom: the deploy reported success and a field is missing.

```sql
SELECT name, state, latest_version FROM ir_module_module
WHERE state NOT IN ('installed', 'uninstalled');
```

Anything sitting in a pending upgrade or install state did not finish. Do not clear the
state by hand on production. Restore the snapshot, fix the module, deploy again.

## What not to do

- Do not `docker compose down` on production to fix a hang. Stop the odoo service only.
- Do not edit records in the database directly to work around an application bug. It
  works, and then six months later nobody can explain the data.
- Do not turn `list_db` back on to use the database manager. Restore from the CLI.
- Do not disable the version assertion because a deploy is urgent. That assertion exists
  because of an urgent deploy.
