# Agentile — Outcomes: the layer above specs

Design spec. Status: **proposed 2026-09-14, implemented 2026-09-14** (same day, to dogfood on a live project). Extends the backlog layout (`agentile-backlog-layout-and-abandon.md`), dependencies and prioritisation (`agentile-dependencies-and-prioritisation.md`), and the store contract (`agentile-workspaces-participants-and-stores.md` §3). Nothing here changes the loop's stages; it adds one stored layer *above* specs and the skills that read and write it.

## Context

Agentile has three stored things: the **brief** (who it's for, prioritised outcomes, constraints, non-goals), **specs** (shaped, Ready-to-build units of change), and **stubs** (one-line ideas in the Inbox). People who have used Jira reach for two more — *epics* to group specs, *initiatives* or *strategies* to group epics — because those are the views they are used to steering by.

The Jira epic is the wrong model to copy. It is a **container**: its purpose is rollup and navigation, it has a status that is really the sum of its children, and its cost is that a human must keep it true by hand. Every team that has run Jira for a year has a graveyard of epics that no longer mean anything.

Three observations reshape the ask:

1. **Agentile already has a strategy layer — the brief.** It is load-bearing, not decoration: `/ag-shape` and `/ag-prioritise` score Business Value against its prioritised outcomes, and `/ag-retro` treats it as an update target. Adding a *Strategy* entity would duplicate it and immediately create two places that disagree.
2. **Grouping is a lens, not a fact.** Cluster the specs under any real objective — identity, say — and they fall into authentication, provisioning, continuity, audit. Cut the same specs along a different axis (cloud vs. air-gapped deployment) and the groups change but the specs don't. A grouping that changes when the lens changes should be computed, never stored.
3. **In an agentic loop the upper layer is an input, not a report.** A well-formed objective with a claim, a measure, and constraints is a *prompt*: the thing specs get decomposed *from*. That inverts the design — the layer's value is in feeding `/ag-decompose` and carrying standing context into every agent beneath it, not in a burndown.

So the middle layer earns its place only if it carries something no spec can: a **claim that spans specs** and is falsifiable independently of them, and a **stop rule** — what would make us abandon the whole line, not just one spec. That layer is an **Outcome**.

## Governing principles

- **Facts are stored, lenses are computed.** Anything derivable from children — progress, counts, "what's left", themes — is never a field. The one exception is a materialised cache that is regenerable on demand (spec rank, see §5.4).
- **Every stored layer moves at its own cadence.** Brief at retro; Outcome when evidence arrives; spec per unit of work; stub instantly. Two layers moving at the same rhythm are one layer.
- **A parent never gates a child.** Specs and stubs are claimable with no Outcome, forever. `/ag-next` does not change. The moment work cannot be captured without first creating an Outcome, the friction Jira imposes has been rebuilt.
- **Outcomes are flat.** A grouping with its own independent claim is a *sibling* Outcome; one without is a tag. Neither case produces nesting.
- **Tags carry no state.** No status, no rank, no owner. The day a tag grows a status column, delete it.
- **An Outcome without a stop rule is not Ready.** The same discipline `.agentile/shape.md` applies to a spec.
- **Outcome status is the one status that is not derived.** An Outcome can have every spec shipped and still fail its measure; recording that is precisely the point.

## 1. The stack

| Layer | What it is | Irreducible fields | Cadence | Where |
|---|---|---|---|---|
| **Brief** | The strategy — one per project | who for, constraints, non-goals, shipped-v1 | retro | `<dir>/brief.md` (unchanged) |
| **Outcome** | A falsifiable bet, ranked, flat | claim, measure, stop rule, rank, status | when evidence arrives | `<dir>/outcomes/` or the store's `Outcomes` table |
| **Spec** | A shippable unit of change | as today, plus optional `serves`, optional `tags` | per unit of work | unchanged |
| **Stub** | An idea, uncommitted | text, plus optional `serves` hint | instant | unchanged |

Cross-cutting facts, unchanged: **`depends_on`** (order between specs) and **ADRs** (the why). ADRs may cite an Outcome slug in prose; no field is added.

Not in the stack, on purpose: no Epic, no Initiative, no Milestone, no Release. Milestones and releases are the deploy stage (`event=deployed` in the run log), so "what went out in v1.2" is a lens over the run log already. A **Strategy** above the brief becomes real only when the workspaces design ships and the loop spans several repos — it slots in above Brief then without touching anything here.

## 2. The Outcome artefact

An Outcome is canonical markdown, like a spec: frontmatter facts plus a short body. Template at `templates/agentile/outcome-template.md`, scaffolded to `.agentile/outcome-template.md`.

```markdown
---
title: A regulated buyer's security review cannot reject on identity grounds
slug: identity-passes-procurement
status: open              # open | achieved | abandoned
rank:                     # integer; blank = unranked
created: 2026-09-14
# achieved_at / abandoned_at / abandoned_reason — set by the store on transition
---

# A regulated buyer's security review cannot reject on identity grounds

## Claim

Reviewers sign in through their own IdP, access is granted and revoked centrally,
and every approval in the evidence chain stays attributable after they leave.

## Measure

A pilot deployment authenticating against a real Entra ID or Okta tenant; the
identity section of a buyer's security questionnaire answered without caveats;
a deprovisioned user provably unable to approve.

## Stop rule

If two pilot buyers say local accounts are acceptable for an on-prem, air-gapped
install, stop.

## Notes

Optional: evidence gathered, links, what changed the assessment.
```

**Definition of Ready for an Outcome** (what `/ag-outcome` interviews for):

- The **claim** describes what becomes *true*, not what gets *built*. "Provide SSO" fails; "a buyer cannot reject us on identity grounds" passes. Test: could you state the measure without listing the specs?
- The **measure** is observable and can be judged by a human when evidence arrives.
- The **stop rule** names the evidence that would end the line of work.

**Status semantics.** `open` while the bet is live. `achieved` when a human judges the measure met — `/ag-retro` proposes it, a person confirms. `abandoned` when the stop rule fires, via `/ag-abandon`, which cascades to serving specs. Spec counts inform neither transition.

## 3. Links from specs and stubs

A spec's frontmatter gains two optional keys:

```yaml
serves: identity-passes-procurement   # one Outcome slug, or blank
tags: [authentication, testing]       # free-form labels, or blank
```

`serves` is named for how it reads — "this spec serves that outcome" — and because `outcome:` already exists on every spec as *the spec's own* observable metric. The two are different things and keep different names.

A stub may carry `serves` too (the `airtable` store records it; the `local` store's one-line inbox drops it, as it drops `title` and `type`). `/ag-decompose` sets it on every stub it proposes so provenance survives to shaping.

Neither key is ever required. A spec with no `serves` is a free-standing spec and ranks in its own bucket (§5.4). `tags` are labels for computed views and nothing else.

## 4. Store contract

New ops on `bin/ag-store`, implemented by both adapters:

| Op | Semantics |
|---|---|
| `outcome_list [--status s]` | JSON array of `{slug, title, status, rank, created, achieved_at, abandoned_at}` sorted by rank (unranked last), then slug |
| `outcome_read <slug>` | canonical markdown |
| `outcome_create <slug>` (markdown on stdin) | writes a new Outcome; refuses a duplicate slug |
| `outcome_write <slug> --set k=v …` | patches frontmatter keys in place |
| `outcome_rank <slug> [<slug>…]` | assigns dense integer ranks by position to `open` Outcomes; others untouched |
| `outcome_achieve <slug>` | `status: achieved`, stamps `achieved_at` |
| `outcome_abandon <slug> --reason "…"` | `status: abandoned`, stamps `abandoned_at` and the reason |
| `map` | the computed world view — see below |
| `brief_sync` | regenerates the brief's "Prioritised outcomes" section from open Outcomes by rank |

Changed ops: `spec_list` entries gain `serves` and `tags`; `spec_create` / `spec_write` accept them; `inbox_add` takes `--serves <slug>` and `inbox_list` returns `serves`.

### 4.1 `map` — the one computed view

```json
{
  "outcomes": [
    { "slug": "…", "title": "…", "status": "open", "rank": 1,
      "specs": { "ready": ["a"], "in_progress": ["b"], "shipped": ["c"], "abandoned": [] },
      "blocked": ["a"] }
  ],
  "unlinked": { "ready": ["d"], "in_progress": [], "shipped": ["e"], "abandoned": [] },
  "tags": { "authentication": ["a", "b"], "testing": ["b"] }
}
```

`blocked` lists ready specs whose `depends_on` is not fully shipped. Every number a reporting layer would want is derivable from this; none of it is stored.

### 4.2 `local` adapter

Outcomes live at `<dir>/outcomes/<slug>.md`, a flat directory. Status and rank live in frontmatter — no `NNNN-` prefix and no `done/`/`abandoned/` moves. There are few Outcomes, nothing claims them, and a stable filename is worth more than a visible sort order in `ls`. `outcome_list` sorts by the `rank` field.

`brief_sync` rewrites the text between `## Prioritised outcomes` and the next `## ` heading as a numbered list, one open Outcome per line by rank: `1. **<title>** (`<slug>`)`. Everything else in the brief is human-authored and untouched. Unranked open Outcomes are listed after ranked ones. If the heading is absent, the op is a no-op and says so.

### 4.3 `airtable` adapter

A fourth table, **`Outcomes`**: `Title` (primary), `Slug`, `Status` (select: open / achieved / abandoned), `Rank` (number), `Claim`, `Measure`, `Stop Rule`, `Notes` (long text), `Created` (date), `Achieved At`, `Abandoned At` (datetime), `Abandoned Reason` (long text), plus a `Created By` link to `Members` for attribution, matching `Captured By`/`Shaped By` elsewhere.

On `Specs`: `Serves Outcome` (single link to `Outcomes`) and `Tags` (multiple select; records are written with `typecast: true` so a new tag creates its option without a schema call). On `Inbox`: `Serves Outcome` (single link).

`provision` creates the table and backfills the fields on an existing base; `doctor` reports them under schema drift; `create_base` includes the table from the start. The markdown ↔ fields translation in `schema.rb` gains an Outcome renderer/parser with the same no-blob discipline as specs.

## 5. Skills

### 5.1 `/ag-outcome` — new

The shaping interview one level up, short: claim, measure, stop rule, in that order, one or two questions at a time. Pushes back on a claim phrased as a deliverable. Writes the artefact with `outcome_create`. `/ag-outcome <slug>` re-opens an existing one for editing (`outcome_write`); `/ag-outcome achieve <slug>` records the measure as met after confirming what evidence supports it. Unranked on creation — `/ag-prioritise` ranks.

### 5.2 `/ag-decompose <slug>` — new, and the reason the layer exists

Reads the Outcome, the brief, `CLAUDE.md` and the ADRs, and proposes **four to eight stubs** — one line each with a derived title and type, as `/ag-capture` would write them — that together would make the claim true. The user picks, edits, or rejects each (`AskUserQuestion`). Accepted stubs land in the Inbox via `inbox_add --serves <slug>`. **It never creates specs**: decomposition is a proposal, shaping remains the gate. Landmines the decomposer must name: existing specs that already serve this Outcome, and existing specs the new work would collide with.

### 5.3 `/ag-map` — new, read-only

Renders `map`: each Outcome by rank with status, spec counts by state, blocked specs, then the unlinked bucket, then tags. Flags an open Outcome with no specs ("no work serves this yet — `/ag-decompose`?") and a ranked Outcome whose specs are all shipped ("all serving specs shipped — is the measure met? `/ag-outcome achieve`"). Makes no changes.

### 5.4 Changes to existing skills

- **`/ag-shape`** — after dependencies, asks which Outcome the spec serves, offering `outcome_list` slugs (or none). Business Value is scored as *contribution to that Outcome's claim*; with no `serves`, it falls back to the brief's prose as today. Asks for tags only if the conversation surfaced natural ones; never invents them.
- **`/ag-prioritise`** — Step 0: if any open Outcome is unranked, rank Outcomes first (`outcome_rank`). The proposed spec order becomes Outcome rank → BV × TC → dependencies, with unlinked specs in a final bucket unless their BV is high. The result is still materialised into spec rank via `ag-store rank`, so `/ag-next` is unchanged. Outcome rank is authored; spec rank is derived and cached.
- **`/ag-retro`** — reviews each open Outcome against its measure using what shipped; proposes `achieve` or `abandon` with the evidence; runs `brief_sync` so the brief's list and the store cannot drift.
- **`/ag-abandon`** — accepts an Outcome slug: lists the specs serving it as the cascade candidates (the existing per-spec flow, with dependents), then `outcome_abandon`.
- **`/ag-capture`** — passes an explicit `--serves <slug>` through; asks nothing.
- **`/ag-spec`** — may set `serves` when the idea names an Outcome; otherwise leaves it blank.
- **`/ag-init`** — scaffolds `<dir>/outcomes/` (Solo) and `.agentile/outcome-template.md`; Team mode gets the table via `provision`. The brief's "Prioritised outcomes" section becomes the sync target — `/ag-init` says so when it writes the brief.
- **`ag-planner`** — if the spec has `serves`, reads that Outcome so the plan serves the claim, not just the acceptance criteria.

`/ag-next`, `/ag-loop`, `/ag-wip`, `/ag-deploy`, `/ag-plan`: unchanged.

## 6. What this deliberately leaves out

- **Nesting.** No Outcome under an Outcome. Siblings or tags.
- **Any derived field on an Outcome.** No progress, no percentage, no "specs remaining".
- **Ownership.** `Created By` is attribution, as everywhere else — not an approver. Participants (§2 of the workspaces design) remains unbuilt.
- **Outcome-level `depends_on`.** Sequencing lives on specs. If two Outcomes genuinely order each other, rank expresses it.
- **A Strategy entity.** The brief is the strategy until workspaces exist.

## 7. Migration

None required. Every addition is optional: a project with no `outcomes/` and no `serves` on any spec behaves exactly as before. `ag-store provision` backfills the Airtable table and fields idempotently; `doctor` names anything missing.

## 8. Dogfooding

First use is Tekmor (`agenta/products/docassure`, Team store): promote the four prioritised outcomes from its brief into Outcomes with `/ag-outcome`, link `playwright-vite-dev-server` to outcome 2 via `serves`, rank them, run `brief_sync`, and read `/ag-map`. Then `/ag-decompose` against the procurement outcome, where the identity work is the worked example above.

## 9. The honest caveat

This adds one stored layer, and it pays for itself only through `/ag-decompose` and `/ag-map`. As a reporting surface it would be stale within a month, and this document would then be describing another epic. If the decomposition skill is not used, remove the layer rather than maintain it.
