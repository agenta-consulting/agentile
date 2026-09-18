---
name: ag-build
description: Take one Agentile spec from claim to shipped — claim the top prioritised ready spec (or a named one), plan it, implement it, verify it, ship it, and stop. Every pause is a checkpoint file in the spec's directory, so a factory worker and a person at a terminal run the same skill. Trigger phrases include "/ag-build", "build the next spec", "build <slug>", "work the next item".
allowed-tools: AskUserQuestion, Bash, Read, Edit, Skill, Agent
arguments: [slug]
---

# ag-build

Take **one** spec through plan → implement → verify → ship, then stop. There is no iteration here: several specs at once means several sessions or several factory workers, each running this skill on its own spec.

**Stay thin.** This skill is an orchestrator, not a reader. Never `Read` a spec body, `plan.md`, a diff, or gate output yourself: `/ag-plan`, `ag-builder` and `ag-reviewer` read those in their own context and hand back a one-line verdict plus a terse summary. If you are about to `Read` a spec or plan file "just to check", stop — that check belongs in the subagent.

## Identity

Resolve the claim identity once: `${AGENTILE_RUNNER_ID}` if set, otherwise `${CLAUDE_SESSION_ID}`. A factory worker arrives with `AGENTILE_RUNNER_ID=factory/<project>/<NNNN-slug>` and a claim already stamped with it; an interactive session claims for itself under its session id. A fresh process meant to resume a paused item must carry the same `AGENTILE_RUNNER_ID` the claim was made under; a session resumes itself with `claude --resume <session-id>`.

## Concurrency

You may be one of several sessions running this skill against the same
backlog right now. Seeing another spec `in_progress` under a `claimed_by`
that is not your own identity, a worktree under `.claude/worktrees/` you did
not create, or — in a shared checkout — uncommitted changes elsewhere in the
tree belonging to another spec's build, is normal under concurrent
`/ag-build` runs. None of that is your concern or a sign anything is wrong:
do not surface it to the user as an anomaly, do not stop to ask about it —
just proceed with Step 0/1 for your own identity. Step 6's merge is the one
place two sessions can genuinely collide (see that step).

## Run log

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`); the run log is `<dir>/runs.md` (create it from `templates/agentile/runs.md` if missing). Append one line per event, format `- <ISO8601 from `date -u +%Y-%m-%dT%H:%M:%SZ`> runner=<id> event=<started|claimed|shipped|paused|failed|idle> spec=<slug|-> detail=<free text>`.

## Policy

Read the frontmatter of these playbooks (absent file or key means the default):

- `.agentile/plan.md` — `human_checkpoint`: `true` | `false` | `route` (default `route`).
- `.agentile/build.md` — `delegate_to`, `human_checkpoint` (default `false`).
- `.agentile/verify.md` — `human_checkpoint` (default `false`), `retry_limit` (default `1`), `stop_on_gate_failure` (default `true`).
- `.agentile/ship.md` — `human_checkpoint` (default `true`).

If a project still has the retired `.agentile/loop.md`, ignore it and say once that `/ag-version` explains where its keys went.

## Tools

`ag-store` ships in this plugin's `bin/`, on `PATH` while the plugin is enabled; every checkpoint and run-event call takes the same `--dir "<dir>" --store "<store>"` as any other op, because since 0.15.0 they are store records rather than files (fallback `"${CLAUDE_PLUGIN_ROOT}/bin/<tool>"`). Every `ag-store` call takes `--dir "<dir>" --store "<store>"`, with `store:` from `.agentile/store.md` (default `local`). Every `ag-store checkpoint_open` call passes `--session "${CLAUDE_SESSION_ID}"`, so the factory console can tie a pause back to the session that wrote it; it prints the checkpoint file it wrote, and that path is the `<checkpoint-path>` in the status line.

A headless run must pre-authorise these tools and the gates: `--permission-prompts none` denies anything not on the allowlist rather than asking, so pass e.g. `--allowedTools "Bash(ag-store:*)" "Bash(git:*)"` plus each command in `.agentile/gates.json`. The allowlist matches the command text as typed, so **call each tool by its bare name as the first word of its own command**: never prefix `export PATH=…;` or `cd …;`, never use the absolute path, and never chain several commands with `;` or `&&` in one call. A pipe whose every command is allowed (`printf … | ag-checkpoint open …`) is fine. If a bare tool name is not found, end with `AG_BUILD: failed <slug> tool_missing` rather than working around it; after one denial the session denies every later prompt-requiring command.

The **spec directory** for checkpoints is the directory holding `plan.md`: for the `local` store the directory of the claimed `SPEC.md`; for `airtable`, `<dir>/specs/<slug>/`. It exists once `/ag-plan` has run (it promotes a flat spec); every pause in this skill happens after that.

Every `ag-store checkpoint_open` call also passes `--by <who>`, naming what asked — `plan`, `build`, `verify` or `ship` for a stage checkpoint, and `builder` or `reviewer` for a `question`. It lands as the `asked_by` field, and Step 0 routes an answered `question` by it.

**Record an answer that arrives in chat.** The checkpoint file is the record of the decision; the transcript is not. So when the human answers in conversation rather than in the file — an interactive session where you relayed the ask with `AskUserQuestion`, or where the user simply replied in their next turn — record it before you act on it:

```
printf '%s' "<reply>" | ag-store checkpoint_answer "<checkpoint-id>" --by "<identity>"
```

then proceed exactly as Step 0's routing for an answered checkpoint of that reason. Never act on an unrecorded answer: the factory console, `/ag-wip` and any later resume read the file.

## Steps

### Step 0 — Resume check

Run `ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"`. If no entry's `claimed_by` equals this identity, nothing of yours is in flight: append `event=started` and go to Step 1. Otherwise that entry is your spec and you claim nothing this run — take its `slug` (the `<slug>` every run-log line and status line uses) and its `route` from the listing, and derive `<spec-dir>` from its identifier (see **Tools**) — that identifier is the `<id>` for every later `ag-store` call, exactly as in Step 1. Then:

