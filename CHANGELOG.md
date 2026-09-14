# Changelog

Every change to the plugin bumps the version in `.claude-plugin/plugin.json`
(and the matching marketplace entry) **in the same commit**, and adds a line
here. See the Versioning section in [README.md](./README.md) for why.

## 0.12.0 — 2026-09-14

- **`/ag-plan` writes a read-only `SPEC.md` snapshot** beside `plan.md` on
  stores with no filesystem spec (`airtable`). The spec directory previously
  held a plan for a spec that could not be read without a network call and a
  token, so the builder, the reviewer and the pull request saw the approach but
  not the acceptance criteria the diff has to satisfy. The store stays
  canonical: the snapshot is stamped with the record id and read time, and
  state (status, rank, claim) is never read from it.

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
