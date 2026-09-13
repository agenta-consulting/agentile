---
name: ag-prioritise
description: Interactively order the ready Agentile specs by assigning dense NNNN- filename prefixes that encode priority rank. Trigger phrases include "/ag-prioritise", "prioritise the backlog", "order the ready work", "re-rank specs".
allowed-tools: AskUserQuestion, Bash, Read
disable-model-invocation: true
---

# ag-prioritise

Prioritisation encodes rank directly in the filename: `0001-<slug>.md` is first in the queue, `0002-<slug>.md` is second, and so on (an `airtable` store instead uses a `Rank` field with the same meaning — `ag-store rank` handles the difference). The claim helper always picks the lowest-numbered ready spec whose dependencies are shipped, so the order *is* the work order. This skill is a short interactive conversation that produces that ordering.

## Apply this project's playbook

Before doing anything else, check for `.agentile/prioritise.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Baseline steps

### Step 1 — Read the active set

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`).
(If the project still uses the old `Specs directory:` key or a root-level `specs/` with
no `Agentile directory` key, honour that path and note `/ag-init` can migrate.) Resolve
which store answers this project: read `store:` from `.agentile/store.md` if it exists,
default `local`. Read `<dir>/brief.md` if present — rank Business Value against its
prioritised outcomes rather than gut feel.

Run `ag-store spec_list --dir "<dir>" --store "<store>"` (bare command; fallback
`"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) and parse the JSON array. Each entry already
carries `slug`, `prefix` (null if unprioritised), `status`, `business_value`,
`technical_certainty`, `depends_on`, and claim fields — classify into three groups from
that, no file reading required:

- **Prioritised** — `prefix` is not null. Sort ascending by `prefix` to produce the
  current queue order.
- **Unprioritised ready** — `prefix` is null and `status` is `ready`. Shaped and
  buildable but not yet placed in the queue.
- **In-progress** — `status` is `in_progress`, regardless of `prefix`. Actively being
  worked and must never be reordered.

Treat missing `business_value`/`technical_certainty` as `0`.

### Step 2 — Show the current state

Present the user with two lists:

1. **Current queue** — the prioritised specs in their existing order, one per line,
   showing slug, business value, technical certainty, and dependencies.
2. **Unprioritised ready specs** — the same columns for every spec not yet in the
   queue.

Note any in-progress specs separately so the user knows they are excluded from
reordering.

### Step 3 — Propose a starting order

Combine the prioritised specs and the unprioritised ready specs into a single
candidate list. Rank it by **Business Value × Technical Certainty** (descending),
breaking ties alphabetically by slug. Then enforce dependency ordering: if spec A
declares `depends_on: [B]`, move A to a position *after* B in the list.

Present this proposal as a clear numbered list. For each entry note the BV × TC
score and any dependencies. Use `AskUserQuestion` to ask the user whether they want
to accept this proposal as-is or adjust it.

### Step 4 — Reorder interactively

Accept adjustments from the user in plain language ("put X first", "move Y above Z",
"add the new login spec after auth-tokens") and apply each change to the working
list. Show the revised list after each change. Continue until the user confirms the
final order. Use `AskUserQuestion` for discrete choices (e.g. "Accept this order, or
make more changes?").

### Step 5 — Apply the order

Once the user confirms, apply it in one call:

```
ag-store rank <slug-1> <slug-2> ... --dir "<dir>" --store "<store>"
```

passing every **ready** slug (previously prioritised and unprioritised alike) in the
final confirmed order. `ag-store` assigns dense sequential ranks by position —
`0001-<slug>.md`, `0002-<slug>.md`, and so on for the `local` store, or the `Rank`
field for `airtable` — using `git mv`'s collision-safe two-step under the hood so an
in-flight reorder (e.g. swapping `0001`↔`0002`) never collides. **Never pass an
in-progress slug** — `ag-store rank` only reorders `status: ready` specs and leaves
anything else untouched, but omit them from the list regardless so the intent is
explicit in what you asked for.

### Step 6 — Report

Print the final ordered list. For each entry, annotate its claimability:

- **claimable** — `status: ready` and every slug listed in `depends_on` belongs to a
  spec whose `status` is `shipped`.
- **blocked — waiting on `<slug>`** — one or more `depends_on` slugs are not yet
  shipped.

Additionally, emit a warning for each of the following problems detected in the
final order:

- **Dependency tension** — a spec appears earlier in the queue than a spec it depends
  on (the dependency will not be shipped first).
- **Dependency cycle** — two or more specs depend on each other, directly or
  transitively.

Finish with a one-line summary: how many specs were renamed, how many were left
untouched (in-progress), and how many are immediately claimable.
