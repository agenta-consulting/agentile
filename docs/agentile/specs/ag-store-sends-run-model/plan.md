# Plan — ag-store sends the model when it opens a run

Written by the plan stage into the spec's directory as `plan.md`. Review and
amend this file directly — the build stage follows what it says.

## Files to touch

- `bin/ag-store`
  - New helper on `Ops`, beside `identity`: `model(flag)`. Returns the `--model`
    flag value when it is a non-blank String, else `ENV["AGENTILE_MODEL"]` when
    non-blank, else `nil`. (Guard against `parse_flags` turning a bare
    `--model` with no value into `true`: treat a non-String as absent, so we
    never send `"true"`.) Do not strip/normalise beyond the blank check; send the
    string exactly as given.
  - `claim` branch: after `body[:slug] = ...`, add
    `m = model(flags["model"]); body[:model] = m if m`.
  - `ensure_run(slug, runner, session, model = nil)`: build the `POST /runs`
    body as today and add `model:` only when non-nil (e.g.
    `{ spec:, runner_id:, session_id:, model: }.compact`). The
    `active_run_for` short-circuit stays first, so an existing run sends
    nothing model-related (no PATCH, no retroactive update).
  - `checkpoint_open` and `run_event` callers: pass `model(flags["model"])` as
    the fourth argument. `run_close` is untouched (it never creates a run).
  - Header usage comment: add `[--model <id>]` to the `claim`,
    `checkpoint_open` and `run_event` lines, and one note line: "--model (else
    AGENTILE_MODEL; omitted when both are blank) is sent as `model` when claim
    or ensure_run opens a run; never sent for an existing run; sent verbatim,
    no alias normalisation." Also extend the "Runs belong to a spec" paragraph
    by one clause saying the same.
- `skills/ag-build/SKILL.md` — Step 1 (around lines 139-152): both claim code
  blocks gain `--model "<your model id>"`, plus one sentence: use your own
  exact model id from your system context (e.g. `claude-opus-5-5`); if
  `AGENTILE_MODEL` is set in the environment, omit `--model` and leave it to
  the env var; if you do not know your model id, omit `--model` — never let it
  block the claim.
- `dev/test-ag-store-http.rb`
  - Add `"AGENTILE_MODEL" => nil` to `ISOLATE` so a developer's exported value
    cannot leak into offline assertions (existing exact-body equality checks on
    claim and `POST /runs` would otherwise break).
  - Section 11 (claim): new cases — `--model claude-opus-5-5` puts
    `"model" => "claude-opus-5-5"` in the body; `AGENTILE_MODEL=sonnet` env with
    no flag puts `"model" => "sonnet"` (verbatim, alias untouched); flag wins
    over env; `AGENTILE_MODEL=""` and no flag → body has no `model` key (the
    existing "omits wip and slug" exact-equality assertion already covers the
    neither-set case; keep it and add the empty-env variant).
  - Section 16 (runs): a new spec slug (e.g. `"m"`, with its own
    `/runs/<id>/events` route, or reuse a generic events route) where
    `run_event ... --model claude-opus-5-5` creates the run and the `POST /runs`
    body equals `{spec, runner_id, session_id, model}`; then a second
    `run_event`/`checkpoint_open --model other` against the now-active run
    makes no further `POST /runs` and no request body contains `model`.
    Also one `checkpoint_open --model` case on a fresh spec asserting the
    created run carries `model`, and env fallback via `AGENTILE_MODEL` on
    `ensure_run`. Note the fake `POST /runs` assigns `id => runs.size + 1`, so
    add the needed `/runs/<n>/events` and `/runs/<n>/checkpoints` routes for the
    new ids (or register them by a small loop).
- `CHANGELOG.md` — new `## 0.22.0 — <date>` entry (the Unreleased docs bullet
  moves under it, or stays Unreleased — follow whatever the release commit
  convention is at build time): `ag-store` sends `model` on claim and on the run
  `ensure_run` creates; `--model` / `AGENTILE_MODEL`; `/ag-build` passes its
  model id on claim.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` — bump
  `0.21.0` → `0.22.0` (minor: changes what a skill instructs; README
  Versioning rule, both files must agree).

## Approach

Smallest increment: one resolver (`model(flag)`) and two call sites that open
runs (`claim` body, `ensure_run` POST body), mirroring the existing
`identity(flag)` flag-then-env pattern in `Ops`. Omission is achieved by only
adding the key when the resolved value is non-nil (the codebase already uses
`.compact` for optional keys, e.g. `inbox_add`). No app change, no version
check, no PATCH for existing runs.

Assumptions (low-stakes, recorded rather than asked):
- Whitespace-only `--model`/`AGENTILE_MODEL` counts as blank (`strip.empty?`),
  but a non-blank value is sent unstripped/verbatim.
- `--model` given explicitly but blank falls through to `AGENTILE_MODEL`
  (simplest reading of "when --model is absent"; blank flag == absent).
- `skills/ag-next/SKILL.md` also calls `claim`; the spec scopes only
  `/ag-build`, so ag-next is left unchanged (candidate follow-up stub). Likewise
  the skill's `run_event failed` / `checkpoint_open` calls are not given
  `--model` — they act on the run claim already opened, so it would be a no-op.

## Test strategy

`.agentile/gates.json` has every gate blank (`test`, `lint`, `build` all
`""`), so there is no configured gate command. The proving command is the one
the spec names:

- `ruby dev/test-ag-store-http.rb` — offline section against the fake API covers
  every acceptance criterion on request shape (flag on claim, env fallback on
  claim, omission when neither/blank, model on the `ensure_run`-created
  `POST /runs`, nothing on an existing run, verbatim alias).
- `ruby -c bin/ag-store` as a syntax check.
- `ruby dev/test-ag-run.rb` — regression only (ag-run shells to ag-store).
- Manual (post-merge, per spec Verification): `/ag-build` against a real spec,
  then `ag-store run_list --spec <slug>` shows `model` = session model id, and
  the run appears in the LLM-time-per-model chart.

Optionally the online section of `dev/test-ag-store-http.rb` (if
`AGENTILE_PROJECTS_*` are set) can pass `--model` on its claim and assert
`run_list` returns it; add only if cheap.

## Risks and unknowns

- Top risk: existing exact-equality body assertions in the test file break if
  `AGENTILE_MODEL` is set in the developer's shell — mitigated by adding it to
  `ISOLATE`.
- `parse_flags` maps a valueless `--model` (or one followed by a `--flag`) to
  `true`; without the String guard ag-store would send `"true"`.
- Run-list response shape: the manual check assumes the app's run JSON exposes
  `model`; if it does not, the chart is the verification instead. Not a
  plugin-side concern.
- The model id the session reports is self-declared from system context; an
  agent may write an alias or guess. Accepted by the spec (no normalisation).
- Factory claims before resolving the model, so factory runs stay "unknown"
  until the separate factory stub lands — expected, out of scope.

## ADR

None. Additive, optional request parameter the app already accepts; trivially
reversible.
