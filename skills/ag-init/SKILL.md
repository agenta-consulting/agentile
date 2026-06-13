---
name: ag-init
description: Initialise Agentile in the current project — scaffold inbox.md, the .agentile/ config layer, docs/adr/, and the CLAUDE.md standing-context section, then optionally enable the deterministic gate hooks. Idempotent; never overwrites existing files. Trigger phrases include "/ag-init", "set up Agentile here", "initialise Agentile", "scaffold the loop".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
disable-model-invocation: true
---

# ag-init

Scaffold the **tailorable layer** of Agentile into this project. The methodology core (skills, agents, hooks) is already installed via the plugin; this skill drops the per-project files the skills read at runtime, so the team can tailor *content* without touching the methodology.

This skill is **idempotent**: it must never overwrite a file that already exists. For each target, check first, and report whether it was created or left as-is.

## Step 1 — Locate the plugin templates

The files to copy live in this plugin's `templates/` directory, one level up from this skill: `${CLAUDE_SKILL_DIR}/../../templates/`. (`${CLAUDE_SKILL_DIR}` is the directory containing this `SKILL.md` — it resolves to `…/skills/ag-init/`, so `../../templates/` is the plugin's templates root. Fallback: `"${CLAUDE_PLUGIN_ROOT}/templates/"`.)


## Step 2 — Confirm setup choices

Use `AskUserQuestion` to gather (one compact round):

- **Gate commands** — the project's `format`, `lint`, `test`, `build`, and `deploy` commands (any may be left blank). These populate `.agentile/gates.json`.
- **Protected branches** — branches agents must not commit to directly (default `main`, `master`).
- **Configure gate commands now?** — the project's `format`, `lint`, `test`, `build`, and `deploy` commands for `.agentile/gates.json` (any may be left blank). The plugin's hooks are active whenever the plugin is enabled; they simply no-op until these commands are filled in. So this is about *enabling the gates*, not the hooks themselves.

If the user is mid-flow and does not want questions, accept defaults and leave `gates.json` blank — they can fill it in later.

## Step 2a — Project brief (fresh projects)

Detect a fresh project: no `CLAUDE.md` of substance (absent, or only the Agentile
section) AND a near-empty repo (no significant source tree). If it looks
established, skip this step — the brief is optional for existing code, and
`/ag-retro` can seed it later.

For a fresh project, offer a short interview (decline-able — accept defaults and
leave the brief a template to fill in later). Ask, a couple at a time
(`AskUserQuestion` where the choices are discrete): who is this for; the one
outcome that matters first; the next two or three outcomes; hard constraints
(stack, platform, timeline); explicit non-goals; what "shipped v1" looks like.
Write the answers into `<dir>/brief.md` from `templates/agentile/brief-template.md`,
replacing every `<…>` placeholder. If a stack decision emerges, offer to capture
it as `docs/adr/0001-…` from the ADR template.

The brief is what makes triage real: without it, `/ag-shape` and `/ag-prioritise`
score Business Value against nothing. With it, they score against the brief's
prioritised outcomes.

## Step 3 — Migrate a legacy layout (only if one is detected)

Older Agentile projects kept the backlog at the repo root (`inbox.md`, `specs/`,
`specs/archive/`) with `Inbox:` / `Specs directory:` keys in `.agentile/config.md`. The
current layout puts everything under one **Agentile directory** (default `docs/agentile/`):
`inbox.md`, `specs/`, `specs/done/` (was `archive/`), `specs/abandoned/`.

Detect a legacy layout if **any** of these are present: a root-level `inbox.md`, a
root-level `specs/` directory, a `specs/archive/` directory, or an `.agentile/config.md`
that still has an `Inbox:` or `Specs directory:` key (and no `Agentile directory:` key).

If detected, do **not** silently move anything. Show the user exactly what will move and
ask for confirmation (`AskUserQuestion`):

```
Detected a legacy Agentile layout. Migrate to docs/agentile/ ?
  inbox.md            → docs/agentile/inbox.md
  specs/*.md          → docs/agentile/specs/
  specs/archive/*     → docs/agentile/specs/done/
```

On confirmation:

