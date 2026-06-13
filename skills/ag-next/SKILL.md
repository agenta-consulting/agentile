---
name: ag-next
description: Pull the next piece of Agentile work — atomically claim the highest-priority unclaimed ready spec, stamp it with this session so it is resumable, and report it. Safe for concurrent loops. Trigger phrases include "/ag-next", "what's next", "pull the next item", "give me the next thing to work on".
allowed-tools: Bash, Read
---

# ag-next

Atomically claim the highest-priority unclaimed ready spec for this session and report it. Safe for concurrent loops — the lock in `ag-claim` prevents double-claiming.

## Apply this project's playbook

Before doing anything else, check for `.agentile/next.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Baseline steps

1. This session's id is `${CLAUDE_SESSION_ID}` — Claude Code substitutes the real session id here when the skill runs. Use it directly as the claim's `claimed_by` handle; it is what `claude --resume <id>` needs. (If for any reason it is empty, fall back to `echo "$(whoami)@$(hostname -s)/$(date +%s)"` and note that this fallback is not a resume handle.)

2. Resolve the specs directory: read **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`); the specs dir is `<dir>/specs/`. (If the project still uses the old `Specs directory:` key or a root-level `specs/` with no `Agentile directory` key, honour that path and note `/ag-init` can migrate.) Read `wip_limit` from `.agentile/prioritise.md` (default: unlimited if the file or field is absent).

3. The claim helper ships in this plugin's `bin/`, which is on your PATH while the plugin is enabled — call it as the bare command `ag-claim`. (Fallback only if it is not found: `"${CLAUDE_PLUGIN_ROOT}/bin/ag-claim"`.)

4. Run the helper:

   ```
   ag-claim "<specs-dir>" "${CLAUDE_SESSION_ID}" "<optional label from $ARGUMENTS>" "<wip_limit>"
   ```

5. Interpret the single line of output:

   - **A file path** — the claim succeeded. Report: claimed `<path>` as session `<session-id>`. Tell the user that to resume this loop later they can run `claude --resume <session-id>`. The path is the spec's `.md` file — for a directory spec, its `SPEC.md`; the spec's working set (`plan.md`, supporting files) lives in the same directory.
   - **`NONE`** — no ready work is available. Suggest running `/ag-shape` to shape inbox items or `/ag-prioritise` to rank the backlog.
   - **`WIP_FULL`** — the WIP limit (`<wip_limit>`) is already reached. Suggest shipping or releasing something first, then checking `/ag-wip` to see what is in flight.
   - **`BLOCKED`** — all prioritised ready specs are waiting on unshipped dependencies; no work can be claimed right now. Suggest running `/ag-prioritise` to see which items are blocked and what each is waiting on.
   - **`UNPRIORITISED`** — there is shaped work in the backlog but none of it has been prioritised yet (no `NNNN-` filename prefix). Suggest running `/ag-prioritise` to rank and number the ready specs so they can be claimed.

6. **v1 behaviour: claim and report only — do NOT auto-start the build cycle.** Tell the user they can now run `/ag-plan <path>` to begin planning the claimed spec.
