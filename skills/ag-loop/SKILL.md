---
name: ag-loop
description: Run the Agentile loop as a runner — claim the next ready item, carry it through plan/build/verify, pause at plan for foreground/spike work, pause before ship, and honour any human checkpoint, then repeat. Drains the backlog within one turn; wrap in /loop to also watch for new work, or pass --once to process exactly one item (what the headless bin/ag-run driver uses). Trigger phrases include "/ag-loop", "run the loop", "start working through the backlog", "keep building ready items".
allowed-tools: AskUserQuestion, Bash, Read, Edit, Skill, Agent
arguments: [--once]
---

# ag-loop

Orchestrate the Agentile pipeline in a continuous cycle: claim, plan, build, verify, and ship ready specs one after another until the backlog is drained, a human checkpoint is reached, or a configured stop condition fires.

**Stay thin.** This skill is an orchestrator, not a reader. Its own context should hold the loop's bookkeeping — which spec, which step, the counter — and nothing else. Never `Read` a spec body, `plan.md`, a diff, or gate output yourself: `/ag-plan`, `ag-builder`, and `ag-reviewer` already read those in their own context (a subagent's, when this skill dispatches one) and hand back only a short verdict and summary. If you find yourself about to `Read` a spec or plan file "just to check", stop — that check belongs in the subagent you're about to dispatch, not here.

## Runner identity

Every claim needs an identity for `claimed_by`. Resolve it once at the start of a run and reuse it for every claim this invocation makes: `${AGENTILE_RUNNER_ID}` if set, otherwise `${CLAUDE_SESSION_ID}` (see `ag-next`, which does this same resolution). `AGENTILE_RUNNER_ID` is how the headless `bin/ag-run` driver claims under a stable name of its own rather than a throwaway session id — each item it drains runs `/ag-loop --once` in a **fresh `claude -p` process**, so nothing but the claim itself carries state between items, and a fresh process has no `${CLAUDE_SESSION_ID}` to resume by anyway.

