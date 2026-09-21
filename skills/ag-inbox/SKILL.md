---
name: ag-inbox
description: List the current Agentile inbox stubs and nothing else, so you can see what needs shaping at a glance. Read-only. Trigger phrases include "/ag-inbox", "show the inbox", "what's in the inbox", "what needs shaping", "list stubs".
allowed-tools: Bash, Read
---

# ag-inbox

Show the stubs currently awaiting shaping. This is a deliberate review surface, not part of the build loop — it never blocks anything.

## Steps

1. Resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — exit 2 means the project is not linked: tell the user to run `/ag-init` and stop.
2. List the stubs: `ag-store inbox_list`. The output is a JSON array of `{id, title, type, text, captured_at, captured_by, serves, suggested_kind, duplicate_of}` — parse it directly.
3. Present each stub numbered by its `id`, exactly as captured — including its capture date and `captured_by`. Lead the line with its `title`, tag it with its `type` when that is anything but `feature`, note `serves` when set and flag `duplicate_of` when present, then the full text; the title is a label for scanning, never a replacement for the stub. Do not reword, triage, or summarise them.
4. End with a one-line count and a gentle nudge: e.g. "5 stubs awaiting shaping. Run `/ag-shape <id>` to shape one — or triage them in the app's Inbox." If a stub has sat unshaped for weeks, you may flag it as a candidate to drop.

Do nothing else. Do not start shaping or working.
