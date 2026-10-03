<!-- SNAPSHOT — not the source of truth.
     Spec ag-store-sends-run-model read from Agentile Projects at 2026-10-03T05:32:37Z.
     Rank, claim and status live in the store; re-run /ag-plan to refresh.
     Never edit this file: edits are lost, and the store will not see them. -->

---
title: ag-store sends the model when it opens a run
slug: ag-store-sends-run-model
status: in_progress
type: feature
route: background
business_value: medium
technical_certainty: high
rank: 3
created_at: 2026-09-30T09:54:37Z
tags: [ag-store, runs]
outcome: A run opened by /ag-build after this ships shows its model (not "unknown") in the Agentile Projects LLM-time-per-model chart
claimed_by: factory-next/agentile/ag-store-sends-run-model
label: factory-next
claimed_at: 2026-10-03T05:31:53Z
claimed_by_member: keith@keithrowell.com
shaped_by: [keith@keithrowell.com]
source_inbox: Plugin sends model on run_start
---

# ag-store sends the model when it opens a run

## Problem / why now

Agentile Projects now has an LLM-time-per-model chart (`Projects::Trends#agent_hours_by_model`). It groups runs by `runs.model` and puts every run with no model under "unknown". The app already accepts `model` on `POST /projects/:slug/specs/claim` (it passes it to `Specs::Claim` and then `Runs::Start`) and on `POST /projects/:slug/runs`. The plugin never sends it, so every run is "unknown" and the chart is empty.

The stub said "run_start", but since 0.20.0 there is no run_start op. `ag-store claim` opens the run on the server, and `ensure_run` (used by `run_event` and `checkpoint_open`) creates one with `POST /runs` only when no active run exists. Those are the two places to send the model.

## Acceptance criteria

- [ ] `ag-store claim <identity> [label] [wip] [--spec <slug>] [--model <id>]` sends `model` in the `POST /specs/claim` body.
- [ ] `ag-store run_event` and `ag-store checkpoint_open` accept `--model <id>`. When `ensure_run` has to create a run, the `POST /runs` body carries `model`. When an active run already exists, nothing about the model is sent (no retroactive update).
- [ ] When `--model` is absent, ag-store falls back to the `AGENTILE_MODEL` environment variable. When both are absent or blank, the `model` key is omitted from the body entirely, not sent as `""` or `null`.
- [ ] The model string is sent exactly as given (e.g. `claude-opus-5-5` or `sonnet`). ag-store does not normalise aliases.
- [ ] The usage header comment in `bin/ag-store` documents `--model` on claim/run_event/checkpoint_open and the `AGENTILE_MODEL` fallback.
- [ ] `skills/ag-build/SKILL.md` Step 1 claim commands pass `--model "<your model id>"`, where the session uses its own exact model id (e.g. `claude-opus-5-5`, from its system context). If `AGENTILE_MODEL` is set, the skill leaves it to the env var.
- [ ] `dev/test-ag-store-http.rb` covers: the flag is sent on claim; the env fallback on claim; omission when neither is set; the model is sent on the `POST /runs` created by `ensure_run`; nothing is sent when a run already exists.
- [ ] CHANGELOG entry.

## Scope boundary

**In scope:** `bin/ag-store` (claim, ensure_run and its callers, the usage comment), the /ag-build claim instructions, tests and the CHANGELOG.

**Out of scope:** - The Agentile Factory. Its daemon claims before it resolves the model, so it needs its own change: resolve the model first, then pass `--model` or set `AGENTILE_MODEL`. That is captured as a separate stub.
- `bin/ag-run`. It passes claude flags through verbatim. Users can set `AGENTILE_MODEL` themselves; parsing `--model` out of the pass-through args is not part of this spec.
- Any app change. The app already accepts `model`.
- Updating the model on an existing run, or recording a model change mid-run.
- Normalising model aliases (`sonnet`) to full ids.

## Edge cases and failure paths

- The session does not know its model id: the skill omits `--model` and the run stays "unknown", as it is today. This must never block a claim.
- `AGENTILE_MODEL` is set but empty: treat it as absent.
- A claim result that is not a slug (WIP_FULL, NONE, etc.): no run is opened and the model is irrelevant. Behaviour is unchanged.
- An older app that ignores an unknown `model` param: this is harmless (Rails permits extra params here). No version check.

## Affected areas

- `bin/ag-store`: the `claim` branch of `Ops#run`, `ensure_run`, the `run_event` and `checkpoint_open` callers, and the header usage comment
- `skills/ag-build/SKILL.md`: Step 1 claim commands (around lines 93-102)
- `dev/test-ag-store-http.rb`
- `CHANGELOG.md`
- App reference (read-only): `agentile_projects/app/controllers/api/v1/specs_controller.rb#claim` and `runs_controller.rb`

## Open questions

None.

## Verification

`ruby dev/test-ag-store-http.rb` passes with the new cases. Then do a manual check: run `/ag-build` against a spec in Agentile Projects, and the new run's `model` (from `ag-store run_list --spec <slug>`) is the session's model id. The run also appears under that model in the LLM-time-per-model chart.
