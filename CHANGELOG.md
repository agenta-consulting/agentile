# Changelog

Every change to the plugin bumps the version in `.claude-plugin/plugin.json`
(and the matching marketplace entry) **in the same commit**, and adds a line
here. See the Versioning section in [README.md](./README.md) for why.

## 0.13.0 — 2026-09-16

- **`/ag-build` replaces `/ag-loop`.** One spec from claim to shipped, then
  stop; no skill iterates any more. `/ag-build <slug>` claims a named spec
  (`ag-store claim --spec`, with `NOT_FOUND` and `TAKEN`). `/ag-loop` stays
  for one release as an alias.
- **Checkpoints.** Every pause writes `specs/NNNN-<slug>/checkpoints/NNN-<reason>.md`
  via the new `bin/ag-checkpoint` (open, list, open_count, answer). The status
  line carries the path: `AG_BUILD: paused <slug> <reason> <path>`. New reason
  `question`: `ag-builder` and `ag-reviewer` may return `BUILD: question` /
  `VERDICT: question` with options and a recommendation. `open` takes `--by
  <who>`, recorded as the `asked_by` frontmatter field and reported by `list`,
  so an answered `question` routes back to whichever of the builder or the
  reviewer asked it.
- **`.agentile/loop.md` retired.** `pause_at_plan` → `human_checkpoint` on
  `plan.md` (new playbook, accepts `route`); `pause_before_ship` →
  `human_checkpoint` on `ship.md` (new playbook); `verify_retry_limit` and
  `stop_on_gate_failure` → `verify.md`. `/ag-version` warns when a project
  still has `loop.md`.
- Spec template gains optional `model:`; `gates.json` gains an optional
  `review` block; `templates/factory-worker.md` is the system prompt for a
  headless factory worker. `bin/ag-run` drives `/ag-build`. Design:
  `docs/agentile-factory.md`.
- **Upgrading with work in flight:** finish or release any spec claimed by a
  `/ag-loop` session before upgrading; a pre-0.13.0 claim resumed by
  `/ag-build` finds no checkpoints and restarts at implement, in a fresh
  worktree.

## 0.12.0 — 2026-09-14

- **Outcomes: the layer above specs.** A flat, ranked list of falsifiable bets
  — claim, measure, stop rule — that specs may optionally `serve`. Nothing
  derivable is stored on one; `ag-store map` computes the grouped view. New
  skills `/ag-outcome` (shape a bet), `/ag-decompose` (propose the stubs that
  would make it true), `/ag-map` (the world at Outcome level). Design, and the
  Jira-epic model it deliberately rejects: `docs/agentile-outcomes.md`.
- Specs gain optional `serves:` and `tags:`; stubs gain an optional `serves`
  hint; `/ag-shape` asks, `/ag-prioritise` ranks Outcomes before specs,
  `/ag-retro` reviews bets against their measures, `/ag-abandon` closes a bet
  and cascades to the work serving it.
- `ag-store brief_sync` regenerates the brief's "Prioritised outcomes" list
  from the store so prose and table cannot drift.
- Airtable: new `Outcomes` table, `Serves Outcome` links on Specs and Inbox,
  `Tags` multiple-select written with `typecast`; `provision` backfills an
  existing base and `doctor` reports the drift.

## 0.11.0 — 2026-09-14

- **The `Stop`/`SubagentStop` test gate is removed.** It ran `gates.json`'s
  `test` command at the end of every assistant turn. `Stop` fires when the
  assistant stops talking, not when work completes, so the full suite ran on
  questions, status reports and refusals — anything that ended a turn. Its one
  escape, a clean `git status --porcelain`, is defeated indefinitely by a single
  untracked file, so in a repo with untracked scratch files the gate never
  short-circuited. On a slow or infrastructure-dependent suite (minutes, Docker)
  that cost minutes per turn and dominated the session.
- **Full tests stay where they already were: `verify` and `ship`.** Both run the
  same `gates.json` command against a spec that claims to be done — the trigger
  that actually means something. The hook was a second, uncoordinated invocation
  of an identical command on a meaningless trigger, and its
  `MAX_CONSECUTIVE_BLOCKS` cap meant it stopped enforcing after five failures
  anyway.
- `hooks/test-gate.rb` and its tests are kept, unwired, for a redesign around a
  separate cheap opt-in command (a `check`/`test_fast` key, defaulting off) and
  an edit-aware trigger rather than the dirty-tree proxy.
- `format-on-edit` (`PostToolUse`) is unchanged and remains the only wired hook.

## 0.10.0 — 2026-09-14

- **Deploy is a stage.** `deploy` was declared in `gates.json`, documented in
  the README and `/ag-init`, and executed by nothing — a dead key. New
  `/ag-deploy` runs the project's pre-deploy checklist (`.agentile/deploy.md`),
  then the deploy gate, then records `event=deployed` with the sha in
  `runs.md`, so the next batch and any rollback are computable.
- **Ship and deploy are no longer conflated.** `methodology.md` said "SHIP —
  merge to trunk, deploy behind a flag, observe", welding a per-spec merge to a
  batched release. They now stand as separate stages with different cadences and
  different gates: fast checks gate a change, slow evidentiary ones gate a
  release. `/ag-loop` ships but never deploys.
- `.agentile/deploy.md` playbook template, defaulting to `human_checkpoint:
  true` — the only stage that does, because a deploy is outward-facing.

## 0.9.5 — 2026-09-14

First pinned version. Everything before this shipped as bare commits, so this
entry covers the state at the time of pinning rather than one change.

- Inbox stubs carry a `Title` — a short label `/ag-capture` derives from the
  stub text — used as the Airtable primary field so a record is nameable.
- Inbox stubs carry a `Type` (`feature`/`bug`/`chore`/`spike`), derived at
  capture. `/ag-shape` branches on it: a bug gets the short repro interview and
  skips Business Value × Technical Certainty scoring, and `/ag-prioritise`
  ranks unscored bugs by how much the defect hurts.
- `ag-store doctor` reports Airtable schema drift by name, and `provision`
  backfills fields a pre-existing base is missing. Adding a field to the schema
  no longer silently does nothing to live bases.
- New `/ag-version` skill: reports the running version, the installed snapshot,
  and whether the source repo is ahead of it.
