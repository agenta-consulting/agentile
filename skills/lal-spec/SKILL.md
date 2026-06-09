---
name: lal-spec
description: Write a Ready spec for a trivial change straight from a one-line idea, skipping the full shaping interview. Use only for small, certain work; non-trivial items should go through /lal-shape. Trigger phrases include "/lal-spec", "spec this", "quick spec", "write a spec for".
allowed-tools: Bash, Read, Write, Edit
---

# lal-spec

A shortcut for **trivial, high-certainty** work: write a Ready spec directly from an idea without the back-and-forth of `/lal-shape`. If the change is non-trivial, or you find yourself guessing at acceptance criteria or scope, stop and use `/lal-shape` instead — shaping is where uncertainty gets resolved cheaply.

## Steps

1. The idea is `$ARGUMENTS`. If empty, ask for it once.
2. Read `.lal/spec-template.md` (the output structure) and `.lal/config.md` (the specs path). Skim `CLAUDE.md` for standing context.
3. **Self-check the triage.** Estimate Business Value × Technical Certainty. If Technical Certainty is not High, or the work touches more than a small, well-understood area, tell the user this should be shaped, and offer to run `/lal-shape` instead. Only continue for genuinely trivial work.
4. Write `specs/<slug>.md` from the template, filling every field. For a trivial spec, keep edge cases and scope tight and explicit. Set `route` (usually `foreground` or `background`), `business_value`, `technical_certainty`, and today's date.
5. Report the path and the next step (`/lal-plan specs/<slug>.md`). Do not start building.
