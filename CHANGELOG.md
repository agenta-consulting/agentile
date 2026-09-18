# Changelog

Every change to the plugin bumps the version in `.claude-plugin/plugin.json`
(and the matching marketplace entry) **in the same commit**, and adds a line
here. See the Versioning section in [README.md](./README.md) for why.

## 0.18.0 — 2026-09-18

- **Inbox and Specs both get an `Attachments` field** (Airtable's native
  `multipleAttachments` type) for dragging in supporting files — screenshots,
  docs — directly in the Airtable UI. No `ag-store` CLI or skill wiring: it's
  human-driven only, not surfaced in `spec_read`/`inbox_list` output or
  written by any skill. `provision` adds it to existing bases; `doctor`
  reports the gap until it does.

## 0.17.0 — 2026-09-18

- **Specs now remember which Inbox stub they came from.** A new `Source Inbox
  Item` link on Specs (reciprocal `Specs` on Inbox, auto-maintained by
  Airtable) records provenance — one stub can link to several specs, since
  `/ag-shape`'s "Split" case can turn one stub into more than one. Written by
  `/ag-shape` on every spec it creates via a new `source_inbox` frontmatter
  key; `ag-store spec_create`/`spec_write` resolve it the same way as
  `captured_by`/`shaped_by` (a raw record id, no lookup). `spec_read` shows
  it back as the stub's Title, for readability. `provision` adds the field to
  existing bases; `doctor` reports the gap until it does.

## 0.16.1 — 2026-09-16

- `doctor` reports a **stale select**: a choice added to `schema.rb` after a base
  was provisioned. Found the hard way — writing `Runs.Event: closed` to the live
  base failed with a 422 because `provision` adds missing *fields* but the field
  already existed with an older choice list.
- Airtable has no API for adding a choice to an existing select (both PATCH
  forms are rejected as a type change), so `Runs` and `Checkpoints` writes pass
  `typecast: true` — Airtable then creates the option on first use. `doctor`
  still names the gap, so a base behind the schema is visible rather than
  silently self-healing.

## 0.16.0 — 2026-09-16

- **Run events carry a status.** `Runs` was the only table without one, so
  finished runs accumulated in the same view as live ones. Each event is now
  `active` or `closed`, and `ag-store run_list --status active|closed` filters —
  in Airtable the `Status` field is what a view hides finished runs on.
- **Retiring a run appends, never edits.** `ag-store run_close --spec <slug>
  [--runner <id>]` records a `closed` event; the log stays append-only and every
  row is kept, because the flow metrics are computed from that history. Which
  runs are live is *derived* — a (spec, runner) pair is active until a terminal
  event (`shipped`, `failed`, `deployed`, `closed`) lands for it — so both stores
  answer identically and a stored flag can never go stale against the log.
- `/ag-wip` cross-checks the two: a spec still `in_progress` with no active run
  is a claim whose worker is gone, and it now says so instead of looking busy.
- Log lines written before this release parse unchanged; a missing `status=` is
  inferred from the event.

## 0.15.0 — 2026-09-16

- **Checkpoints and run events move into the store.** Both were repo files, so a
  headless worker that paused wrote its question to an uncommitted file on its
  own machine and printed a path only that machine could act on — which defeats
  the point of a checkpoint, and breaks as soon as two people or two machines are
  involved. They are now store records: new `Checkpoints` and `Runs` tables in
  Airtable, linked to `Specs`. The `local` store keeps files exactly as before,
  so solo mode is unchanged.
- New ops: `checkpoint_open`, `checkpoint_list`, `checkpoint_open_count`,
  `checkpoint_answer`, `run_event`, `run_list`. `/ag-build` calls them instead of
  `bin/ag-checkpoint`, which is deprecated and now only drives the local files.
- **The line is events vs artefacts, not local vs remote.** `plan.md`, the
  `SPEC.md` snapshot, findings, supporting files and ADRs stay in the repo in
  both modes — they are reviewed and amended beside the diff they describe.
- `ag-store flow` takes its human-wait intervals from the store's checkpoints
  rather than the filesystem, so the agent/human split is correct on a machine
  that never ran the build.
- `provision` adds both tables to an existing base; `doctor` reports them.

## 0.14.0 — 2026-09-16

- **Flow metrics: `ag-store flow [<slug>]`.** Reports, per spec,
  `queue_wait_seconds` (created→claim), `cycle_seconds` (claim→ship), and the
  split of that cycle into `agent_seconds` and `human_wait_seconds`, with a
  per-checkpoint breakdown. Every number is derived from timestamps that already
  existed — nothing new is stored. A checkpoint is by definition an interval
  where the loop stopped and waited for a person, so summing
  `answered_at - asked_at` across a spec's checkpoints separates time the agents
  worked from time the work sat waiting on a human. An unanswered checkpoint
  counts its wait up to now, so the split is live for work in flight.
- `/ag-wip` prints the agent/human split for each in-progress spec and names the
  open checkpoint the loop is waiting on. `/ag-retro` reads `flow` instead of
  doing the arithmetic by hand, and distinguishes the three bottlenecks a single
  "lead time" number hides: queue wait, human wait, and agent time.
- **`created` becomes `created_at`, a datetime.** A date could not measure a
  queue wait shorter than a day, which on this loop is most of them. The
  Airtable `Created` date field stays as a read-only fallback for specs written
  before this release; `provision` adds `Created At` to existing bases. Bare
  dates parse as midnight **UTC**, not local, so the same spec yields the same
  numbers on any machine.

## 0.13.1 — 2026-09-16

- Headless workers are told to call `ag-store`, `ag-checkpoint`, `git` and the
  gates by bare name as the first word of their own command — no
  `export PATH=…;` prefix, absolute path, or `;`/`&&` chain — because the
  `--allowedTools` allowlist matches command text as typed, and a first
  denial makes the session deny every later prompt-requiring command. Found
  on a real `/ag-build` run whose ship-approval checkpoint write was denied.
- `bin/ag-run` tolerates a status line wrapped in backticks or bold.

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

## 0.12.1 — 2026-09-14

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
