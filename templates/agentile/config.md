# Agentile Config

This file tailors Agentile for **this project**. The methodology (the skills, the loop, the gates) is fixed and installed; the *content* below is yours to edit. Change it freely — the loop's shape stays the same.

## Paths

Where the loop keeps its backlog. Change **Agentile directory** if you want it somewhere other than `docs/agentile/` — the internal layout under it is fixed:

- `inbox.md` — captured stubs awaiting shaping
- `specs/` — active specs (`ready` / `in_progress`)
- `specs/done/` — shipped specs
- `specs/abandoned/` — abandoned specs

The settings:

- **Agentile directory:** `docs/agentile/`
- **ADR directory:** `docs/adr/`

## Two-axis triage

Every stub is scored on **Business Value** and **Technical Certainty**, then routed. The loop uses this table during `/ag-shape`. Adjust the routes to match how your team works.

| | High certainty | Low certainty |
|---|---|---|
| **High value** | Delegate to a **background/async agent**, review the PR | **Pair in foreground** — you drive, agent executes step by step |
| **Low value** | Batch to background agents; thin review | **Spike first** (timeboxed exploration) or drop |

### Scoring guidance

- **Business Value** — how much does shipping this move the outcome that matters right now? Score High / Medium / Low against the project brief's prioritised outcomes (`brief.md`), not gut feel. No brief yet? Run `/ag-init`'s interview (or write one) — otherwise this score is guesswork.
- **Technical Certainty** — how confident are we in *how* to build it? High = the approach is obvious and low-risk; Low = unknowns in approach, data, or dependencies.

A Low-certainty item usually leaves shaping as a **spike** (a timeboxed exploration spec), not a build.

## Routes

The names `/ag-shape` may recommend. Rename or re-scope to taste.

- **foreground** — pair in real time; you steer step by step. Under `/ag-loop`,
  a foreground spec pauses after planning so you can review `plan.md` before
  any code is written.
- **background** — hand to a background/async agent; review the resulting PR.
- **spike** — timeboxed exploration to resolve unknowns; produces findings
  (`findings.md` or an ADR in the spec's directory), not shipping code. Pauses
  at plan like foreground work.
- **drop** — not worth doing now; remove the stub.
