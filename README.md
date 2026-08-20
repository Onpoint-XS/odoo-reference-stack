# odoo-reference-stack

A self-hosted Odoo 18 deployment that can be changed safely.

Getting Odoo running on a server is a morning's work. Keeping it changeable for two years is a
different problem, and it is the one this repository is about. Everything here exists because of
something that goes wrong in production:

- A module upgrade half-applies and leaves the database in a state nobody planned for.
- An upstream image tag moves and a rebuild quietly ships something different from what was tested.
- A deploy reports success, and the module version never actually moved.
- Somebody has backups. Nobody has ever restored one.

## What is in here

| Piece | File | What it is for |
|---|---|---|
| Compose stack | `compose.yaml` | Odoo, PostgreSQL and Nginx, all images pinned by digest |
| CI | `.github/workflows/ci.yml` | Lint and the full Odoo test suite, gating every pull request |
| Deploy | `.github/workflows/deploy.yml` | Snapshot, deploy, assert, roll back on failure |
| Version assertion | `scripts/assert_version.sh` | Fails when a module's installed version did not move |
| Rollback | `scripts/rollback.sh` | Restores the database **and** the code together |
| Backup | `scripts/backup.sh` | restic, every six hours, customer-held key |
| Restore drill | `scripts/restore_drill.sh` | Restores into a throwaway database and times it |
| Runbook | `docs/runbook.md` | What to do at 2am |
| DR plan | `docs/disaster-recovery.md` | RPO, RTO, and what has actually been tested |

## The part most deployments skip

A deploy that reports success is not the same as a deploy that worked. Odoo will happily finish an
upgrade where a module failed to load, and you find out days later when a field is missing.

So the deploy pipeline does this:

```
1. Snapshot the database and record the current commit
2. Pull digest-pinned images
3. Run the module upgrade
4. Assert the installed version of every changed module actually moved
5. If the assertion fails, restore the database AND check out the previous commit
```

Step 4 and step 5 are the ones that matter. Rolling back code without the database leaves you with
old code against a migrated schema, which is worse than the failure you were recovering from.

## Backups you have actually restored

`scripts/backup.sh` runs restic every six hours against a repository the customer holds the key
for. That is table stakes.

`scripts/restore_drill.sh` is the part that is not. It restores the most recent snapshot into a
throwaway database, counts rows in a handful of tables, and prints how long the whole thing took.
Run it on a schedule. An untested backup is a hypothesis.

```
$ ./scripts/restore_drill.sh
==> restoring snapshot 4a7f21c9 into odoo_drill_20260820
==> restore completed in 3m41s
==> res_partner        14,208 rows
==> account_move       31,905 rows
==> ir_module_module      412 rows
==> drill PASSED, dropping odoo_drill_20260820
```

## Digest pinning

`compose.yaml` pins every image by `sha256` digest rather than by tag:

```yaml
image: odoo:18.0@sha256:<digest>
```

A tag is a moving pointer. `odoo:18.0` today and `odoo:18.0` in three months are not guaranteed to
be the same image, which means a rebuild can ship something that was never tested. A digest cannot
move. The cost is that updates become deliberate, which is the point.

## Running it

```bash
cp .env.example .env      # then edit it
docker compose up -d
```

Odoo comes up on `localhost:8069` behind Nginx. `addons/reference_health` is a small module that
exists so version bumps and rollbacks are demonstrable end to end.

## What this is not

Not a Kubernetes reference architecture, not a multi-tenant SaaS platform, and not a substitute for
reading the Odoo documentation. It is a single-instance deployment done carefully, which is what
most companies running self-hosted Odoo actually need.

## Licence

MIT. Take any of it.
