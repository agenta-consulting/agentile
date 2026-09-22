---
name: ag-outcome
description: Create or edit an Agentile Outcome — the falsifiable bet above specs — through a short interview for its claim, measure and stop rule; or record one as achieved. Non-coding. Trigger phrases include "/ag-outcome", "new outcome", "add an outcome", "edit the outcome", "mark the outcome achieved", "what are we betting on".
allowed-tools: AskUserQuestion, Bash, Read
arguments: [slug-or-achieve]
---

# ag-outcome

An **Outcome** is a bet: a claim about what becomes true, a measure a human can judge it by, and a stop rule that says when to give up. It is the layer above specs (`docs/agentile-outcomes.md`) and the input `/ag-decompose` works from. This skill is the shaping interview one level up — short, and biased toward rejecting a claim that is really a deliverable.

**You do not write code or specs here.** You produce or edit one Outcome.

## Modes

- `/ag-outcome` — interview and create a new Outcome.
- `/ag-outcome <slug>` — re-open an existing one; ask what changed and patch it.
- `/ag-outcome achieve <slug>` — record the measure as met.

## Step 1 — Resolve the store

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`. Read `<dir>/brief.md` — an Outcome should sit inside the brief's constraints and non-goals, and usually elaborates one of its prioritised outcomes.

Run `ag-store outcome_list` and show the existing Outcomes (slug, title, status, rank) so the user does not create a duplicate.

## Step 2 — Interview (create mode)

One or two questions at a time, `AskUserQuestion` for discrete choices.

1. **The claim.** "When this is achieved, what is true that isn't true today?" Push back on any answer that names a deliverable — "provide SSO", "build the export" — with: *what would that let someone do, or stop someone doing?* The claim passes when the measure can be stated without listing the work.
2. **The measure.** "What evidence would you accept that the claim now holds?" It must be observable by a human when evidence arrives — a pilot passing, a questionnaire answered, a number crossing a line. A spec count is not a measure.
3. **The stop rule.** "What would make you abandon this whole line of work?" An Outcome without a stop rule is not Ready; if the user cannot name one, say so and ask what evidence would embarrass the bet.
4. **Title and slug.** Derive a short title from the claim (no colons — dashes or commas), and a kebab-case slug. Confirm both in one question.

Optional, only if it comes up: notes (evidence already in hand, links).

## Step 3 — Write it

Build the markdown from `.agentile/outcome-template.md` (fallback `"${CLAUDE_PLUGIN_ROOT}/templates/agentile/outcome-template.md"`): frontmatter `title`, `slug`, `status: open`, `rank:` blank, `created:` today; body sections **Claim**, **Measure**, **Stop rule**, **Notes**. Keep every frontmatter value valid YAML.

```
ag-store outcome_create <slug>
```

piping the markdown on stdin; the store records you as its creator from the token. The Outcome is created **unranked**; `/ag-prioritise` ranks it, and the app regenerates the brief's "Prioritised outcomes" list from ranked Outcomes.

## Step 2b — Edit mode (`/ag-outcome <slug>`)

`ag-store outcome_read <slug>`, show it, ask what changed (one question). Patch frontmatter with `ag-store outcome_write <slug> --set key=value ...` — `status` and `rank` are endpoint-only and come back 422 from `outcome_write` (route those through `/ag-prioritise` or the achieve step instead). Body sections (claim, measure, stop rule, notes) are edited with `ag-store outcome_write <slug> --set claim="..."` (keys `claim`, `measure`, `stop_rule`, `notes`), or in the app.

## Step 2c — Achieve mode (`/ag-outcome achieve <slug>`)

Read the Outcome and `ag-store map` for the specs serving it. Ask one question: *what evidence shows the measure is met?* Record the answer in Notes where the store allows it, then `ag-store outcome_achieve <slug>`. If serving specs are still `ready`/`in_progress`, say so — achieving does not abandon them, and the user may want `/ag-abandon` on leftovers.

## Step 4 — Report

One short block: slug, title, status, and the next move — `/ag-prioritise` to rank it, `/ag-decompose <slug>` to propose the work that would make it true.
