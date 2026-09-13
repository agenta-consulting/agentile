---
name: ag-capture
description: Append a one-line stub to the Agentile inbox with today's date. Instant capture — no questions, no work, safe to run mid-build. Trigger phrases include "/ag-capture", "capture this idea", "drop a stub", "add to the inbox", "note this down for later".
allowed-tools: Bash, Read
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
2. Resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`). If the project still has the old `Inbox:` key or a root-level `inbox.md` and no `Agentile directory` key, honour that path for this run and tell the user `/ag-init` can migrate the layout.
3. Resolve which store answers this project: read `store:` from `.agentile/store.md` if it exists, default `local` if it does not.
4. Resolve who is capturing it: run `ag-store whoami` (bare command — it ships on `PATH` while the plugin is enabled; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store" whoami`). This is how a team-mode Inbox knows *who added it* — for the `local` store this is informational only (git blame already gives attribution for free); for a shared store it stamps the record.
5. Add the stub:

   ```
   ag-store inbox_add "<stub text>" --by "<whoami output>" --dir "<Agentile directory>" --store "<store>"
   ```

   A non-zero exit means the inbox doesn't exist yet (project not initialised, or a path mismatch) — tell the user to run `/ag-init` first rather than working around it.
6. Reply with one short line confirming the stub was captured (and by whom, if the store records it). Nothing more.
