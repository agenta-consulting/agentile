---
name: ag-wip
description: Show Agentile work in progress — which specs are claimed, by which session/label, since when, and the exact command to resume each. Read-only. Trigger phrases include "/ag-wip", "what's in progress", "what's being worked on", "show work in flight".
allowed-tools: Bash, Read
---

# ag-wip

Display all specs currently in flight — their owner, label, age, and how to resume each. Makes no changes.

## Steps

1. Read the specs directory from `.agentile/config.md` (default `specs/`).

2. List all spec files in that directory whose frontmatter contains `status: in_progress`.

3. For each in-progress spec, print:

   ```
   <slug>  in_progress  <label if present, otherwise claimed_by>  (claimed <relative age>)
     → resume: claude --resume <claimed_by>
   ```

   Compute the relative age from `claimed_at` (e.g. "2 h ago", "3 d ago").

4. Flag any spec whose `claimed_at` timestamp is older than approximately 24 hours with a warning:

   > Likely stale — reclaim by setting `status: ready` and clearing `claimed_by`, `claimed_at`, and `label`.

5. Make no changes to any file.
