---
human_checkpoint: route   # pause for plan review: true (always) | false (never) | route (foreground and spike specs only)
---

# Plan — how this project wants plans reviewed

`/ag-plan` writes `plan.md` beside `SPEC.md`. `human_checkpoint` decides whether
`/ag-build` stops for you to read it before any code is written:

- `route` (default) pauses when the spec's `route` is `foreground` or `spike`.
  That is the cheapest place to steer low-certainty work. `background` specs run
  straight through to build.
- `true` pauses for every spec; `false` never pauses.

Review or amend `plan.md` in place (in the build worktree; the path is in the checkpoint ask), then answer the checkpoint (reply "approved"
in a session, or answer it on the factory console). An amended `plan.md` is the
approved plan.
