# Changelog

Every change to the plugin bumps the version in `.claude-plugin/plugin.json`
(and the matching marketplace entry) **in the same commit**, and adds a line
here. See the Versioning section in [README.md](./README.md) for why.

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
