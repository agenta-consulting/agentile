# Plan — Create the build worktree and branch before planning, so plan.md and SPEC.md are committed on the build branch

Prose-only change to the plugin's skills, agents and templates (plus one small
`ag-store` regression test). No server change. Lands as one diff, version
0.23.0.

## Files to touch

- `skills/ag-build/SKILL.md` — the bulk of the change:
  - New section **Build worktree** (after **Tools**), the single definition of
    "ensure the build worktree" that `/ag-plan` also points at (same pattern as
    agents pointing at the **Checkpoint ask format**). See Approach §1.
  - **Tools**: `<spec-dir>` becomes `<worktree>/<dir>/specs/<slug>/`; define
    `<worktree>` = absolute `<repo-root>/.claude/worktrees/build-<slug>` and
    `<branch>` = `build/<slug>`.
  - **Step 0**: after identifying the slug, run Build worktree (it recreates
    from `build/<slug>` if the dir is gone); look for `plan.md` under the
    worktree. Routing for an answered `plan_review` changes: approval →
    commit any amendment (`Amend plan <slug>`) then Step 3; any other answer →
    Step 2 with the answer passed to `/ag-plan` as the re-plan instruction.
  - **Step 1**: on a successful claim, run Build worktree before Step 2.
  - **Step 2**: `/ag-plan <slug>` is told the worktree; checkpoint ask's
    context line and the end-of-turn line name `<worktree>/<dir>/specs/<slug>/plan.md`.
    The `printf` example's second string becomes
    `"Review or amend <worktree path of plan.md> in place, then answer."`.
  - **Step 3**: before dispatch, commit an amended plan (see Step 0). Dispatch
    `ag-builder` with Agent `cwd: <worktree>`, plus worktree path and branch in
    the prompt. Delegated path: invoke the skill with worktree path, branch,
    spec slug, `plan.md` path and the literal instruction "Work in this
    worktree on this branch. Do not create another worktree or branch."
  - **Step 4**: dispatch `ag-reviewer` with `cwd: <worktree>` and the branch +
    trunk name so it diffs `<trunk>...<branch>`.
  - **Step 6**: merge `build/<slug>` from the main checkout per `ship.md`;
    delete current 6.3; after `ag-store ship` succeeds, cleanup (Approach §5).
  - **Interactive use beside the factory**: rewrite — `/ag-build` now creates
    the builder's worktree itself; still refuse to run from inside any linked
    worktree (Approach §6).
- `skills/ag-plan/SKILL.md` — step 1 adds the main-checkout check; step 4
  runs the Build worktree procedure (reference `/ag-build`'s section, do not
  duplicate it), calls `ag-store promote "<slug>" --dir "<worktree>/<dir>"`,
  writes `plan.md`/`SPEC.md` there, ADR drafts go to `<worktree>/docs/adr/`,
  then commits once as `Plan <slug>` (Approach §3). Accept an optional
  re-plan instruction (from a send-back) and pass it to `ag-planner`. Step 6
  (standalone handoff) passes worktree path + branch and dispatches
  `ag-builder` with `cwd`; replace "(ideally in a worktree)".
- `agents/ag-builder.md` — remove `isolation: worktree` from frontmatter;
  update `description` ("…in the build worktree it is given…"); replace the
  line-29 bullet: you are dispatched into `.claude/worktrees/build-<slug>` on
  `build/<slug>`; work and commit only there; never create another worktree or
  switch branches; never commit on a `protected_branches` entry. Delete
  "that skill owns worktree creation".
- `agents/ag-reviewer.md` — one bullet: it runs in the build worktree; the
  diff under review is `git diff <trunk>...build/<slug>` (spec dir and ADR
  included); run gates there.
- `agents/ag-planner.md` — one line: when given a worktree, read code there
  (cosmetic; the planner returns content, `/ag-plan` writes).
- `templates/agentile/build.md` — reword the prose: `/ag-build` creates
  `.claude/worktrees/build-<slug>` on `build/<slug>` before planning; a
  `delegate_to` skill is handed that worktree and must not create its own.
- `templates/agentile/plan.md` — "Review or amend `plan.md` in place" → in the
  build worktree (path is in the checkpoint ask).
- `templates/CLAUDE.agentile-section.md` — Specs bullet: spec dir is created on
  the build branch `build/<slug>` in `.claude/worktrees/build-<slug>` and
  reaches trunk with the build merge; "Build on a short-lived branch/worktree"
  bullet names the same. Also mirror into this repo's own `CLAUDE.md`
  Agentile section (it is a copy of the template).
- `skills/ag-init/SKILL.md` line 55 — same wording fix about where the spec
  dir lives before ship.
- `templates/factory-worker.md` — "Work in the project's checkout" bullet:
  add that `/ag-build` puts the spec's plan and code in its build worktree;
  the worker itself stays in the checkout.
- `docs/agentile-factory.md` lines ~77 and ~110 — they state the builder
  "still declares its own `isolation: worktree`"; correct to the new model.
