# Agentile — `/ag-loop` Drain-Mode Runner

Design spec. Status: draft for review. Date: 2026-06-10.

## Context

Agentile has the pieces to run work — `/ag-prioritise` orders the ready backlog, `/ag-next` atomically claims the top item (session-stamped, resumable), and the per-stage playbooks customise how each stage runs. What's missing is the **runner**: something that pulls an item, carries it through the cycle, and goes back for the next — so a person isn't hand-invoking each `/ag-` command. This was explicitly deferred (the customisation/concurrency spec, §8: "auto-running loops — the pieces enable it, the runner itself is a later piece") and supersedes the parked `auto_start` flag.

Claude Code is **turn-based** — there is no always-on process. So the runner is **drain mode**: a single `/ag-loop` invocation works through the ready backlog *within the turn*, keeping full context across items, and **pauses** (ends the turn) at human checkpoints. The human resumes by replying. This needs no external scheduler. (A "watch mode" that keeps polling an empty backlog is out of scope — the existing `/loop` harness can wrap `/ag-loop` for that later.)

## The runner

`/ag-loop` is a meta-skill that **composes** the existing skills; it does not reimplement them. One invocation runs this algorithm:

1. **Resume check.** If *this session* already holds an `in_progress` claim (i.e. a paused loop is being resumed), continue that item from where it stopped. Otherwise call `/ag-next` to claim the highest-priority unclaimed ready item.
2. **Run the item.** Drive the cycle for the claimed spec: `/ag-plan` → build (honouring `.agentile/build.md` `delegate_to`, e.g. `worktree-workflow`) → verify (the `ag-reviewer` agent, honouring `.agentile/verify.md` Definition of Done).
3. **Checkpoints → pause.** At any stage whose playbook sets `human_checkpoint: true`, and (default) immediately **before ship**, the loop pauses: it ends the turn with a concise summary of exactly what needs sign-off. The human replies "continue"/"approved" to resume (see Resume, below).
4. **Ship.** On approval (or if no checkpoint applies), ship/merge per the project's ship conventions, set the spec `status: shipped`, and clear the claim.
5. **Repeat.** Return to step 1 for the next item.

### Stop conditions (report and halt — never barrel on red)

- `/ag-next` returns `NONE` — backlog drained. Stop, report what was completed.
- `/ag-next` returns `WIP_FULL` — the WIP limit is held by other loops. Stop, report.
- A gate or verify **fails** after `verify_retry_limit` bounce-backs to build — **pause** with the failure for human judgement (do not continue to the next item on red).
- `max_iterations` reached this invocation — stop, report, tell the user to run `/ag-loop` again to continue.
- Any unrecoverable error — stop, report.

### Pause vs stop

- **Pause** = end the turn; all state lives in the claimed spec (`in_progress` + the session stamp), so nothing is lost. The user resumes by replying.
- **Stop** = the loop is done for this invocation; the user starts a new `/ag-loop` when ready.

## Resume after a pause

When the loop pauses and yields, the user's next message ("continue", "approved", "yes ship it", or a fresh `/ag-loop`) resumes it. Resumption is made robust by step 1's **resume check**: `/ag-loop` always looks first for an `in_progress` spec owned by the current session and continues it before claiming anything new. This makes `/ag-loop` idempotent and safe to re-invoke. If the whole session died, `claude --resume <id>` (surfaced by `/ag-wip`) restores the session, then `/ag-loop` continues the held item.

## Config — `.agentile/loop.md`

A playbook scaffolded by `/ag-init` (consistent with the per-stage contract; loop-level config rather than `delegate_to`):

```markdown
---
max_iterations: 5          # items per /ag-loop invocation — a runaway guard
pause_before_ship: true    # stop for human sign-off before each ship/merge
stop_on_gate_failure: true # halt/pause on a failing gate rather than continuing
verify_retry_limit: 1      # bounce a failed verify back to build this many times before pausing
---

# Loop policy

Notes on how this project wants the runner to behave. The runner also honours
every per-stage `human_checkpoint: true` regardless of these settings.
```

Defaults are conservative: bounded iterations, pause before merge, stop on red. A team loosens them deliberately (e.g. `pause_before_ship: false` for a low-risk repo with strong gates).

## Concurrency & resumability (inherited, not rebuilt)

- `/ag-loop` pulls via `/ag-next`, whose claim is mutex-protected — so **N `/ag-loop` sessions run safely in parallel**, each draining different items.
- Every item is session-stamped; `/ag-wip` shows progress and the `claude --resume <id>` handle for each in-flight item.

## Safety posture

- Stop on red (failing gate/verify) — never proceed to the next item on a failure.
- Pause before ship/merge by default; never auto-merge a protected branch (see `gates.json` `protected_branches`) without the checkpoint.
- Bounded `max_iterations` per invocation.
- The runner only *orchestrates* the existing skills, so it inherits their gates (the test-gate hook, the reviewer, `/security-review` if wired).

## Changes to the plugin

New:

- `skills/ag-loop/SKILL.md` — the runner.
- `templates/agentile/loop.md` — the config stub (with the defaults above).

Modified:

- `skills/ag-init/SKILL.md` — scaffold `loop.md`; mention `/ag-loop` in the closing report.
- `README.md`, `lean-agentic-loop.md`, `templates/CLAUDE.agentile-section.md` — document the runner, drain mode, the default pause-before-ship posture, and that it supersedes `auto_start`.
- `templates/agentile/next.md` — drop/redirect the reserved `auto_start` note now that `/ag-loop` owns iteration.

## Out of scope

- **Watch mode** (polling an empty backlog) — wrap `/ag-loop` with the existing `/loop` harness when wanted; not built here.
- **Scheduled/unattended cloud runs** — possible via the `schedule` skill later; a detached runner can't service a live human checkpoint, so it's a separate mode.
- Parallel *fan-out within one `/ag-loop`* (claiming several items at once) — the loop is sequential per session; parallelism comes from running multiple `/ag-loop` sessions.

## Deferred / open

- Whether a completed-item summary is appended anywhere durable (e.g. a run log) or just reported in-turn — default: in-turn report only for v1; `/ag-retro` already mines git/specs for the digest.
