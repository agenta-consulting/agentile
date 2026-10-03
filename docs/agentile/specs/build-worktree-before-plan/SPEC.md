<!-- SNAPSHOT — not the source of truth.
     Spec build-worktree-before-plan read from Agentile Projects at 2026-10-03T12:23:17Z.
     Rank, claim and status live in the store; re-run /ag-plan to refresh.
     Never edit this file: edits are lost, and the store will not see them. -->

---
title: Create the build worktree and branch before planning, so plan.md and SPEC.md are committed on the build branch
slug: build-worktree-before-plan
status: in_progress
type: chore
route: foreground
business_value: medium
technical_certainty: high
rank: 1
created_at: 2026-10-03T10:50:56Z
tags: [ag-build, worktrees]
outcome: After the next spec ships through /ag-build, `git log` on trunk shows plan.md and SPEC.md arriving inside the build merge, with no separate "plan and SPEC snapshot" commit on trunk, and `git status` on trunk never shows an untracked spec directory while a build is in flight
claimed_by: factory-next/agentile/build-worktree-before-plan
label: factory-next
claimed_at: 2026-10-03T12:21:07Z
claimed_by_member: keith@keithrowell.com
captured_by: keith@keithrowell.com
shaped_by: [keith@keithrowell.com]
source_inbox: Make /ag-build create build worktree and branch before /ag-plan runs
---

# Create the build worktree and branch before planning, so plan.md and SPEC.md are committed on the build branch

## Problem / why now

`/ag-build` runs `/ag-plan` in the main checkout, so `plan.md` and the `SPEC.md` snapshot sit untracked on trunk from plan until ship. The builder's worktree only appears later, through `isolation: worktree` at dispatch. Three things go wrong:

- Concurrent builds leave untracked `docs/agentile/specs/<slug>/` directories in the shared trunk checkout.
- The plan is not on the branch that the reviewer and the PR read.
- Ship has to make a separate trunk commit for the spec directory. Recent history shows these commits (`4bc41af`, `abc6396`, `2de8155`), and one of them was even made from another repo.

This is the user's own loop, run daily by factory workers, so every build pays this cost.

## Acceptance criteria

- [ ] Right after a successful claim (Step 1), `/ag-build` creates `.claude/worktrees/build-<slug>` on a new branch `build/<slug>` cut from trunk (`git worktree add <path> -b build/<slug>`). If it already exists, it is reused.
- [ ] `/ag-plan` (from `/ag-build` **and** run directly by a human) creates or reuses the same worktree and branch, then writes `plan.md` and `SPEC.md` under `<worktree>/<dir>/specs/<slug>/`, never in the main checkout.
- [ ] Right after `/ag-plan` writes them, `plan.md` and `SPEC.md` (and any ADR draft) are committed on `build/<slug>` as one commit, `Plan <slug>`, before any `plan_review` pause.
- [ ] The `plan_review` checkpoint ask and the end-of-turn line give the **worktree path** of `plan.md`. If the human amends `plan.md` there, the change is committed (`Amend plan <slug>`) before the builder starts. A send-back re-plan regenerates `SPEC.md` and commits again.
- [ ] `ag-builder` no longer uses `isolation: worktree`. It is dispatched with the worktree path and branch, and does all its work and commits there.
- [ ] If `.agentile/build.md` sets `delegate_to: <skill>` (e.g. `worktree-workflow`), `/ag-build` still creates the worktree first and invokes the delegate with the worktree path and branch, plus an explicit instruction to work in that worktree and not create another. The `ag-builder.md` note that says "that skill owns worktree creation" is replaced to match.
- [ ] Step 0 (resume) looks for `plan.md` in the build worktree. If the worktree is missing but `build/<slug>` exists (another machine, or cleaned up), it recreates the worktree with `git worktree add <path> build/<slug>` and continues. If neither exists, it goes to Step 2 and plans fresh.
- [ ] Ship (Step 6) merges `build/<slug>`, which already carries the spec directory. The separate "commit the spec directory" step 6.3 is removed. After the merge and `ag-store ship`, the worktree is removed (`git worktree remove`) and the branch deleted (`git branch -d`).
- [ ] Docs that describe the old order (`/ag-build` and `/ag-plan` SKILL.md, `agents/ag-builder.md`, `templates/agentile/build.md`, the CLAUDE.md template text about where `plan.md` lives, the CHANGELOG) are updated.

## Scope boundary

**In scope:** `/ag-build` Steps 0/1/2/3/6, `/ag-plan` step 4 and standalone handoff, `ag-builder` frontmatter and worktree prose, the delegated-build handoff contract, cleanup after ship, and the docs and templates above.

**Out of scope:** editing the external `worktree-workflow` skill itself (we only change what `/ag-build` hands it), `bin/ag-run` and the factory daemon (they invoke `/ag-build`, which now owns this), `ag-store promote` server behaviour (it still just returns a directory path; the caller now passes a `--dir` rooted in the worktree), and cleaning up existing stale worktrees under `.claude/worktrees/`.

## Edge cases and failure paths

- `build/<slug>` exists from an earlier, closed run of the same spec: reuse it and do not reset it. A re-plan just adds commits.
- The worktree path exists but is on a different branch, or is not a registered worktree: fail with `AG_BUILD: failed <slug> worktree_conflict`. Never delete it automatically.
- `git worktree add` fails (dirty index, lock, disk): treat it as unrecoverable per the existing rules (`run_event failed --detail worktree_create_failed`).
- Merge rejected because trunk moved: the existing pull/rebase-once-and-retry rule applies. Cleanup runs only after a successful merge **and** `ag-store ship`.
- `git branch -d` refuses because the branch is not fully merged (e.g. a squash-merge convention in `ship.md`): fall back to `-D` only when `ship.md` declares squash. Otherwise leave the branch and say so in the ship report.
- Abandon or release mid-build: the worktree and branch are left in place (no cleanup), so the work can be inspected or resumed.
- `/ag-plan` run from inside a worktree, or `/ag-build` run from inside one: keep the existing rule, run from the main checkout and refuse otherwise.

## Affected areas

`skills/ag-build/SKILL.md`, `skills/ag-plan/SKILL.md`, `agents/ag-builder.md` (drop `isolation: worktree`), possibly `agents/ag-reviewer.md` (point it at the worktree), `templates/agentile/build.md`, CLAUDE.md template text in `skills/ag-init` / `templates`, and `CHANGELOG.md`.

## Open questions

None blocking. The planner should confirm how a subagent is pointed at an existing worktree once `isolation: worktree` is gone (its prompt gives the absolute path and it `cd`s there, or every tool call uses absolute paths) and pick one.

## Verification

Run `/ag-build` on a throwaway spec in this repo with a `foreground` route:

1. At the plan_review pause, `git -C <worktree> log -1` shows `Plan <slug>` and `git status` on trunk is clean.
2. Kill the session, delete the worktree, and resume. The worktree is recreated from the branch and the build continues.
3. After ship, trunk's history has the spec directory only through the merge, and `git worktree list` / `git branch` no longer show `build/<slug>`.

Repeat once with `delegate_to` set to a stub skill and confirm it received the worktree path and created no second worktree.
