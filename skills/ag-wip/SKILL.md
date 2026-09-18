---
name: ag-wip
description: Show Agentile work in progress — which specs are claimed, by which session/label, since when, and how to resume or answer each. Read-only. Trigger phrases include "/ag-wip", "what's in progress", "what's being worked on", "show work in flight".
allowed-tools: Bash, Read
---

# ag-wip

Display all specs currently in flight — their owner, label, age, and how to resume each. Makes no changes.

## Steps

1. Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`). (If the project still uses the old `Specs directory:` key or a root-level `specs/` with no `Agentile directory` key, honour that path and note `/ag-init` can migrate.) Resolve which store answers this project: read `store:` from `.agentile/store.md` if it exists, default `local`.

2. Run `ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) and parse the JSON array.

   Also run `ag-store run_list --status active --dir "<dir>" --store "<store>"` — the runs still live, on any machine. A spec listed `in_progress` with **no** active run is a claim whose worker is gone: say so, and point at `ag-store release` rather than leaving it looking busy.

3. For each in-progress spec, classify `claimed_by`: a Claude session id (a UUID), a factory worker (starts with `factory/`), or another named runner (anything else, e.g. `ag-run@host/12345`, set via `AGENTILE_RUNNER_ID`). Then run `ag-store checkpoint_list "<slug>" --dir "<dir>" --store "<store>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"` — **not** the deprecated `ag-checkpoint` script, which only reads local files and silently returns `[]` on a non-`local` store) and note the newest checkpoint's `reason` and `status` — the list is oldest first, so the newest is the **last** element of its output. Every branch below ends with the same trailing `[…]` column reporting that checkpoint; when the list comes back empty, the column reads `[running]`. Print:

   ```
   <slug>  in_progress  <label if present, otherwise claimed_by>  (claimed <relative age>)  [waiting: <reason> since <asked_at> | answered: <reason>]
     → resume: claude --resume <claimed_by>
   ```

   for a session id;

   ```
   <slug>  in_progress  factory worker <claimed_by>  (claimed <relative age>)  [waiting: <reason> | running]
     → managed by the Agentile Factory — answer it on the console, or `ag-store checkpoint_answer <checkpoint-id> --dir "<dir>" --store "<store>"`
   ```

   for a factory worker; and

   ```
   <slug>  in_progress  <label if present, otherwise claimed_by>  (claimed <relative age>)  [waiting: <reason> since <asked_at> | answered: <reason>]
     → not a session — claimed by runner "<claimed_by>". Re-run its driver with the
       same AGENTILE_RUNNER_ID to continue it, or export AGENTILE_RUNNER_ID=<claimed_by>
       and run /ag-build interactively to pick it up.
   ```

   for any other named runner. Compute the relative age from `claimed_at` (e.g. "2 h ago", "3 d ago").

4. For each in-progress spec, run `ag-store flow "<slug>" --dir "<dir>" --store "<store>"` and print the split beneath it:

   ```
     elapsed <cycle_seconds>  =  agent <agent_seconds>  +  waiting on a human <human_wait_seconds>
   ```

   Format the durations readably (e.g. "3h 12m"). When `open_checkpoint_count`
   is above zero, name the open checkpoint's `reason` and `asked_by` — that is
   what the loop is waiting for, and its wait is still counting.

5. Flag any spec whose `claimed_at` timestamp is older than approximately 24 hours with a warning:

   > Likely stale — **release the claim** (`ag-store release <slug> --dir "<dir>" --store "<store>"`) to put it back in the queue, or resume it with the command above. Releasing a claim is not abandoning: the spec stays live.

6. Make no changes to any file.
