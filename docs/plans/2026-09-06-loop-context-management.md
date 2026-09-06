# `/ag-loop` Context Management — Design & Implementation Record

**Goal:** Keep a long-running `/ag-loop` drain from silently degrading as its context fills up — instruction drift on later items, in-memory loop state (the iteration counter, the completed list) lost to a compaction, and cross-item bleed between one spec's failure history and the next spec's build. Flagged in `docs/reviews/plugin-review.md` ("strains the context window and compaction across multiple full build cycles") and raised independently by the user.

**Status:** Implemented 2026-09-06, directly (no worktree — plugin markdown/config plus one small Ruby script, not application code needing an isolated build).

**Repo:** this plugin repo (`agenta-consulting/agentile`).

## Decisions

- **Fresh context per item, not "clear context mid-turn".** Claude Code has no mechanism to clear a running turn's context; the practical equivalent is a fresh turn (`/ag-loop --once`) or a fresh process (`bin/ag-run`, one `claude -p` per item). Both are additive to the existing `/ag-loop` / `/loop /ag-loop` pair, not a replacement — an interactive drain across a handful of items is still fine in one session.
- **A durable run log beats a bigger in-memory guard.** `docs/agentile/runs.md` (append-only, one line per claim/ship/pause/failure/idle event) means the iteration counter and completed-list — previously held only in the turn — can always be reconstructed from a file, so a compaction can't quietly reset them.
- **Runner identity split from session identity.** `claimed_by` was always `${CLAUDE_SESSION_ID}`, which only exists for an interactive session. `bin/ag-run` spawns a fresh `claude -p` process per item, so it needs a claim identity that survives across those processes — `AGENTILE_RUNNER_ID`, resolved in `ag-next` and `ag-loop`'s resume check ahead of the session id. `ag-wip` tells the two apart by shape (a session id is a UUID) and gives the right resume instructions for each.
- **Thin orchestrator, not just fresh contexts.** The plan/build/verify split into subagents already existed and was already right. What was missing was discipline in `/ag-loop` itself: it's now told explicitly never to `Read` a spec, `plan.md`, or a diff — that's the subagent's job — and to branch on a one-line machine-readable verdict (`BUILD: done|blocked`, `VERDICT: pass|fail`) rather than re-deriving the outcome from a full report. `/ag-plan`, when invoked from the loop, now always dispatches the `ag-planner` subagent rather than Plan Mode, since Plan Mode runs inline in the caller's own context.
- **`ag-planner` keeps its read-only contract.** It was tempting to also give it `Write`/`Edit` so it could persist `plan.md` itself (removing the plan text from the orchestrator's context entirely), but that widens an agent whose whole point is "you do not write or edit implementation code" — out of scope for a context-management fix. The plan text landing once in the orchestrator's context as a subagent's necessary return is accepted; it's the exploration (multiple file reads, code tracing) that's expensive, and that stays in the subagent.
- **No new project-level config.** `AGENTILE_RUNNER_ID` is an operator/environment concern (set by whoever runs `bin/ag-run`), not something `.agentile/loop.md` should carry. `--once` is an invocation argument, not a config key.

## What changed

- `templates/agentile/runs.md` (new) — the run log template, scaffolded by `/ag-init`.
- `skills/ag-init/SKILL.md` — scaffolds `runs.md` alongside `inbox.md`.
- `skills/ag-next/SKILL.md` — claim identity resolves `${AGENTILE_RUNNER_ID}` before `${CLAUDE_SESSION_ID}`; reporting reflects which.
- `skills/ag-wip/SKILL.md` — distinguishes a session-id claim (resume command) from a named-runner claim (re-run instructions).
- `skills/ag-plan/SKILL.md` — always dispatches `ag-planner` when invoked from `/ag-loop`; Plan Mode only for a direct human invocation.
- `agents/ag-builder.md` — first line of its report is `BUILD: done` or `BUILD: blocked`; the rest is explicitly terse.
- `agents/ag-reviewer.md` — first line is `VERDICT: pass` or `VERDICT: fail`; findings stay terse bullets.
- `skills/ag-loop/SKILL.md` — runner identity, the run log (what gets appended, when, and how to reconstruct the counter from it), `--once`, the thin-orchestrator framing, an **Exit contract** (`AG_LOOP: <shipped|paused|failed|idle> …` as the mandatory last line), and `bin/ag-run` documented alongside `/loop /ag-loop` in "Watch mode".
- `bin/ag-run` (new) — headless driver: loops `claude -p "/ag-loop --once"` in a fresh process per item, reads the `AG_LOOP:` line, continues on `shipped`, stops cleanly (exit 0) on `idle`/`paused` with instructions, exits 1 on `failed` or a malformed/crashed invocation. `--limit N` bounds it; anything after `--` passes through to `claude` (e.g. a `--permission-mode`, since nothing here can answer a permission prompt).
- `dev/test-ag-run.rb` (new) — 9 cases against a stub `claude` on `PATH`: normal drain to idle, default and explicit `AGENTILE_RUNNER_ID` (and its stability across items in one run), pause, failure, a crash, a missing status line, `--limit`, and an unknown flag. `ruby dev/test-ag-run.rb` → `ALL PASS`.
- `README.md` — "Running the loop" documents `--once` and `bin/ag-run`; the claim-identity note explains `AGENTILE_RUNNER_ID`; glossary gains "run log" and an updated "claimed" entry.
- `templates/CLAUDE.agentile-section.md` — mentions the run log and `bin/ag-run` for unattended runs.
- `docs/agentile-loop-runner.md` — amendment note pointing here.

## Verification

- `claude plugin validate .` — passes (pre-existing version-omitted warning only).
- `ruby dev/test-ag-claim.rb`, `ruby dev/test-ag-dependents.rb`, `ruby hooks/test-gates.rb` — all still `ALL PASS` (no regression).
- `ruby dev/test-ag-run.rb` — `ALL PASS` (new).
- No end-to-end run of `/ag-loop` itself in this pass — it's markdown-driven agent instructions, not code with a unit-testable harness; the existing plugin has never had that kind of test, and this change doesn't add one. The next real drain run (or a deliberate dry run) is the practical verification for the skill-level changes.

## Out of scope (not done here)

- Migrating `/ag-loop`'s multi-item drain to `/goal` (raised as an alternative in the plugin review) — `--once` plus `bin/ag-run` solves the same problem without adopting a different primitive; revisit if `/goal` gains capabilities `--once` can't match.
- Giving `ag-planner` write access to persist `plan.md` itself — see Decisions above.
- Any change to `methodology.md` — this is implementation, not methodology.
