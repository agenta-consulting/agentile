## Agentile

This project runs the **Agentile**: capture → shape → spec → plan → build → verify → ship → learn. Work builds from a written, shaped spec — never from a prompt typed from memory.

### Where things live

- **Inbox** (`inbox.md`) — one-line stubs awaiting shaping. Capture freely with `/ag-capture`.
- **Specs** (`specs/`) — shaped, Ready-to-build specs. The Definition of Ready is `.agentile/shape.md`.
- **ADRs** (`docs/adr/`) — the *why* behind significant decisions.
- **Config** (`.agentile/`) — this project's tailoring: `config.md` (paths + triage), `shape.md` (what Ready means), `gates.json` (deterministic build/test/lint/deploy commands), and the spec/ADR templates. Any loop stage can be further customised via `.agentile/<stage>.md` (playbook frontmatter: `delegate_to`, `also_run`, `human_checkpoint`).

### How to work

- An idea arrives → `/ag-capture <one line>`. Never lose an idea for lack of a place to put it.
- Ready to develop something → `/ag-shape` to interview it into a spec, then `/ag-plan` before any code.
- Order the ready queue with `/ag-prioritise` (scores by Business Value × Technical Certainty). Pull the top item with `/ag-next` — safe for concurrent loops; the claim is atomic and session-stamped so it can be resumed with `claude --resume <id>`. Check what's in flight with `/ag-wip`.
- Run the loop with `/ag-loop` (or `/loop /ag-loop` to keep watching for work); it pauses for your sign-off before each ship.
- Build on a short-lived branch/worktree; run the gates in `.agentile/gates.json`; a fresh-context reviewer critiques the diff before merge.
- Integrate to trunk in small, reversible, flagged batches. Close the loop with `/ag-retro`.

### Rules

- Determinism over instruction: repeatable steps (build, test, lint, deploy) are commands in `.agentile/gates.json`, not hopeful sentences.
- Trust but verify: no agent output merges until it passes tests, static analysis, a security skim, and a human read of the diff.
- Measure flow, not output: if lead time does not drop, the constraint is upstream — fix that, not the agents.
