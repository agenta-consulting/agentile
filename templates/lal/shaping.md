# Shaping — Definition of Ready

This file defines **what "shaped" means in this project**: the questions a stub must answer before it graduates from the Inbox into a Ready spec. The `/lal-shape` skill reads this file and runs the interview against it.

This is the single most useful file to tailor. Add a question and every future shaping conversation asks it. Remove one and it stops. The *structure* — interview one or two questions at a time, then write the spec — never changes; only the checklist below does.

## Required — a stub is not Ready until all of these are answered

- **Problem / who for / why now** — the business justification behind the stub. What hurts, for whom, and why it matters this cycle.
- **Acceptance criteria** — what "done" observably looks like. Concrete, checkable statements, not vibes.
- **Edge cases and failure paths** — what the agent must *not* assume; what happens when things go wrong.
- **Scope boundary** — what is explicitly **out**, so the work can't balloon.
- **Affected areas** — the files, services, or data the change likely touches.
- **Open questions** — anything still unknown. Surviving unknowns become a timeboxed **spike**, not a guess.

## Triage (always run during shaping)

- Estimate **Business Value × Technical Certainty** (see `.lal/config.md`).
- Recommend a **route**: foreground pair, background agent, spike, or drop.

## Interview style

- Ask **one or two questions at a time**, not a form. Let answers shape the next question.
- Prefer concrete examples over abstractions ("show me what the user sees" beats "describe the feature").
- It is cheaper to kill or reshape an idea here, in words, than after code exists. Splitting, merging, deferring, or dropping a stub are all good outcomes.

## House additions

Add project-specific requirements here. Examples a team might add:

- **Telemetry** — what metric proves this worked, and is it already captured?
- **Rollback** — how do we turn this off if it misbehaves?
- **Accessibility** — does this meet our a11y bar?
