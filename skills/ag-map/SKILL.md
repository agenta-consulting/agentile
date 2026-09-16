---
name: ag-map
description: Show the Agentile world at Outcome level — each Outcome by rank with its specs by state, what is blocked, the free-standing specs, and the tag index. Read-only. Trigger phrases include "/ag-map", "show the map", "outcome view", "where are we", "what serves what", "the big picture".
allowed-tools: Bash, Read
---

# ag-map

The higher-level view. Everything shown is **computed** from Outcomes and specs by `ag-store map` — nothing here is a stored field, so it can never be stale. Makes no changes.

## Steps

1. Resolve the **Agentile directory** and store (`.agentile/config.md`, `.agentile/store.md`). Run `ag-store map --dir "<dir>" --store "<store>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) and parse the JSON object: `outcomes` (rank-ordered, each with `specs` bucketed by `ready`/`in_progress`/`shipped`/`abandoned` and a `blocked` list), `unlinked` (specs serving no Outcome, same buckets), `orphaned` (specs whose `serves` names no known Outcome), and `tags`.

2. Render, in this order:

   ```
   1. <title>  (<slug>)  open · rank 1
      ready 3 (1 blocked: <slug>) · in progress 1 · shipped 4 · abandoned 0
      <spec slugs, grouped by state>
   …
   Unlinked  ready 2 · in progress 0 · shipped 6
   Tags      auth (3) · testing (2)
   ```

   Achieved and abandoned Outcomes go in a short trailer, one line each, after the open ones.

3. Flag, one line each, only when true:
   - an open Outcome with **no specs at all** → "no work serves this yet — `/ag-decompose <slug>`?"
   - an open Outcome whose serving specs are **all shipped or abandoned** → "all serving work is done — is the measure met? `/ag-outcome achieve <slug>`"
   - an open Outcome that is **unranked** → "unranked — `/ag-prioritise`"
   - any **orphaned** specs → name them; the fix is `ag-store spec_write <slug> --set serves=<real-slug>` or clearing it.

4. End with one line: the count of open Outcomes, ready specs, and blocked specs. Do not summarise, triage, or recommend beyond the flags above.
