---
name: ag-inbox
description: List the current Agentile inbox stubs and nothing else, so you can see what needs shaping at a glance. Read-only. Trigger phrases include "/ag-inbox", "show the inbox", "what's in the inbox", "what needs shaping", "list stubs".
allowed-tools: Read
---

# ag-inbox

Show the stubs currently awaiting shaping. This is a deliberate review surface, not part of the build loop — it never blocks anything.

Current inbox (default path; the steps below resolve the real path for non-default layouts):

!`cat docs/agentile/inbox.md 2>/dev/null || echo "(nothing at the default path — this project may use a custom Agentile directory; Step 1 resolves it)"`

## Steps

1. Resolve the inbox path: read **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`); the inbox is `<dir>/inbox.md`. If the project still has the old `Inbox:` key or a root-level `inbox.md` and no `Agentile directory` key, honour that path and note that `/ag-init` can migrate the layout.
2. Read the inbox file. If it does not exist, tell the user to run `/ag-init` first.
3. List the open stubs (lines beginning `- [ ]`), numbered, exactly as written — including any capture dates. Do not reword, triage, or summarise them.
4. End with a one-line count and a gentle nudge: e.g. "5 stubs awaiting shaping. Run `/ag-shape <number>` to shape one." If a stub has sat unshaped for weeks, you may flag it as a candidate to drop — the Inbox should not become a graveyard.

Do nothing else. Do not start shaping or working.
