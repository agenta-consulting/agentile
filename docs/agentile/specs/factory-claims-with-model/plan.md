# Plan — Factory claims with the worker's model

Written by the plan stage into the spec's directory as `plan.md`. Review and
amend this file directly — the build stage follows what it says.

**All implementation is in `~/lab/agentile_factory`, not this repo.** This repo
only holds the plan and the SPEC snapshot. Build on a short-lived branch in the
factory checkout; it has unrelated uncommitted changes (`Gemfile.lock`,
`README.md`, `test/application_system_test_case.rb`) that are not ours: do not
stage them.

## Files to touch

All paths below are relative to `~/lab/agentile_factory`.

- `app/services/agentile_cli.rb`
  - `#spec_list(status: nil, pool: nil)`: push `--pool <pool>` when given.
    (Verified against the live store: `ag-store spec_list --status shipped`
    returns `[]`, because the default pool is `active`. The shipped set has to
    come from `spec_list --pool done`. The API's `done` pool is `shipped` only.)
  - `#claim(identity:, label: "", spec: nil, model: nil)`: push
    `--model <model>` only when `model.present?`. Keep the comment about sending no
    wip, and add a line saying that a blank model omits the flag.
- `app/services/scheduler.rb`
  - Replace `#next_ready_slug(cli)` with `#next_claimable(cli)`, which returns
    the spec hash, or nil when nothing qualifies (logic below).
  - `#runner_identity(project, slug)`: takes the picked slug instead of the cli.
    It still returns `"factory/#{project.name}/#{slug || 'pending'}"`. Rewrite
    its comment, because the store no longer chooses when a spec qualifies.
  - `#claim(project)`: pick, resolve the model, then make a directed or
    undirected claim (below). Return `[spec, identity, run_id, model]`.
  - `#dispatch_one`: unpack the 4-tuple and pass `model` to `start_worker`.
  - `#start_worker(project, spec, identity, run_id, model)`: use the given model.
    Fall back to `ModelResolver.call` only when it is nil, which happens only on
    the undirected path. Each path resolves once.
- `app/services/worker_command.rb`
  - `#env`: `SCRUBBED_ENV.merge("AGENTILE_RUNNER_ID" => runner_id,
    "AGENTILE_MODEL" => model.presence)`. Using nil, not omitting the key, means a
    blank model *unsets* the variable (`Open3.popen3(env, ...)` in
    `worker_runner.rb:52` treats nil as unset). A daemon-level `AGENTILE_MODEL`
    therefore never leaks into a worker. Update the comment above `#env`.
    `Recovery#spawn!` (`app/services/recovery.rb:192`) already builds
    `WorkerCommand` with `worker.model`, so restarted workers get the same env
    with no change there.
- `app/services/model_resolver.rb`: unchanged.
- `test/support/fake_store.rb`: make the fake behave like the real store for
  the new paths (details under Test strategy).
- `test/services/scheduler_test.rb`, `test/services/agentile_cli_test.rb`,
  `test/services/worker_command_test.rb`: new and adjusted tests.

## Approach

### The pick (`Scheduler#next_claimable`)

This mirrors `agentile_projects/app/services/specs/claim.rb` `#from_queue`
exactly. Put a comment on the method that names that file and method as the
source of truth, and says that a drift between the two means the factory claims
a spec the store would not have chosen first.

```ruby
def next_claimable(cli)
  ready = cli.spec_list(status: "ready").select { |s| s["claimed_by"].blank? }
  ranked = ready.select { |s| s["prefix"].present? }
  deps = ranked.flat_map { |s| Array(s["depends_on"]) }.uniq
  shipped = deps.empty? ? [] : cli.spec_list(pool: "done").map { |s| s["slug"] }
  ranked.select { |s| (Array(s["depends_on"]) - shipped).empty? }
        .min_by { |s| [s["prefix"], s["slug"].to_s] }
end
```

- `prefix` is the rank in `spec_list` output (as in the existing code).
- The shipped list is fetched only when some ranked candidate has a
  dependency. Most ticks therefore make no extra store call.
- A `depends_on` slug missing from the shipped set counts as unshipped, so the
  spec is skipped. This covers abandoned and unknown dependencies, as the spec
  requires.

### The claim (`Scheduler#claim`)

```ruby
cli = cli_for(project)
pick = next_claimable(cli)
identity = runner_identity(project, pick&.dig("slug"))
if pick
  model = ModelResolver.call(spec: pick, project: project).presence
  result = cli.claim(identity: identity, label: CLAIM_LABEL, spec: pick["slug"], model: model)
else
  model = nil
  result = cli.claim(identity: identity, label: CLAIM_LABEL)   # unchanged: store records NONE/UNPRIORITISED/BLOCKED/WIP_FULL
end
record_claim(project, result)
return nil if CLAIM_SENTINELS.include?(result)
... claimed_spec / NO_SPEC handling unchanged ...
[spec, identity, run_id_for(cli, spec["slug"], identity), model]
```

- **Race losers.** A directed claim can answer TAKEN, BLOCKED, NOT_FOUND or
  WIP_FULL. All four are already in `CLAIM_SENTINELS`, so `record_claim`
  stores the result and bumps `@idle`. `claim` returns nil and `dispatch_one`
  returns false. `dispatch!` then drops the project for the rest of the tick
  (`projects -= [project]`), so the same tick never makes an undirected
  fallback claim. The next tick makes a fresh pick. No new code is needed for
  this beyond what is shown above. Add a comment that says so.
- **Older ag-store without `--model`.** It exits non-zero, which raises
  `AgentileCli::Error`. `dispatch_one`'s rescue then records
  `ERROR: ...` through `record_project_error`. That is a loud failure, as
  the spec asks.
- **Model for the worker.** It is the value sent on the claim, resolved from
  the pick. The read-back `claimed_spec` hash carries the same fields, so
  resolving from the pick is equivalent. Resolve it once.
- **Undirected claim that still gets a slug.** This happens when a spec
  became claimable between the list and the claim. `start_worker` resolves the
  model, as it does today, and the run is "unknown". The spec accepts that,
  because it requires the undirected path to stay as it is.

## Test strategy

**Gates.** `.agentile/gates.json` in this repo has every command empty, and
the factory has no `.agentile/gates.json`. The real gate is the factory's own
CI, `config/ci.rb`:

- `cd ~/lab/agentile_factory && bin/rails test` must pass. This is the
  acceptance gate.
- `bin/ci` runs the full pipeline (setup, bundler-audit, tests, seeds). Run it
  before merging if time allows.

**Fake store (`test/support/fake_store.rb`).** It must mirror
`Specs::Claim` for the new paths:

- `summary` adds `"depends_on" => s["depends_on"] || []`.
- `RemoteProject#add_spec` gains `depends_on: []`.
- `spec_list` honours `--pool done` (shipped only). With no `--pool`, the
  behaviour is unchanged, so existing tests are not disturbed.
- `claim` checks WIP first, as now. With `--spec` it follows `#targeted`:
  - missing, shipped or abandoned: NOT_FOUND
  - not ready, or claimed: TAKEN
  - a dependency not shipped: BLOCKED
  - otherwise claim it

  Without `--spec`, add the dependency filter so the undirected claim answers
  BLOCKED like the real store. Record `"model" => flags["model"]` on the
  run it opens.
- Simulating a lost race: `garble_op("claim", stdout: '"TAKEN"')` already
  makes the next claim print that JSON string. A thin `answer_op` alias for
  readability is optional.

**New tests in `scheduler_test.rb`** (the spec's list):

1. The pick skips a spec with an unshipped dependency and takes the next
   eligible one. The worker is on that spec, and the claim call carries
   `--spec <that slug>`.
2. The pick skips unranked and already-claimed specs.
3. The claim args include `--spec <slug> --model <resolved>`. Set up the model
   through a spec `model:` (or a route/default model). Assert that the Worker
   row's `model` equals the `--model` value and that the fake run's `model`
   equals it too. This is the "resolved once, same value" criterion.
4. With no eligible spec (none ranked, or all blocked), the claim call has
   no `--spec` and `last_claim_result` is the store's sentinel
   (UNPRIORITISED / BLOCKED / NONE).
5. TAKEN on a directed claim starts no worker. `last_claim_result` is
   "TAKEN", and there is exactly one claim call for that project in the tick
   (no undirected fallback).

**`agentile_cli_test.rb`.** `claim(model: "x")` adds `--model x`;
`model: nil` and `model: ""` omit it. `spec_list(pool: "done")` passes
`--pool done`.

**`worker_command_test.rb`.** `env["AGENTILE_MODEL"]` equals the model. With a
blank model the key is present and nil (unset).

**Existing test to adjust.** `scheduler_test.rb`, "claim sends no wip, so the
store's own limit governs" (~line 262), asserts the claim args equal exactly
`["claim", id, "factory"]`. With `spec-2` eligible, the claim is now directed.
Change the assertion to:

- the first three elements are `["claim", id, "factory"]`
- no fourth positional (wip) argument, meaning anything after index 2 starts
  with `--`

Keep `WIP_FULL` as the expected result. The fake must check WIP before the
directed path.

**Manual verification.** From the spec: run the factory against a project
with a ranked, ready spec. Then check that `ag-store run_list --spec <slug>`
shows the Worker row's model, and that the chart groups it under that model.

## Risks and unknowns

- **Selection drift.** The pick copies `from_queue`. If the app's rule
  changes, for example deps counted differently or a new eligibility field, the
  factory diverges silently. Mitigation: the source-of-truth comment. A
  divergence only costs order, never correctness, because a directed claim on a
  non-claimable spec gets a sentinel back.
- **Missing dependency rows.** In the app, `depends_on` is a join to existing
  Spec rows, so `spec_list` only ever lists dependency slugs that exist. "A
  slug it cannot find" therefore means abandoned, which is also unshipped in the
  app. The two rules agree.
- **Extra store call.** `spec_list --pool done` runs only when a candidate has
  dependencies. It grows with shipped history, which is acceptable at current
  sizes.
- **Model aliases.** The model is sent verbatim, for example `sonnet` vs a
  full id. That is the shipped `ag-store-sends-run-model` behaviour; the chart
  groups by the string.
- **Which factory.** The latest factory commit renames this app "Old Agentile
  Factory", and a new native factory is being built in `~/lab/factory`. The
  spec explicitly targets `~/lab/agentile_factory`, so this plan does too. If
  the new factory also claims undirected, it needs its own follow-up spec.
  That is not in scope here.
- **Running daemon.** The factory runs as a systemd service from this
  checkout. Merging changes code that the live daemon loads on restart. Restart
  it deliberately after merging; do not restart it mid-build.

### Assumptions (low-stakes, recorded rather than asked)

- `ModelResolver` output is treated with `.presence`, so a blank model means
  no `--model` flag and `AGENTILE_MODEL` unset.
- The undirected-path fallback resolution in `start_worker` stays, so a racing
  undirected success still starts a worker with a model.
- No `CHANGELOG` entry in this repo. The change lives in the factory, which
  has no changelog convention beyond its commits.

## ADR

None needed. This is a local, reversible change to how the factory issues a
claim, and the store's semantics are unchanged.
