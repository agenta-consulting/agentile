# Agentile run log

Append-only. One line per event, oldest first. Written by `/ag-loop`; read by
`/ag-wip` and by `/ag-loop` itself to reconstruct progress after a compaction
or when resuming in a fresh process. Not hand-edited — don't reorder or
rewrite existing lines, only append.

Format: `- <ISO8601> runner=<id> event=<started|claimed|shipped|paused|failed|idle> spec=<slug|-> detail=<free text>`
