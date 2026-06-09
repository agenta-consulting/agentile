---
name: ag-shape
description: Promote a stub from the Agentile inbox to a Ready spec through a conversation — interview the user against the project's Definition of Ready, run the Business Value × Technical Certainty triage, then write the spec and remove the stub. Non-coding. Trigger phrases include "/ag-shape", "shape this stub", "shape an inbox item", "turn this into a spec", "make this Ready".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
---

# ag-shape

Shaping is the bridge between a one-line stub and a buildable spec. It is **a conversation, not a form**: you interview the user until the idea is concrete enough to be Ready, then write it up. Shaping is the cheapest place to kill or reshape an idea — do it here, in words, before any code exists.

**You do not write any code in this skill.** You only produce a spec (or split/merge/drop the stub, or emit a spike).

## Step 1 — Load the project's definitions

- Read `.agentile/shaping.md` — this is **this project's Definition of Ready**: the exact questions a stub must answer, plus any house additions. Drive the interview against *this* list, not a generic one.
- Read `.agentile/config.md` for the inbox/specs paths and the two-axis triage table.
- Read the project's `CLAUDE.md` (and `docs/adr/`) for standing context so your questions fit the architecture.

## Step 2 — Pick the stub

- The user may name the stub by number or text (`$ARGUMENTS`). If they did not, read the inbox and ask which stub to shape (offer a numbered list).

## Step 3 — Interview

- Ask **one or two questions at a time**, using `AskUserQuestion` where the choices are discrete. Let each answer shape the next question.
- Work through every required item in `.agentile/shaping.md` — typically problem/who/why-now, acceptance criteria, edge cases and failure paths, scope boundary, affected areas, and open questions — plus any house additions.
- Prefer concrete examples over abstractions. Push back gently on vague acceptance criteria.

## Step 4 — Triage

- Estimate **Business Value** and **Technical Certainty** (guidance in `.agentile/config.md`).
- Recommend a **route** from the triage table: foreground pair, background agent, spike, or drop.
- A low-certainty item usually leaves shaping as a **spike**, not a build.

## Step 5 — Decide the outcome

Based on the conversation, do **one** of:

- **Graduate to a spec** — write `specs/<slug>.md` using `.agentile/spec-template.md`, filling every field from the interview, and set `route`, `business_value`, `technical_certainty`. Then remove the stub line from the inbox.
- **Spike** — write the spec with `type: spike` and `status: ready`, framing the open questions as the timeboxed exploration goal. Remove the stub.
- **Split** — write multiple stubs back to the inbox (or multiple specs), and remove the original.
- **Merge** — fold the stub into an existing stub or spec; remove the original.
- **Drop** — remove the stub with a one-line note on why.

Always **remove the original stub from the inbox** once its fate is decided — the inbox is the list of what still needs shaping.

## Step 6 — Report

Confirm what you wrote (path), the recommended route, and the next step (usually `/ag-plan specs/<slug>.md`). Do not start building.
