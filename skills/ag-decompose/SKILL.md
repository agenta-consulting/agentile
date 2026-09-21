---
name: ag-decompose
description: Propose the inbox stubs that would make an Agentile Outcome true — four to eight one-liners the user accepts, edits or rejects, each landing in the Inbox linked to the Outcome. Never writes specs. Trigger phrases include "/ag-decompose", "decompose this outcome", "what work would achieve", "break down the outcome", "propose specs for".
allowed-tools: AskUserQuestion, Bash, Read
arguments: [outcome-slug]
---

# ag-decompose

The reason Outcomes exist. An Outcome with a sharp claim, a measure and constraints is a *prompt*: this skill turns it into candidate work. It proposes **stubs**, not specs — decomposition is a proposal, shaping (`/ag-shape`) remains the gate where each idea is interviewed into something buildable.

**You do not write code, specs, or plans here.** You add stubs to the Inbox, each linked to the Outcome.

## Step 1 — Load context

- Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.
- The target is `$outcome-slug` (or `$ARGUMENTS`). If absent or ambiguous, run `ag-store outcome_list --status open` and ask which.
- Read the Outcome (`ag-store outcome_read <slug>`), the brief (`<dir>/brief.md`), the project's `CLAUDE.md`, and skim `docs/adr/` — the constraints and non-goals bound what you may propose.
- Run `ag-store map` and note the specs **already serving this Outcome** (any status) and the current Inbox (`ag-store inbox_list`). You are adding to existing work, not restarting it.

## Step 2 — Propose

Produce **four to eight** candidate stubs. Each is one line in the voice `/ag-capture` uses — what to change and why, concrete enough to shape — with a derived **title** (3–6 words) and a **type** (`feature`/`bug`/`chore`/`spike`). Together they should be sufficient for the claim; individually each should be shippable on its own.

Before the list, name the **landmines** in two or three lines: existing specs the proposals overlap or collide with, constraints from the brief or ADRs that shape the approach (an air-gapped install, a determinism guarantee, a non-goal), and anything that should be a spike because the approach is unknown.

Present the proposals as a numbered list. Then, with `AskUserQuestion` (multi-select), ask which to accept as-is. For any the user wants changed, take the edit in plain language and show the revised line. Never add acceptance criteria or estimates — those are shaping's job.

## Step 3 — Capture

For each accepted stub:

```
ag-store inbox_add "<stub text>" --title "<title>" --type "<type>" --serves "<outcome-slug>"
```

Quote the text so the shell cannot eat an apostrophe. The store links the stub to the Outcome so provenance survives to `/ag-shape`, which offers the link as the default `serves`, and records you as the capturer from the token.

## Step 4 — Report

How many stubs landed, their titles, and the next move: `/ag-shape` on each. Mention any proposal the user rejected in one line, so the reasoning is not lost.
