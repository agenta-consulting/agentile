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
- If `human_checkpoint` is `true`, or is `route` and the spec's `route` is
  `foreground` or `spike`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage (when invoked
  from `/ag-build`, return instead; it writes the checkpoint).
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Steps

1. Identify the spec: `$spec` (or `$ARGUMENTS`) names a slug (or ask which spec, if invoked directly by a human). First, resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`. Also accept an optional **re-plan instruction** (a human's send-back answer, passed by `/ag-build`) and hand it to the planner. Check you are in the main checkout (`git rev-parse --git-dir` equals `git rev-parse --git-common-dir`); if not, refuse (standalone: tell the user; from `/ag-build`: `not_main_checkout`). Resolve the spec's content with `ag-store spec_read "<slug>"` — there is no spec file in the repo to read; the `SPEC.md` written below is a snapshot.
2. Decide how the plan gets produced — this determines whose context does the reading:
   - **Invoked from `/ag-build`** (non-interactive orchestration) — always dispatch the `ag-planner` agent, passing the spec slug (`ag-planner` calls `ag-store spec_read <slug>` itself). Never invoke Plan Mode here. The subagent reads the spec, `CLAUDE.md`, the relevant ADRs, and `.agentile/gates.json` itself and returns the finished plan content. Do **not** Read the spec, `CLAUDE.md`, or `gates.json` yourself in this case — keeping them out of your own context is the point, since your context here *is* `/ag-build`'s context.
   - **Invoked directly by a human** — read the spec and the standing context yourself (`CLAUDE.md`, `docs/adr/`, `.agentile/gates.json`, so the plan's test strategy uses the real gate commands), then produce the plan with **Plan Mode** by default (propose the approach, edit nothing until the user approves), or dispatch the **ag-planner subagent** (fresh context) for a sizable spec or when you want an independent read.
3. The plan must cover: **files to touch**, **approach**, **test strategy** (which gates from `.agentile/gates.json` prove it), and **risks / unknowns**.
4. **Persist the plan.** First ensure the **build worktree** `<worktree>` on `build/<slug>` exists by running `/ag-build`'s **Build worktree** procedure (reference it; do not duplicate it — `/ag-build` has usually done this already, and it is idempotent). Standalone, report `worktree_conflict` / `worktree_create_failed` to the user and stop instead of failing a run. Then run `ag-store promote "<slug>" --dir "<worktree>/<dir>"` — it ensures the spec's directory `<worktree>/<dir>/specs/<slug>/` exists (idempotent) and returns its path. Write the plan to `<returned-dir>/plan.md` using `.agentile/plan-template.md` as the structure. Supporting material gathered while planning (sketches, notes) belongs in the same directory.

   **Also write a read-only `SPEC.md` snapshot** beside `plan.md`, from `ag-store spec_read`. Without it the directory holds a plan for a spec that cannot be read without a network call and a token — so the builder, the reviewer, and anyone reading the pull request see the approach but not the acceptance criteria the diff has to satisfy. Head the file exactly:

   ```
   <!-- SNAPSHOT — not the source of truth.
        Spec <slug> read from Agentile Projects at <ISO8601>.
        Rank, claim and status live in the store; re-run /ag-plan to refresh.
        Never edit this file: edits are lost, and the store will not see them. -->
   ```

   Regenerate it on every re-plan. Read acceptance criteria from it freely;
   never read *state* (status, rank, claim) from it — that is what goes stale.
5. **ADR check** — if the spec makes a far-reaching or hard-to-reverse decision, draft a new ADR in `<worktree>/docs/adr/` from `.agentile/adr-template.md` (next number in sequence) as part of the plan, link it from `plan.md`'s ADR section, and have the user accept it.

   **Commit the plan.** Once the files are written: `git -C <worktree> add <dir>/specs/<slug>` (plus any new ADR), skip if `git -C <worktree> diff --cached --quiet` shows nothing changed, else `git -C <worktree> commit -m "Plan <slug>"` — one commit, before returning and so before any `plan_review` checkpoint.
6. Present the plan for approval, pointing at `<worktree>/<dir>/specs/<slug>/plan.md` so the user can amend it directly — an edited `plan.md` is the approved plan. **If invoked from `/ag-build`, stop here and return** — `/ag-build` owns the pause decision (it writes the checkpoint) and the build handoff. If invoked standalone, on approval hand off to the build step: first read `.agentile/build.md`; if it sets `delegate_to: <skill>`, invoke that skill with the spec and `plan.md` **instead**; otherwise dispatch the `ag-builder` agent with Agent `cwd: <worktree>`, passing the worktree path, branch `build/<slug>`, the spec slug, the `SPEC.md` snapshot path and `plan.md`. Do not write implementation code in this skill.
