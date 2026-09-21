---
name: ag-next
description: Pull the next piece of Agentile work — atomically claim the highest-priority unclaimed ready spec, stamp it with this session so it is resumable, and report it. Safe for concurrent loops. Trigger phrases include "/ag-next", "what's next", "pull the next item", "give me the next thing to work on".
allowed-tools: Bash, Read
---

# ag-next

Atomically claim the highest-priority unclaimed ready spec for this session and report it. Safe for concurrent loops — the store claims in one transaction, so two sessions can never take the same spec.

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

1. Resolve the claim identity: use `${AGENTILE_RUNNER_ID}` if it is set, otherwise `${CLAUDE_SESSION_ID}` — Claude Code substitutes the real session id here when the skill runs. `AGENTILE_RUNNER_ID` lets an unattended driver (e.g. `bin/ag-run`) claim under a stable name of its own rather than a session id, so a fresh headless process per item does not orphan the previous one's claim. Use whichever value resolves directly as the claim's `claimed_by` handle. When it came from `CLAUDE_SESSION_ID`, it is also a `claude --resume <id>` handle; when it came from `AGENTILE_RUNNER_ID`, it is not a session and does not resume that way — see `/ag-wip`. (If both are empty, fall back to `echo "$(whoami)@$(hostname -s)/$(date +%s)"` and note that this fallback is not a resume handle either.)

2. Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Read `wip_limit` from `.agentile/prioritise.md`.

3. If `.agentile/prioritise.md` sets a `wip_limit`, pass it as the third positional to `claim`:

   ```
   ag-store claim "<claim-identity from step 1>" "<optional label from $ARGUMENTS>" "<wip_limit>"
   ```

   Otherwise, omit the positional entirely and let the app apply the project's own `wip_limit`:

   ```
   ag-store claim "<claim-identity from step 1>" "<optional label from $ARGUMENTS>"
   ```

   (Passing `0` explicitly means unlimited; only use the first form with `0` if `.agentile/prioritise.md` says unlimited outright — never pass `0` as a default.)

4. Parse the JSON string result. On success it is the claimed spec's **slug** — what every other `ag-store` op's `<slug>` argument expects, and what `/ag-plan` expects. The store has also opened a run for it. Report: claimed `<slug>` as `<claim-identity>`. If the identity is `${CLAUDE_SESSION_ID}`, tell the user that to resume this loop later they can run `claude --resume <claim-identity>`; if it is `${AGENTILE_RUNNER_ID}`, say instead that it is a named runner, not a session, and point at `/ag-wip` for how to continue it.

   Otherwise:
   - **`NONE`** — no ready work is available. Suggest running `/ag-shape` to shape inbox items or `/ag-prioritise` to rank the backlog.
   - **`WIP_FULL`** — the WIP limit (`<wip_limit>`) is already reached. Suggest shipping or releasing something first, then checking `/ag-wip` to see what is in flight.
   - **`BLOCKED`** — all prioritised ready specs are waiting on unshipped dependencies; no work can be claimed right now. Suggest running `/ag-prioritise` to see which items are blocked and what each is waiting on.
   - **`UNPRIORITISED`** — there is shaped work in the backlog but none of it has been prioritised yet (no rank set). Suggest running `/ag-prioritise` to rank the ready specs so they can be claimed.

5. **v1 behaviour: claim and report only — do NOT auto-start the build cycle.** Tell the user they can now run `/ag-plan <slug>` to begin planning the claimed spec.
