# Agentile Factory — one fresh process per spec, and a console for what needs you

Design spec. Status: phase 1 (protocol and `/ag-build`, plugin 0.13.0) implemented 2026-09-16 — see `docs/plans/2026-09-16-ag-build-and-checkpoints.md`; the daemon and console are both built (console phase in progress; see the 0.20.0 status notes below). Supersedes `/ag-loop` and the single-machine `bin/ag-run` driver as the way to run Agentile unattended; `bin/ag-run` stays as the zero-infrastructure fallback. Builds on `docs/agentile-loop-runner.md` (the runner and its exit contract) and `docs/plans/2026-09-06-loop-context-management.md` (fresh context per item, runner identity, thin orchestrator), and is the "separate mode" those documents deferred for detached, unattended runs.

> **Status (0.20.0):** since Agentile Projects landed, checkpoints and runs described below as files or local daemon tables are store records instead: `/ag-build` opens a checkpoint and gets back an **id**, not a path, and that checkpoint is answered by id — on the Agentile Projects dashboard or at a terminal with `ag-store checkpoint_answer <id>`. Runs are likewise store records (`runs`/`run_events`), not a `workers` table the daemon owns alone. §7 and §9 below carry the same note where they describe the console and the daemon's data model; the rest of this document (the file-based checkpoint protocol in §3, the `<checkpoint-path>` status-line slot, the local `checkpoints`/`workers` schema in §9) is history, not current behaviour. The Agentile Factory (`~/lab/agentile_factory`) now implements this — see §7 (the console) and §9 (the checkpoint delivery loop) for how, and the factory's `docs/decisions/0004-agentile-projects-owns-the-backlog.md` for why.

## Context

`/ag-loop` drains a backlog inside one Claude Code session. That has two limits the loop-runner spec accepted and the context-management plan only partly fixed:

- It stops after `max_iterations` (five by default) and cannot sit idle waiting for work; `/loop /ag-loop` papers over that but is still one session.
- Context accumulates across items in that session. `/ag-loop --once` plus `bin/ag-run` gives one process per item, but `bin/ag-run` is sequential, has no model selection, serves one project, and stops dead at the first pause because a detached process has nobody to answer it.

Meanwhile a dozen repos on the same machine already carry a `.agentile/` directory, and several `claude` sessions run side by side by hand. What is missing is the thing that turns a machine into a factory: a scheduler that claims a Ready spec, hands it to a brand-new `claude` process with a chosen model, lets that process take the one spec through plan, build, verify and ship and then exit, and a single place to see every item that is waiting on a human, grouped by project.

Two constraints shape everything below:

- **Tokens bill to the Claude subscription, not the API.** A `claude -p` process authenticated by `claude login` consumes subscription usage (verified 2026-09-16 on Claude Code 2.1.270 with a Max plan and no `ANTHROPIC_API_KEY` in the environment). The Claude Agent SDK requires an API key and is therefore out. Bare mode (`--bare`) never reads OAuth credentials and is also out.
- **A headless worker cannot prompt.** With `--permission-prompts none` Claude Code removes `AskUserQuestion` and denies anything that would prompt. Human input travels through checkpoint files and the worker's open stdin (verified the same day: a headless worker with `--input-format stream-json` accepts further messages after a turn, keeps its context and session, and exits when stdin closes).

## Decisions

