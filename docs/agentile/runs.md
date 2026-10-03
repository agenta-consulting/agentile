# Agentile run log

Append-only. One line per event, oldest first. Written by `/ag-build`; read by
`/ag-wip` and by `/ag-build` itself to reconstruct progress when resuming in a fresh process.
Not hand-edited — don't reorder or rewrite existing lines, only append.

Format: `- <ISO8601> runner=<id> event=<started|claimed|shipped|paused|failed|idle|deployed|closed> spec=<slug|-> status=<active|closed> detail=<free text>`

A run is **active** until a terminal event (`shipped`, `failed`, `deployed`,
`closed`) lands for that spec and runner. Nothing is ever deleted or rewritten:
`ag-store run_close` retires a run by appending a `closed` event, so the history
stays whole for the flow metrics. Filter with
`ag-store run_list --status active`.
