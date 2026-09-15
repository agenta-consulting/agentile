# Agentile run log

Append-only. One line per event, oldest first. Written by `/ag-build`; read by
`/ag-wip` and by `/ag-build` itself to reconstruct progress when resuming in a fresh process.
Not hand-edited — don't reorder or rewrite existing lines, only append.

Format: `- <ISO8601> runner=<id> event=<started|claimed|shipped|paused|failed|idle> spec=<slug|-> detail=<free text>`
