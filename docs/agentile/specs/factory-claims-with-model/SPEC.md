<!-- SNAPSHOT — not the source of truth.
     Spec factory-claims-with-model read from Agentile Projects at 2026-10-03T06:41:56Z.
     Rank, claim and status live in the store; re-run /ag-plan to refresh.
     Never edit this file: edits are lost, and the store will not see them. -->

---
title: Factory claims with the worker's model
slug: factory-claims-with-model
status: in_progress
depends_on: [ag-store-sends-run-model]
type: feature
route: background
business_value: medium
technical_certainty: high
rank: 4
created_at: 2026-09-30T22:37:43Z
tags: [factory, runs]
outcome: A run the Agentile Factory opens after this ships shows the worker's resolved model (not "unknown") in `ag-store run_list --spec <slug>` and in the Agentile Projects LLM-time-per-model chart
claimed_by: factory-next/agentile/factory-claims-with-model
label: factory-next
claimed_at: 2026-10-03T06:40:40Z
claimed_by_member: keith@keithrowell.com
captured_by: keith@keithrowell.com
shaped_by: [keith@keithrowell.com]
source_inbox: Factory passes the worker's model on claim
---

# Factory claims with the worker's model

## Problem / why now

Agentile Projects' LLM-time-per-model chart groups runs by `runs.model`. `ag-store-sends-run-model` lets `ag-store claim` send `--model` (or `AGENTILE_MODEL`). The Agentile Factory (`~/lab/agentile_factory`) cannot use it as things stand. `Scheduler#claim` runs an undirected `ag-store claim`, and only in `#start_worker` does it resolve the model (`ModelResolver`: spec `model`, then the project's route model, then the default model, all factory-local settings). By then the store has already opened the run with no model. Every factory run shows as "unknown". The factory runs most builds, so the chart stays mostly empty.

The model depends on the spec, and the store picks the spec. The app cannot resolve the model because route and default models live in the factory. So the factory picks the spec itself, resolves the model, and makes a **directed** claim: `claim --spec <slug> --model <m>`.

## Acceptance criteria

- [ ] Before claiming, the Scheduler chooses the slug the store's undirected claim would choose (`Specs::Claim#from_queue`): status `ready`, unclaimed, ranked (`prefix` present), every `depends_on` slug shipped, and the lowest `[rank, slug]`. This replaces `next_ready_slug`, which ignores dependencies today. The runner identity still names that slug.
- [ ] If no spec qualifies, the factory makes no directed claim. It sends the undirected claim as today, so the store's sentinel (NONE / UNPRIORITISED / BLOCKED / WIP_FULL) is still recorded in `last_claim_result` exactly as now.
- [ ] If a spec qualifies, the factory resolves its model with `ModelResolver` and calls `AgentileCli#claim(identity:, label:, spec: slug, model: model)`. That becomes `ag-store claim <identity> factory --spec <slug> --model <model>`. `AgentileCli#claim` gains a `model:` keyword. A blank model omits the flag.
- [ ] The model recorded on the `Worker` row and passed to `WorkerCommand` is the same value sent on the claim. It is resolved once, not twice.
- [ ] The worker's environment (`WorkerCommand#env`) sets `AGENTILE_MODEL` to that model, so a run that `ensure_run` re-opens during the worker's life also carries it.
- [ ] A directed claim that returns TAKEN, BLOCKED or NOT_FOUND (another claimer won the race) is recorded in `last_claim_result` and counts as idle for the tick. It is retried on the next tick with a fresh pick. The factory never falls back to an undirected claim in the same tick, because that could open a run with the wrong model.
- [ ] Tests (factory `test/`): the pick skips a spec with an unshipped dependency and takes the next eligible one; the pick skips unranked and claimed specs; the claim args include `--spec` and `--model`; with no eligible spec the undirected claim and its sentinel still happen; TAKEN on a directed claim starts no worker; the worker env includes `AGENTILE_MODEL`.

## Scope boundary

**In scope:** 

**Out of scope:** 

## Edge cases and failure paths

- **Selection drift.** If the factory's pick ever differs from the store's, the directed claim takes a spec the store would not have picked first. The pick must copy `from_queue` exactly. A comment in the Scheduler points at `Specs::Claim#from_queue` as the source of truth.
- **Dependency status.** `spec_list` returns `depends_on` slugs but not whether they are shipped. The factory needs the shipped set (for example `spec_list` over the full pool, or `--status shipped`). A dependency on a slug it cannot find counts as unshipped, so the spec is skipped.
- **Blank model** (no spec model, no route model, no default): no `--model` and no `AGENTILE_MODEL`. The run is "unknown" as today and the claim is never blocked.
- **Older ag-store without `--model`.** `depends_on` rules this out. If it does happen, the claim fails loudly (an error in `last_claim_result`) and nothing is silently dropped.
- **WIP_FULL on a directed claim**: recorded as today, and the tick idles.

## Affected areas

`~/lab/agentile_factory`:
- `app/services/scheduler.rb`: `#claim`, `#runner_identity`, `#next_ready_slug` (becomes a dependency-aware pick), `#start_worker` (takes the resolved model)
- `app/services/agentile_cli.rb`: `#claim` gains `model:`, and possibly a shipped-specs lookup
- `app/services/worker_command.rb`: `#env` adds `AGENTILE_MODEL`
- `app/services/model_resolver.rb` (unchanged, called earlier)
- `test/` for the above
- Reference (read-only): `agentile_projects/app/services/specs/claim.rb` (`#from_queue`, `#targeted`)

## Open questions

None.

## Verification

The factory test suite passes. Manual check: with the factory running against a project that has a ranked, ready spec, the new run's `model` in `ag-store run_list --spec <slug>` equals the Worker row's model, and the run appears under that model in the LLM-time-per-model chart.
