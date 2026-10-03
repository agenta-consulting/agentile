---
number: 0001
title: /ag-build owns one build worktree per spec, created before planning
status: accepted
date: 2026-10-03
---

# ADR-0001: /ag-build owns one build worktree per spec, created before planning

## Status

accepted

## Context

Until 0.22.x, `/ag-plan` wrote `plan.md` and the `SPEC.md` snapshot into the
main checkout, and the builder's worktree only appeared later, created
implicitly by the `ag-builder` agent's `isolation: worktree` frontmatter. So:

- the spec directory sat untracked on trunk from plan until ship, and several
  concurrent builds left several such directories in the shared checkout;
- the plan was not on the branch the reviewer and the PR read;
- ship had to make a separate trunk commit for the spec directory (`4bc41af`,
  `abc6396`, `2de8155`), once from the wrong repository.

The worktree that `isolation: worktree` creates is anonymous, owned by Claude
Code, and exists only for one dispatch: the orchestrator cannot plan into it,
cannot find it again on resume, and cannot hand it to a delegated skill.

Options considered:

1. Keep `isolation: worktree` and copy the spec directory into the builder's
   worktree at dispatch. Still leaves the plan untracked on trunk during the
   plan_review pause, and the copy can drift from an amended plan.
2. A new `bin/ag-worktree` helper. Deterministic, but every headless allowlist
   (factory, `bin/ag-run`, users' own) would need a new entry, and a missing
   entry costs the whole run.
3. `/ag-build` creates a named worktree with plain `git worktree add` right
   after the claim, `/ag-plan` writes into it, and every later stage is
   dispatched into it with the Agent tool's `cwd`.

## Decision

Option 3. One spec has one build worktree, `.claude/worktrees/build-<slug>`,
on one branch, `build/<slug>`, cut from trunk. `/ag-build` creates or reuses it
immediately after a successful claim (and on resume). `/ag-plan` writes
`plan.md`, `SPEC.md` and any ADR draft there and commits them as `Plan <slug>`.
`ag-builder` drops `isolation: worktree`; it and `ag-reviewer` are dispatched
with `cwd` set to the worktree and are told its absolute path and branch. A
`delegate_to` build skill receives the path and branch and must not create
another worktree. Ship merges `build/<slug>`, then removes the worktree and
deletes the branch. Abandon and release leave both in place.

## Consequences

- Trunk never carries an untracked spec directory; the plan and the code
  arrive in the same merge, and the PR shows the acceptance criteria.
- Resume is deterministic: the branch name is derived from the slug, so the
  worktree can be recreated from `build/<slug>` on the machine that has that
  ref. Nothing pushes the branch, so another machine would start over from trunk.
- The orchestrator now does git plumbing (worktree add/prune/remove, branch
  delete) that Claude Code used to do; edge cases (stale registrations, a path
  on the wrong branch, unmerged branches) are ours to handle.
- `.claude/worktrees/` must be ignored by git in every project, or the
  worktree itself shows up as untracked on trunk; `/ag-build` ensures this
  via `.git/info/exclude`.
- Delegated build skills (e.g. `worktree-workflow`) are now consumers of a
  worktree rather than its owner; one that insists on creating its own will
  nest, which the handoff text forbids but cannot enforce.