- If the spec is still in flat form, or `<spec-dir>/plan.md` is absent, go to Step 2.
- Otherwise run `ag-store checkpoint_list "<slug>"`. If it lists no checkpoints, go to Step 3.
- If the newest checkpoint is `answered`, read its `answer` field from the `list` output — that is the human's decision — and resume by the checkpoint's reason, which is the only rule for where to go:
  - `plan_review` → Step 3.
  - `build_blocked` → Step 3, re-dispatching the builder with the answer as its instruction.
  - `build_checkpoint` → Step 3, re-dispatching the builder with the answer as its instruction; if the answer is a bare approval, go to Step 4 instead of rebuilding.
  - `question` → the step that asked, read off the checkpoint's `asked_by` field in the `ag-store checkpoint_list` output: `builder` → Step 3, `reviewer` → Step 4. Pass the answer to the agent you re-dispatch.
  - `gate_failure` → Step 3 with the answer as the builder's instruction — unless the answer says to release or abandon the spec, in which case run `ag-store release "<id>" --dir "<dir>" --store "<store>"` or point at `/ag-abandon <slug>`, append `event=failed detail=gate_failure`, and end with `AG_BUILD: failed <slug> gate_failure`.
  - `verify_checkpoint` → Step 5 on approval; otherwise Step 3 with the answer as the builder's instruction.
  - `ship_approval` → Step 6 on approval; otherwise Step 3 with the answer as the builder's instruction.
- If the newest checkpoint is still `open`, never open a second one for the same ask. In an interactive session, relay its `ask` with `AskUserQuestion`, record the reply against that checkpoint (see **Tools**), and continue by the routing above for its reason. Headless, report that it is waiting and end with `AG_BUILD: paused <slug> <reason> <path>`.

### Step 1 — Claim

Read `wip_limit` from `.agentile/prioritise.md` (default unlimited). Run:

```
ag-store claim "<identity>" "" "<wip_limit>" [--spec "<slug from $ARGUMENTS>"] --dir "<dir>" --store "<store>"
```

