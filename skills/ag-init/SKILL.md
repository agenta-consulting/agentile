---
name: ag-init
description: Link this project to Agentile Projects (the backlog store) and scaffold the tailorable .agentile/ layer, docs/agentile/ and docs/adr/. Idempotent — never overwrites a file that exists. Trigger phrases include "/ag-init", "initialise agentile", "set up agentile here", "link this repo to agentile projects".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
disable-model-invocation: true
---

# ag-init

Link this repo to its project in **Agentile Projects** and scaffold the **tailorable layer** of Agentile into it. The **fixed implementation** (skills, agents, hooks) is already installed via the plugin; this skill drops the per-project files the skills read at runtime, so the team can tailor *content* without touching the plugin.

This skill is **idempotent**: it must never overwrite a file that already exists. For each target, check first, and report whether it was created or left as-is.

## Step 1 — Locate the plugin templates

The files to copy live in this plugin's `templates/` directory, one level up from this skill: `${CLAUDE_SKILL_DIR}/../../templates/` (fallback `"${CLAUDE_PLUGIN_ROOT}/templates/"`).

## Step 2 — Link the project

1. Check the token: `[ -n "$AGENTILE_PROJECTS_TOKEN" ]`. If it is unset, stop and tell the user: sign in to Agentile Projects, create a token on the app's `/account/api_tokens` page, export it as `AGENTILE_PROJECTS_TOKEN` in their shell profile (never in a tracked file), and re-run `/ag-init`.
2. Resolve the app url: `AGENTILE_PROJECTS_URL` if set, else an existing `.agentile/store.md` `url:`, else the default `https://agentile-projects.agentaconsulting.com`. Ask (`AskUserQuestion`) only if the user is running the app somewhere else.
3. If `.agentile/store.md` already has `url:` and `project:`, the project is linked — run `ag-store doctor` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). If it returns `reachable: true`, skip to Step 3. If it does not, print the `detail` it returns, tell the user to check `AGENTILE_PROJECTS_TOKEN`, the `url:` in `.agentile/store.md`, and that the app is up, and stop. If `.agentile/store.md` has a `store:` key instead (`local`/`airtable`, pre-0.20.0), say it is being replaced and continue. If it exists but has neither `url:`+`project:` nor a `store:` key, show its contents, confirm with the user that it's safe to replace, then treat it as not yet linked and continue to point 4 below.
4. Otherwise run `AGENTILE_PROJECTS_URL="<url>" ag-store whoami`. It returns `{user_id, name, email, projects: [{slug, role}]}`. If `projects` is empty, tell the user an admin must create the project (or add them as a member) in the app's web UI — `<url>/projects/new`, or via Members on an existing project — then stop; re-run once that's done. Otherwise ask (`AskUserQuestion`) which project this repo is — offer the listed slugs (owner/member roles only; a `viewer` cannot capture or claim), plus "it isn't there yet". If it isn't there yet, tell the user to create the project in the app (Projects → New) and add themselves as owner, then re-run; project creation is not available from the CLI.
5. Write `.agentile/store.md` from `templates/agentile/store.md`, replacing the `url:` line with the resolved url and `<project-slug>` with the chosen slug. Then run `ag-store doctor` and stop on anything but `reachable: true`.

## Step 2a — Project brief (fresh projects)

The brief lives in the app (Project → Settings → Brief). Detect a fresh project: no `CLAUDE.md` of substance (absent, or only the Agentile section) AND a near-empty repo. If it looks established, skip this step — `/ag-retro` can seed the brief later.

For a fresh project, first recommend `/ag-new-project`: it runs a fuller interview (brief *and* stack), records the stack as an ADR, writes a starter `CLAUDE.md`, and then runs this scaffold. If the user would rather stay here, offer a short interview (decline-able): who is this for; the one outcome that matters first; the next two or three outcomes; hard constraints; explicit non-goals; what "shipped v1" looks like. Compose the brief from `templates/agentile/brief-template.md` (replace every `<…>` placeholder), show it, and tell the user to paste it into the project's Brief in the app — this skill cannot write the brief through the CLI. If a stack decision emerges, offer to capture it as `docs/adr/0001-…` from the ADR template.

The brief is what makes triage real: `/ag-shape` and `/ag-prioritise` score Business Value against its prioritised outcomes, and the app regenerates that list from Outcomes by rank.