- `README.md` lines 18–19 — plan/build bullets: plan lands on `build/<slug>`.
- `docs/adr/0001-ag-build-owns-the-build-worktree.md` — drafted with this plan
  (status `proposed`; flip to `accepted` in the build diff).
- `dev/test-ag-store-http.rb` — add case 13c: `promote a --dir <absolute tmp
  path>/docs/agentile` prints the absolute path and creates it (the new
  caller passes an absolute, worktree-rooted `--dir`; `File.join` already
  handles it — lock it in).
- `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  (plugin entry, line 14) — bump to **0.23.0** in the same commit with a
  changelog entry (repo rule in CHANGELOG header).

Not touched (out of scope per spec): `bin/ag-store` behaviour, `bin/ag-run`,
the factory daemon, the external `worktree-workflow` skill,
`skills/ag-abandon` (abandon leaves worktree/branch in place — no change
needed), existing stale worktrees.

## Approach

**Subagent pointing (the spec's open question) — decision: Agent tool `cwd`.**
Claude Code 2.1.288's Agent tool accepts `cwd` (its own guidance: "To work in
a different directory (including a worktree), spawn an Agent with `cwd` set to
it"). With `cwd` pinned, a subagent's Bash resets to the worktree between
calls, so gate commands from `gates.json` run as typed (`ruby dev/test-…`) —
no `cd …&&` chains, which the headless allowlist rules forbid. The prompt also
carries the absolute worktree path and branch, and tells the agent to use
absolute paths for Read/Edit/Write and to verify with
`git rev-parse --show-toplevel` / `git branch --show-current` on its first
call, returning `BUILD: blocked` if they do not match. Rejected: "cd per
call" (breaks the allowlist) and EnterWorktree (acts on the session, and the
orchestrator must stay in the main checkout to ship).

**§1 Build worktree procedure** (in `/ag-build`, referenced by `/ag-plan`).
All commands are bare `git`, one per call, run from the main checkout:

1. `<repo-root>` = `git rev-parse --show-toplevel`; `<worktree>` =
   `<repo-root>/.claude/worktrees/build-<slug>`.
2. Ignore check: `git check-ignore -q .claude/worktrees/` — if it exits 1,
   append `.claude/worktrees/` to `.git/info/exclude` (local, never
   committed), so the worktree itself never shows untracked on trunk.
3. `git worktree prune` (clears registrations whose directory was deleted —
   without it the resume-after-delete case fails with "missing but already
   registered worktree" / "branch already checked out").
4. `git worktree list --porcelain`, and decide:
   - `<worktree>` registered with `branch refs/heads/build/<slug>` → reuse.
   - `<worktree>` registered on any other branch/detached, **or** the path
     exists on disk but is not registered → `AG_BUILD: failed <slug>
     worktree_conflict` (with `run_event failed` per Unrecoverable errors).
     Never delete it.
   - Path absent, `git rev-parse --verify --quiet refs/heads/build/<slug>`
     succeeds → `git worktree add <worktree> build/<slug>` (reuse, never
     reset — a re-plan just adds commits).
   - Neither → `git worktree add <worktree> -b build/<slug>` (cuts from the
     main checkout's HEAD, which is trunk).
   - Any `git worktree add` failure → unrecoverable,
     `run_event failed --detail worktree_create_failed`,
     `AG_BUILD: failed <slug> worktree_create_failed`.
   - Edge: `build/<slug>` checked out in some *other* registered worktree →
     treat as `worktree_conflict`.

When `/ag-plan` runs standalone there is no run to fail; it reports the same
codes to the user and stops.

**§2 Main-checkout rule.** Both skills check `git rev-parse --git-dir` vs
`--git-common-dir`; if they differ the session is inside a linked worktree →
refuse (standalone: tell the user; from a factory: `AG_BUILD: failed <slug>
not_main_checkout`). This makes the existing prose rule explicit.

**§3 Plan commit.** After `/ag-plan` writes the files:
`git -C <worktree> add <dir>/specs/<slug>` (plus `docs/adr/<new>.md` if
drafted), then `git -C <worktree> commit -m "Plan <slug>"`. One commit,
before `/ag-plan` returns, so before any `plan_review` checkpoint. If nothing
changed (identical re-plan), skip the commit — `git -C <worktree> diff
--cached --quiet` first. `git -C` keeps every call a bare `git` for the
allowlist.

**§4 Amend and send-back.** On an approved `plan_review` (Step 0 routing or
chat answer), before Step 3:
`git -C <worktree> status --porcelain -- <dir>/specs/<slug> docs/adr` — if
non-empty, add + commit `Amend plan <slug>`. On a non-approval answer, go to
Step 2: `/ag-plan` re-dispatches the planner with the instruction, rewrites
`plan.md`, regenerates `SPEC.md`, commits `Plan <slug>` again, and Step 2
opens a fresh plan_review. (Today a plan_review send-back silently goes to the
builder; this fixes that as the AC requires.)

**§5 Ship and cleanup (Step 6).**
1. From the main checkout: merge `build/<slug>` per `ship.md` (default
   `git merge --no-ff build/<slug>`). Lost race → existing rule: rebase the
   branch once in the worktree (`git -C <worktree> rebase <trunk>`) and
   retry.
2. `ag-store ship "<slug>"`.
3. Only after both succeed: `git worktree remove <worktree>`; if it refuses
   (untracked gate artefacts, dirty files) do **not** `--force` — leave it and
   say so in the ship report. Then `git branch -d build/<slug>`; on "not
   fully merged": `git branch -D` only when `ship.md`'s prose declares a
   squash merge, else leave it and say so. Cleanup failures never change the
   `AG_BUILD: shipped <slug>` outcome.
4. Old step 6.3 (separate spec-dir commit) is deleted.

Abandon / release / gate_failure endings: no cleanup (state this once in
Step 6 or Closing the run).

**§6 Interactive section and docs.** Rewrite "Interactive use beside the
factory" to say `/ag-build` creates the build worktree itself and still runs
from the main checkout. Update all doc text listed above; keep wording short.

## Test strategy

Gates from `.agentile/gates.json` (lint/format blank — skip):

- `test`: `ruby dev/test-ag-run.rb && ruby dev/test-ag-store-http.rb` — must
  stay green; new case 13c covers absolute `--dir` for `promote`.
- `build`: `claude plugin validate .` — proves the agent frontmatter (no
  `isolation`) and skill frontmatter still validate, and versions agree.

The behaviour is skill prose, so the real proof is the spec's Verification
run, done by a human before ship approval (record results in the ship ask):

1. `/ag-build` a throwaway `foreground` spec: at plan_review,
   `git -C .claude/worktrees/build-<slug> log -1 --format=%s` = `Plan <slug>`;
   `git status --porcelain` on trunk is empty.
2. Amend `plan.md` in the worktree, approve → `Amend plan <slug>` commit
   precedes builder commits.
3. Kill the session, `rm -rf` the worktree, resume → recreated from
   `build/<slug>` (exercises `git worktree prune`).
4. After ship: `git log --first-parent` on trunk shows only the merge (no
   "plan and SPEC snapshot" commit); `git worktree list` and
   `git branch --list 'build/*'` no longer show it.
5. Repeat with `.agentile/build.md` `delegate_to: <stub skill>` that echoes
   its args and runs `git worktree list` — it got the path/branch, no second
   worktree exists.
6. Headless spot-check: `claude -p "/ag-build <slug>" --permission-prompts
   none --allowedTools "Bash(ag-store:*)" "Bash(git:*)" "Bash(ruby dev/test-ag-run.rb:*)" …`
   reaches plan_review with no denials (proves `git -C` and Agent `cwd` fit
   the allowlist).

## Risks and unknowns

- **Agent `cwd` availability.** Confirmed present in the installed Claude Code
  (2.1.288) by its tool guidance, but it is not in the plugin docs we cite.
  If a user's older Claude Code ignores `cwd`, the builder would edit the main
  checkout. Mitigation: the first-call `--show-toplevel`/branch check in the
  builder prompt turns that into `BUILD: blocked`, not silent damage.
- **Headless allowlist.** Every new git call is a bare `git …` (`-C` for the
  worktree), so `Bash(git:*)` covers it; writing `.git/info/exclude` needs
  Edit/Write or a shell redirect — use the Edit tool path, not
  `echo >>`, to stay inside allowed tools. Verify with step 6 above.
- **`.claude/worktrees/` not ignored** in a user project would put an
  untracked `.claude/` on trunk; handled by §1.2. This repo already ignores it.
- **Stale registration** after a manual delete — handled by `git worktree
  prune`; without it AC "recreate" fails.
- **This spec builds under the old flow.** The plugin runs from the main
  checkout (dev link), so this build itself still uses `isolation: worktree`
  and the old Step 6.3; the new flow is exercised only after merge + reinstall.
  Expect one last "spec directory" commit for this spec.
- **Delegate compliance.** `worktree-workflow` may still create its own
  worktree; we can only instruct it (out of scope to edit). Verification step
  5 uses a stub, not the real skill.
- **`brief_sync`** still rewrites tracked `docs/agentile/brief.md` on trunk;
  untouched by this spec, but it can make trunk `git status` non-clean during
  a build — note it if verification step 1 trips on it, do not fix here.
- **Branch name collisions**: a project already using `build/*` for
  something else; acceptable, documented in ADR.
- **Squash detection** reads `ship.md` prose — judgement, not a flag.
  Conservative default (leave the branch) is safe.

## ADR

[ADR-0001: /ag-build owns one build worktree per spec, created before planning](../../../adr/0001-ag-build-owns-the-build-worktree.md)
— drafted, status `proposed`; the builder flips it to `accepted` in the diff.
