---
# Uncomment to execute ready work by delegating to a skill:
# delegate_to: worktree-workflow
# human_checkpoint: false
---

# Build — how this project executes ready work

Document execution conventions here (commit granularity, etc.). `/ag-build`
creates `.claude/worktrees/build-<slug>` on branch `build/<slug>` before
planning; a `delegate_to` skill is handed that worktree and must not create its own.
With `delegate_to: worktree-workflow`, each ready spec is built as an isolated
worktree chunk and merged back to main. Run `/ag-customise build` to set this up.
