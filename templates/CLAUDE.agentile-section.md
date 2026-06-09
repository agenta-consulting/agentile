## Agentile

This project runs the **Agentile**: capture → shape → spec → plan → build → verify → ship → learn. Work builds from a written, shaped spec — never from a prompt typed from memory.

### Where things live

- **Inbox** (`inbox.md`) — one-line stubs awaiting shaping. Capture freely with `/ag-capture`.
- **Specs** (`specs/`) — shaped, Ready-to-build specs. The Definition of Ready is `.agentile/shaping.md`.
- **ADRs** (`docs/adr/`) — the *why* behind significant decisions.
- **Config** (`.agentile/`) — this project's tailoring: `config.md` (paths + triage), `shaping.md` (what Ready means), `gates.json` (deterministic build/test/lint/deploy commands), and the spec/ADR templates.

### How to work

- An idea arrives → `/ag-capture <one line>`. Never lose an idea for lack of a place to put it.
- Ready to develop something → `/ag-shape` to interview it into a spec, then `/ag-plan` before any code.
- Build on a short-lived branch/worktree; run the gates in `.agentile/gates.json`; a fresh-context reviewer critiques the diff before merge.
- Integrate to trunk in small, reversible, flagged batches. Close the loop with `/ag-retro`.

### Rules

- Determinism over instruction: repeatable steps (build, test, lint, deploy) are commands in `.agentile/gates.json`, not hopeful sentences.
- Trust but verify: no agent output merges until it passes tests, static analysis, a security skim, and a human read of the diff.
- Measure flow, not output: if lead time does not drop, the constraint is upstream — fix that, not the agents.
