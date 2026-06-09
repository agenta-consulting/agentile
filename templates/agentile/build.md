---
# Uncomment to execute ready work by delegating to a skill:
# delegate_to: worktree-workflow
# human_checkpoint: false
---

# Build — how this project executes ready work

Document execution conventions here (commit granularity, branch naming, etc.).
With `delegate_to: worktree-workflow`, each ready spec is built as an isolated
worktree chunk and merged back to main. Run `/ag-customise build` to set this up.
