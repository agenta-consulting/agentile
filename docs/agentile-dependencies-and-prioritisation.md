# Agentile — Spec Dependencies & Prefix-Based Prioritisation

Design spec. Status: implemented 2026-06-10 — historical snapshot; the README and `methodology.md` are normative. `specs/archive/` was later renamed `specs/done/` (see agentile-backlog-layout-and-abandon.md); specs may now be directories (`NNNN-<slug>/SPEC.md`).

## Context

Two related backlog improvements, designed together because they share the same files (`ag-claim`, `ag-prioritise`, `ag-next`, the spec template, shaping):

1. **Dependencies** — a spec can declare it depends on others; it isn't claimable until those have shipped. Default behaviour: every spec considers its dependencies as part of being Ready.
2. **Prefix-based, interactive prioritisation** — priority becomes *visible in the filename* (`0001-…`) and is set by an interactive `/ag-prioritise`. An unprefixed spec is, by definition, not yet prioritised.

Both are **derived / stateless**: nothing stores a "blocked" flag or a numeric priority field; eligibility and order are computed from filenames and statuses each time.

## Backlog model

Spec states are visible in the filename, in the specs dir (`<Agentile directory>/specs/`, default `docs/agentile/specs/`, from `.agentile/config.md`):

| File | Meaning |
|------|---------|
| `specs/<slug>.md` | shaped, `status: ready`, **unprioritised** (no prefix) → **not claimable** |
| `specs/<NNNN>-<slug>.md` | **prioritised**; `NNNN` (zero-padded, e.g. `0001`) is its rank |
| `specs/done/<NNNN>-<slug>.md` | **shipped** — moved out of the active list on ship |
| `specs/abandoned/<NNNN>-<slug>.md` | **abandoned** (`status: abandoned`) — dropped via `/ag-abandon`, reason recorded |

- **Slug** is the filename minus an optional leading `NNNN-` prefix and the `.md` — it is the stable identifier (used by `depends_on`).
- The `priority:` frontmatter field added in the concurrency work is **retired**; the filename prefix is the single source of truth for order.

## Dependencies

- Frontmatter: `depends_on: [slug, …]` (default empty), referencing other specs by **slug** (never by prefixed filename, so renumbering never breaks a link).
- A dependency is **satisfied** when a spec with that slug has `status: shipped` (including archived ones).
- A **missing** dependency (no spec matches the slug) is treated as **unsatisfied** and **flagged** — never silently ignored.
- A **cycle** (A→B→A) leaves all involved specs unclaimable; the helper returns `BLOCKED`, and `/ag-prioritise` detects and flags the cycle.

## `ag-claim` — the gate (testable core)

`bin/ag-claim <specs-dir> <session-id> [label] [wip-limit]`, under the existing exclusive `flock`, changes to:

1. Build a **status map** from every spec under the specs dir **recursively** (`specs/**/*.md`, so archived shipped specs count for dependency resolution): for each, derive `slug` (strip optional `^\d+-` prefix and `.md`) and read `status`. A slug is "shipped" if any spec with that slug is `shipped`.
2. The **claim pool** is only the top-level `specs/*.md` (exclude `specs/done/**`).
3. WIP check first: if `wip-limit > 0` and the in_progress count (top-level) ≥ limit → print `WIP_FULL`.
4. `ready` = claim-pool specs with `status: ready` and empty `claimed_by`. If none → print `NONE`.
5. `prioritised` = `ready` specs whose filename has an `^\d+-` prefix. If none → print `UNPRIORITISED`.
6. `eligible` = `prioritised` specs where **every** slug in `depends_on` is shipped (per the status map). If none → print `BLOCKED`.
7. Otherwise choose the `eligible` spec with the **lowest numeric prefix** (tie-break by filename), stamp it `status: in_progress` + `claimed_by`/`label`/`claimed_at` (with the silent-no-op guard from the existing helper), and print its path.

Output contract: a path · `WIP_FULL` · `BLOCKED` · `UNPRIORITISED` · `NONE`. The existing flock, claim-stamp, and guard logic are unchanged; only candidate selection gains prefix-ordering and dependency-filtering.

## `/ag-prioritise` — interactive ordering

Replaces the auto-rank behaviour:

