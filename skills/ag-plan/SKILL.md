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

1. Identify the spec: `$spec` (or `$ARGUMENTS`) names a slug or path (or ask which spec, if invoked directly by a human). Resolve its content with `ag-store spec_read "<slug>" --dir "<dir>" --store "<store>"` rather than reading the file directly — under the `local` store this is the file's bytes; a shared store has no file to read at all.
2. Decide how the plan gets produced — this determines whose context does the reading:
   - **Invoked from `/ag-loop`** (non-interactive orchestration) — always dispatch the `ag-planner` agent, passing the spec identifier plus the resolved Agentile directory and store (`ag-planner` doesn't inherit your resolved variables — it needs `<id> --dir <dir> --store <store>` verbatim in its prompt so it can call `ag-store spec_read` itself). Never invoke Plan Mode here. The subagent reads the spec, `CLAUDE.md`, the relevant ADRs, and `.agentile/gates.json` itself and returns the finished plan content. Do **not** Read the spec, `CLAUDE.md`, or `gates.json` yourself in this case — keeping them out of your own context is the point, since your context here *is* the loop's context.
   - **Invoked directly by a human** — read the spec and the standing context yourself (`CLAUDE.md`, `docs/adr/`, `.agentile/gates.json`, so the plan's test strategy uses the real gate commands), then produce the plan with **Plan Mode** by default (propose the approach, edit nothing until the user approves), or dispatch the **ag-planner subagent** (fresh context) for a sizable spec or when you want an independent read.
3. The plan must cover: **files to touch**, **approach**, **test strategy** (which gates from `.agentile/gates.json` prove it), and **risks / unknowns**.
4. **Persist the plan.** Resolve which store answers this project (`store:` in `.agentile/store.md`, default `local`). Run `ag-store promote "<slug>" --dir "<dir>" --store "<store>"` — for the `local` store this promotes a flat spec to its directory form (`git mv <specs>/NNNN-<slug>.md <specs>/NNNN-<slug>/SPEC.md`) and is a no-op if it's already a directory; it returns the spec's directory path. Write the plan to `<returned-dir>/plan.md` using `.agentile/plan-template.md` as the structure, then run `ag-store attach "<slug>" "<returned-dir>/plan.md" --dir "<dir>" --store "<store>"` so a shared store (a future `airtable` store, which has no filesystem directory of its own) can record where the plan lives. Supporting material gathered while planning (sketches, notes) belongs in the same directory.

   **On a store with no filesystem spec (`airtable`), also write a read-only
   `SPEC.md` snapshot** beside `plan.md`, from `ag-store spec_read`. Without it
   the directory holds a plan for a spec that cannot be read without a network
   call and a token — so the builder, the reviewer, and anyone reading the pull
   request see the approach but not the acceptance criteria the diff has to
   satisfy. Head the file exactly:

   ```
   <!-- SNAPSHOT — not the source of truth.
        Spec <record-id> read from the <store> store at <ISO8601>.
        Rank, claim and status live in the store; re-run /ag-plan to refresh.
        Never edit this file: edits are lost, and the store will not see them. -->
   ```

   Regenerate it on every re-plan. Read acceptance criteria from it freely;
   never read *state* (status, rank, claim) from it — that is what goes stale.
5. **ADR check** — if the spec makes a far-reaching or hard-to-reverse decision, draft a new ADR in `docs/adr/` from `.agentile/adr-template.md` (next number in sequence) as part of the plan, link it from `plan.md`'s ADR section, and have the user accept it.
6. Present the plan for approval, pointing at `plan.md` so the user can amend it directly — an edited `plan.md` is the approved plan. **If invoked from `/ag-loop`, stop here and return** — the loop owns the pause decision and the build handoff. If invoked standalone, on approval hand off to the build step: first read `.agentile/build.md`; if it sets `delegate_to: <skill>`, invoke that skill with the spec and `plan.md` **instead**; otherwise dispatch the `ag-builder` agent (ideally in a worktree), passing the spec path and `plan.md`. Do not write implementation code in this skill.