- **The unit of work is one spec, and the skill is `/ag-build`.** `/ag-build [slug]` takes one spec from claim to shipped and stops. It replaces `/ag-loop`; there is no skill that iterates. Running several specs at once means several sessions or several factory workers, each on one spec.
- **One worker process per spec, headless.** Each claimed spec runs as `claude -p "/ag-build"` in its own process, in the project's main checkout, with a model chosen for that spec. The worker exits when the spec is shipped, failed, or a pause has outlasted the keep-alive window.
- **The daemon answers nothing; the console collects answers.** When a worker needs a decision it writes a checkpoint file into the spec directory and ends its turn. The console shows the checkpoint, takes the answer, and the daemon delivers it on the worker's stdin if the process is still alive, or by `--resume <session_id>` if not. Either way the item's own context survives the pause and nothing from any other item enters it.
- **Claim first, spawn second.** The daemon claims through the existing store (`bin/ag-store claim`, under the file lock) using the worker's identity as `AGENTILE_RUNNER_ID`, reads the claimed spec's frontmatter to pick the model, then spawns the worker with the same runner id. `/ag-build` finds a spec already claimed by its identity and continues with it. Interactively, `/ag-build` claims for itself.
- **One daemon per machine, no project registration.** The daemon is the slot manager, because the rate limit is per subscription. Whether a project feeds the factory, and how many workers it gets, is set on that project's own Settings page in Agentile Projects, not typed at the machine; `factory start`, `factory stop`, `factory status` and `factory scan` take no project path at all — the daemon discovers each project's checkout on this machine by scanning configured roots and asking Agentile Projects which of what it finds is switched on.
- **Rails console on the Practice Manager stack.** The review surface is a Rails 8 + DaisyStack app (the pattern of `company/internal_projects/practice_manager`): SQLite, Devise, resource pages, live updates through `DaisyStack::Push` over Solid Cable. The daemon runs as a Rails runner inside the same app (`bin/factory`), sharing its models and broadcasting the same events, not as a Solid Queue job.
- **Stage policy lives in stage playbooks and nowhere else.** `.agentile/loop.md` is retired. Its per-project keys move to the playbooks of the stages they govern; its scheduling keys move to the factory.
- **The plugin changes stay additive.** Every existing way of running Agentile keeps working through one release of aliases.

## Architecture

```
                 ┌──────────────────────────────────────────────┐
                 │  Factory console (Rails 8 + DaisyStack)      │
  Keith ───────▶ │  Floor · Attention · Projects · Settings      │
  (browser,      │  answers checkpoints, edits plan.md, chats    │
   phone)        └───────────────┬──────────────────────────────┘
                                 │ SQLite + Solid Cable (live push)
                 ┌───────────────┴──────────────────────────────┐
                 │  bin/factory  (daemon, Rails runner)          │
                 │  poll projects → claim → spawn → stream →     │
                 │  deliver answers → review servers → notify    │
                 └───┬───────────────┬──────────────┬───────────┘
                     │ stdin/stdout  │              │  one process each,
                     ▼ stream-json   ▼              ▼  in the project's checkout, own model
              claude -p        claude -p       claude -p
              /ag-build        /ag-build       /ag-build
              (numnums, opus)  (oma_bom, sonnet)(numnums, sonnet)
                     │               │              │
                     └── AG_BUILD: shipped | paused <slug> <reason> <checkpoint> | failed
```

The daemon reads backlogs through `bin/ag-store`, writes worker state and events to SQLite, and holds each worker's stdin and stdout. The console reads SQLite and the spec directories, writes answers into checkpoint files and `plan.md`, and posts chat messages that the daemon forwards. Neither the console nor the daemon ever reads a diff or a spec body into a Claude context; that discipline stays with the worker's subagents.

## 1. `/ag-build`: one spec, claim to shipped

`/ag-build [slug]` is `/ag-loop --once` with a targeted claim and a name that says what it does. Its algorithm:

1. **Claim.** If a spec is already `in_progress` and `claimed_by` this identity (`AGENTILE_RUNNER_ID`, else the session id), work that one. Otherwise claim: the named slug if given, else the top prioritised unblocked Ready spec, through `bin/ag-store claim`. Report `idle` with the store's reason if nothing is claimable.
2. **Plan, build, verify, ship** exactly as the runner spec describes, honouring every stage playbook.
3. **Pause** at any stage whose playbook requires it by writing a checkpoint (section 3) and ending the turn.
4. **Finish** with one status line, the last line of the turn:

```
AG_BUILD: shipped <slug>
AG_BUILD: paused <slug> <reason> <checkpoint-id>
AG_BUILD: failed <slug-or-'-'> <reason>
AG_BUILD: idle <NONE|WIP_FULL|BLOCKED|UNPRIORITISED>
```