1. Read the active set (top-level `specs/*.md`): the **prioritised** specs (current `NNNN` order) and the **unprioritised** ready specs.
2. Show the current order, then **propose** a starting order — value × certainty as a *suggestion*, dependencies respected (a spec is suggested after its dependencies).
3. **Interactively reorder** with the user (present the proposed list; accept "move X above Y", "X first", insertions, etc.).
4. Apply the order by **densely renaming the ready specs** to `0001-<slug>.md`, `0002-…` via `git mv`:
   - **In-progress** specs are **not renamed** — they are being actively worked (possibly by another session whose claim references the current path), so renaming would break that loop. They keep their existing filename and are shown at the top of the listing as "in progress" for context, but they are outside the renumbered ready queue.
   - **Shipped** specs are not part of the active list (they live in `specs/done/`).
   - Numbering therefore covers only the **ready** specs (`0001…N`). An in-progress spec may share a number with a ready one; that is harmless because `ag-claim` filters by status before ordering, and in-progress items are transient.
5. Annotate the final list: each entry as claimable or `blocked — waiting on <slug>`; warn on **dependency tension** (a dependant ordered above a dependency) and on **cycles**.

`/ag-prioritise` is the only place that assigns/changes prefixes.

## Shipping → done

When a spec ships (the `/ag-loop` ship step, or a manual ship), set `status: shipped` and **move the file to `specs/done/`** (preserving its `NNNN-<slug>.md` name as a record). This keeps the active numbered list clean and keeps numbers from colliding with done work. `ag-claim` still sees done specs for dependency resolution (recursive status map), but its claim pool is **top-level only**, so neither `done/` nor `abandoned/` specs are ever claimed.

## Shaping asks about dependencies (default)

- `shape.md` (the Definition of Ready template) gains a **dependencies** question.
- `/ag-shape` asks, by default, "does this depend on other specs being shipped first?" and writes `depends_on: [slug, …]` (or `[]`). It offers existing spec slugs as candidates. Newly shaped specs land **unprefixed** (Ready but unprioritised) as today.

## Consumers of the new signals

- `/ag-next` interprets `BLOCKED` ("all prioritised work is waiting on dependencies — see `/ag-prioritise`"), `UNPRIORITISED` ("shaped work exists but isn't prioritised — run `/ag-prioritise`"), `NONE`, `WIP_FULL`.
- `/ag-loop` treats `BLOCKED` and `UNPRIORITISED` like an idle/empty tick: stop (drain mode) or, under `/loop`, wait — a dependency may ship, or the human may prioritise.

## Changes to the plugin

Modified:

- `bin/ag-claim` + `bin/test-ag-claim.rb` — prefix-ordering, dependency filtering, the `BLOCKED`/`UNPRIORITISED` tokens, archive-aware status map; new test cases (deps satisfied/unsatisfied, missing dep, unprioritised, prefix ordering, archived dep).
- `skills/ag-prioritise/SKILL.md` — rewrite to the interactive prefix-rename flow.
- `skills/ag-shape/SKILL.md` + `templates/agentile/shape.md` — add the dependencies question / DoR item.
- `templates/agentile/spec-template.md` — add `depends_on: []`; remove `priority:`.
- `skills/ag-next/SKILL.md`, `skills/ag-loop/SKILL.md` — handle the new tokens.
- The ship step (in `ag-loop`, and documented for manual ship) — archive on ship.
- `README.md`, `lean-agentic-loop.md`, `templates/CLAUDE.agentile-section.md` — document the model.

## Edge cases

- **Missing/typo'd dep** → unsatisfied + flagged in `/ag-prioritise`; `ag-claim` simply never treats it satisfied.
- **Cycle** → `BLOCKED` from `ag-claim`; flagged by `/ag-prioritise`.
- **Two specs sharing a slug** → not expected (slug ≈ unique); the status map treats a slug as shipped if any matching spec is shipped. `/ag-prioritise` warns on duplicate slugs.
- **Renumber churn** → dense renumber on each prioritise pass is accepted (deliberate, occasional act); `depends_on` is slug-based so links survive.

## Out of scope

- Auto-inferring dependencies from spec content — shaping *asks*; it does not infer.
- A separate `/ag-blocked` view — blocked visibility lives in `/ag-prioritise`'s listing for now.
- Cross-repo dependencies — slugs are within one project's specs dir.
