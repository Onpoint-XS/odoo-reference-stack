# Odoo major version upgrades

Most upgrade quotes are wrong because they are written before anyone has looked at what is
customised. The version numbers tell you almost nothing. Two companies both on Odoo 15 can
be a weekend apart or a month apart depending entirely on what sits in their addons
directory.

## Take an inventory first

For every module in `addons/`, decide one of four things:

| Verdict | When | Cost |
|---|---|---|
| **Port** | Still used, still needed, no equivalent exists | Highest |
| **Drop** | Nobody has used the feature in a year | Lowest, and usually the biggest saving |
| **Replace with OCA** | A community module now does it | Low, and someone else maintains it afterwards |
| **Rebuild** | The original approach fought the framework | High, but pays back |

Dropping is nearly always cheaper than porting, and nobody quoting an upgrade has an
incentive to mention it. Go through the list before pricing anything.

## Breakages worth knowing before you start

**15 or 16 to 17: analytic tags became analytic distribution.** Anything reading
`analytic_tag_ids` breaks. Custom reports and integrations touching analytic accounting are
the usual casualties, and they break quietly, producing wrong numbers rather than errors.

**Views: `tree` became `list` in 17.** Old view definitions need updating.

**The ORM tightened.** Patterns that worked by accident in older versions now raise. In
particular, writing to a computed field with no inverse, and search calls inside a compute
that quietly do not respect sudo.

**Reports.** QWeb templates referencing fields that moved or were renamed fail at render
time rather than at upgrade time, so a clean upgrade can still leave every invoice PDF
broken.

## Sequence

1. Restore production into a scratch environment. Never upgrade production first.
2. Run OpenUpgrade or the Odoo upgrade service against the copy.
3. Fix the module list against the four verdicts above.
4. Reconcile the data. Row counts per model, before against after. This is where a
   half-migrated table shows up.
5. Re-run every report that anyone actually uses.
6. Time the whole thing, because that time is the cutover window you will have to book.
7. Then, and only then, schedule production.

## The question that changes every estimate

How many custom modules, and does anyone still know what they all do?

If the answer to the second half is no, the inventory step is most of the work, and any
quote given before it is a guess.