The status line being the turn's *last* line is what a reader can rely on, not its *only* line: a `plan_review` pause typically ends a paragraph of prose and a pointer to `plan.md` with this line, and a driver reading the turn should scan for the last matching line rather than expect the whole turn to be just this.

The name collides with the build stage (`ag-builder`, `.agentile/build.md`) and that is accepted: "build the spec" is the whole trip, "the build stage" is the implementing part of it. Stage prose says "implement" wherever the two would otherwise be confused.

Interactive use is unchanged in spirit: you run `/ag-build 0009-unit-conversion-rules` in a session to hand-drive one spec while the factory works the rest of the queue. Pauses in an interactive session are still asked in chat, but the checkpoint file is written regardless so the item appears on the console. The builder already implements in its own worktree, so an interactive `/ag-build` beside factory workers touches the main checkout only to claim and to ship, both under the repo's locks.

`/ag-next` stays as "claim and tell me" for reserving a spec to build later. `/ag-wip` recognises a `factory/…` runner id and points at the console. `/ag-loop` remains for one release as an alias that runs `/ag-build` once and mentions the factory.

### Stage policy moves into the playbooks

`.agentile/loop.md` is retired. Its keys:

- `pause_at_plan` becomes `human_checkpoint` on `.agentile/plan.md`, which already exists and already overrides it; `route` is an allowed value alongside `true` and `false`, meaning pause for `foreground` and `spike` specs.
- `pause_before_ship` becomes `human_checkpoint` on a new `.agentile/ship.md` playbook, so ship is configured like every other stage.
- `verify_retry_limit` and `stop_on_gate_failure` move to `.agentile/verify.md`.
- `max_iterations`, `on_empty` and `watch` are scheduling and belong to the factory.

`/ag-init` stops scaffolding `loop.md`; `/ag-version` warns if one is present.

## 2. The worker

Per claimed spec the daemon runs:

```
cd <project>
AGENTILE_RUNNER_ID=factory/<project>/<slug> \
claude -p "/ag-build" \
  --model <chosen> \
  --name "<project> · <slug>" \
  --permission-mode <project setting, default acceptEdits> \
  --permission-prompts none \
  --allowedTools <derived from the project's gates.json and settings> \
  --input-format stream-json --output-format stream-json --verbose \
  --max-turns <project setting> \
  --append-system-prompt-file <plugin>/templates/factory-worker.md
```

The cwd is the project's own main checkout, not a worktree the daemon creates per worker — a worktree checks out trunk with no working copy of the claim `ag-store claim` just wrote into the spec's frontmatter, so a worker started there would find nothing claimed by its own identity. See the factory's `docs/decisions/0001-workers-run-in-the-main-checkout.md` for the full reasoning. Isolation of code changes is handled one level down instead: the `ag-builder` subagent still declares its own `isolation: worktree`, so gate runs and commits for the build stage happen in a worktree regardless. Ship merges to trunk through `bin/ag-lock` per repo, serialising the main checkout across whatever workers share it.

The daemon holds stdin open for the life of the worker. That gives three things: chat messages from the console reach the worker at its next turn boundary at the latest; a paused worker can stay alive and idle, costing nothing, so an answer is delivered instantly; and the process still stops when it is done, because the daemon closes stdin when it sees a terminal status line. A paused worker that outlives the keep-alive window (Settings, default 30 minutes) is closed, and later answers go through `--resume <session_id>`. If a resume fails, the daemon falls back to a fresh `claude -p "/ag-build"` with the same runner id; the claim and the answered checkpoint are on disk, so the item continues from its plan and branch.

The worker's subagents keep their models: `ag-builder` pins `sonnet`, `ag-planner` and `ag-reviewer` inherit the worker's model, so choosing the model for a spec chooses what plans and reviews it.

## 3. The checkpoint protocol

Every pause reason (`plan_review`, `build_blocked`, `build_checkpoint`, `gate_failure`, `verify_checkpoint`, `ship_approval`) plus one new reason, `question`, becomes a file:

