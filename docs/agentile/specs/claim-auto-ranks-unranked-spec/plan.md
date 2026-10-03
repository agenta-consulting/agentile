# Plan: Targeted claim ranks an unranked spec, and rank accepts in_progress specs

Written by the plan stage into the spec's directory as `plan.md`. Review and
amend this file directly. The build stage follows what it says.

> **Which repo this lands in.** The spec lives in the `agentile` project's
> backlog, but **every code change lands in the Agentile Projects web app repo,
> `/home/keith/projects/agentile_projects`**. `Specs::Claim`, `Specs::Rank` and
> the API controller are there. Nothing changes in `/home/keith/projects/agentile`.
> `bin/ag-store` is a thin HTTP client and the spec rules out any change to it.
> This repo's `.agentile/gates.json` is empty, so the gates to run are the ones in
> `/home/keith/projects/agentile_projects/.agentile/gates.json`. Branch and
> worktree in `agentile_projects` and merge to its `main`. Only this plan and the
> `SPEC.md` snapshot live in `agentile`.

## Files to touch

All paths below are relative to `/home/keith/projects/agentile_projects`.

- `app/services/specs/claim.rb`: auto-rank on a targeted claim that succeeds.
- `app/services/specs/rank.rb`: accept `ready` and `in_progress` specs, reject
  `shipped`/`abandoned` with a message that names the bad status, and renumber
  across all open specs.
- `app/controllers/api/v1/specs_controller.rb`: change the `rank` action (line ~63)
  so the `ranked` response lists open specs, not only ready ones.
- `test/services/specs/claim_test.rb`: new failing tests (see the test strategy).
- `test/services/specs/rank_test.rb`: new failing tests, plus updates to the
  existing tests whose expectations this change alters (details below).
- `test/integration/api/specs_test.rb`: the test "rank of a non-ready spec is 409"
  (line ~143) currently uses `in-progress-spec`. Repoint it to `shipped-one`, and
  add a test that `in-progress-spec` ranks with a 200 response.

No changes to the model, migration, fixtures, `bin/ag-store`, the web rank page
(`app/matestack/web/pages/projects/rank.rb`) or `FactoryPush`.

## Approach

**Reuse `Spec.active`** (`app/models/spec.rb:43`, `where(status: %w[ready in_progress])`)
as the definition of "open" everywhere below. Do not add a new constant or scope.

### 1. `Specs::Claim`: auto-rank inside the claim transaction

In `attempt`, after `updated = claim_row(chosen, now)` and **after** the
`next Result.new(result: "RETRY") if updated.zero?` guard, and before
`chosen.reload`, add:

```ruby
auto_rank(chosen, now) if @slug && chosen.rank.nil?
```

Then add a private method:

```ruby
# A targeted claim can take an unranked spec; leave it ranked so it stays in
# rank-filtered views. One past the highest open rank; gaps are fine.
def auto_rank(spec, now)
  top = @project.specs.active.maximum(:rank).to_i
  Spec.where(id: spec.id).update_all(rank: top + 1, updated_at: now)
end
```

Why it is shaped this way:
- It sits after the zero-rows guard, inside the same `Spec.transaction`
  (BEGIN IMMEDIATE). A RETRY or TAKEN outcome therefore writes no rank. Two
  concurrent targeted claims are serialised by the write lock, so each one reads
  the other's committed max and they get different ranks.
- `chosen.rank` is the value loaded before the claim. `claim_row` does not touch
  `rank`, so the check is accurate. `chosen.reload` already follows, so `r.spec`
  carries the new rank and `FactoryPush.spec_changed(chosen)` pushes it.
- `maximum(:rank).to_i` treats "no ranked open specs" as 0, so the new rank is 1.
  The fixture `tek_in_progress` has rank 0, which also gives max 0 and rank 1.
- Limiting it to `@slug` makes queue claims provably untouched (`from_queue`
  only returns ranked specs anyway). `Result`, `Runs::Start` and `SanityJob`
  are unchanged.

### 2. `Specs::Rank`: open specs, not just ready ones

```ruby
bad = listed.reject { |s| s.ready? || s.in_progress? }
raise ApiError::Conflict, "cannot rank closed specs: #{bad.map { |s| "#{s.slug} (#{s.status})" }.join(', ')}" if bad.any?
rest = @project.specs.active.where.not(id: listed.map(&:id)).where.not(rank: nil).ranked.to_a
```

Leave the rest as it is: dense renumbering from 1, `update_columns`, and
`FactoryPush.specs_changed`. The message no longer says "not ready". It names
each bad slug and its status, as the acceptance criteria require.

### 3. `Api::V1::SpecsController#rank`