## Step 3 — Scaffold files (skip any that exist)

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`). Copy from `templates/` into the project, preserving structure:

- `.agentile/config.md`
- `.agentile/shape.md`
- `.agentile/playbooks.md`
- `.agentile/build.md`
- `.agentile/verify.md`
- `.agentile/prioritise.md`
- `.agentile/next.md`
- `.agentile/plan.md`
- `.agentile/ship.md`
- `.agentile/deploy.md`
- `.agentile/gates.json` — then fill in the commands and protected branches gathered in Step 4.
- `.agentile/spec-template.md`
- `.agentile/outcome-template.md`
- `.agentile/plan-template.md`
- `.agentile/adr-template.md`
- `<dir>/deploys.md` (from `templates/agentile/deploys.md`) — the deploy log `/ag-deploy` appends to.
- `docs/adr/0000-record-architecture-decisions.md` (from `templates/docs/adr/0000-record-architecture-decisions.md`) — replace `<YYYY-MM-DD>` with today's date (`date +%Y-%m-%d`).
- Create the bare directory `<dir>/specs/` (no `.gitkeep`, no `done`/`abandoned` subdirectories — terminal states are status values in the store). Once a spec starts planning, its `plan.md`, `SPEC.md` snapshot and supporting files live at `<dir>/specs/<slug>/`, created on demand by `ag-store promote` on the spec's build branch `build/<slug>` (in `.claude/worktrees/build-<slug>`), reaching trunk with the build merge.
- Pull the brief: `ag-store brief_sync --dir "<dir>"` writes `<dir>/brief.md` (a read-only copy; the app owns it). If the project's brief is still empty, the file holds the app's placeholder — that is fine.

There is no `inbox.md`, `runs.md`, `outcomes/` directory or `.pull.lock` — the Inbox, Outcomes, checkpoints and runs are store records, and claiming is transactional in the app.

Note the source `templates/agentile/` maps to the project's `.agentile/` directory.

## Step 4 — Gate commands and protected branches

Use `AskUserQuestion` to gather (one compact round):

- **Gate commands** — the project's `format`, `lint`, `test`, `build`, and `deploy` commands (any may be left blank). These populate `.agentile/gates.json`: `test`, `lint` and `build` run at verify and ship, `deploy` at `/ag-deploy`, and `format` after each edit via the `format-on-edit` hook. Every gate no-ops while its command is blank.
- **Protected branches** — branches agents must not commit to directly (default `main`, `master`).

If the user is mid-flow and does not want questions, accept defaults and leave `gates.json` blank.

## Step 5 — Standing context

Append the contents of `templates/CLAUDE.agentile-section.md` to the project's root `CLAUDE.md`:

- If `CLAUDE.md` exists and does **not** already contain a "## Agentile" heading, append the section (with a blank line before it).
- If `CLAUDE.md` does not exist, suggest the user run `/init` first to bootstrap it from the codebase, then create `CLAUDE.md` containing just the Agentile section.
- If the section is already present, leave it.

Offer to write the section to `.claude/rules/agentile.md` instead, for users who keep `CLAUDE.md` short. Default remains appending to `CLAUDE.md`.

The section ends with `@docs/agentile/brief.md`; rewrite that path if the Agentile directory differs from `docs/agentile/`.

## Step 6 — Hooks

Nothing to wire per-project. The plugin's hooks (`hooks/hooks.json`) register automatically whenever the plugin is enabled; the only project-level control is `.agentile/gates.json`.

## Step 7 — Readiness report (observations, not blockers)

The methodology's precondition is "first be agile, then agentic" — a working trunk, gates, and tests. Check and report, without blocking:

- **Tests** — does `gates.json` have a `test` command? Does the repo have a test directory/framework?
- **CI** — is there a CI config (`.github/workflows/`, etc.)?
- **Trunk** — is there a default branch the team integrates to? Any long-lived divergent branches?
- **Store** — `ag-store doctor` reachable, and this user's role in the project (from `whoami`).

If your test/build command can't run twice at once (shared SQLite file, fixed port, single build cache), wrap it with `ag-lock` in `.agentile/gates.json` — see the `$comment` there.

Phrase each as an observation ("No test command configured — verify and ship will have nothing to run").

## Step 8 — Report

Summarise what was created versus skipped, then:

> Agentile is initialised — this repo is linked to project **<slug>** at <url>. Capture ideas with `/ag-capture`, review them with `/ag-inbox` (or the app's Inbox), and shape one into a spec with `/ag-shape`. Tailor what "Ready" means by editing `.agentile/shape.md`. To configure how any loop stage runs, use `/ag-customise <stage>`; see `.agentile/playbooks.md` for the directive contract. Build the next ready spec with `/ag-build` (or a named one with `/ag-build <slug>`); for an unattended machine, see the Agentile Factory (`docs/agentile-factory.md`) or the `bin/ag-run` fallback. Dashboards, checkpoints waiting on you and run history are in the app.
