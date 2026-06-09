---
name: ag-inbox
description: List the current Agentile inbox stubs and nothing else, so you can see what needs shaping at a glance. Read-only. Trigger phrases include "/ag-inbox", "show the inbox", "what's in the inbox", "what needs shaping", "list stubs".
allowed-tools: Read
---

# ag-inbox

Show the stubs currently awaiting shaping. This is a deliberate review surface, not part of the build loop — it never blocks anything.

## Steps

1. Find the inbox path: read `.agentile/config.md` for the **Inbox** path under "## Paths". Default to `inbox.md` at repo root.
2. Read the inbox file. If it does not exist, tell the user to run `/ag-init` first.
3. List the open stubs (lines beginning `- [ ]`), numbered, exactly as written — including any capture dates. Do not reword, triage, or summarise them.
4. End with a one-line count and a gentle nudge: e.g. "5 stubs awaiting shaping. Run `/ag-shape <number>` to shape one." If a stub has sat unshaped for weeks, you may flag it as a candidate to drop — the Inbox should not become a graveyard.

Do nothing else. Do not start shaping or working.
