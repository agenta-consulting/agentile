---
name: ag-wip
description: Show Agentile work in progress — which specs are claimed, by which session/label, since when, and the exact command to resume each. Read-only. Trigger phrases include "/ag-wip", "what's in progress", "what's being worked on", "show work in flight".
allowed-tools: Bash, Read
---

# ag-wip

Display all specs currently in flight — their owner, label, age, and how to resume each. Makes no changes.

## Steps

1. Resolve the specs directory: read **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`); the specs dir is `<dir>/specs/`. (If the project still uses the old `Specs directory:` key or a root-level `specs/` with no `Agentile directory` key, honour that path and note `/ag-init` can migrate.)

2. List the specs at the top level of that directory — flat `*.md` files and `*/SPEC.md` directory specs (not the `done/` or `abandoned/` subdirectories) — whose frontmatter contains `status: in_progress`.

3. For each in-progress spec, print:

   ```
   <slug>  in_progress  <label if present, otherwise claimed_by>  (claimed <relative age>)
     → resume: claude --resume <claimed_by>
   ```

   Compute the relative age from `claimed_at` (e.g. "2 h ago", "3 d ago").

4. Flag any spec whose `claimed_at` timestamp is older than approximately 24 hours with a warning:

   > Likely stale — **release the claim** (set `status: ready` and clear `claimed_by`, `claimed_at`, and `label`) to put it back in the queue, or resume it with the command above. Releasing a claim is not abandoning: the spec stays live.

5. Make no changes to any file.
