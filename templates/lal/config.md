# LAL Config

This file tailors the Lean Agentic Loop for **this project**. The methodology (the skills, the loop, the gates) is fixed and installed; the *content* below is yours to edit. Change it freely — the loop's shape stays the same.

## Paths

Where the loop keeps its artefacts. Edit if your repo uses different locations.

- **Inbox:** `inbox.md`
- **Specs directory:** `specs/`
- **ADR directory:** `docs/adr/`

## Two-axis triage

Every stub is scored on **Business Value** and **Technical Certainty**, then routed. The loop uses this table during `/lal-shape`. Adjust the routes to match how your team works.

| | High certainty | Low certainty |
|---|---|---|
| **High value** | Delegate to a **background/async agent**, review the PR | **Pair in foreground** — you drive, agent executes step by step |
| **Low value** | Batch to background agents; thin review | **Spike first** (timeboxed exploration) or drop |

### Scoring guidance

- **Business Value** — how much does shipping this move the outcome that matters right now? Score High / Medium / Low against current priorities, not gut feel.
- **Technical Certainty** — how confident are we in *how* to build it? High = the approach is obvious and low-risk; Low = unknowns in approach, data, or dependencies.

A Low-certainty item usually leaves shaping as a **spike** (a timeboxed exploration spec), not a build.

## Routes

The names `/lal-shape` may recommend. Rename or re-scope to taste.

- **foreground** — pair in real time; you steer step by step.
- **background** — hand to a background/async agent; review the resulting PR.
- **spike** — timeboxed exploration to resolve unknowns; produces findings, not shipping code.
- **drop** — not worth doing now; remove the stub.
