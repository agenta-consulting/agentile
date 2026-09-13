---
name: ag-init
description: Initialise Agentile in the current project — scaffold inbox.md, the project brief, the .agentile/ config layer, docs/adr/, and the CLAUDE.md standing-context section, and configure the deterministic gate commands. Idempotent; never overwrites existing files. Trigger phrases include "/ag-init", "set up Agentile here", "initialise Agentile", "scaffold the loop".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
disable-model-invocation: true
---

# ag-init

Scaffold the **tailorable layer** of Agentile for Claude into this project. The **fixed implementation** (skills, agents, hooks) is already installed via the plugin; this skill drops the per-project files the skills read at runtime, so the team can tailor *content* without touching the plugin.

This skill is **idempotent**: it must never overwrite a file that already exists. For each target, check first, and report whether it was created or left as-is.

## Step 1 — Locate the plugin templates

The files to copy live in this plugin's `templates/` directory, one level up from this skill: `${CLAUDE_SKILL_DIR}/../../templates/`. (`${CLAUDE_SKILL_DIR}` is the directory containing this `SKILL.md` — it resolves to `…/skills/ag-init/`, so `../../templates/` is the plugin's templates root. Fallback: `"${CLAUDE_PLUGIN_ROOT}/templates/"`.)


## Step 2 — Confirm setup choices

Use `AskUserQuestion` to gather (one compact round):

- **Gate commands** — the project's `format`, `lint`, `test`, `build`, and `deploy` commands (any may be left blank). These populate `.agentile/gates.json`. There is no separate "enable hooks?" step: the plugin's hooks are active whenever the plugin is enabled; they simply no-op until these commands are filled in. So this question *is* how you enable the gates.
- **Protected branches** — branches agents must not commit to directly (default `main`, `master`).
- **Backlog store** — **Solo** (default: the Inbox and specs are files in this repo, exactly today's behaviour) or **Team** (they live in a shared datastore — Airtable by default — so prioritising and claiming are visible live across machines instead of relying on "pull before you touch the queue"). Solo needs no follow-up. Team branches into Step 2b below.
- **Concurrency safety** (only if `test` and/or `build` were filled in) — can two invocations of that command run safely at the same time? Ask plainly: "If two test runs happened at once, would they interfere with each other (a shared SQLite file, a fixed dev port, a single build cache), or are they already safe to overlap (Postgres/MySQL, per-worker test databases, stateless)?" Default the question itself toward "not sure" being treated as *unsafe* — false-positive serialization only costs a little queueing time; false-negative collisions produce the flaky, hard-to-diagnose failures this question exists to prevent. If unsafe, wrap the affected command(s) with the plugin's `ag-lock` (ships in `bin/`, on `PATH` while the plugin is enabled; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-lock"`):
  ```
  "test": "ag-lock storage/.test.lock 'bin/rails test'"
  ```
  Pick the lockfile path from the project's own ignored runtime-state directory (e.g. `storage/`, `tmp/`, tests' own scratch dir) — never a tracked path — and confirm the parent directory's `.gitignore` entry covers it (or add one). This is separate from, and lighter than, the hook-level protection: `hooks/test-gate.rb` already serializes its own Stop/SubagentStop-triggered runs per project directory unconditionally, with no config needed — `ag-lock` in `gates.json` additionally covers a human or `ag-builder` invoking the gate command directly.

If the user is mid-flow and does not want questions, accept defaults, leave `gates.json` blank, and skip the concurrency question (nothing to wrap yet) — they can fill it in later, including running `/ag-customise` or editing `gates.json` by hand to add `ag-lock` once a `test`/`build` command exists.

## Step 2a — Project brief (fresh projects)

Detect a fresh project: no `CLAUDE.md` of substance (absent, or only the Agentile
section) AND a near-empty repo (no significant source tree). If it looks
established, skip this step — the brief is optional for existing code, and
`/ag-retro` can seed it later.

