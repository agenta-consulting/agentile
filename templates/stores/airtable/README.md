# The `airtable` store

Team mode: the Inbox and every spec live in an Airtable base instead of
`docs/agentile/inbox.md` / `specs/`. `plan.md`, supporting files, and ADRs
still live in the repo in this mode — only the Inbox and the canonical spec
content move to the base.

## Setup

1. Create a personal access token at <https://airtable.com/create/tokens>
   with `data.records:read`, `data.records:write`, `schema.bases:read`, and
   `schema.bases:write` scopes, scoped to the workspace (or base) you'll use.
   Export it as `AGENTILE_AIRTABLE_TOKEN` — never write it into
   `.agentile/store.md` or any other tracked file.
2. Either:
   - **Create a new base**: `ag-store create_base "<project name>" --airtable-workspace <workspace-id>`.
     Prints the new base's id.
   - **Use an existing base**: have its id ready (`appXXXXXXXXXXXXXX`, from
     the base's URL or the API docs page for that base).
3. Run `ag-store provision --dir <agentile-dir> --store airtable --airtable-base <base-id>`
   — idempotent: creates the `Inbox`, `Specs`, and `Members` tables and every
   field listed below if they don't already exist, and is safe to re-run.
4. Add yourself (and your teammates) to the `Members` table — `Name`,
   `Email`, `Git Email`. `ag-store whoami` matches the current `git config
   user.email` against `Git Email` to attribute captures/shaping/claims; an
   unmatched email just means attribution is skipped, never a hard failure.
5. `ag-store doctor --dir <agentile-dir> --store airtable --airtable-base <base-id>`
   to confirm connectivity and schema.

## Schema

No blob field anywhere — every frontmatter key in
`templates/agentile/spec-template.md` and every body section is a real,
independently viewable/sortable/filterable Airtable field. See
`bin/ag-store-adapters/airtable/schema.rb` for the exact field list and the
`bin/ag-store-adapters/airtable.rb` for how it maps to the canonical
frontmatter+body markdown every skill actually reads and writes (`ag-store
spec_read`/`spec_create`/`spec_write` render/parse that mapping — no skill
needs to know it's talking to Airtable underneath).

The `Inbox` table carries a `Type` (`feature`/`bug`/`chore`/`spike`) using the
same vocabulary as `Specs.Type`, so shaping carries it across as a copy rather
than a mapping. `/ag-capture` derives it from the stub text and defaults to
`feature`. It exists to *route*, not to label: `/ag-shape` gives a `bug` the
short repro interview (repro, expected vs actual, the failing check, blast
radius) and skips the Business Value × Technical Certainty scoring, which is
theatre for a defect. Unscored bugs are still ranked by `/ag-prioritise` —
unranked means unclaimable.

The `Inbox` table's primary field is `Title` — a short label `/ag-capture`
derives from the stub text when the human doesn't dictate one (`--title`).
The stub itself lives in `Text` and is never truncated; the title exists
because a paragraph makes a useless record name in the Airtable UI and in
every linked-record chip. The `local` store accepts `--title` and drops it:
its inbox is a flat markdown list that is already scannable. A base
provisioned before this field existed gets it on the next `ag-store
provision` — that pass now adds any schema field a pre-existing table is
missing (it never alters or deletes one), which is how later schema
additions reach live bases. It lands as an ordinary field there: field
*order* is fixed at creation, so making it primary on an existing base is
a one-off manual step in the Airtable UI (which does allow it), as is
retyping `Text` to long text. Both are UI-only — the provision pass adds
fields, it never reorders or retypes them.

`Rank` (a number field) replaces the `local` store's `NNNN-` filename prefix
as the queue order. `Claimed By (Session)` is the resume handle (same
meaning as `local`'s `claimed_by`); `Claimed By (Member)`, `Captured By`,
and `Shaped By` are linked records into `Members` — attribution, not
permissions.

## Changing the schema

A base is provisioned once, so a field added to
`bin/ag-store-adapters/airtable/schema.rb` afterwards does **not** appear in
bases that already exist. Until it does, every write silently drops that field:
Airtable accepts the record and ignores the unknown key. Nothing errors, and
the data is simply not there.

So a schema change is always two steps:

1. Edit the field list in `schema.rb` (and whatever reads it — the adapter's
   `INBOX_FIELDS`/`SPECS_FIELDS` maps, the skills that parse the JSON).
2. Run `ag-store provision --dir <agentile-dir> --store airtable
   --airtable-base <base-id>` **against every live base**, including your own.
   It is idempotent, and its `ensure_base_fields` pass adds exactly the fields
   that are missing.

`ag-store doctor` reports the gap between the two, so drift is visible rather
than inferred:

    "schema up to date": false,
    "missing fields": ["Inbox.Type"]

Run `doctor` after pulling a change that touches `schema.rb`, and after adding
a field yourself. What provision **cannot** do is change an existing field:
field *order*, field *type*, and which field is *primary* are all fixed at
creation. Those stay manual, one-off edits in the Airtable UI (which does allow
all three) — see the `Title` note above for a worked example. Provision only
ever adds; it never reorders, retypes, renames, or deletes, so a field renamed
in `schema.rb` lands as a **new, empty column** beside the old one, and moving
the data across is on you.

## Known limitation: claim and rank are not atomic

Airtable has no server-side conditional write. `ag-store claim` does
read → check the field is empty → update → re-read to confirm; `ag-store
rank` is a batch field update. Both leave a real, small race window: two
claims or two reorders within the same moment can both appear to succeed.
This is accepted for v1 — for two people, at worst you both see a claim
succeed and one of you resolves it by hand; it does not corrupt data. If
this becomes a real problem in practice, candidates for hardening it
further are a short random back-off + re-check retry on claim, or a
dedicated per-spec "lock" record to serialize both operations through one
conditional write — neither is built yet.