- A spec identifier → the claim succeeded. What comes back is an **identifier** (a path to the spec's `SPEC.md` under the `local` store, a bare slug under `airtable`): use it verbatim as `<id>` for other `ag-store` calls and as the argument to `/ag-plan`, never in a run-log line or a status line. Establish the spec's own fields now — run `ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"` and take the entry whose `claimed_by` is this identity: its `slug` is the `<slug>` every run-log line and status line uses, its `route` is what Step 2 reads, and `<spec-dir>` is derived from its identifier (see **Tools**). Append `event=claimed`, continue.
- `NONE`, `WIP_FULL`, `BLOCKED`, `UNPRIORITISED` → append `event=idle detail=<code>`, explain in one line (`/ag-prioritise` for `UNPRIORITISED` or `BLOCKED`, `/ag-wip` for `WIP_FULL`, `/ag-shape` for `NONE`), and end with `AG_BUILD: idle <code>`.
- `NOT_FOUND` or `TAKEN` (targeted claim only) → append `event=failed detail=<code>`, say which slug, and end with `AG_BUILD: failed <slug> <code>`.

### Step 2 — Plan

Invoke `/ag-plan <id>`. Invoked from `/ag-build`, it dispatches the `ag-planner` subagent, writes `<spec-dir>/plan.md`, and returns a short confirmation. Under the `local` store this is where a flat spec becomes a directory, so re-read the entry for this identity from `ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"` afterwards: `<spec-dir>` and the `<id>` used from here on come from that refreshed listing.

Pause for plan review when the stage playbook `.agentile/plan.md`'s `human_checkpoint` is `true`, or is `route` and the spec's `route` (from the Step 1 listing, or the Step 0 listing on a resumed run) is `foreground` or `spike`. To pause: write the checkpoint with the plan summary `/ag-plan` returned as the ask,

```
printf '%s' "<summary>. Review or amend plan.md in place, then answer this checkpoint." | ag-store checkpoint_open "<slug>" plan_review --session "${CLAUDE_SESSION_ID}" --by plan
```

append `event=paused detail=plan_review`, and end the turn: one paragraph, the line "Plan written to `<spec-dir>/plan.md` — review or amend it, then reply 'approved'.", and the status line `AG_BUILD: paused <slug> plan_review <checkpoint-path>`. An amended `plan.md` is the approved plan. If the approval instead comes back in chat, record it against the checkpoint (see **Tools**) and continue as Step 0 routes an answered `plan_review`.

### Step 3 — Implement

Read `.agentile/build.md`'s frontmatter. If `delegate_to: <skill>` is set, invoke that skill; otherwise dispatch the `ag-builder` agent with the spec identifier, its `plan.md` path, the build playbook path, and, when resuming from an answered `question` checkpoint, the answer text. The builder's first line is one of:

- `BUILD: done` → continue.
- `BUILD: blocked` → checkpoint `build_blocked` (`--by build`) with the builder's reason as the ask; `event=paused detail=build_blocked`; end with `AG_BUILD: paused <slug> build_blocked <path>`.
- `BUILD: question` → checkpoint `question` (`--by builder`, which is how Step 0 sends the answer back here) with the builder's question block (question, options, recommendation) as the ask; `event=paused detail=question`; end with `AG_BUILD: paused <slug> question <path>`.

If `build.md` sets `human_checkpoint: true`: checkpoint `build_checkpoint` (`--by build`) with the builder's summary; `event=paused detail=build_checkpoint`; end with `AG_BUILD: paused <slug> build_checkpoint <path>`.

At any of these pauses, an answer that arrives in chat is recorded against the checkpoint first (see **Tools**), then followed by Step 0's routing for that reason.

### Step 4 — Verify

Dispatch the `ag-reviewer` agent. Its first line is one of:

- `VERDICT: pass` → continue.
- `VERDICT: question` → checkpoint `question` exactly as in Step 3, but `--by reviewer`, which is how Step 0 sends the answer back here.
- `VERDICT: fail` → re-run Steps 3 and 4 up to `retry_limit` more times, passing the reviewer's must-fix findings to the builder. Still failing: if `stop_on_gate_failure` is `true`, checkpoint `gate_failure` (`--by build`) with the findings as the ask, `event=paused detail=gate_failure`, and end with `AG_BUILD: paused <slug> gate_failure <path>` (mention `/ag-abandon <slug>` as the way to drop it). If `false`, `event=failed detail=gate_failure` and end with `AG_BUILD: failed <slug> gate_failure`.

If `verify.md` sets `human_checkpoint: true`: checkpoint `verify_checkpoint` (`--by verify`) with the reviewer's findings summary; `event=paused detail=verify_checkpoint`; end with `AG_BUILD: paused <slug> verify_checkpoint <path>`.

At either pause, an answer that arrives in chat is recorded against the checkpoint first (see **Tools**), then followed by Step 0's routing for that reason.

### Step 5 — Ship approval

If the spec's acceptance criteria, or the builder's or reviewer's report, describe a visual or UI outcome — a rendered image, a layout, a color, a screen — render or screenshot the actual result and show it before asking for approval, in whatever form the surface allows (an inline image, a screenshot, a published comparison page). A sentence describing what something looks like is not evidence a human can approve against; the human has to see it. Do this whether the caller is interactive or headless — headless still writes the checkpoint's ask with the evidence attached or linked, since whoever answers it later still needs to see it.

If `ship.md`'s `human_checkpoint` is `true` (default): checkpoint `ship_approval` (`--by ship`) whose ask has three lines — the spec slug and title, what was built (one sentence from the builder's report), and the verify outcome (one sentence from the reviewer's) — plus the visual evidence above when it applies, then `event=paused detail=ship_approval`, end the turn with those three lines, "Approve to ship `<slug>`?", and `AG_BUILD: paused <slug> ship_approval <path>`. An approval that comes back in chat is recorded against the checkpoint first (see **Tools**), then followed by Step 0's routing for `ship_approval`.

An answered `ship_approval` whose answer says anything other than approval (a note, "send back") is a bounce: go to Step 3 with the answer as the builder's instruction.

### Step 6 — Ship

1. Merge per `.agentile/ship.md`'s prose (or repository convention), never onto a `protected_branches` entry from a builder branch without the merge step itself. This is the one step where two concurrent `/ag-build` sessions can genuinely collide, since it writes to the shared trunk checkout: if the merge is rejected because trunk moved since you branched (another session shipped first), pull/rebase once and retry before treating it as a failure — a lost race here is expected under concurrency, not an error to surface or ask about.
2. `ag-store ship "<id>" --dir "<dir>" --store "<store>"` — sets `status: shipped`, stamps `shipped_at`, keeps the claim fields, moves the spec to `specs/done/` (local).
3. Append `event=shipped` and commit `runs.md` (and, for the local store, the spec move and its `checkpoints/`) with the ship.
4. End with `AG_BUILD: shipped <slug>`.

## Unrecoverable errors

Any error you cannot recover from — a required file missing, an agent that returns no verdict line, a tool that fails repeatedly, a denied permission you cannot work around — ends the run: append `event=failed detail=<short-code>` and end with `AG_BUILD: failed <slug-or-'-'> <short-code>`. The code is one lowercase snake_case word or short phrase naming the cause (`no_verdict_line`, `checkpoint_write_denied`); use `-` for the slug when no spec was claimed. Do not invent new checkpoint reasons for these — the seven reasons are fixed, and an error is a failure, not a pause.

## Closing the run

When the spec ships, fails unrecoverably, or you release the claim, append a
closing event so the run drops out of the active view while its history is kept
for the flow metrics:

```
ag-store run_close --spec "<slug>" --runner "<identity>" --detail "<why>" --dir "<dir>" --store "<store>"
```

A `shipped` or `failed` event already closes the run on its own; `run_close` is
for the cases those do not cover — a released claim, an abandoned spec, or a
worker that stopped for good.

## Exit contract

The **very last line** of every turn this skill ends is exactly one of:

```
AG_BUILD: shipped <slug>
AG_BUILD: paused <slug> <reason> <checkpoint-path>
AG_BUILD: failed <slug-or-'-'> <reason>
AG_BUILD: idle <NONE|WIP_FULL|BLOCKED|UNPRIORITISED>
```

`<reason>` is the checkpoint reason or the failure code. A plain single line, no markdown, so the factory daemon and `bin/ag-run` can match it.

## Questions instead of guesses

A worker cannot prompt. When the builder or reviewer needs a human decision the spec, plan, `CLAUDE.md` and ADRs cannot settle, it returns `question` and this skill writes the checkpoint. Prefer a recorded assumption in `plan.md` when the stakes are low; ask once, with options and a recommendation, when they are not. In an interactive session you may also relay the question with `AskUserQuestion` — but still write the checkpoint first, so the item shows on the factory console, and record the reply against it (see **Tools**) before acting on it.

## Interactive use beside the factory

`/ag-build <slug>` claims a specific spec and leaves the top of the queue to the workers. The builder already works in its own worktree; the ship step merges to trunk in the main checkout, which is where the backlog lives — never run `/ag-build` from inside a builder's worktree.
