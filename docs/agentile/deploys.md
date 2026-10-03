# Agentile deploy log

Append-only. One line per deploy, oldest first. Written by `/ag-deploy`; read
by `/ag-deploy` to compute the next batch (every spec shipped after the last
line's timestamp). Not hand-edited — only append.

Format: `- <ISO8601> runner=<identity> target=<target> ref=<git sha> specs=<n> detail=<free text>`

A rollback is recorded as a new line too — the log is a history of what was
live, not a list of successes.
- 2026-10-03T10:23:42Z runner=b1e6bda3-644b-41fa-a640-58240950b562 target=github:agenta-consulting/agentile tag=agentile--v0.22.1 ref=26ce037c43c54d9638b2d3b9fbdba72357ada12c specs=2 detail=structured-checkpoint-asks,ag-store-sends-run-model
