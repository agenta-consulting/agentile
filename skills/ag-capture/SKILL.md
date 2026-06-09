---
name: ag-capture
description: Append a one-line stub to the Agentile inbox with today's date. Instant capture — no questions, no work, safe to run mid-build. Trigger phrases include "/ag-capture", "capture this idea", "drop a stub", "add to the inbox", "note this down for later".
allowed-tools: Bash, Read, Edit
---

# ag-capture

Drop an idea into the Inbox as a **stub** in one move. A stub is a placeholder that is *not yet ready to build*. The whole point is that capture costs less than holding the idea in your head, so this skill never interrupts you.

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