## Run log

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`); the run log is `<dir>/runs.md` (scaffolded by `/ag-init` from `templates/agentile/runs.md`; if a project predates that, create it from the same template the first time this skill needs it). It is append-only durable history — read it, and append one line to it, at the points below. It exists so that a compaction mid-run, or a resume in a fresh process, does not depend on anything held only in this turn's context: the counter and the completed-list required by Step 3 and the stop report are **reconstructed by reading the log**, not carried solely in memory.

- **At the start of a fresh (non-resumed) invocation**, append `event=started` and note the resolved runner identity and `max_iterations` in `detail`.
- **After Step 2 claims a spec**, append `event=claimed`.
- **After Step 8 ships a spec**, append `event=shipped`.
- **Whenever the loop pauses** (plan review, a checkpoint, ship approval, or a gate failure with `stop_on_gate_failure: true`), append `event=paused` with the reason in `detail`.
- **On an unrecoverable error**, append `event=failed` with the reason in `detail`.
- **When Step 2 finds nothing to do** (`NONE`, `WIP_FULL`, `BLOCKED`, `UNPRIORITISED`), append `event=idle` with the code in `detail`.

Use the format from the top of `runs.md`: `- <ISO8601, from `date -u +%Y-%m-%dT%H:%M:%SZ`> runner=<id> event=<...> spec=<slug|-> detail=<free text>`.

**Reconstructing the counter.** If you ever lose track of how many iterations this invocation has completed — after a compaction, for instance — re-read this skill and then scan `runs.md` backward for `event=shipped` lines with this run's `runner=` since the most recent `event=started` line for that runner: that count is the counter's true value. Trust the log over anything you recall from earlier in the turn.

## Load policy

Read `.agentile/loop.md` from the project root. If it is absent, use the defaults below. Extract these fields from its frontmatter (or body prose if not in frontmatter), falling back to each default:

- `max_iterations` — maximum specs to process in one run (default `5`)
- `pause_before_ship` — pause and request sign-off before shipping each item (default `true`)
- `pause_at_plan` — when to pause for plan review: `always`, `route` (pause when the spec's `route` is `foreground` or `spike`), or `never` (default `route`)
- `stop_on_gate_failure` — halt the entire loop if verify fails past the retry limit (default `true`)
- `verify_retry_limit` — how many times to retry build+verify before giving up on an item (default `1`)
- `on_empty` — behaviour when the backlog is drained: `watch` continues under `/loop`, `stop` exits (default `watch`)
- `watch` — pacing hint when idle under `/loop`: `self-paced` (default)

Regardless of the above settings, always honour `human_checkpoint: true` on any per-stage playbook (`.agentile/plan.md`, `.agentile/build.md`, `.agentile/verify.md`). A human checkpoint always forces a pause.

**`--once`** (in `$ARGUMENTS`): if present, treat `max_iterations` as `1` for this invocation only — do not edit `loop.md`. This is what `bin/ag-run` passes so each of its fresh processes handles exactly one item. It changes nothing else: pause behaviour, retries, and every other setting still come from `loop.md`.

## The loop

Repeat the following steps up to `max_iterations` times (see `--once` above). Track a counter starting at `0`; increment it each time a full claim-to-ship cycle completes. Track a `completed` list of spec slugs for the final report. Both are cross-checked against `runs.md` — see **Run log** above — so a compaction cannot silently reset them.

### Step 1 — Resume check

Before claiming anything new, scan the specs directory (resolve **Agentile directory** from `.agentile/config.md`, default `docs/agentile/`; the specs dir is `<dir>/specs/` — honour the old `Specs directory:` key or a root-level `specs/` if that is what the project still has, and note `/ag-init` can migrate) — both flat `*.md` files and `*/SPEC.md` directory specs at its top level — for any spec whose frontmatter has both `status: in_progress` and `claimed_by` equal to this run's identity (see **Runner identity** above). If such a spec exists, resume it — proceed to Step 4 with that spec path. Do NOT invoke `ag-next` for a spec that is already claimed by this run's identity.

If no in-progress spec is found for this identity, proceed to Step 2.

### Step 2 — Claim the next item

Invoke the `ag-next` skill to atomically claim the highest-priority ready spec. Interpret its output:

- A file path → claim succeeded; append the `claimed` log line (see **Run log**); proceed to Step 4 with that path.
- `NONE` → the backlog is drained. Append `event=idle detail=NONE`. Report what was completed this run and stop. If running under `/loop` and `on_empty` is `watch`, report "idle — nothing ready" so `/loop` can pace its next iteration cheaply. If `on_empty` is `stop`, signal that the loop is complete and exit.
- `WIP_FULL` → the WIP limit is already reached. Append `event=idle detail=WIP_FULL`. Report that the WIP limit is held, suggest running `/ag-wip` to inspect what is in flight, and stop.
- `BLOCKED` → all prioritised specs are waiting on unshipped dependencies. Append `event=idle detail=BLOCKED`. In drain mode, stop and report that the backlog is blocked; suggest `/ag-prioritise` to inspect dependencies. Under `/loop`, report "idle — blocked on dependencies" and return so `/loop` can re-invoke later (a dependency may ship in another iteration).
- `UNPRIORITISED` → ready specs exist but none have been prioritised. Append `event=idle detail=UNPRIORITISED`. In drain mode, stop and report that the backlog needs prioritisation; suggest `/ag-prioritise`. Under `/loop`, report "idle — backlog unprioritised" and return so the human can prioritise and the next iteration can proceed.

**Never stop silently.** Whenever you stop in drain mode (i.e. invoked as a bare `/ag-loop`, not under `/loop`) because there was nothing to do — `NONE`, `BLOCKED`, `UNPRIORITISED`, or `max_iterations` reached — end your report with an explicit reminder, so the user is never left wondering why it stopped:

> Stopped (drain mode — one pass). To keep the loop running and pick up new work as it appears, run `/loop /ag-loop`.

Every stop or pause ends with the machine-readable status line required in **Exit contract**, below — add it after this reminder, not instead of it.

### Step 3 — Guard: max iterations

If the counter has reached `max_iterations` before a new claim, report the limit reached, list what was completed, and stop (with the **Exit contract** status line).

### Step 4 — Plan

Invoke `/ag-plan <spec-path>`. Being invoked from `/ag-loop`, `/ag-plan` dispatches the `ag-planner` subagent itself rather than using Plan Mode — see its own Steps — so the spec body and standing context stay out of this skill's context. It writes the plan to `plan.md` inside the spec's directory (promoting a flat spec to its directory form first) and returns only a short confirmation.

Then decide whether to pause for plan review:

- If `.agentile/plan.md` (the stage playbook) sets `human_checkpoint: true` — always pause.
- Else if `pause_at_plan` is `always` — pause.
- Else if `pause_at_plan` is `route` and the spec's `route` is `foreground` or `spike` — pause. This is the methodology's "cheapest place to steer": low-certainty work gets a human eye on the plan before any code exists; `background` (high-certainty) work runs through.
- Else continue to Step 5.

On a pause: append `event=paused detail=plan_review` to the run log, then end the turn with a one-paragraph summary of the plan and the line "Plan written to `<spec-dir>/plan.md` — review or amend it, then reply 'approved'." An amended `plan.md` is the approved plan; do not advance until approval is given. Do not `Read` `plan.md` yourself to write this summary beyond what `/ag-plan` already returned to you.

### Step 5 — Build

Read `.agentile/build.md`. If its frontmatter sets `delegate_to: <skill>`, invoke that skill to perform the build. Otherwise dispatch the `ag-builder` agent to carry out the build, passing the spec path, its `plan.md`, and the build playbook as context — the agent reads those itself; do not read them into this skill's context first.

The builder's response starts with `BUILD: done` or `BUILD: blocked` — branch on that line. `blocked` means the spec itself is wrong or underspecified; append `event=paused detail=build_blocked`, pause, and report the builder's reason rather than proceeding to verify.

If `.agentile/build.md` sets `human_checkpoint: true`, pause after build output is produced — append `event=paused detail=build_checkpoint`, end the turn with a summary, and require explicit sign-off before proceeding to verify.

### Step 6 — Verify

Dispatch the `ag-reviewer` agent, which applies `.agentile/verify.md`. Its response starts with `VERDICT: pass` or `VERDICT: fail` — branch on that line; do not re-derive the verdict by reading the diff or gate output yourself.

**On a failing gate:** retry the build+verify cycle (Steps 5–6) up to `verify_retry_limit` additional times, noting the failure reason each time.

- If verify passes on a retry, continue to Step 7.
- If verify still fails after all retries and `stop_on_gate_failure` is `true`, append `event=paused detail=gate_failure`, **pause** — end the turn, report the failure, name the spec that is blocked, and stop the loop. Do not claim or start any new item while this failure is unresolved. If the spec cannot be salvaged and should be dropped rather than fixed, point the user at `/ag-abandon <slug>` to drop it (and walk its dependents).
- If `stop_on_gate_failure` is `false`, log the failure, skip this item, and continue the loop.

If `.agentile/verify.md` sets `human_checkpoint: true`, pause after a passing verify — append `event=paused detail=verify_checkpoint`, end the turn with the reviewer's findings, and require explicit approval before shipping.

### Step 7 — Pause before ship

If `pause_before_ship` is `true`, or if any stage in this cycle had `human_checkpoint: true` that has not yet triggered a pause, **pause** — append `event=paused detail=ship_approval`, end the turn. Present a concise summary:

- The spec slug and title
- What was built (one sentence)
- The verify outcome

Then ask explicitly: "Approve to ship `<slug>`?" Do not proceed until the user replies with approval.

If `pause_before_ship` is `false` and no checkpoint requires a pause, continue directly to Step 8.

### Step 8 — Ship

On approval (or when no pause applies):

1. Ship or merge the work per the project's conventions (check `.agentile/ship.md` if present; otherwise follow repository conventions).
2. Set `status: shipped` in the spec's frontmatter and add `shipped_at:` (ISO8601 — `date -u +%Y-%m-%dT%H:%M:%SZ`).
3. **Keep** `claimed_by`, `claimed_at`, and `label` — the claim→ship interval is the cycle-time data `/ag-retro` mines; never erase it at the finish line.
4. Move the spec into `<dir>/specs/done/` (create the directory if it does not exist) using `git mv` — the whole `NNNN-<slug>/` directory for a directory spec (plan and supporting files travel with it), or the `NNNN-<slug>.md` file for a flat spec. This removes it from the active numbered list while keeping it resolvable as a shipped dependency by `ag-claim`.
5. Append `event=shipped` to the run log, add the spec slug to the `completed` list, and increment the counter. Commit `runs.md` alongside the ship, so the log's history travels with normal repository history rather than sitting as a perpetual uncommitted diff.
6. If `--once` was passed, stop here regardless of `max_iterations` — emit the **Exit contract** line for this item and end the turn. Otherwise return to Step 1 for the next iteration.

## Exit contract

Every time this skill ends its turn — a stop or a pause — the **very last line** of the response must be exactly one of:

```
AG_LOOP: shipped <slug>
AG_LOOP: paused <slug> <reason>
AG_LOOP: failed <slug-or-'-'> <reason>
AG_LOOP: idle <NONE|WIP_FULL|BLOCKED|UNPRIORITISED>
```

`<reason>` is the same `detail` value used in the matching run-log line (`plan_review`, `build_blocked`, `build_checkpoint`, `gate_failure`, `verify_checkpoint`, `ship_approval`, or a short slug for an unrecoverable error). This line exists for the headless `bin/ag-run` driver, which runs `/ag-loop --once` in a fresh, non-interactive process and greps stdout for it — it cannot see anything else in the turn. Keep it a plain, single line with no surrounding markdown formatting so it is trivial to match.

## Pausing and resuming

Pausing means ending the current turn. All resumable state lives in the spec file itself (`status: in_progress`, `claimed_by: <runner identity>`) plus the run log's history. When the user replies (e.g. "approved", "continue", "ship it") or re-invokes `/ag-loop`, the resume check in Step 1 finds the in-progress spec and picks up exactly where the loop left off. Never claim new work while an item is paused awaiting a human decision.

## Stop conditions

The loop halts and reports its summary in any of these situations:

- `NONE` returned by `ag-next` (backlog drained)
- `WIP_FULL` returned by `ag-next` (WIP limit reached)
- `BLOCKED` returned by `ag-next` in drain mode (all prioritised specs blocked on dependencies)
- `UNPRIORITISED` returned by `ag-next` in drain mode (no prioritised specs to claim)
- Gate failure past `verify_retry_limit` with `stop_on_gate_failure: true`
- `max_iterations` reached, or `--once` completed its one item
- Any unrecoverable error (missing required file, agent crash, etc.)

Always include in the stop report: specs completed this run, the stop reason, and the next suggested action — then the **Exit contract** line.

## Watch mode

A bare `/ag-loop` drains the backlog in a single turn and then stops. It cannot wait for new work on its own — a single agent turn has no way to sleep and poll.

To watch for new work continuously, run `/loop /ag-loop`. The `/loop` skill re-invokes `/ag-loop` on each interval. When the backlog is empty, `/ag-loop` reports "idle — nothing ready" cheaply so `/loop` does not churn. When `on_empty: stop` is set, `/ag-loop` signals completion and `/loop` exits.

Behave well as a `/loop` body:

- When idle, return quickly with the "idle — nothing ready" message — do not spend tokens scanning unnecessarily.
- When there is work, complete as much as `max_iterations` allows, then return so `/loop` can decide whether to re-invoke.
- If self-paced (`watch: self-paced`), the caller (`/loop`) controls the interval; `/ag-loop` does not introduce its own delays.

For an unattended, non-interactive run — where nobody is present to answer a pause — see `bin/ag-run` instead of `/loop`: it runs `/ag-loop --once` in a fresh process per item, so each item gets a clean context rather than sharing one long-lived, ever-filling session. It stops cleanly at the first pause it can't answer (checkpoints still need a human).

**Summary of invocation patterns:**

- `/ag-loop` — drain mode: process up to `max_iterations` ready specs in one turn, then stop.
- `/loop /ag-loop` — watch mode: drain, idle cheaply, and re-invoke automatically when new work appears, all in one long-lived session.
- `/ag-loop --once` — process exactly one item then stop, emitting the **Exit contract** line. Used interactively for tight, reviewable steps, and by `bin/ag-run` to get a fresh context per item.
- `bin/ag-run` — headless driver: repeatedly runs `/ag-loop --once` in a fresh `claude -p` process per item, for long unattended drains without one session's context filling up.
