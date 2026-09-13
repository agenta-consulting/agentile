# Changelog

Every change to the plugin bumps the version in `.claude-plugin/plugin.json`
(and the matching marketplace entry) **in the same commit**, and adds a line
here. See the Versioning section in [README.md](./README.md) for why.

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
