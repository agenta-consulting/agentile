---
name: ag-inbox
description: List the current Agentile inbox stubs and nothing else, so you can see what needs shaping at a glance. Read-only. Trigger phrases include "/ag-inbox", "show the inbox", "what's in the inbox", "what needs shaping", "list stubs".
allowed-tools: Bash, Read
---

# ag-inbox

Show the stubs currently awaiting shaping. This is a deliberate review surface, not part of the build loop — it never blocks anything.

## Steps

1. Resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`). If the project still has the old `Inbox:` key or a root-level `inbox.md` and no `Agentile directory` key, honour that path and note that `/ag-init` can migrate the layout.
2. Resolve which store answers this project: read `store:` from `.agentile/store.md` if it exists, default `local`.
3. List the stubs: `ag-store inbox_list --dir "<Agentile directory>" --store "<store>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). A non-zero exit means the inbox doesn't exist — tell the user to run `/ag-init` first. The output is a JSON array of `{id, text, captured_at, captured_by}` — parse it directly.
4. Present each stub numbered by its `id`, exactly as captured — including its capture date, and its `captured_by` when the store records one (a shared store; `local` leaves this blank). Do not reword, triage, or summarise them.
5. End with a one-line count and a gentle nudge: e.g. "5 stubs awaiting shaping. Run `/ag-shape <id>` to shape one." If a stub has sat unshaped for weeks, you may flag it as a candidate to drop — the Inbox should not become a graveyard.

Do nothing else. Do not start shaping or working.
