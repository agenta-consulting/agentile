---
name: ag-init
description: Initialise Agentile in the current project — scaffold inbox.md, the .agentile/ config layer, docs/adr/, and the CLAUDE.md standing-context section, then optionally enable the deterministic gate hooks. Idempotent; never overwrites existing files. Trigger phrases include "/ag-init", "set up Agentile here", "initialise Agentile", "scaffold the loop".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
---

# ag-init

Scaffold the **tailorable layer** of Agentile into this project. The methodology core (skills, agents, hooks) is already installed via the plugin; this skill drops the per-project files the skills read at runtime, so the team can tailor *content* without touching the methodology.

This skill is **idempotent**: it must never overwrite a file that already exists. For each target, check first, and report whether it was created or left as-is.

## Step 1 — Locate the plugin templates

The files to copy live in this plugin's `templates/` directory. Resolve its absolute path:

1. Run `echo "$CLAUDE_PLUGIN_ROOT"`. If set, templates are at `$CLAUDE_PLUGIN_ROOT/templates/`.
2. If unset, locate the plugin install: look under `~/.claude/plugins/cache/agentile-local/agentile/*/templates/` (or the symlinked dev path if `bin/ag-dev-link` was used). Use the newest version directory.

## Step 2 — Confirm setup choices

Use `AskUserQuestion` to gather (one compact round):

- **Gate commands** — the project's `format`, `lint`, `test`, `build`, and `deploy` commands (any may be left blank). These populate `.agentile/gates.json`.
- **Protected branches** — branches agents must not commit to directly (default `main`, `master`).
- **Enable hooks?** — whether to wire the format-on-edit and test-gate hooks into this project's `.claude/settings.json` now. Default yes; they no-op until `gates.json` has commands, so they are safe.

If the user is mid-flow and does not want questions, accept defaults and leave `gates.json` blank — they can fill it in later.

## Step 3 — Scaffold files (skip any that exist)

Copy from `templates/` into the project root, preserving structure:

- `inbox.md`
- `.agentile/config.md`
- `.agentile/shape.md`
- `.agentile/playbooks.md`
- `.agentile/build.md`
- `.agentile/verify.md`
- `.agentile/prioritise.md`
- `.agentile/next.md`
- `.agentile/gates.json` — then fill in the commands and protected branches gathered in Step 2.
- `.agentile/spec-template.md`
- `.agentile/adr-template.md`
- `docs/adr/0000-record-architecture-decisions.md` — replace `<YYYY-MM-DD>` with today's date (`date +%Y-%m-%d`).
- Create an empty `specs/` directory (add a `.gitkeep`).

Note the source `templates/agentile/` maps to the project's `.agentile/` directory.

## Step 4 — Standing context

Append the contents of `templates/CLAUDE.agentile-section.md` to the project's root `CLAUDE.md`:

- If `CLAUDE.md` exists and does **not** already contain a "## Agentile" heading, append the section (with a blank line before it).
- If `CLAUDE.md` does not exist, suggest the user run `/init` first to bootstrap it from the codebase, then create `CLAUDE.md` containing just the Agentile section.
- If the section is already present, leave it.

## Step 5 — Hooks (only if enabled in Step 2)

Merge the plugin's hooks into the project so the gates enforce themselves. The plugin ships `hooks/hooks.json`; if the user enabled hooks, ensure the project's `.claude/settings.json` references them (the plugin's own `hooks` declaration already registers them when the plugin is installed, so in most cases no project edit is needed — confirm the plugin is installed rather than duplicating the hook registration). Explain that the hooks read `.agentile/gates.json` and no-op while commands are blank.

## Step 6 — Report

Summarise what was created versus skipped, then point the user at the next move:

> Agentile is initialised. Capture ideas with `/ag-capture`, review them with `/ag-inbox`, and shape one into a spec with `/ag-shape`. Tailor what "Ready" means by editing `.agentile/shape.md`. To configure how any loop stage runs in this project, use `/ag-customise <stage>`; see `.agentile/playbooks.md` for the full directive contract.
