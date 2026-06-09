---
name: ag-prioritise
description: Order the ready Agentile specs by this project's scheme, writing a priority onto each. Only sets the priority field. Trigger phrases include "/ag-prioritise", "prioritise the backlog", "order the ready work", "re-rank specs".
allowed-tools: Bash, Read, Edit
---

# ag-prioritise

Order every ready spec by the project's priority scheme, writing a `priority` integer onto each. No other fields are touched.

## Apply this project's playbook

Before doing anything else, check for `.agentile/prioritise.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Baseline steps

1. Read `.agentile/prioritise.md` for the ranking scheme and `wip_limit`. If the file is absent, use the default scheme (Business Value × Technical Certainty) and no WIP limit.

2. Read the specs directory from `.agentile/config.md` (default `specs/`).

3. List all spec files in that directory whose frontmatter contains `status: ready`.

4. Rank the ready specs per the project scheme. The default ranking is **Business Value × Technical Certainty** — multiply each spec's `business_value` by its `technical_certainty` and sort descending (high product first). Where scores are equal, break ties alphabetically by slug.

5. Write a `priority:` integer into each ready spec's frontmatter via Edit, assigning `1` to the highest-ranked spec and incrementing by one for each subsequent spec. Touch **only** the `priority` field — leave all other frontmatter unchanged.

6. Report the ordered list in a table: rank, slug, business_value, technical_certainty, and computed score. Note any specs that were missing `business_value` or `technical_certainty` values (treat missing as `0`).
