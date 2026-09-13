---
name: ag-new-project
description: Start a brand-new project on Agentile — interview the user for a project brief and stack, write the brief, a stack ADR and a starter CLAUDE.md, run the ag-init scaffold with gates pre-filled from the stack, then offer stage customisations and first inbox stubs. For fresh directories only; use /ag-init on an existing codebase. Trigger phrases include "/ag-new-project", "start a new project", "new Agentile project", "bootstrap a project with Agentile".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit, Skill
disable-model-invocation: true
---

# ag-new-project

Take an empty (or nearly empty) directory from "I have an idea" to "the loop can
run": a written brief, a recorded stack decision, standing context for every
session, deterministic gates, and an inbox with something in it. This is the
front door for a **fresh** project; `/ag-init` remains the tool for adding
Agentile to code that already exists.

The methodology's thesis is that as building becomes automatic, what you *ask
for* matters most — so this skill spends its questions on the brief and the
constraints, and derives the mechanical parts (gates, CLAUDE.md, ADR) from those
answers rather than asking for them cold.

This skill **never overwrites** an existing file. It does **not** run any
framework generator (`rails new`, `npm create vite`, `cargo init`, …) — the
user scaffolds code with the stack's own tool, before or after this runs.

## Step 0 — Preflight

1. Resolve the plugin's skills root: `${CLAUDE_SKILL_DIR}/..` (fallback
   `"${CLAUDE_PLUGIN_ROOT}/skills"`). You will read sibling skills from here.
2. Check the directory is fresh: no `.agentile/` and no substantial source tree
   (a handful of files — README, LICENSE, `.gitignore`, a generator's skeleton —
   is fine). If `.agentile/` already exists, stop: tell the user Agentile is
   already initialised here and point them at `/ag-init` (idempotent, safe to
   re-run) and `/ag-customise <stage>`. If there is a real codebase but no
   `.agentile/`, say this looks like an existing project and offer `/ag-init`
   instead; continue only if the user insists.
3. If `git rev-parse --show-toplevel` is not this directory — there is no
   repository, or the directory sits inside a larger one such as a dotfiles
   checkout — run `git init` here (default branch as the user's git config
   dictates) and say so. A new project is its own repository. Do not create a
   commit.

## Step 1 — Brief interview

Read `${CLAUDE_SKILL_DIR}/../../templates/agentile/brief-template.md` for the
sections to fill. Ask **one or two questions per message**, using
`AskUserQuestion` where the choices are discrete and plain prompts where they
are open-ended. Cover, in order:

1. **Name and pitch** — the project name (also used for the directory name in
   the CLAUDE.md head) and a one-paragraph description of what it is.
2. **Who it's for** — the user or customer; who feels the pain this removes.
3. **The outcome that matters first** — one thing, stated observably. This is
   the yardstick Business Value is scored against in `/ag-shape` and
   `/ag-prioritise`.
4. **The next two or three outcomes**, in priority order.
5. **Non-goals** — what the project explicitly will not do.
6. **What "shipped v1" looks like** — the first releasable slice, concretely.

Constraints are gathered in Step 2 (the stack *is* most of them). Keep the
answers short: the brief loads into context every session.

The interview is decline-able. If the user wants to skip it, write the brief
as the bare template and say every `<…>` placeholder is theirs to fill.

## Step 2 — Stack interview

Ask, one or two at a time, with `AskUserQuestion` offering the common answers
plus "Other":

1. **Language / runtime** (e.g. Ruby, TypeScript/Node, Python, Go, Rust, Elixir).
2. **Framework** appropriate to that language (e.g. Rails, Sinatra; Next.js,
   SvelteKit, Express; Django, FastAPI; none).
3. **Package / build tool** if not implied (npm / pnpm / bun; pip / uv / poetry;
   bundler; cargo; mix).
4. **Test framework** (Minitest / RSpec; Vitest / Jest; pytest; `go test`;
   `cargo test`).
5. **Lint and format** (RuboCop; ESLint + Prettier; Biome; Ruff; gofmt; rustfmt/clippy).
6. **Deploy target** (Kamal, Fly.io, Vercel, Docker/Compose, a plain server,
   none yet).
7. **Other hard constraints** — platform, timeline, compliance, budget, a
   database or hosting decision already made. Free text; may be empty.

From the answers, derive a **proposed gates map**: the `format`, `lint`,
`test`, `build`, and `deploy` commands the stack conventionally uses. Examples
(adapt, do not copy blindly):

| Stack | format | lint | test | build | deploy |
|---|---|---|---|---|---|
| Rails + Minitest + RuboCop | `bundle exec rubocop -a {file}` | `bundle exec rubocop` | `bin/rails test` | *(blank)* | `bin/kamal deploy` |
| Node + Vitest + ESLint + Prettier | `npx prettier --write {file}` | `npx eslint .` | `npm test` | `npm run build` | *(blank)* |
| Python + pytest + Ruff | `ruff format {file}` | `ruff check .` | `pytest` | *(blank)* | *(blank)* |
| Go | `gofmt -w {file}` | `go vet ./...` | `go test ./...` | `go build ./...` | *(blank)* |
| Rust | `rustfmt {file}` | `cargo clippy -- -D warnings` | `cargo test` | `cargo build` | *(blank)* |

