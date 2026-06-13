---
name: ag-prioritise
description: Interactively order the ready Agentile specs by assigning dense NNNN- filename prefixes that encode priority rank. Trigger phrases include "/ag-prioritise", "prioritise the backlog", "order the ready work", "re-rank specs".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
disable-model-invocation: true
---

# ag-prioritise

Prioritisation encodes rank directly in the filename: `0001-<slug>.md` is first in the queue, `0002-<slug>.md` is second, and so on. The claim helper always picks the lowest-numbered ready spec whose dependencies are shipped, so the file order *is* the work order. This skill is a short interactive conversation that produces that ordering.

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

Resolve the specs directory: read **Agentile directory** from `.agentile/config.md`
(default `docs/agentile/`); the specs dir is `<dir>/specs/`. (If the project still uses
the old `Specs directory:` key or a root-level `specs/` with no `Agentile directory`
key, honour that path and note `/ag-init` can migrate.) Read `<dir>/brief.md` if present — rank Business Value against its prioritised outcomes rather than gut feel. List every spec at the top level of that directory — flat `*.md` files and `NNNN-<slug>/` directories containing a `SPEC.md` (skip `done/` and `abandoned/`) — do **not** descend into `specs/done/`, `specs/abandoned/`, or any other subdirectory looking for more.

For each file, read its frontmatter and classify it into one of three groups:

- **Prioritised** — filename begins with an `NNNN-` prefix (one or more digits followed
  by a hyphen). Sort these ascending by their numeric prefix to produce the current
  queue order.
- **Unprioritised ready** — filename has no `NNNN-` prefix and `status: ready`.
  These are shaped and buildable but have not yet been placed in the queue.
- **In-progress** — `status: in_progress`, regardless of whether the filename is
  prefixed. These are actively being worked and must never be renamed.

A spec's **slug** is its filename (flat form) or directory name (directory form) with any leading `NNNN-` prefix and the `.md` extension stripped. Read each spec's `business_value`, `technical_certainty`, and
`depends_on` (default `[]`) fields. Treat missing numeric fields as `0`.

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

Once the user confirms, rename the **ready** specs only — both previously prioritised
and unprioritised — using dense sequential prefixes: `0001-<slug>.md`,
`0002-<slug>.md`, and so on. Strip any existing `NNNN-` prefix from the filename to
obtain the bare `<slug>` before constructing the new name. Perform every rename with
`git mv` so the history is preserved.

For a directory spec, rename the **directory** (`git mv <specs>/0003-<slug>/ <specs>/0001-<slug>/`) — never the `SPEC.md` inside it. The collision-safe two-step applies to directories exactly as to files.

To avoid intermediate filename collisions (e.g. renaming `0002-b.md` → `0001-b.md` while
`0001-a.md` → `0002-a.md`), first move all affected files to unique temporary names
(such as `tmp-<slug>.md` — or `tmp-<slug>/` for a directory spec — or a high reserved prefix), then move them to their final
`NNNN-<slug>.md` names.

**Never rename in-progress specs.** Their filenames are fixed references that may be
held by another active session's claim; leave them entirely untouched.

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
