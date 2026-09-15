---
name: ag-loop
description: Retired alias for /ag-build (since 0.13.0). Runs /ag-build once and points at the replacement. Trigger phrases include "/ag-loop", "run the loop".
allowed-tools: AskUserQuestion, Bash, Read, Edit, Skill, Agent
arguments: [--once]
---

# ag-loop (retired)

`/ag-loop` drained a backlog inside one session, which is what filled a session's context and stopped at `max_iterations`. Since 0.13.0 the unit of work is one spec and the skill is `/ag-build`; scheduling belongs to the Agentile Factory (`docs/agentile-factory.md`) or the `bin/ag-run` fallback.

1. Invoke `/ag-build` with `$ARGUMENTS` minus any `--once`.
2. After it returns, add one line before its status line: "`/ag-loop` is retired — use `/ag-build [slug]` for one spec, `bin/ag-run` or the factory for many."

Do not loop. Do not read `.agentile/loop.md`.
