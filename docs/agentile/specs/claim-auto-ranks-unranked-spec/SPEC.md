<!-- SNAPSHOT — not the source of truth.
     Spec claim-auto-ranks-unranked-spec read from Agentile Projects at 2026-10-03T05:24:57Z.
     Rank, claim and status live in the store; re-run /ag-plan to refresh.
     Never edit this file: edits are lost, and the store will not see them. -->

---
title: Targeted claim ranks an unranked spec, and rank accepts in_progress specs
slug: claim-auto-ranks-unranked-spec
status: in_progress
type: bug
route: background
rank: 2
created_at: 2026-09-30T22:38:14Z
tags: [claim, rank, store-api]
outcome: A targeted claim of an unranked spec leaves it in_progress with a rank, and PUT /specs/rank accepts in_progress specs, both proven by service tests
claimed_by: factory-next/agentile/claim-auto-ranks-unranked-spec
label: factory-next
claimed_at: 2026-10-03T05:23:56Z
claimed_by_member: keith@keithrowell.com
shaped_by: [keith@keithrowell.com]
source_inbox: Warn when a targeted claim takes an unranked spec
---

# Targeted claim ranks an unranked spec, and rank accepts in_progress specs

## Problem / why now

A targeted claim (`/ag-build <slug>`, `ag-store claim --spec <slug>`) takes an unranked spec without saying anything. The spec goes `in_progress` with `rank: nil` and drops out of the rank-filtered views. It can't be repaired afterwards either: `Specs::Rank` rejects any spec that is not `ready` (409 "not ready"). Seen in the tekmor ground-truth-scorer build, 2026-09-24.

**Repro:** shape a spec and don't rank it, then run `ag-store claim <id> "" --spec <slug>`. Result: the slug is returned, the spec is in_progress with no rank, and `ag-store rank <slug>` fails with 409 "not ready".

**Expected:** the claim leaves the spec ranked, and rank works on claimed specs.

## Acceptance criteria

- [ ] A targeted claim of an unranked, unblocked, ready spec succeeds and, in the same transaction, sets its rank to one past the highest rank among the project's open (ready + in_progress) specs. The claim result and the run are unchanged.
- [ ] A targeted claim of an already-ranked spec leaves its rank alone.
- [ ] Queue claims (no slug) are unchanged. They only pick ranked specs, and UNPRIORITISED still fires when nothing is ranked.
- [ ] `Specs::Rank` / `PUT /specs/rank` accepts `ready` and `in_progress` specs. It rejects `shipped`/`abandoned` specs with 409 (the message changes from "not ready" to name the bad status).
- [ ] Ranking renumbers the listed specs followed by the remaining ranked **open** (ready + in_progress) specs, densely from 1. The endpoint's `ranked` response lists open specs.
- [ ] Failing tests are written first: `test/services/specs/claim_test.rb` (targeted claim of an unranked spec ends ranked) and `test/services/specs/rank_test.rb` (ranking an in_progress spec succeeds; shipped still 409). Both go green with the fix.

## Scope boundary

**In scope:** `Specs::Claim#targeted`/`claim_row` path, `Specs::Rank`, `Api::V1::SpecsController#rank` response.

**Out of scope:** the web rank page/rank editor UI (whether it shows in_progress rows), the dashboard's up-next list (still ready-only), any ag-store CLI change, and warning text in `/ag-build`.

## Edge cases and failure paths

- A claim that loses the race (RETRY/TAKEN) must not leave a rank written. Assign the rank only after the conditional update succeeds, inside the same transaction.
- With no ranked open specs, the auto-rank is 1.
- Ranks can have gaps after ship or abandon. "One past the max" is enough and needs no renumbering on claim.
- Two concurrent targeted claims of different unranked specs are serialised by BEGIN IMMEDIATE, so they get distinct ranks.

## Affected areas

In the agentile_projects repo: `app/services/specs/claim.rb`, `app/services/specs/rank.rb`, `app/controllers/api/v1/specs_controller.rb` (rank action), `test/services/specs/claim_test.rb`, `test/services/specs/rank_test.rb`, and the API controller test for rank if one exists. `Specs::Rank` also calls `FactoryPush.specs_changed`, which should need no change.

## Open questions

None.

## Verification

The two new service tests fail before the fix and pass after, and the full suite stays green. Manual check: a targeted claim of an unranked spec shows a rank in `ag-store spec_list --status in_progress`.
