# Agentile deploy log

Append-only. One line per deploy, oldest first. Written by `/ag-deploy`; read
by `/ag-deploy` to compute the next batch (every spec shipped after the last
line's timestamp). Not hand-edited — only append.

Format: `- <ISO8601> runner=<identity> target=<target> ref=<git sha> specs=<n> detail=<free text>`

A rollback is recorded as a new line too — the log is a history of what was
live, not a list of successes.
