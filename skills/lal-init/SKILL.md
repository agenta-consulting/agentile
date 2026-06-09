---
name: lal-init
description: Initialise the Lean Agentic Loop in the current project — scaffold inbox.md, the .lal/ config layer, docs/adr/, and the CLAUDE.md standing-context section, then optionally enable the deterministic gate hooks. Idempotent; never overwrites existing files. Trigger phrases include "/lal-init", "set up LAL here", "initialise the lean agentic loop", "scaffold the loop".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
---

# lal-init

Scaffold the **tailorable layer** of the Lean Agentic Loop into this project. The methodology core (skills, agents, hooks) is already installed via the plugin; this skill drops the per-project files the skills read at runtime, so the team can tailor *content* without touching the methodology.

This skill is **idempotent**: it must never overwrite a file that already exists. For each target, check first, and report whether it was created or left as-is.

## Step 1 — Locate the plugin templates

The files to copy live in this plugin's `templates/` directory. Resolve its absolute path:

1. Run `echo "$CLAUDE_PLUGIN_ROOT"`. If set, templates are at `$CLAUDE_PLUGIN_ROOT/templates/`.
2. If unset, locate the plugin install: look under `~/.claude/plugins/cache/lean-agentic-loop-local/lean-agentic-loop/*/templates/` (or the symlinked dev path if `bin/lal-dev-link` was used). Use the newest version directory.

## Step 2 — Confirm setup choices

Use `AskUserQuestion` to gather (one compact round):

- **Gate commands** — the project's `format`, `lint`, `test`, `build`, and `deploy` commands (any may be left blank). These populate `.lal/gates.json`.
- **Protected branches** — branches agents must not commit to directly (default `main`, `master`).
- **Enable hooks?** — whether to wire the format-on-edit and test-gate hooks into this project's `.claude/settings.json` now. Default yes; they no-op until `gates.json` has commands, so they are safe.

If the user is mid-flow and does not want questions, accept defaults and leave `gates.json` blank — they can fill it in later.

## Step 3 — Scaffold files (skip any that exist)

Copy from `templates/` into the project root, preserving structure:

- `inbox.md`
- `.lal/config.md`
- `.lal/shaping.md`
- `.lal/gates.json` — then fill in the commands and protected branches gathered in Step 2.
- `.lal/spec-template.md`
- `.lal/adr-template.md`
- `docs/adr/0000-record-architecture-decisions.md` — replace `<YYYY-MM-DD>` with today's date (`date +%Y-%m-%d`).
- Create an empty `specs/` directory (add a `.gitkeep`).

Note the source `templates/lal/` maps to the project's `.lal/` directory.

## Step 4 — Standing context

Append the contents of `templates/CLAUDE.lal-section.md` to the project's root `CLAUDE.md`:

- If `CLAUDE.md` exists and does **not** already contain a "## Lean Agentic Loop" heading, append the section (with a blank line before it).
- If `CLAUDE.md` does not exist, suggest the user run `/init` first to bootstrap it from the codebase, then create `CLAUDE.md` containing just the LAL section.
- If the section is already present, leave it.

## Step 5 — Hooks (only if enabled in Step 2)

Merge the plugin's hooks into the project so the gates enforce themselves. The plugin ships `hooks/hooks.json`; if the user enabled hooks, ensure the project's `.claude/settings.json` references them (the plugin's own `hooks` declaration already registers them when the plugin is installed, so in most cases no project edit is needed — confirm the plugin is installed rather than duplicating the hook registration). Explain that the hooks read `.lal/gates.json` and no-op while commands are blank.

## Step 6 — Report

Summarise what was created versus skipped, then point the user at the next move:

> LAL is initialised. Capture ideas with `/lal-capture`, review them with `/lal-inbox`, and shape one into a spec with `/lal-shape`. Tailor what "Ready" means by editing `.lal/shaping.md`.
