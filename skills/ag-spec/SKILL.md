---
name: ag-spec
description: Write a Ready spec for a trivial change straight from a one-line idea, skipping the full shaping interview. Use only for small, certain work; non-trivial items should go through /ag-shape. Trigger phrases include "/ag-spec", "spec this", "quick spec", "write a spec for".
allowed-tools: Bash, Read, Write, Edit
arguments: [idea]
---

# ag-spec

A shortcut for **trivial, high-certainty** work: write a Ready spec directly from an idea without the back-and-forth of `/ag-shape`. If the change is non-trivial, or you find yourself guessing at acceptance criteria or scope, stop and use `/ag-shape` instead — shaping is where uncertainty gets resolved cheaply.

## Apply this project's playbook

Before doing anything else, check for `.agentile/spec.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Steps

1. The idea is `$idea` (or `$ARGUMENTS`). If empty, ask for it once.
2. Read `.agentile/spec-template.md` (the output structure) and `.agentile/config.md` for the **Agentile directory** (default `docs/agentile/`); specs live in `<dir>/specs/`. (If the project still uses the old `Specs directory:` key or a root-level `specs/` with no `Agentile directory` key, honour that and note `/ag-init` can migrate.) Skim `CLAUDE.md` for standing context, and `<dir>/brief.md` if present (for the project's outcomes and constraints, so the triage self-check has a reference).
3. **Self-check the triage.** Estimate Business Value × Technical Certainty. If Technical Certainty is not High, or the work touches more than a small, well-understood area, tell the user this should be shaped, and offer to run `/ag-shape` instead. Only continue for genuinely trivial work.
4. Write `<dir>/specs/<slug>.md` from the template, filling every field, including `outcome:` (the observable check that proves it worked). For a trivial spec, keep edge cases and scope tight and explicit. Set `route` (usually `foreground` or `background`), `business_value`, `technical_certainty`, and today's date.
5. Report the path and the next step (`/ag-plan <dir>/specs/<slug>.md`). Do not start building.