```
docs/agentile/specs/0007-<slug>/checkpoints/
  001-plan_review.md
  002-question.md
  003-ship_approval.md
```

```markdown
---
reason: question            # one of the pause reasons above
asked_at: 2026-09-16T03:12:40Z
session_id: 2eb81f90-…      # the worker session to resume if the process is gone
asked_by: builder           # what asked: plan | build | builder | reviewer | verify | ship
status: open                # open | answered
answered_at:
answered_by:
---

## Ask

<what the worker needs, in plain language; for a question, the options it sees and its own recommendation>

## Answer

<empty until a human writes here>
```

- The worker writes the file, references it in the status line, ends its turn. It never polls.
- `plan_review` needs no prose answer: an amended `plan.md` is the approved plan. The console renders `plan.md` in an editor with Approve; approving marks the checkpoint answered.
- `ship_approval` and `verify_checkpoint` show the reviewer's verdict summary, the gate results, the diff stat, and the review banner (section 6). The answer is approve, or a note that sends the item back to build.
- `question` is for anything the builder or reviewer genuinely cannot decide from the spec, the plan, `CLAUDE.md` and the ADRs. The worker prompt tells it to prefer a recorded assumption in `plan.md` when the stakes are low, and to ask once with options and a recommendation rather than many times.
- `gate_failure`, `build_blocked` and a crash show the failing output tail; the answers are retry, release (back to Ready) or abandon.

When the console marks a checkpoint answered, the daemon writes one message to the worker's stdin, or resumes the session with it: "Checkpoint `<path>` is answered. Read it and continue." Checkpoints live in the repo, not only in SQLite, so a worker continues correctly even after a resume or a fallback fresh start.

## 4. The daemon and its commands