Leave a gate blank when the stack has no obvious command for it. `{file}` in
`format` is substituted with the edited path by the format-on-edit hook.

## Step 3 — Write the brief and the stack ADR

1. Resolve the Agentile directory: it is `docs/agentile/` for a fresh project
   (the config template's default). Create it.
2. Write `docs/agentile/brief.md` from the brief template, replacing every
   `<…>` placeholder with the interview answers. The **Constraints** section is
   the stack summary plus any hard constraints from Step 2.
3. Write `docs/adr/0001-<stack-slug>.md` from
   `${CLAUDE_SKILL_DIR}/../../templates/agentile/adr-template.md` (e.g.
   `0001-rails-minitest-kamal.md`): `status: accepted`, today's date
   (`date +%Y-%m-%d`), context = the project's constraints and the options
   considered (ask if the user weighed alternatives; otherwise note the choice
   was the team's default), decision = the stack, consequences = what it
   commits the project to. Keep every frontmatter value valid YAML — no
   unquoted colons in `title`. Number `0000` is reserved for the
   record-architecture-decisions ADR that init writes in Step 5.

## Step 4 — Starter CLAUDE.md

There is no codebase for `/init` to read, so write the standing context from
the interview. If `CLAUDE.md` already exists, leave it (init will append the
Agentile section). Otherwise write a short head:

```
# <Project name>

<One-paragraph pitch.>

## Stack

<Language, framework, package manager, test framework, lint/format, deploy — one line each.>

## Commands

- Test: `<test command>`
- Lint: `<lint command>`
- Format: `<format command>`
- Build: `<build command>`   (omit blank ones)

## Conventions

<Anything the user stated: style, structure, constraints. Omit the section if empty.>
```

Do not add the Agentile section yourself — Step 5 does.

## Step 5 — Run the ag-init scaffold

Read `${CLAUDE_SKILL_DIR}/../ag-init/SKILL.md` and execute its procedure with
these adjustments:

- **Skip its Step 2a** (brief) — the brief is already written.
- **Skip its Step 3** (legacy migration) — there is nothing to migrate.
- **Its Step 2 (gates)** becomes a confirm-or-edit: present the proposed gates
  map from Step 2 above and ask the user to accept it or amend any command,
  then ask for protected branches (default `main`, `master`). Write the result
  into `.agentile/gates.json`.
- Run its **Steps 1, 4, 5, 6 and 7** as written (templates, scaffold — which
  will skip the brief because it now exists — standing context appended to the
  CLAUDE.md head from Step 4, hooks note, readiness report). Hold its Step 8
  report until the end of this skill.

## Step 6 — Customisations

Do not ask the user to pick stages from a list — derive the customisations
from what the interview already told you, then confirm the set in one
question.

1. **Ask one question: how much should the loop pause for a human?**
   (`AskUserQuestion`): *no human gates at all* / *only before ship* /
   *baseline* (pause at plan for foreground and spike specs, and before ship).
   Write the answer into `.agentile/loop.md` (`pause_at_plan`,
   `pause_before_ship`; with no gates, raise `verify_retry_limit` to 2 and add
   a prose section saying what replaces the human read). This is the one
   customisation every project needs decided.
2. **Derive the playbooks** from the answers so far and write them directly:
   - `build.md` — the conventions the stack implies (where logic versus UI
     lives, test-per-module, vendoring/dependency rules, how to run the gates,
     branch-per-spec), plus any constraint from Step 2 the builder must honour.
   - `verify.md` — a Definition of Done the reviewer can check without a
     person: gates green, spec met and nothing more, each hard constraint as a
     concrete check (a grep, a launch, a fixture to inspect), a security skim
     for any untrusted input the brief mentions. Make this strict when there
     are no human gates: the reviewer is then the last read before merge.
   - `ship.md` — only when there is no pause before ship: how a branch reaches
     trunk unattended, the deploy gate to run, and the revert rule if trunk
     stops working.
   - `shape.md` house additions — the questions this project's specs must
     answer: the constraints from Step 2 turned into questions, a
     reviewer-checkable acceptance rule when there are no human gates, and a
     rollback question when ship is unattended.
   The default is Agentile's baseline (pause at plan for foreground and spike
   specs, pause before ship). Only remove pauses, or write an unattended
   `ship.md`, when the user explicitly chose fewer gates in item 1.
3. **Confirm in one message**: list each file and the one-line policy it
   carries; apply any corrections. Tell the user `/ag-customise <stage>` can
   revise any of them later.

## Step 7 — Seed the inbox (optional)

Offer to turn the "shipped v1" answer into the first inbox stubs: propose two
to five one-line stubs that together make up the v1 slice, let the user edit
or decline, then invoke the `ag-capture` skill once per accepted stub. Decline
means the inbox stays as the template.

## Step 8 — Report

List what was created (brief, ADR, CLAUDE.md, `.agentile/` files, gates,
playbooks, stubs) and what was skipped and why, then the readiness
observations from init, then the next move:

> The project is set up. Shape a stub into a spec with `/ag-shape`, order the
> queue with `/ag-prioritise`, and run the loop with `/ag-loop`
> (`/loop /ag-loop` to keep it running). Scaffold the codebase with your
> stack's generator whenever you like — the gates will start enforcing as
> soon as the commands in `.agentile/gates.json` can run.

Remind the user that nothing has been committed: suggest a first commit once
they have scaffolded the code.
