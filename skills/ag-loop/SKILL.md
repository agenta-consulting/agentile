---
name: ag-loop
description: Run the Agentile loop as a runner — claim the next ready item, carry it through plan/build/verify, pause before ship (and at any human checkpoint), then repeat. Drains the backlog within one turn; wrap in /loop to also watch for new work. Trigger phrases include "/ag-loop", "run the loop", "start working through the backlog", "keep building ready items".
allowed-tools: AskUserQuestion, Bash, Read, Edit, Skill, Agent
---

# ag-loop

Orchestrate the Agentile pipeline in a continuous cycle: claim, plan, build, verify, and ship ready specs one after another until the backlog is drained, a human checkpoint is reached, or a configured stop condition fires.

## Load policy

Read `.agentile/loop.md` from the project root. If it is absent, use the defaults below. Extract these fields from its frontmatter (or body prose if not in frontmatter), falling back to each default:

- `max_iterations` — maximum specs to process in one run (default `5`)
- `pause_before_ship` — pause and request sign-off before shipping each item (default `true`)
- `stop_on_gate_failure` — halt the entire loop if verify fails past the retry limit (default `true`)
- `verify_retry_limit` — how many times to retry build+verify before giving up on an item (default `1`)
- `on_empty` — behaviour when the backlog is drained: `watch` continues under `/loop`, `stop` exits (default `watch`)
- `watch` — pacing hint when idle under `/loop`: `self-paced` (default)

Regardless of the above settings, always honour `human_checkpoint: true` on any per-stage playbook (`.agentile/plan.md`, `.agentile/build.md`, `.agentile/verify.md`). A human checkpoint always forces a pause.

## The loop

Repeat the following steps up to `max_iterations` times. Track a counter starting at `0`; increment it each time a full claim-to-ship cycle completes. Track a `completed` list of spec slugs for the final report.

### Step 1 — Resume check

Before claiming anything new, scan the specs directory (read path from `.agentile/config.md`, default `specs/`) for any spec whose frontmatter has both `status: in_progress` and `claimed_by` equal to this session's id (surfaced by the SessionStart hook as "Agentile: this session's id is …"). If such a spec exists, resume it — proceed to Step 4 with that spec path. Do NOT invoke `ag-next` for a spec that is already claimed by this session.

If no in-progress spec is found for this session, proceed to Step 2.

### Step 2 — Claim the next item

Invoke the `ag-next` skill to atomically claim the highest-priority ready spec. Interpret its output:

- A file path → claim succeeded; proceed to Step 4 with that path.
- `NONE` → the backlog is drained. Report what was completed this run and stop. If running under `/loop` and `on_empty` is `watch`, report "idle — nothing ready" so `/loop` can pace its next iteration cheaply. If `on_empty` is `stop`, signal that the loop is complete and exit.
- `WIP_FULL` → the WIP limit is already reached. Report that the WIP limit is held, suggest running `/ag-wip` to inspect what is in flight, and stop.

### Step 3 — Guard: max iterations

If the counter has reached `max_iterations` before a new claim, report the limit reached, list what was completed, and stop.

### Step 4 — Plan

Invoke `/ag-plan <spec-path>`. If the plan stage's playbook (`.agentile/plan.md`) sets `human_checkpoint: true`, pause here — end the turn with a summary of the plan output and require an explicit "approved" reply before continuing. Do not advance until approval is given.

### Step 5 — Build

Read `.agentile/build.md`. If its frontmatter sets `delegate_to: <skill>`, invoke that skill to perform the build. Otherwise dispatch the `ag-builder` agent to carry out the build, passing the spec path and the build playbook as context.

If `.agentile/build.md` sets `human_checkpoint: true`, pause after build output is produced — end the turn with a summary and require explicit sign-off before proceeding to verify.

### Step 6 — Verify

Dispatch the `ag-reviewer` agent, which applies `.agentile/verify.md`. The reviewer reports a gate result: pass or fail.

**On a failing gate:** retry the build+verify cycle (Steps 5–6) up to `verify_retry_limit` additional times, noting the failure reason each time.

- If verify passes on a retry, continue to Step 7.
- If verify still fails after all retries and `stop_on_gate_failure` is `true`, **pause** — end the turn, report the failure, name the spec that is blocked, and stop the loop. Do not claim or start any new item while this failure is unresolved.
- If `stop_on_gate_failure` is `false`, log the failure, skip this item, and continue the loop.

If `.agentile/verify.md` sets `human_checkpoint: true`, pause after a passing verify — end the turn with the reviewer's findings and require explicit approval before shipping.

### Step 7 — Pause before ship

If `pause_before_ship` is `true`, or if any stage in this cycle had `human_checkpoint: true` that has not yet triggered a pause, **pause** — end the turn. Present a concise summary:

- The spec slug and title
- What was built (one sentence)
- The verify outcome

Then ask explicitly: "Approve to ship `<slug>`?" Do not proceed until the user replies with approval.

If `pause_before_ship` is `false` and no checkpoint requires a pause, continue directly to Step 8.

### Step 8 — Ship

On approval (or when no pause applies):

1. Ship or merge the work per the project's conventions (check `.agentile/ship.md` if present; otherwise follow repository conventions).
2. Set `status: shipped` in the spec's frontmatter.
3. Clear the claim fields: remove or blank `claimed_by`, `claimed_at`, and `label`.
4. Append the spec slug to the `completed` list and increment the counter.
5. Return to Step 1 for the next iteration.

## Pausing and resuming

Pausing means ending the current turn. All resumable state lives in the spec file itself (`status: in_progress`, `claimed_by: <session-id>`). When the user replies (e.g. "approved", "continue", "ship it") or re-invokes `/ag-loop`, the resume check in Step 1 finds the in-progress spec and picks up exactly where the loop left off. Never claim new work while an item is paused awaiting a human decision.

## Stop conditions

The loop halts and reports its summary in any of these situations:

- `NONE` returned by `ag-next` (backlog drained)
- `WIP_FULL` returned by `ag-next` (WIP limit reached)
- Gate failure past `verify_retry_limit` with `stop_on_gate_failure: true`
- `max_iterations` reached
- Any unrecoverable error (missing required file, agent crash, etc.)

Always include in the stop report: specs completed this run, the stop reason, and the next suggested action.

## Watch mode

A bare `/ag-loop` drains the backlog in a single turn and then stops. It cannot wait for new work on its own — a single agent turn has no way to sleep and poll.

To watch for new work continuously, run `/loop /ag-loop`. The `/loop` skill re-invokes `/ag-loop` on each interval. When the backlog is empty, `/ag-loop` reports "idle — nothing ready" cheaply so `/loop` does not churn. When `on_empty: stop` is set, `/ag-loop` signals completion and `/loop` exits.

Behave well as a `/loop` body:

- When idle, return quickly with the "idle — nothing ready" message — do not spend tokens scanning unnecessarily.
- When there is work, complete as much as `max_iterations` allows, then return so `/loop` can decide whether to re-invoke.
- If self-paced (`watch: self-paced`), the caller (`/loop`) controls the interval; `/ag-loop` does not introduce its own delays.

**Summary of invocation patterns:**

- `/ag-loop` — drain mode: process up to `max_iterations` ready specs in one turn, then stop.
- `/loop /ag-loop` — watch mode: drain, idle cheaply, and re-invoke automatically when new work appears.