`bin/factory` is one long-running Ruby process per machine, started on demand by the first `factory start` (like herdr's server) or by a `systemd --user` unit. None of the commands take a project — projects come from Agentile Projects:

```
factory start                                    # make sure a daemon is running, wake it
factory stop                                     # ask a running daemon to shut down
factory status                                   # every project: on/off, running, waiting on you
factory scan                                     # sync now; report each project's checkout state
```

Turning a project on or off, and setting its worker cap, happens on that project's Settings page in Agentile Projects; the daemon finds where it is checked out on this machine by scanning the roots in Settings (default `~/lab`, `~/projects`) for a direct child carrying a linked `.agentile/store.md`. `factory scan` is the troubleshooting command for that: it syncs immediately and prints every project's checkout state.

Resource direction is one number per project plus a machine-wide cap:

- `factory_workers`: the most that project may run at once, set in Agentile Projects.
- The machine-wide `max_workers` (Settings, default 3), set once for the subscription.

There is no rank any more. When the machine-wide cap is the binding one, dispatch goes round-robin across every switched-on, checked-out project — one claim per project per pass — so a small cap is shared out rather than won outright by whichever project sorts first. Changing an allocation — the switch, the cap, or the checkout itself — takes effect at the next sync without touching running workers. There is deliberately no weighted sharing and no cross-project spec priority; round-robin and caps say "share it out" legibly. The claim itself carries no wip limit of its own: the store's own `wip_limit` for the project governs how many of its specs may be in progress at once, across every person and machine that claims from it; `factory_workers`/`workers_cap` is only this machine's own ceiling on how many it runs concurrently, which the scheduler enforces before it ever asks the store to claim.

The daemon's loop, every `poll_interval` (default 30 seconds):

1. **Stream.** Drain every worker's stdout into `events`; on a terminal status line record `shipped`, `paused` (creating the checkpoint row from the file, starting a review server if the reason calls for one), `failed`, or a crash (non-zero exit with no status line). Close stdin on `shipped` and `failed`; on `paused` start the keep-alive clock.
2. **Deliver.** For each checkpoint answered since the last tick, and each chat message posted, write to the worker's stdin, or resume the session if the process is gone. Stop the review server when its checkpoint is answered.
3. **Throttle.** Claude Code reports one of three rate-limit statuses: `allowed`, `allowed_warning` and `rejected`. Only `rejected` should stop dispatch — `allowed_warning` is a utilisation warning, not a denial, and treating it as one would hold the whole factory off for the rest of a five-hour window on a warning alone. If any worker reported `rejected`, dispatch nothing until the recorded reset time, and show that on the Floor.
4. **Dispatch.** While running workers are below the machine cap, round-robin across every project Agentile Projects has switched on that has exactly one checkout on this machine, below its own cap: claim with a fresh runner id; read the frontmatter, choose the model (section 5), spawn. Record `NONE`, `WIP_FULL`, `BLOCKED` or `UNPRIORITISED` on the project so the Floor can show why it is idle. There is no drain any more — switch a project off in Agentile Projects instead.
5. **Notify.** For each new attention item, a desktop notification (`notify-send`) and, when configured, an ntfy push linking to the item.

The daemon is the only thing that spawns, resumes or messages workers, so the caps are real. On restart it reconciles `workers` marked running against live pids and marks the dead ones crashed. The daemon never runs `/ag-deploy`; the Floor shows how many shipped specs await a deploy per project.

## 5. Choosing the model

Resolved once per claim, first match wins:

1. `model:` in the spec frontmatter (new, optional).
2. The project's route table, keyed by the spec's `route`: default `background: sonnet`, `foreground: opus`, `spike: opus`.
3. The project's default model, set as an override on its detail page in the factory console.
4. The factory default from Settings (`sonnet`).

A worker on a heavier model also gets `--fallback-model sonnet`, so a capacity error degrades rather than fails. The Projects page shows the resolved model beside each Ready spec before anything is spawned.

## 6. Review servers and credentials

Sign-off needs the running thing in front of the reviewer, and its login. That is project configuration, not something the model types. `gates.json` gains a `review` block:

```json
"review": {
  "start": "bin/dev -p {port}",
  "url": "http://localhost:{port}",
  "ready": "http://localhost:{port}/up",
  "login": { "user": "admin@example.com", "password_env": "REVIEW_PASSWORD" }
}
```

When a `ship_approval` or `verify_checkpoint` checkpoint opens on a project with a review block, the daemon allocates a port from the Settings range, starts the app in the worker's working directory — the project's main checkout, per `docs/decisions/0001-workers-run-in-the-main-checkout.md`, not a worktree of its own — polls `ready`, and records the URL. The item page shows a banner at the top with the URL and the login, each with a copy button; the password is read from the environment by the console, never stored in SQLite or written by the model. The Approve button is disabled until the server reports ready, and a failed start is its own attention item, `review_unavailable`, with the log. The server is stopped when the checkpoint is answered. Projects without a review block show a plain approval page.

## 7. The console

> **Status (0.20.0):** the console pages described here are absorbed by Agentile Projects' dashboards (home and per-project attention/in-progress/up-next). The daemon keeps spawning workers; its checkpoints and runs are the store's records (`ag-store checkpoint_open`/`run_event`), and a checkpoint answered on the dashboard is what resumes a worker. This is implemented, and the console below is not: the factory has no answer form of its own; instead it links to the checkpoint's page in Agentile Projects (`<url>/p/<project>/checkpoints/<id>/edit`) and to the project's dashboard. See the factory's `docs/decisions/0004-agentile-projects-owns-the-backlog.md`.

Four pages. All of them re-render on push: every daemon write to `workers`, `checkpoints`, `projects` and `events` broadcasts through `DaisyStack::Push` after commit, the RaceBox pattern, and the grids and cards declare `rerender_on:`.

- **Floor** is the landing page, grouped by project. One card per project: a status line (On, 2 of 2 running, 1 waiting on you; or Off; or Idle: nothing prioritised), then its live workers (spec, model, elapsed, turns, tokens, last tool call), then its open attention items. A worker row opens the worker page; an attention row opens the item page.
- **Attention** is the flat cross-project queue, newest first, badged by reason. It is the page to leave open on a phone.
- **Projects** is the registry: an on/off switch per project, worker cap, rank, default model and route table, permission posture, review block status, last claim result, and the Ready queue with each spec's resolved model. Filterable by On, Off and Idle. Adding a project is a path.
- **Settings**: machine-wide worker cap, poll interval, keep-alive window, default model and route table, default permission posture, worktree root, review port range, notification targets, wall-clock limit per worker.

Two detail pages hang off those:

- **Item page** for a checkpoint or failure. The same layout for every reason: spec title, route, project and model at the top; the review banner when there is one; the artefact in the middle (`plan.md` in an editor, or the question with options and recommendation and a text box, or verdict plus gates plus diff stat, or the log tail); the actions for that reason; and the hand-over command at the bottom.
- **Worker page** for a running or paused worker: the live transcript on the left (assistant text in full, tool calls collapsed to one line each), a message box beneath it that posts to the worker's stdin, and the worker's checkpoints on the right. Two buttons: **Stop** (SIGTERM, release the claim) and **Hand over**, which stops the worker, opens a foot terminal (or a herdr pane when herdr is running) in the worker's working directory — the project's main checkout, not a worktree of its own — with `claude --resume <session_id>`, and marks the item handed over until you release or ship it. Hand-over is stop-then-open because one session cannot have two drivers. Add `--remote-control` to the printed command to drive that terminal from the claude.ai app.

The console runs on the factory machine and is reached over the LAN or Tailscale; it is not deployed to server1 because the workers and repos are on the factory machine.

## 8. Permissions and safety posture

- No `ANTHROPIC_API_KEY` in the daemon's environment, ever; the daemon refuses to start if one is set.
- Never `--bare`.
- Every worker runs in the project's main checkout; trunk is touched only by the ship step under `bin/ag-lock`, and `gates.json` protected branches still apply.
- `--permission-prompts none`: an unauthorised action is denied, not waited on. Default posture is `acceptEdits` plus an allowlist built from the project's `gates.json` commands, `git`, and the plugin's own tools (`ag-store`, `ag-lock`). `bypassPermissions` is a per-project opt-in and the Projects page labels it.
- `--max-turns` and a wall-clock limit end runaway workers as `failed timeout` with the claim and checkout left as they are for inspection.
- Review credentials come from the environment through the console; the model never sees or writes them.

## 9. Data model

> **Status (0.20.0):** `checkpoints` and the run state live in Agentile Projects (`runs`, `run_events`, `checkpoints`); the daemon's local tables become a cache of process state (pid, pipes) only. This is implemented: the factory keeps no local `checkpoints` table at all. A paused worker's `AG_BUILD: paused <slug> <reason> <id>` line gives the daemon the store's checkpoint id; each tick it asks the store (`ag-store checkpoint_list <slug>`) whether that id is answered, then either writes "Checkpoint `<id>` is answered. Read it and continue." on the worker's stdin or restarts it on the same claim with the same `AGENTILE_RUNNER_ID`. See the factory's `docs/decisions/0004-agentile-projects-owns-the-backlog.md`.

- **projects**: name, path, on, drain, rank, workers_cap, default_model, route_models (json), permission_mode, allowed_tools (json), review (json, mirrored from gates.json at registration and refreshed each poll), last_claim_result, last_polled_at.
- **workers**: project_id, spec_slug, spec_rank, runner_id, session_id, model, worktree_path, branch, pid, status (`running`, `paused`, `handed_over`, `shipped`, `failed`, `crashed`, `stopped`), started_at, ended_at, paused_at, turns, input_tokens, output_tokens, cost_reported, exit_status, last_line.
- **checkpoints**: worker_id, reason, path, status (`open`, `answered`), asked_at, asked_by, answered_at, answered_by, answer_summary, review_url, review_port, review_pid.
- **messages**: worker_id, direction (`to_worker`, `from_worker`), body, at. The chat transcript.
- **events**: worker_id, at, kind (`tool_use`, `assistant`, `result`, `stderr`), summary. Pruned after seven days; the transcript on disk is the durable record.

Specs are not stored; the console reads them through `bin/ag-store spec_list` when it renders a project.

## 10. Changes to the plugin

- `skills/ag-build/SKILL.md` (new): section 1. `skills/ag-loop/SKILL.md` becomes the one-release alias.
- `bin/ag-store`'s `claim` op: accept a target slug.
- Checkpoint writing at every pause; the `question` reason; the checkpoint path on the status line.
- `agents/ag-builder.md` and `agents/ag-reviewer.md`: report a genuine human decision as a question with options and a recommendation; prefer a recorded assumption when stakes are low; say "implement" where "build" would be ambiguous.
- `templates/agentile/spec-template.md`: optional `model:`.
- `templates/agentile/ship.md` (new playbook) and `human_checkpoint: route` on `plan.md`; `verify.md` gains `retry_limit` and `stop_on_gate_failure`; `loop.md` retired from `/ag-init`, warned about by `/ag-version`.
- `templates/agentile/gates.json`: the optional `review` block.
- `templates/factory-worker.md` (new): the appended system prompt for a factory worker: you are headless, you cannot prompt, checkpoints are files, messages may arrive on stdin between turns, finish with the status line.
- `skills/ag-wip/SKILL.md`: recognise `factory/…` runner ids.
- `bin/ag-run`: calls `/ag-build` instead of `/ag-loop --once`; otherwise unchanged, documented as the fallback when no console is running.

## 11. Alternatives considered

- **Interactive workers inside herdr panes.** herdr 0.8.2 can start a `claude` agent in a pane, detect `blocked` and `done`, wait on state and show notifications. Rejected as the worker host because a blocked interactive session holds a terminal and a prompt until someone attaches, the answer surface is a terminal rather than a form with the plan, diff or review URL in it, and state detection is heuristic. Kept as the hand-over host.
- **The Claude Agent SDK.** The cleanest programmatic control, including permission callbacks in code, but it requires an API key. Ruled out by the subscription constraint.
- **One daemon per project.** Natural to type, but three of them share nothing: no total worker cap, no shared rate-limit brake, and the attention view only spans them if they share a database anyway. The shared piece got built by the back door, so it is built once, deliberately, with per-project commands on top.
- **One long `/loop /ag-loop` session per project.** What exists today; context accumulates, the loop stops at five, and the model is per session.
- **Closing the worker at every pause and always resuming by id.** Simpler daemon, but every answer costs a resume and there is no chat. Open stdin with a keep-alive window gives instant answers and a conversation, and still stops the process when work ends.

## 12. Phasing

1. **Protocol and `/ag-build`.** The plugin changes in section 10. Usable immediately by hand and by `bin/ag-run`.
2. **Daemon.** `bin/factory` inside a skeleton Rails app: registry, commands, claim and spawn, streaming, checkpoint delivery over stdin and resume, desktop notifications. Answers typed into checkpoint files by hand or through a minimal Attention list.
3. **Console.** Floor, Attention, Projects, Settings, item and worker pages, live push, chat, review servers, hand-over.
4. **Reach.** ntfy push, token usage per five-hour window on the Floor, herdr pane for hand-over.

## 13. Out of scope

- Deploying from the factory; `/ag-deploy` stays a human-run batch.
- Participants and approval roles (`team.md`); `answered_by` is recorded so they can join later.
- Workers on more than one machine; a second machine is a second factory.
- Airtable or Jira as the checkpoint store; checkpoints are Agentile Projects store records, so a worker needs network reachability to the app (beyond Claude) to open or answer one.
- Weighted fair sharing across projects.

## 14. Open decisions for Keith

- **Name and home.** The console depends on the private DaisyStack gem; if the factory is to ship with the public plugin the UI needs a public stack or the gem needs publishing. Suggested home for now: `~/lab/agentile_factory`.
- **Default posture for lab repos.** `acceptEdits` plus allowlist is the safe default; flipping lab repos to `bypassPermissions` is per project.
- **Starting caps on a Max 20x plan.** Three machine-wide is the proposal; the usage view in phase 4 is what makes the right number obvious.
