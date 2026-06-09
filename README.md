# Lean Agentic Loop (LAL) — Claude Code plugin

A low-ceremony methodology for **1–5 person teams** who direct AI agents as their primary way of building software. It keeps the agile *spirit* — short loops, working software, respond to change — while dropping the ceremony small teams can't justify.

The full methodology write-up is in [`lean-agentic-loop.md`](./lean-agentic-loop.md). This README is the operating manual for the plugin that implements it.

## The loop

```
capture → shape → spec → plan → build → verify → ship → learn
```

- **capture** — `/lal-capture <idea>` drops a one-line stub in `inbox.md`. Instant, mid-build safe.
- **shape** — `/lal-shape` interviews a stub into a Ready spec, against your project's Definition of Ready.
- **spec** — shaped specs land in `specs/`. `/lal-spec` writes one directly for trivial work.
- **plan** — `/lal-plan` (Plan Mode or the `lal-planner` agent) proposes the approach before any code.
- **build** — the `lal-builder` agent implements on a branch/worktree, running your gates.
- **verify** — the `lal-reviewer` agent critiques the diff with fresh context; gates + `/security-review` + a human read.
- **ship** — small, flagged, reversible PRs to trunk.
- **learn** — `/lal-retro` compiles a flow digest and encodes lessons into `CLAUDE.md` and ADRs.

## Fixed core vs. tailorable content

The plugin ships the **methodology** — the skills, the agents, the hooks. You don't fork them. Each project tailors its **content** through the `.lal/` files that `/lal-init` scaffolds:

| File | What it controls |
|------|------------------|
| `.lal/shaping.md` | **What "Ready" means** — the questions a stub must answer before it's a spec. The prime tailoring surface. |
| `.lal/config.md` | Paths and the Business Value × Technical Certainty triage routes. |
| `.lal/gates.json` | The deterministic commands — format, lint, test, build, deploy — and protected branches. |
| `.lal/spec-template.md` | The shape of a Ready spec. |
| `.lal/adr-template.md` | The shape of an ADR. |

The fixed skills *read* these at runtime, so content flexes while the loop's structure holds. To change what a shaped item must answer, edit one file — `.lal/shaping.md` — and every future `/lal-shape` asks accordingly.

## Install (in a project)

1. Add the marketplace and install the plugin:

   ```
   claude plugin marketplace add <path-or-git-url-to-this-repo>
   claude plugin install lean-agentic-loop@lean-agentic-loop-local
   ```

   (Or run [`bin/lal-sync`](./bin/lal-sync), which does both.)
2. Restart the session, then in your target project run `/lal-init` to scaffold `inbox.md`, `.lal/`, `docs/adr/`, and the `CLAUDE.md` standing-context section.
3. Start the loop: `/lal-capture`, `/lal-inbox`, `/lal-shape`, …

## Skills

`/lal-init`, `/lal-capture`, `/lal-inbox`, `/lal-shape`, `/lal-spec`, `/lal-plan`, `/lal-retro`.

## Agents (the "hats")

`lal-planner` (architecture & approach), `lal-builder` (implementation), `lal-reviewer` (verification & security). Each runs in its own context so the reviewer catches what the builder missed.

## Hooks

Config-driven and **opt-in safe** — they read `.lal/gates.json` and no-op when a command is blank, so installing the plugin never disrupts an unconfigured repo:

- **format-on-edit** (`PostToolUse`) — runs your formatter after each edit. If the `format` command contains `{file}`, the edited path is substituted.
- **test-gate** (`Stop` / `SubagentStop`) — blocks "done" until your `test` command passes.

The hook scripts are Ruby (`hooks/*.rb`), so Ruby must be on `PATH`.

## Developing the plugin while it's installed

Claude Code freezes an installed plugin as a snapshot, so source edits aren't seen until you reinstall. Two layered modes over this one repo:

- **Live (your machine):** run [`bin/lal-dev-link`](./bin/lal-dev-link) once (after a first `bin/lal-sync`) to symlink the install location to this repo. Edits to skills/agents/hooks then apply on the next session reload — no reinstall.
- **Snapshot (distribution / fresh machine / CI):** [`bin/lal-sync`](./bin/lal-sync) validates, registers the marketplace, and installs/updates. This is the path everyone else uses, so what you test equals what ships.

## The one rule

**First be agile, then agentic.** LAL amplifies a healthy loop — and amplifies a broken one. Get the trunk, the gates, and the written spec right first; the agents make a good loop fast, not a bad loop safe.
