---
name: ag-abandon
description: Abandon an Agentile spec that won't ship — record why, walk its dependent chain, and offer to cascade the abandonment so nothing is left silently blocked. Trigger phrases include "/ag-abandon", "abandon this spec", "drop this spec", "this didn't pass review", "kill this work item".
allowed-tools: AskUserQuestion, Bash, Read, Edit
---

# ag-abandon

Abandoning is the deliberate counterpart to shipping: a spec that failed review, lost its
rationale, or simply isn't worth doing moves out of the active queue into
`specs/abandoned/`, with the reason recorded. Because specs can depend on each other,
abandoning one can strand its dependents — so this skill **walks the dependency chain** and
lets you cascade the abandonment, capturing why each downstream spec was dropped.

**You do not write or revert any code in this skill.** You only move specs and edit their
frontmatter. Shipping/merging is out of scope; this is purely backlog hygiene.

## Step 1 — Resolve paths

Read **Agentile directory** from `.agentile/config.md` under "## Paths" (default
`docs/agentile/`); the specs dir is `<dir>/specs/` and the abandoned dir is
`<dir>/specs/abandoned/`. If the project still uses the old `Specs directory:` key or a
root-level `specs/` with no `Agentile directory` key, honour that path and note that
`/ag-init` can migrate the layout.

## Step 2 — Identify the target spec

The target may be named in `$ARGUMENTS` (a slug, or text matching a title). If it is not,
or is ambiguous, list the active top-level specs (`<dir>/specs/*.md`, `status: ready` or
`in_progress`) and ask which one to abandon. A spec's **slug** is its filename with any
leading `NNNN-` prefix and the `.md` extension stripped.

If the target is `in_progress`, note who holds it (`claimed_by`) — abandoning will clear
that claim. If it is owned by another active session, surface that so the user is aware
before proceeding.

## Step 3 — Find the dependent chain

Resolve the dependents helper path. Use `"${CLAUDE_PLUGIN_ROOT}/bin/ag-dependents"`. If
`$CLAUDE_PLUGIN_ROOT` is empty or the file is not found there, fall back to the newest
match of `~/.claude/plugins/cache/agentile/agentile/*/bin/ag-dependents`.

Run it:

```
ruby "<helper>" "<specs-dir>" "<target-slug>"
```

It prints the transitive set of active specs whose `depends_on` reaches the target, one
slug per line, nearest first (empty if none). These are the specs that will be left
waiting if the target is abandoned.

## Step 4 — Get the reason (top level only)

Ask the user, in plain language, **why** the target is being abandoned (e.g. "spike showed
the approach won't work", "requirement withdrawn", "failed review and not worth fixing").
This free-text reason is recorded only on the target. Down-the-chain abandonments get an
automatic reason that references this one — do not ask for a separate reason per dependent.

## Step 5 — Decide the cascade

If Step 3 returned dependents, present them as a tree (target → its dependents →
theirs), then, for **each** dependent, ask whether to also abandon it (`AskUserQuestion`,
defaulting to your recommendation). The user chooses per dependent.

For every dependent the user chooses to **keep active**: warn that it will become `BLOCKED`
(its dependency is now abandoned, not shipped, so `ag-claim` will not pick it up), and
**offer to strip** the abandoned slug from that spec's `depends_on`. If the user accepts,
edit its frontmatter to remove the slug; if not, leave it (it stays BLOCKED until they
fix it). Apply this per dependent.

## Step 6 — Apply the abandonment

For each spec being abandoned — the target plus every dependent the user chose to cascade —
do the following. Move them in **dependency order is unimportant**, but to avoid filename
collisions when several share a prefix, first `git mv` each to a unique temporary name in
the abandoned dir, then to its final name (the same collision-safe two-step `git mv`
pattern `/ag-prioritise` uses).

For each abandoned spec:

1. Set `status: abandoned` in the frontmatter.
2. Add `abandoned_at:` (ISO8601 — get it with `date -u +%Y-%m-%dT%H:%M:%SZ`).
3. Add `abandoned_reason:`:
   - **Target** — the user's reason from Step 4.
   - **Cascaded dependent** — an automatic reason referencing the target, e.g.
     `Abandoned as a consequence of abandoning <target-slug>: <target-reason>`.
4. Clear the claim fields: blank `claimed_by`, `claimed_at`, and `label`.
5. `git mv` the file into `<dir>/specs/abandoned/` (create the directory if it does not
   exist), preserving its `NNNN-<slug>.md` filename as a record.

## Step 7 — Report

Summarise:

- Which specs were abandoned, each with its recorded reason.
- Any dependents kept active, flagged as now-`BLOCKED`, and whether their `depends_on` link
  to the target was stripped.
- A pointer to re-rank if needed: abandoning removes specs from the active queue, so the
  remaining numbers may be sparse — suggest `/ag-prioritise` if the user wants them dense
  again.
