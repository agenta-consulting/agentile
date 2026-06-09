---
name: ag-capture
description: Append a one-line stub to the Agentile inbox with today's date. Instant capture — no questions, no work, safe to run mid-build. Trigger phrases include "/ag-capture", "capture this idea", "drop a stub", "add to the inbox", "note this down for later".
allowed-tools: Bash, Read, Edit
---

# ag-capture

Drop an idea into the Inbox as a **stub** in one move. A stub is a placeholder that is *not yet ready to build*. The whole point is that capture costs less than holding the idea in your head, so this skill never interrupts you.

## Apply this project's playbook

Before doing anything else, check for `.agentile/capture.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Rules

- **Do not ask follow-up questions.** Whatever the user gave you is the stub.
- **Do not start work, plan, or shape.** That is what `/ag-shape` is for.
- **Do not estimate, triage, or add acceptance criteria.** A stub is one line.

## Steps

1. The stub text is `$ARGUMENTS`. If it is empty, ask the user for the one line (this is the only question allowed) and stop until they answer.
2. Find the inbox path: read `.agentile/config.md` for the **Inbox** path under "## Paths". Default to `inbox.md` at repo root if `.agentile/config.md` is absent.
3. Get today's date with `date +%Y-%m-%d`.
4. Append a new line at the end of the file, under the `# Inbox` heading:

   ```
   - [ ] <stub text> — (captured <YYYY-MM-DD>)
   ```

   If the file does not exist yet, tell the user to run `/ag-init` first (do not silently create a bare inbox — the project may not be initialised).
5. Reply with one short line confirming the stub was captured. Nothing more.
