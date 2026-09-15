---
human_checkpoint: true   # pause for sign-off before each ship/merge; false ships on a passing verify
---

# Ship — how this project integrates finished work

Ship is the merge to trunk plus the store bookkeeping: `status: shipped`,
`shipped_at` stamped, the spec moved to `specs/done/` (local store). Describe
this project's merge conventions here (squash or merge commit, branch naming,
flags for incomplete features). `/ag-build` follows them.

With `human_checkpoint: true` (default) nothing merges without your approval:
`/ag-build` writes a `ship_approval` checkpoint with the reviewer's verdict and
the diff summary, and waits for your answer.
