# Agentile — Claude Code plugin

*Agile, with agency.*

A low-ceremony methodology for **1–5 person teams** who direct AI agents as their primary way of building software. It keeps the agile *spirit* — short loops, working software, respond to change — while dropping the ceremony small teams can't justify. We replaced the standup with a digest, so you can stand down.

Agentile is the implementation of the **Lean Agentic Loop** methodology — the full synthesis is in [`lean-agentic-loop.md`](./lean-agentic-loop.md). This README is the operating manual for the plugin.

## The loop

```
capture → shape → spec → plan → build → verify → ship → learn
```

- **capture** — `/ag-capture <idea>` drops a one-line stub in `inbox.md`. Instant, mid-build safe.
- **shape** — `/ag-shape` interviews a stub into a Ready spec, against your project's Definition of Ready.
- **spec** — shaped specs land in `specs/`. `/ag-spec` writes one directly for trivial work.
- **plan** — `/ag-plan` (Plan Mode or the `ag-planner` agent) proposes the approach before any code.
- **build** — the `ag-builder` agent implements on a branch/worktree, running your gates.
- **verify** — the `ag-reviewer` agent critiques the diff with fresh context; gates + `/security-review` + a human read.
- **ship** — small, flagged, reversible PRs to trunk.
- **learn** — `/ag-retro` compiles a flow digest and encodes lessons into `CLAUDE.md` and ADRs.

## Fixed core vs. tailorable content

The plugin ships the **methodology** — the skills, the agents, the hooks. You don't fork them. Each project tailors its **content** through the `.agentile/` files that `/ag-init` scaffolds:

| File | What it controls |
|------|------------------|
| `.agentile/shape.md` | **What "Ready" means** — the questions a stub must answer before it's a spec. The prime tailoring surface. |
| `.agentile/config.md` | Paths and the Business Value × Technical Certainty triage routes. |
| `.agentile/gates.json` | The deterministic commands — format, lint, test, build, deploy — and protected branches. |
| `.agentile/spec-template.md` | The shape of a Ready spec. |
| `.agentile/adr-template.md` | The shape of an ADR. |

The fixed skills *read* these at runtime, so content flexes while the loop's structure holds. To change what a shaped item must answer, edit one file — `.agentile/shape.md` — and every future `/ag-shape` asks accordingly.

### Customising any stage

Every loop stage can be further tailored through a **playbook**: a `.agentile/<stage>.md` file with optional YAML frontmatter and prose policy. The frontmatter keys are:

- `delegate_to: <skill>` — run this stage by invoking a named skill instead of the built-in behaviour.
- `also_run: [skill-a, skill-b]` — run additional skills alongside the built-in.
- `human_checkpoint: true` — pause for human sign-off before the stage completes.

Absent a playbook, the built-in baseline applies. Use `/ag-customise <stage>` to build one out conversationally — it interviews you about your project's needs and writes the file.

### Concurrent loops

Two skills govern the transition from ready work to in-flight work, and they are deliberately separate acts:

- **`/ag-prioritise`** orders the ready list by writing a `priority` score onto each spec (default scheme: Business Value × Technical Certainty; the `wip_limit` and weighting live in `.agentile/prioritise.md`). Run it whenever the ready queue changes.
- **`/ag-next`** is a transactional pull: it atomically claims the top unclaimed ready spec under a file lock (`bin/ag-claim`), stamps it with `status: in_progress`, `claimed_by: <session-id>`, and `claimed_at`, then reports what was claimed. Two loops running concurrently can never grab the same item.
- **`/ag-wip`** lists every in-progress claim and prints the resume command (`claude --resume <session-id>`) for each. Stale claims are surfaced for human judgement — Agentile flags them, but does not auto-reclaim.

The session id is a resume handle, so a loop that was interrupted mid-cycle can be picked back up exactly where it stopped.

### Running the loop

- **`/ag-loop`** drains the ready backlog: claim → build → verify → pause for your sign-off before ship → repeat, up to `max_iterations`. Use this when you want to clear a queue of ready specs in one session.
- **`/loop /ag-loop`** drains and then watches — once the backlog is empty it keeps running, picking up new ready work as it appears.
- Pause-before-ship is the default posture, so nothing merges without your approval.
- All of this is configurable in `.agentile/loop.md`.

## Install (in a project)

1. Add the marketplace and install the plugin:

   ```
   claude plugin marketplace add agenta-consulting/agentile
   claude plugin install agentile@agentile
   ```
2. Restart the session, then in your target project run `/ag-init` to scaffold `inbox.md`, `.agentile/`, `docs/adr/`, and the `CLAUDE.md` standing-context section.
3. Start the loop: `/ag-capture`, `/ag-inbox`, `/ag-shape`, …

## Skills

`/ag-init`, `/ag-capture`, `/ag-inbox`, `/ag-shape`, `/ag-spec`, `/ag-plan`, `/ag-prioritise`, `/ag-next`, `/ag-wip`, `/ag-loop`, `/ag-customise`, `/ag-retro`.

## Agents (the "hats")

`ag-planner` (architecture & approach), `ag-builder` (implementation), `ag-reviewer` (verification & security). Each runs in its own context so the reviewer catches what the builder missed.

## Hooks

Config-driven and **opt-in safe** — they read `.agentile/gates.json` and no-op when a command is blank, so installing the plugin never disrupts an unconfigured repo:

- **format-on-edit** (`PostToolUse`) — runs your formatter after each edit. If the `format` command contains `{file}`, the edited path is substituted.
- **test-gate** (`Stop` / `SubagentStop`) — blocks "done" until your `test` command passes.

The hook scripts are Ruby (`hooks/*.rb`), so Ruby must be on `PATH`.

## Developing the plugin while it's installed

Claude Code freezes an installed plugin as a snapshot, so source edits aren't seen until you reinstall. Two layered modes over this one repo:

- **Live (your machine):** run [`bin/ag-dev-link`](./bin/ag-dev-link) once (after a first `bin/ag-sync`) to symlink the install location to this repo. Edits to skills/agents/hooks then apply on the next session reload — no reinstall.
- **Snapshot (distribution / fresh machine / CI):** [`bin/ag-sync`](./bin/ag-sync) validates, registers the marketplace, and installs/updates. This is the path everyone else uses, so what you test equals what ships.

## The one rule

**First be agile, then agentic.** Agentile amplifies a healthy loop — and amplifies a broken one. Get the trunk, the gates, and the written spec right first; the agents make a good loop fast, not a bad loop safe.
