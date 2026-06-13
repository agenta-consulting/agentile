---
name: ag-plan
description: Turn a Ready spec into a written, reviewable plan before any code — promotes the spec to its directory form and writes plan.md (files to touch, approach, test strategy, risks) beside SPEC.md, using the ag-planner subagent or Plan Mode. Recommends an ADR for risky specs. Trigger phrases include "/ag-plan", "plan this spec", "plan the work", "propose an approach".
allowed-tools: Bash, Read, Write, Edit, Agent
arguments: [spec]
---

# ag-plan

The cheapest place to steer is *before* code exists. This skill reads a Ready spec plus the standing context and produces a plan you approve or correct — it writes no implementation code.

## Apply this project's playbook

Before doing anything else, check for `.agentile/plan.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Steps

1. Identify the spec: `$spec` (or `$ARGUMENTS`) names a file in `specs/` (or ask which spec). Read it.
2. Read the standing context: `CLAUDE.md`, the relevant ADRs in `docs/adr/`, and `.agentile/gates.json` (so the plan's test strategy uses the real gate commands).
3. Produce the plan. Prefer one of:
   - **Plan Mode** — propose the approach and edit nothing until the user approves. This is the default for foreground work.
   - **ag-planner subagent** — dispatch the `ag-planner` agent (fresh context) for a focused plan when the spec is sizable or you want an independent read.
4. The plan must cover: **files to touch**, **approach**, **test strategy** (which gates from `.agentile/gates.json` prove it), and **risks / unknowns**.
5. **Persist the plan.** Promote the spec to its directory form if it is still a flat file, then write the plan beside it:
   - If the spec is `<specs>/NNNN-<slug>.md`: `mkdir <specs>/NNNN-<slug>/` then `git mv <specs>/NNNN-<slug>.md <specs>/NNNN-<slug>/SPEC.md`.
   - Write the plan to `<specs>/NNNN-<slug>/plan.md` using `.agentile/plan-template.md` as the structure.
   - Supporting material gathered while planning (sketches, notes) belongs in the same directory.
6. **ADR check** — if the spec makes a far-reaching or hard-to-reverse decision, draft a new ADR in `docs/adr/` from `.agentile/adr-template.md` (next number in sequence) as part of the plan, link it from `plan.md`'s ADR section, and have the user accept it.
7. Present the plan for approval, pointing at `plan.md` so the user can amend it directly — an edited `plan.md` is the approved plan. **If invoked from `/ag-loop`, stop here and return** — the loop owns the pause decision and the build handoff. If invoked standalone, on approval hand off to the build step: first read `.agentile/build.md`; if it sets `delegate_to: <skill>`, invoke that skill with the spec and `plan.md` **instead**; otherwise dispatch the `ag-builder` agent (ideally in a worktree), passing the spec path and `plan.md`. Do not write implementation code in this skill.
