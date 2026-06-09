---
name: ag-plan
description: Turn a Ready spec into an approved plan before any code is written — files to touch, approach, test strategy, and risks — using the ag-planner subagent or Plan Mode. Recommends an ADR for risky specs. Trigger phrases include "/ag-plan", "plan this spec", "plan the work", "propose an approach".
allowed-tools: Bash, Read, Write, Edit, Agent
---

# ag-plan

The cheapest place to steer is *before* code exists. This skill reads a Ready spec plus the standing context and produces a plan you approve or correct — it writes no implementation code.

## Steps

1. Identify the spec: `$ARGUMENTS` names a file in `specs/` (or ask which spec). Read it.
2. Read the standing context: `CLAUDE.md`, the relevant ADRs in `docs/adr/`, and `.agentile/gates.json` (so the plan's test strategy uses the real gate commands).
3. Produce the plan. Prefer one of:
   - **Plan Mode** — propose the approach and edit nothing until the user approves. This is the default for foreground work.
   - **ag-planner subagent** — dispatch the `ag-planner` agent (fresh context) for a focused plan when the spec is sizable or you want an independent read.
4. The plan must cover: **files to touch**, **approach**, **test strategy** (which gates from `.agentile/gates.json` prove it), and **risks / unknowns**.
5. **ADR check** — if the spec makes a far-reaching or hard-to-reverse decision, draft a new ADR in `docs/adr/` from `.agentile/adr-template.md` (next number in sequence) as part of the plan, and have the user accept it.
6. Present the plan for approval. On approval, hand off to the build step (the `ag-builder` agent, ideally in a worktree). Do not write implementation code in this skill.
