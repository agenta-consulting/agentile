---
name: ag-retro
description: Close the loop with a data-driven mini-retro — compile a flow digest from git history, specs, and ADRs (and PRs when available), surface where work waited and what needed rework, then propose concrete updates to CLAUDE.md and ADRs. Non-coding. Trigger phrases include "/ag-retro", "run a retro", "flow digest", "what did we learn", "weekly retro".
allowed-tools: Bash, Read, Edit, Agent
context: fork
agent: general-purpose
---

# ag-retro

The LEARN step. A non-coding pass that turns recent delivery into encoded lessons, so the next cycle is cheaper. Replaces the status-meeting standup with a digest of what the data actually shows.

This skill **does not change code**. It reads history and proposes edits to the standing context.

## Apply this project's playbook

Before doing anything else, check for `.agentile/learn.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Step 1 — Gather the window

Default to the last 7 days (or a window the user names). First Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`. Collect, read-only:

- `git log --since` with stats — commits, churn, which areas changed most.
- Merge/PR history via `gh pr list --state merged` and `gh pr view` when the `gh` CLI is available; otherwise rely on git.
- `ag-store spec_list` (active) and `ag-store spec_list --pool done` (shipped) — which specs shipped, which stalled, which became spikes. - `ag-store flow` — the flow numbers for every spec, already computed: `queue_wait_seconds` (created→claim), `cycle_seconds` (claim→ship), and the split of that cycle into `agent_seconds` and `human_wait_seconds`, with a per-checkpoint breakdown. Do not recompute these from timestamps by hand.
- `docs/adr/` — decisions made in the window.

Run heavy log/grep commands so only your summary lands in context, not raw output.

## Step 2 — Find the signal

Answer, with evidence:

- **Where did work wait?** Use `flow`. Three different bottlenecks look identical in a "lead time" number and need different fixes: a large `queue_wait_seconds` means shaped work sat unclaimed (a prioritisation problem), a large `human_wait_seconds` means the loop stalled at checkpoints (you are the constraint — look at which `reason` and `asked_by` dominate), and a large `agent_seconds` means the building itself is slow (gates, environment, spec quality).
- **What needed the most rework?** Files or areas with repeated churn or repeated review bounces.
- **What surprised us?** Incidents, reverts, or specs that ballooned past their scope boundary.
- **Lead time** — is it dropping? If not, the constraint is upstream of coding; say so plainly.
- **Did shipped work actually work?** For each spec shipped since the last retro, check its `outcome:` field — was the outcome observed? Unverified or unmet outcomes become new inbox stubs (`/ag-capture`), referencing the original slug.
- **Are the bets still good?** For each open Outcome (`ag-store outcome_list --status open`) read its measure and stop rule against what shipped (`ag-store map`). Propose `achieved` where the evidence meets the measure, `abandoned` where the stop rule has fired, and say plainly where neither is yet decidable. A person confirms; you do not transition an Outcome on your own.

Measure **flow, not output** — do not report lines of code or "agent velocity".

## Step 3 — Encode the lessons

For each lesson worth keeping, propose a concrete change (and make it on approval):

- A **`CLAUDE.md`** edit — a new convention, a do/don't, a clarified standard.
- A new or updated **ADR** when the lesson is a decision.
- A **`.agentile/shape.md`** addition when an item shipped wrong because shaping missed a question.
- A **brief** update (in the app — `docs/agentile/brief.md` is a read-only copy) when the project's outcomes, constraints, or non-goals have shifted.
- An **Outcome transition** on approval — `ag-store outcome_achieve <slug>`, or `/ag-abandon <slug>` (which cascades to the specs serving it).

## Step 4 — Report

Deliver a short digest: the window, the bottleneck, the rework hotspot, the lead-time read, and the encoded changes (with paths). Keep it scannable.