Change the response to:
`render json: { ranked: current_project.specs.active.where.not(rank: nil).ranked.pluck(:slug) }`.
`ApiError::Conflict` is already mapped to 409 for the API (the existing 409 test
passes today). Leave the web `Projects::SpecsController#rank` as it is: it
already rescues the conflict and returns 422 with the message.

## Test strategy

Gates come from `/home/keith/projects/agentile_projects/.agentile/gates.json`.
Run them from that repo:
- test: `ag-lock storage/.test.lock 'bin/rails db:test:prepare test'`
- lint: `bin/rubocop` (`bin/rubocop -A` to format)
- build: `npm run build && npm run build:css`. No asset changes are expected,
  but run it anyway as the standard gate.

Write the tests first and confirm they fail before the fix. To iterate on single
files, use `bin/rails test test/services/specs/claim_test.rb test/services/specs/rank_test.rb test/integration/api/specs_test.rb`.

**`claim_test.rb`** (non-transactional, so fixtures reload per test and a
written rank does not leak). The fixture `tek_unranked` (slug `unranked`) is
ready, unranked and unblocked.
- A targeted claim of `unranked` returns `"unranked"`, leaves the spec
  `in_progress` with `rank == 5` (open max is `tek_dependent` at 4), and has a
  run. To avoid coupling to fixture values, assert
  `rank == @project.specs.active.where.not(id: spec.id).maximum(:rank) + 1`,
  computed before the claim.
- A targeted claim of an already-ranked spec (`ready-b`, rank 2) keeps rank 2.
- With no ranked open specs (first `update_all(rank: nil)` on the project's
  active specs), a targeted claim of `unranked` ends with rank 1.
- A losing targeted claim writes no rank. Override `claim_row` with `define_singleton_method(:claim_row) { |*, **| 0 }` (Minitest 6 has no `stub`), using
  the same pattern as the existing "TAKEN when both the pick and its retry lose"
  test. Assert the result is `"TAKEN"` and `specs(:tek_unranked).reload.rank` is nil.
- The existing "UNPRIORITISED when only unranked ready specs remain" test must
  still pass unchanged. It covers the queue-unchanged criterion.

**`rank_test.rb`**
- New: ranking `%w[in-progress-spec]` succeeds and gives it rank 1.
- New: `%w[shipped-one]` raises `ApiError::Conflict`, and the message includes
  `"shipped"`. Do the same for `abandoned-one`.
- Update "refuses a non-ready slug". It currently passes `in-progress-spec`,
  which becomes legal. Point it at `shipped-one`, which merges into the test above.
- Update "writes dense ranks ... pushes unlisted ready specs after". `rest` now
  includes `tek_in_progress` (rank 0, sorts first), so the expected order for
  slugs `[blocked, ready-b]` becomes: blocked 1, ready-b 2, in-progress-spec 3,
  ready-a 4, dependent 5, unranked nil. Rename the test to say "open".
- Update "a duplicated slug ..." for the same reason: ready-b 1, blocked 2,
  in-progress-spec 3, ready-a 4, dependent 5.

**`test/integration/api/specs_test.rb`**
- "rank of a non-ready spec is 409": change the slug to `shipped-one`, still 409.
- New: `PUT /specs/rank` with `%w[in-progress-spec]` returns 200, and
  `ranked` includes `in-progress-spec`.

**Manual check from the spec:** after deploy, run a targeted claim of an unranked
spec, then `ag-store spec_list --status in_progress` shows a rank.

## Risks and unknowns

- **Web rank page side effect (accepted, out of scope).**
  `app/matestack/web/pages/projects/rank.rb` lists and submits only ready specs.
  After this change, each save from that page renumbers ranked in_progress specs
  *after* every ready spec (they fall into `rest`). Claimability is unaffected,
  because in_progress specs are not claimable, but in_progress ranks will shift
  on each web re-rank. The spec puts the rank page out of scope. Flag this for
  the reviewer and raise a follow-up stub if it matters.
- **Other callers expecting "ready-only" ranks.** The dashboard's up-next list
  and the queue claim filter by `status: ready` themselves, so a ranked
  in_progress spec does not leak into them. Before merging, grep for `.rank`
  consumers that assume uniqueness among ready specs only. A quick read found none.
- **Integration test for the web rank endpoint**: none exists for 409/422 on
  in_progress. If the builder finds one, update it the same way.
- **Concurrency**: correctness depends on the existing BEGIN IMMEDIATE behaviour
  documented in `claim.rb`. No new locking is needed. The existing "two
  concurrent claims" test pattern could be extended to two targeted unranked
  claims, but the only fixture that is unranked, ready and unblocked is
  `unranked`. Create a second spec in the test if this is extended. This is
  optional.
- **Gap growth**: repeated auto-ranks after ships leave gaps. The spec says gaps
  are acceptable, and `/ag-prioritise` renumbers densely.

## ADR

None. This is a bug fix inside existing service boundaries and is easy to reverse.
