# Inbox ↔ Spec provenance links

## Problem

Agentile's Team-mode (Airtable) backlog has no way to trace which Spec(s) a
given Inbox stub was shaped into, or which Inbox stub (if any) a given Spec
came from. `/ag-shape` promotes a stub to a spec and marks the stub
`Dropped`, discarding the connection. Keith wants to see this provenance
from either side, in the Airtable UI, going forward — and backfilled into
existing data where it can be determined with confidence.

## Scope

- The Airtable schema (default, for new bases, and the one live base today).
- `/ag-shape`, which is the only flow that turns an Inbox item into a Spec.
- A one-off retrofit of the live OmaGames base (`appFVlbVAWb4T4E8j`), the
  only Agentile Airtable base that currently exists.

Out of scope: the `local` (file-based) store — this is Team-mode/Airtable
only, since that's where "see it in the base" applies. `/ag-decompose` and
`/ag-capture` are unaffected (they only ever produce Inbox items). `/ag-spec`
is unaffected (it never consumes an Inbox item).

## Design

### Schema

Mirrors the existing `Serves Outcome` link pattern (Specs/Inbox → Outcomes),
which is the only precedent for cross-table provenance in the schema today.

- **Specs.`Source Inbox Item`** — link to Inbox. Holds zero or one record.
  Not hard-enforced as single by the schema mechanism (no link field in the
  current schema enforces cardinality — the `LINK_FIELDS` tuple's
  "multiple?" element is already decorative/unused), but conventionally
  single: one spec has at most one originating stub.
- **Inbox.`Specs`** — the reciprocal, auto-created and auto-maintained by
  Airtable when the Specs-side field is created. Holds zero-to-many records,
  since `/ag-shape`'s "Split" case can turn one stub into several specs.

Field names follow the existing convention of naming a reciprocal field
after the table it points to (see `Outcomes` → `Specs`/`Inbox` today).

Added in `bin/ag-store-adapters/airtable/schema.rb`'s field/`LINK_FIELDS`
definitions, so it lands in the default schema for `/ag-init` and any future
base, and — because `ensure_link_fields` in `airtable.rb`'s `Adapter#provision`
is idempotent and additive-only — running `ag-store provision` against an
existing base adds it there without touching any existing data.

### Write path (going forward)

- `ag-store spec_create` gains an optional `--source-inbox <inbox-id>`
  parameter, mirroring the existing `--serves <outcome-slug>` parameter,
  setting the link at creation time.
- `/ag-shape` Step 5 (currently `spec_create` → `inbox_drop`) passes the
  shaped stub's id as `--source-inbox` on every `spec_create` call it makes,
  including each call in the "Split" case — so every resulting spec links
  back to the one stub, and the stub's `Specs` reciprocal shows all of them.
- No other skill changes. `/ag-decompose`/`/ag-capture` only write Inbox
  items; `/ag-spec` never touches the Inbox table.

### Retrofit (live OmaGames base)

1. Run `ag-store provision` against `appFVlbVAWb4T4E8j`. This adds
   `Source Inbox Item` to Specs (Airtable auto-creates the `Specs`
   reciprocal on Inbox), and separately fixes unrelated pre-existing schema
   drift on the same base: Specs is missing the `Created At` (datetime)
   field the schema defines (only the older `Created` date field exists).
   Both are additive; nothing existing is modified.
2. Pull all Inbox (28) and Spec (20) records.
3. Build a candidate mapping using title similarity, `Serves Outcome`
   agreement, and date proximity (stub `Dropped` at/before spec `Created`).
4. Write high-confidence matches directly (e.g. near-identical titles,
   matching Outcome, close dates) — set the Spec's `Source Inbox Item`.
   Known one-to-many case: "Drop the Oma prefix everywhere" links to both
   `web-drop-oma-prefix-and-reddoor` and `native-drop-oma-prefix-and-reddoor`.
5. Leave ambiguous cases (multiple similarly-plausible candidates, or no
   clear match) blank and report them to Keith for a manual decision — no
   guessing. A Spec that never came from a stub is legitimately left blank.
6. Report the final match list (written + flagged-for-review) as the
   completion of the retrofit.

## Testing

- After the `schema.rb` change: `ag-store provision` against a scratch/dev
  base (or a dry run if the tool supports one) confirms the new fields are
  created with the right type and direction, and that a second run is a
  no-op (idempotency).
- After the `/ag-shape` change: shape a stub end-to-end (including a
  deliberate "Split" case) against a test base and confirm both the single
  and split cases link correctly from both the Spec and Inbox sides in the
  Airtable UI.
- Retrofit: spot-check a handful of written links against the source data
  manually before calling it done; the ambiguous-case report itself is the
  verification that nothing was guessed.

## Risks / non-goals

- No cardinality enforcement is added for `Source Inbox Item` — consistent
  with how every other link field in this schema already works. If this
  becomes a real problem later, enforcing "one" is a separate, small change.
- This does not touch the `local` file-based store; a future request to add
  equivalent provenance there is out of scope here.
