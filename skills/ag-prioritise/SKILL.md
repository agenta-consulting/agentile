---
name: ag-prioritise
description: Interactively order the ready Agentile specs — the rank is a field in the store; the claim always takes the lowest-ranked claimable spec. Trigger phrases include "/ag-prioritise", "prioritise the backlog", "order the ready work", "re-rank specs".
allowed-tools: AskUserQuestion, Bash, Read
disable-model-invocation: true
---

# ag-prioritise

Prioritisation writes a dense rank onto each ready spec in the store (`ag-store rank`). The claim always picks the lowest-ranked ready spec whose dependencies are shipped, so the order *is* the work order. This skill is a short interactive conversation that produces that ordering.

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

### Step 0 — Rank the Outcomes first

Run `ag-store outcome_list --status open`. If there are none, skip to Step 1. If any open Outcome has a null `rank`, show the open Outcomes (slug, title, rank) and ask for their order (`AskUserQuestion`, or plain language), then apply it:

```
ag-store outcome_rank <slug-1> <slug-2> ...
```

Outcome rank is **authored**; spec rank below is **derived** from it and materialised — that is the one prioritisation authority, made practical. The app regenerates the brief's "Prioritised outcomes" list from this order.

### Step 1 — Read the active set

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`. Read `<dir>/brief.md` — rank Business Value against its prioritised outcomes rather than gut feel.

Run `ag-store spec_list` and parse the JSON array. Each entry already
carries `slug`, `prefix` (null if unprioritised), `status`, `business_value`,
`technical_certainty`, `depends_on`, `serves` (the Outcome slug, or null), and claim fields — classify into three groups from
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
candidate list. Bugs arrive **unscored** (`/ag-shape` skips the two axes for
them) — rank them on how much the defect actually hurts: a wrong-answer or
data-integrity bug outranks most features, a cosmetic one usually does not.
Rank the rest by the **rank of the Outcome each serves** first (specs serving the
rank-1 Outcome before those serving rank-2, and so on), then within an Outcome by
**Business Value × Technical Certainty** (descending), ties alphabetically by slug.
Specs serving no Outcome form a final bucket in BV × TC order — promote one above
the buckets only if its BV is high and you say why. Then enforce dependency
ordering: if spec A declares `depends_on: [B]`, move A to a position *after* B in
the list, even across Outcome buckets.

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
ag-store rank <slug-1> <slug-2> ...
```

passing every **ready** slug (previously prioritised and unprioritised alike) in the
final confirmed order. The store assigns dense sequential ranks by position in one
transaction. **Never pass an in-progress slug** — `ag-store rank` only reorders
`status: ready` specs and rejects anything else (409), but omit them from the list
regardless so the intent is explicit in what you asked for.

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

Finish with a one-line summary: how many specs were ranked, how many were left
untouched (in-progress), and how many are immediately claimable.