1. Create `docs/agentile/specs/done/` and `docs/agentile/specs/abandoned/` (with `.gitkeep`).
2. `git mv` each file into its new home (root `inbox.md` → `docs/agentile/inbox.md`;
   each top-level `specs/*.md` → `docs/agentile/specs/`; each `specs/archive/*.md` →
   `docs/agentile/specs/done/`), preserving filenames so history follows via `git mv`.
3. Rewrite the "## Paths" section of `.agentile/config.md`: drop the `Inbox:` and
   `Specs directory:` keys and add `**Agentile directory:** docs/agentile/` (keep
   `ADR directory:`). Use the template's Paths block as the model.
4. Remove the now-empty `specs/` and `specs/archive/` directories.

If the project already uses the new layout (an `Agentile directory:` key, or a populated
`docs/agentile/`), there is nothing to migrate — skip this step. Migration is a one-time,
explicitly-confirmed action; a second `/ag-init` run is a no-op here.

## Step 4 — Scaffold files (skip any that exist)

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`).
Copy from `templates/` into the project, preserving structure:

- `<dir>/inbox.md` (from `templates/inbox.md`)
- `<dir>/brief.md` (from `templates/agentile/brief-template.md`) — only if it does not exist; populated by the interview in Step 2a below.
- `.agentile/config.md`
- `.agentile/shape.md`
- `.agentile/playbooks.md`
- `.agentile/build.md`
- `.agentile/verify.md`
- `.agentile/prioritise.md`
- `.agentile/next.md`
- `.agentile/loop.md`
- `.agentile/gates.json` — then fill in the commands and protected branches gathered in Step 2.
- `.agentile/spec-template.md`
- `.agentile/plan-template.md`
- `.agentile/adr-template.md`
- `docs/adr/0000-record-architecture-decisions.md` — replace `<YYYY-MM-DD>` with today's date (`date +%Y-%m-%d`).
- Create the specs tree: `<dir>/specs/`, `<dir>/specs/done/`, and `<dir>/specs/abandoned/`, each with a `.gitkeep`.
- Add `**/specs/.pull.lock` to the project's `.gitignore` (create `.gitignore` if absent; skip if the entry is already present) — the claim lock is a runtime file, not source.

Note the source `templates/agentile/` maps to the project's `.agentile/` directory.

## Step 5 — Standing context

Append the contents of `templates/CLAUDE.agentile-section.md` to the project's root `CLAUDE.md`:

- If `CLAUDE.md` exists and does **not** already contain a "## Agentile" heading, append the section (with a blank line before it).
- If `CLAUDE.md` does not exist, suggest the user run `/init` first to bootstrap it from the codebase, then create `CLAUDE.md` containing just the Agentile section.
- If the section is already present, leave it.

Ensure the appended Agentile section imports the brief so it loads every session — the template ends with `@docs/agentile/brief.md` (rewrite this path to the configured Agentile directory if it differs from `docs/agentile/`).

## Step 6 — Hooks

There is nothing to wire per-project. The plugin's hooks (`hooks/hooks.json`) register automatically whenever the plugin is enabled — they merge in without any edit to the project's `.claude/settings.json`. The only project-level control is `.agentile/gates.json`: the hooks read it and no-op while its commands are blank, then enforce the gates once commands are filled in. Confirm the plugin is enabled rather than duplicating the hook registration.

## Step 7 — Readiness report (observations, not blockers)

The methodology's precondition is "first be agile, then agentic" — a working
trunk, gates, and tests. Check and report, without blocking:

- **Tests** — does `gates.json` have a `test` command? Does the repo have a test directory/framework?
- **CI** — is there a CI config (`.github/workflows/`, etc.)?
- **Trunk** — is there a default branch the team integrates to? Any long-lived divergent branches?

Phrase each as an observation ("No test command configured — the test-gate hook
will no-op until one exists"), so an unhealthy loop is visible rather than
silently amplified.

## Step 8 — Report

Summarise what was created versus skipped, then point the user at the next move:

> Agentile is initialised. Capture ideas with `/ag-capture`, review them with `/ag-inbox`, and shape one into a spec with `/ag-shape`. Tailor what "Ready" means by editing `.agentile/shape.md`. To configure how any loop stage runs in this project, use `/ag-customise <stage>`; see `.agentile/playbooks.md` for the full directive contract. Run the loop with `/ag-loop` (drains the backlog); `/loop /ag-loop` to also watch for new work.
