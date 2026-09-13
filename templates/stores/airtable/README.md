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

`Rank` (a number field) replaces the `local` store's `NNNN-` filename prefix
as the queue order. `Claimed By (Session)` is the resume handle (same
meaning as `local`'s `claimed_by`); `Claimed By (Member)`, `Captured By`,
and `Shaped By` are linked records into `Members` — attribution, not
permissions.

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