For a fresh project, first recommend `/ag-new-project`: it runs a fuller interview
(brief *and* stack), records the stack as an ADR, writes a starter `CLAUDE.md`, and
then runs this scaffold with the gates pre-filled. If the user would rather stay
here, offer a short interview (decline-able — accept defaults and
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

## Step 2b — Team store setup (only if Team was chosen in Step 2)

1. Confirm `AGENTILE_AIRTABLE_TOKEN` is set (`[ -n "$AGENTILE_AIRTABLE_TOKEN" ]`). If not, stop here and point the user at `templates/stores/airtable/README.md` — a personal access token with `data.records:read/write` and `schema.bases:read/write` scopes, set as an environment variable, never written into a tracked file. Re-run this step once it's set.
2. Ask (`AskUserQuestion`) whether to **create a new base** or **use an existing one**:
   - **Create**: ask for the Airtable workspace id, then run `ag-store create_base "<project name>" --airtable-workspace <workspace-id>` (bare command `ag-store`, on `PATH` while the plugin is enabled; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). It prints the new base's id — this also creates and fully provisions the `Inbox`/`Specs`/`Members` tables in one step, so Step 2's provisioning call below is redundant for a freshly created base but still safe (idempotent) to run.
   - **Existing**: ask for the base id directly.
3. Provision (idempotent — safe even on a base `create_base` just built): `ag-store provision --dir "<Agentile directory>" --store airtable --airtable-base "<base-id>"`.
4. Verify: `ag-store doctor --dir "<Agentile directory>" --store airtable --airtable-base "<base-id>"` — all checks should be `true`. If not, stop and surface the failure rather than continuing.
5. Write `.agentile/store.md` directly (not from the generic template — this project's real values):
   ```yaml
   ---
   store: airtable
   airtable_base: <base-id>
   ---
   ```
   (omit the table-name keys entirely when they're the defaults `Inbox`/`Specs`/`Members`). Step 4 below skips re-copying the template over this file.
6. Tell the user to add themselves (and any teammates) to the base's `Members` table now — `Name`, `Email`, `Git Email` — so `ag-store whoami` can attribute their captures/claims. This is attribution only, not a permission system; an unmatched email just means attribution is silently skipped, never a hard failure.

## Step 2c — Migrate an existing local backlog into the new store (only if Step 2b just ran AND the Inbox or specs already have content)

Ask for confirmation before moving anything (`AskUserQuestion`), showing counts (e.g. "3 inbox stubs and 5 specs will be copied into Airtable; nothing is deleted locally"). On confirmation:

1. For each stub from `ag-store inbox_list --dir "<dir>" --store local`, run `ag-store inbox_add "<text>" --dir "<dir>" --store airtable --airtable-base "<base-id>"`.
2. For each spec from `ag-store spec_list --dir "<dir>" --store local` (every pool: active, `--pool done`, `--pool abandoned`), read its markdown with `ag-store spec_read "<slug>" --dir "<dir>" --store local` and recreate it with `ag-store spec_create "<slug>" --dir "<dir>" --store airtable --airtable-base "<base-id>"` (piping the markdown on stdin) — then, for a spec that isn't `ready`/`in_progress`, immediately apply its real terminal state with `ag-store ship`/`ag-store abandon --reason "<reason>"` against the airtable store so shipped/abandoned history isn't lost.
3. Once every **ready** spec has been recreated, restore the queue order with one `ag-store rank <slug-1> <slug-2> ... --dir "<dir>" --store airtable --airtable-base "<base-id>"` call, in the same order the local `NNNN-` prefixes encoded.
4. Report what moved. The local files are left untouched (nothing is deleted) — once the user has confirmed the Airtable copy looks right, they can remove the local `inbox.md`/`specs/` content themselves; this skill does not do that automatically.

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

- `<dir>/inbox.md` (from `templates/inbox.md`) — **Solo only.** In Team mode the Inbox lives in the store (Step 2b already provisioned it) — do not create this file at all; it would never be read.
- `<dir>/runs.md` (from `templates/agentile/runs.md`) — the durable run log `/ag-loop` appends to. Created regardless of store mode — this is Agentile's own operational log, unrelated to the backlog store.
- `<dir>/brief.md` (from `templates/agentile/brief-template.md`) — only if it does not exist; populated by the interview in Step 2a above.
- `.agentile/config.md`
- `.agentile/store.md` — **skip this copy if Step 2b already wrote a real one** (Team mode); for Solo, copy the template as-is (`store: local`, matching today's behaviour with nothing further to configure).
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
- Create the specs tree: **Solo** — `<dir>/specs/`, `<dir>/specs/done/`, and `<dir>/specs/abandoned/`, each with a `.gitkeep`. **Team** — just the bare `<dir>/specs/` directory, no `.gitkeep`, and no `done`/`abandoned` subdirectories — terminal states live in the store's `Status` field, nothing ever moves into a local subdirectory. The bare directory still matters: once a spec starts planning, its `plan.md` and supporting files live at `<dir>/specs/<slug>/` (created on demand by `ag-store promote`) even under Team mode.
- Add `**/specs/.pull.lock` to the project's `.gitignore` (create `.gitignore` if absent; skip if the entry is already present) — the claim lock is a runtime file, not source.

Note the source `templates/agentile/` maps to the project's `.agentile/` directory.

## Step 5 — Standing context

Append the contents of `templates/CLAUDE.agentile-section.md` to the project's root `CLAUDE.md`:

- If `CLAUDE.md` exists and does **not** already contain a "## Agentile" heading, append the section (with a blank line before it).
- If `CLAUDE.md` does not exist, suggest the user run `/init` first to bootstrap it from the codebase, then create `CLAUDE.md` containing just the Agentile section.
- If the section is already present, leave it.

Offer to write the section to `.claude/rules/agentile.md` instead of appending to `CLAUDE.md`, for users who keep `CLAUDE.md` short. Default remains appending to `CLAUDE.md`.

Ensure the appended Agentile section imports the brief so it loads every session — the template ends with `@docs/agentile/brief.md` (rewrite this path to the configured Agentile directory if it differs from `docs/agentile/`).

**Team mode: do not copy the template verbatim.** It describes the `local` store's file layout (`docs/agentile/inbox.md`, specs renamed to `specs/NNNN-<slug>.md`, shipped/abandoned specs moved into `specs/done/`/`specs/abandoned/`) — every one of those sentences is wrong for a project whose Inbox and specs live in Airtable. Adapt the "Where things live" bullets and the prioritise/ship/abandon lines in "How to work" to describe the actual store instead: the Inbox and Specs tables it's in, that rank is a field (not a filename prefix) and shipped/abandoned are status values (not directory moves), and that `plan.md`/supporting files still live at `<dir>/specs/<slug>/` in this repo either way. Keep the rest of the template (capture, shape, plan, loop, gates, rules) unchanged — it's already store-agnostic.

## Step 6 — Hooks

There is nothing to wire per-project. The plugin's hooks (`hooks/hooks.json`) register automatically whenever the plugin is enabled — they merge in without any edit to the project's `.claude/settings.json`. The only project-level control is `.agentile/gates.json`: the hooks read it and no-op while its commands are blank, then enforce the gates once commands are filled in. Confirm the plugin is enabled rather than duplicating the hook registration.

## Step 7 — Readiness report (observations, not blockers)

The methodology's precondition is "first be agile, then agentic" — a working
trunk, gates, and tests. Check and report, without blocking:

- **Tests** — does `gates.json` have a `test` command? Does the repo have a test directory/framework?
- **CI** — is there a CI config (`.github/workflows/`, etc.)?
- **Trunk** — is there a default branch the team integrates to? Any long-lived divergent branches?
- **Store** — Solo or Team? If Team, did `doctor` in Step 2b come back all-green?

Phrase each as an observation ("No test command configured — the test-gate hook
will no-op until one exists"), so an unhealthy loop is visible rather than
silently amplified.

## Step 8 — Report

Summarise what was created versus skipped, then point the user at the next move:

> Agentile is initialised (backlog store: **<Solo/local — or — Team/airtable>**). Capture ideas with `/ag-capture`, review them with `/ag-inbox`, and shape one into a spec with `/ag-shape`. Tailor what "Ready" means by editing `.agentile/shape.md`. To configure how any loop stage runs in this project, use `/ag-customise <stage>`; see `.agentile/playbooks.md` for the full directive contract. Switch the backlog store later with `/ag-customise store`. Run the loop with `/ag-loop` (drains the backlog); `/loop /ag-loop` to also watch for new work.
