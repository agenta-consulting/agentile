# Agentile deploy log

Append-only. One line per deploy, oldest first. Written by `/ag-deploy`; read
by `/ag-deploy` to compute the next batch (every spec shipped after the last
line's timestamp). Not hand-edited — only append.

Format: `- <ISO8601> runner=<identity> target=<target> ref=<git sha> specs=<n> detail=<free text>`

A rollback is recorded as a new line too — the log is a history of what was
live, not a list of successes.
- 2026-10-03T10:23:42Z runner=b1e6bda3-644b-41fa-a640-58240950b562 target=github:agenta-consulting/agentile tag=agentile--v0.22.1 ref=26ce037c43c54d9638b2d3b9fbdba72357ada12c specs=2 detail=structured-checkpoint-asks,ag-store-sends-run-model
- 2026-10-03T10:26:36Z runner=b1e6bda3-644b-41fa-a640-58240950b562 target=github:agenta-consulting/agentile tag=agentile--v0.22.2 ref=76b8f013c7939fbe1466934e0e42786abe283fc6 specs=0 detail=ag-dev-link links the main checkout (no spec)
- 2026-10-03T13:03:13Z runner=bd89d434-11a5-465f-9536-e3270cfc97c3 target=github:agenta-consulting/agentile tag=agentile--v0.23.0 ref=f323d19aa2c95d8112e7cac3767716adbd761618 specs=1 detail=build-worktree-before-plan
