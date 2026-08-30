# Security and reliability review, August 2026

**Subject:** this repository, at commit `d9834bf`.
**Reviewed:** 29 August 2026, read-only, static.
**Outcome:** six findings, three of them critical. **All six are fixed**, in [#2](https://github.com/Onpoint-XS/odoo-reference-stack/pull/2) and its follow-up.

This is a review of our own public reference implementation. It found three critical issues, which is
why it is published rather than filed.

**In scope:** `compose.yaml`, `config/odoo.conf`, `config/nginx/odoo.conf`, `.env.example`, the three
GitHub Actions workflows, `scripts/rollback.sh`, `scripts/restore_drill.sh`.

**Not in scope:** `scripts/assert_version.sh`, `config/postgresql.conf`, `addons/reference_health`,
`ruff.toml`, `docs/`. No live environment, no logs, no traffic. Every finding was read from the
repository, not observed running.

---

## Summary

The discipline in this stack is real and unusually well documented: images pinned by digest with the
update procedure written down, a health check that hits a genuine Odoo endpoint rather than a port,
and a post-deploy assertion that catches the specific failure where Odoo reports success and leaves
the module at its old version.

**Three critical findings sat underneath that, and all three were invisible from the outside.** The
Odoo master password was defined in the environment file, documented as the master password, and never
reached the container, so it fell back to the built-in default. The nginx rule that was supposed to put
the database manager out of reach matched two routes and left the destructive ones open. And the
rollback script dropped the production database before checking that the snapshot it was about to
restore could actually be read.

The first two were one line each and together they were a route to a full database dump from the
public internet.

---

## How severity is rated

Rated by consequence, not by category, so the ratings can be argued with.

| Severity | Definition | Response |
|---|---|---|
| **CRITICAL** | Data loss, credential exposure, or an outage path with no tested recovery | Before the next deploy |
| **HIGH** | **It can fail silently.** Something breaks and nobody finds out until a customer, an auditor or a demo tells you | This sprint |
| **MEDIUM** | Increases blast radius or slows recovery, but the failure is detectable | This quarter |
| **LOW** | Hygiene and consistency. Real, but nothing breaks | When convenient |

---

## Findings at a glance

| # | Finding | Severity | Status |
|---|---|---|---|
| F-01 | Master password defined, documented, never reaches the container | CRITICAL | Fixed |
| F-02 | nginx database block covers two routes, leaves the destructive ones open | CRITICAL | Fixed |
| F-03 | Rollback destroys the database before checking the snapshot restores | CRITICAL | Fixed |
| F-04 | Pre-deploy snapshots accumulate with no retention | HIGH | Fixed |
| F-05 | Deploy workflow depends on variables nothing in the repository provides | MEDIUM | Fixed |
| F-06 | Environment guards inconsistent between the two scripts | LOW | Fixed |

---

## F-01 — The Odoo master password is defined, documented, and never reaches the container

**Severity:** CRITICAL · **Area:** Secrets · **Status:** Fixed

### What was found

`.env.example` defined it and said what it was:

```
# Odoo master password. Controls the database manager.
ADMIN_PASSWD=change_me_too
```

The `odoo` service in `compose.yaml` passed three variables and this was not among them:

```yaml
environment:
  HOST: db
  USER: ${DB_USER}
  PASSWORD: ${DB_PASSWORD}
```

`config/odoo.conf` contained no `admin_passwd` line.

### What goes wrong

The variable was set, named correctly and commented, so any reader concluded the master password was
configured. Nothing connected it to Odoo. Odoo falls back to its built-in default, which is publicly
known. Nothing errors, nothing warns, and nothing in CI would catch it.

### Why this severity

The master password is the only credential protecting the database management endpoints. Combined with
F-02 it was a route to a complete database dump. It was also the worst kind of gap: one that looks
closed.

### Fix

`admin_passwd` is now set in `config/odoo.conf` as `CHANGE_ME_BEFORE_DEPLOY`, which is inert and
obviously a placeholder. `ADMIN_PASSWD` has been removed from `.env.example` entirely, because a
variable that looks configured and does nothing is worse than one that is absent.

### How to confirm it worked

```
docker compose exec odoo grep -c '^admin_passwd' /etc/odoo/odoo.conf
```

Expect `1`, and confirm the value is not the placeholder.

---

## F-02 — The nginx database block covers two routes and leaves the destructive ones open

**Severity:** CRITICAL · **Area:** Network · **Status:** Fixed

### What was found

```nginx
# The database manager stays unreachable from outside. Belt and braces alongside
# list_db = False in odoo.conf.
location ~ ^/web/database/(manager|selector) {
    return 404;
}
```

### What goes wrong

The pattern matched `manager` and `selector`. It did not match `backup`, `restore`, `drop`,
`duplicate`, `create` or `change_password`. Those are the routes that do damage: backup is data
exfiltration, drop is data loss, restore replaces the database wholesale.

The comment above the block stated the manager was unreachable from outside. That is not what the rule
achieved, and the comment is why nobody would look again.

**It also chained.** `.env.example` documented `DB_NAME=odoo`, so the database name an attacker needs
was the published default rather than a guess, and F-01 left the credential at its default.

### Fix

The pattern now covers the whole prefix:

```nginx
location ~ ^/web/database/ {
    return 404;
}
```

### How to confirm it worked

```
curl -sk -o /dev/null -w '%{http_code}\n' -X POST https://<host>/web/database/backup
```

Expect `404`. Repeat for `restore` and `drop`.

---

## F-03 — The rollback destroys the database before checking the snapshot can be restored

**Severity:** CRITICAL · **Area:** Recovery · **Status:** Fixed

### What was found

`scripts/rollback.sh` ran, in this order:

```bash
docker compose exec -T db psql ... -c "DROP DATABASE IF EXISTS ${DB_NAME} WITH (FORCE)"
docker compose exec -T db psql ... -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}"
docker compose exec -T db pg_restore ... -d "${DB_NAME}" --no-owner < "${SNAPSHOT}"
```

The script guarded that the argument was non-empty but never checked that the file existed, was
non-zero, or was a readable archive.

### What goes wrong

The database was dropped first. If `pg_restore` then failed for any reason at all, there was nothing to
go back to. `set -euo pipefail` exits, leaving an empty database and a stopped Odoo, at the exact moment
someone is already recovering from a bad deploy.

The dump can plausibly be bad. `deploy.yml` creates it with a shell redirect, `> "${file}"`, which
creates the file before `pg_dump` writes to it. A dump interrupted by a full disk or a restarting
container leaves a truncated archive at a path that exists and is non-empty.

**And the repository already contained the correct pattern.** `scripts/restore_drill.sh` restores into
a throwaway database, counts rows on tables that should never be empty, and only then drops it. That
script was careful in exactly the way this one was not.

The script's own header argues that rolling back code alone is *"a worse failure than the one you were
recovering from"*. Dropping production before validating the replacement has the same shape.

### Why this severity

Data loss with no second copy, on the one code path that only ever runs when something has already gone
wrong. It had also never been executed: the restore drill is `workflow_dispatch` only, and in any case
it drills **restic** snapshots, not the pre-deploy `pg_dump` files this script consumes. The pre-deploy
dumps were never tested by anything.

### Fix

Two checks before the DROP. The file must be non-empty, and `pg_restore --list` must be able to read its
table of contents. `--list` reads the archive header without touching a database, so it costs nothing
and catches truncation, corruption and zero-byte files.

### How to confirm it worked

```
head -c 100 /var/backups/some.dump > /tmp/truncated.dump
DB_NAME=x DB_USER=y ./scripts/rollback.sh /tmp/truncated.dump HEAD~1
```

Expect it to abort before the DROP, with the database still present.

---

## F-04 — Pre-deploy snapshots accumulate with no retention

**Severity:** HIGH · **Area:** Capacity · **Status:** Fixed

### What was found

`deploy.yml` wrote a full custom-format dump on every run and nothing removed them:

```bash
file="/var/backups/pre-deploy-$(date +%Y%m%d-%H%M%S).dump"
```

### What goes wrong

Every deploy left a full copy of the database on the production host. No rotation, no retention, and
nothing in this stack watches disk. On an active repository the volume fills gradually and then Postgres
cannot write, which takes Odoo down with it.

It also interacted with F-03: a disk that is nearly full is exactly the condition that produces a
truncated dump.

### Why this severity

Silent by construction. Nothing reports it until it is an outage, and the failure lands on the
production database host rather than somewhere recoverable.

### Fix

The dump step now keeps the five most recent and deletes the rest, in the same step that creates them.
Five is generous for a rollback window measured in one deploy.

### How to confirm it worked

Run the deploy six times against a test host and confirm `/var/backups/` holds five files.

---

## F-05 — The deploy workflow depends on variables nothing in the repository provides

**Severity:** MEDIUM · **Area:** CI/CD · **Status:** Fixed

### What was found

`deploy.yml` used `${DB_USER}` and `${DB_NAME}` inside `run:` steps. The workflow declared no `env:`
block, and neither did the job.

Docker Compose reads `.env` for its own variable substitution inside `compose.yaml`. **It does not
export those values into the shell running a workflow step.**

### What goes wrong

On a runner where those were not already exported, both expanded to empty. `pg_dump -U "" -Fc ""` fails,
the step fails, and the deploy stops.

It failed loudly, which is why this was MEDIUM rather than HIGH. But the reason it stayed safe was
incidental: the failing step never set `steps.snap.outputs.file`, so the rollback step was invoked with
an empty argument and the `${1:?}` guard aborted it. **The safety came from an interaction nobody
designed**, and it would have disappeared if the snapshot step were ever reordered.

### Fix

Both are declared at job level from repository secrets, with a first step that fails fast and names
which one is missing.

### How to confirm it worked

Unset both on the runner and dispatch the workflow. Expect a clear failure at the assertion step, not at
`pg_dump`.

---

## F-06 — Environment guards are inconsistent between the two scripts

**Severity:** LOW · **Area:** Scripting · **Status:** Fixed

### What was found

`rollback.sh` guarded one variable and not the other. `DB_USER` was then used unguarded in four
commands. `restore_drill.sh` guarded neither.

### What goes wrong

Nothing, on the day it was written. If `DB_USER` were empty the first `psql` call fails before the DROP,
so the ordering happened to protect it. That is luck rather than design, and F-03 shows what happens
when ordering is the only thing standing between a script and the database.

### Fix

Both scripts now guard every variable they actually use, with a named error naming which one is missing. `restore_drill.sh` uses only `DB_USER`, so that is the one it guards. Worth noting that this one was fixed in two
passes: `rollback.sh` was corrected alongside F-03, and `restore_drill.sh` was missed and caught later
while writing up this document. A finding is not closed because part of it was.

### How to confirm it worked

`DB_USER= ./scripts/rollback.sh f sha` should abort with a named error, and the same for
`restore_drill.sh`.

---

## What is already good, specifically

Named with the same evidence standard as the findings, because a report that is all criticism reads as a
sales document for the remediation.

**Every image is pinned by digest, and the reasoning and update procedure are written down** in the
compose header. This is the single most-skipped practice in self-hosted Odoo, and the comment explains
why a tag is a moving pointer.

**The Odoo health check hits `/web/health`, not a port.** The comment states the distinction exactly:
*"A container that is running is not the same as an Odoo that is serving."*

**The post-deploy assertion is the uncommon part.** Odoo will finish an upgrade, report no error and
leave the module at its old version. Almost no pipeline checks. This one does, and rolls back database
and code together when it fails.

**`restore_drill.sh` is the best file in the repository.** It restores into a throwaway database, counts
rows on tables that should never be empty, prints a timing, and drops it. Checking that the restore is
non-empty rather than merely exit-zero is the difference between having backups and having recovery.

**`limit_time_real_cron` is set with the reason attached** — long crons holding locks during business
hours as a cause of "Odoo is slow" that has nothing to do with the server. That is operational
experience, not a template.

**The nginx timeouts are 720s with the reason stated**: exports genuinely take minutes, and a 60 second
default produces "the export is broken" tickets that are really timeouts.

---

## What could not be assessed

**No live environment.** Everything here was read from the repository. Nothing was executed, no container
was started, and no request was made against a running instance.

**F-02 needs one live check to confirm its severity rather than its existence.** Whether
`/web/database/backup` remains reachable when `list_db = False` depends on the exact Odoo 18 handler
behaviour, which was not tested. **The nginx regex gap was real regardless of that answer**, and the
comment above it was inaccurate regardless, so the fix stands either way.

**Four files were not read:** `scripts/assert_version.sh`, `config/postgresql.conf`,
`addons/reference_health`, and `docs/`. The assertion script in particular is load-bearing for the deploy
pipeline and deserves its own pass.

**No view of the runner.** The self-hosted runner's environment, permissions and isolation are outside
the repository and are where several of the remaining questions would live.

---

## Deliberately not changed

**The restore drill stays `workflow_dispatch`.** It needs a self-hosted runner on a production host and
there isn't one here. The file says so in a comment. Faking a schedule that cannot run would be worse
than the honest marker.

**The open demonstration pull request stays open.** It breaks a test, then changes a module without
bumping the manifest, then fixes both. It is documentation of the gates firing, not a defect.

---

## A note on this document

This is an audit of our own public reference implementation, and it found three critical issues.

That is the point of running it. A clean report on your own repository reads as marketing. **The useful
version of this exercise is the one where the format survives contact and finds something.** The total
fix was under two hours of work, and the three criticals had been sitting in a repository whose entire
subject is doing this carefully.

Two of the six are worth dwelling on, because neither is a coding mistake.

**F-01 and F-02 were both protected by their own comments.** A variable named `ADMIN_PASSWD` with an
accurate comment above it, and an nginx block whose comment stated the database manager was unreachable.
Both comments described an intention that the code did not implement, and both are the reason nobody
looked again. Documentation that asserts a property is not evidence of it.

**F-06 was fixed twice.** The first pass corrected `rollback.sh` and missed `restore_drill.sh`, and that
was only caught while writing this page up. A finding that names two files is not closed when one of them
is done, and a review is worth re-reading against the diff before it is called complete.
