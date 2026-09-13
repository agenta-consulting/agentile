---
name: ag-version
description: Report the installed Agentile version, and whether the running copy matches this repo. Read-only. Trigger phrases include "/ag-version", "what version of Agentile", "agentile version", "which Agentile is installed".
allowed-tools: Bash, Read
---

# ag-version

Report which Agentile is actually running. Makes no changes, asks nothing.

There are two versions in play and they can disagree: the **running** plugin is
a snapshot Claude Code installed, while the **source** repo may have moved on.
Saying so is the whole point of this skill — a rule that was changed in the
source but is not in the snapshot does not apply to the current session.

## Steps

1. Read the running plugin's version:

   ```
   cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
   ```

   Take the `version` field. If `CLAUDE_PLUGIN_ROOT` is unset (the skill is
   being read straight from a source checkout rather than an installed
   plugin), say so and read the manifest from the repo root instead.

2. Read the install record — which snapshot is registered, and where it points:

   ```
   cat ~/.claude/plugins/installed_plugins.json
   ```

   From the `agentile@agentile` entry take `version` (a git sha for a
   git/directory-sourced install), `installPath`, and `lastUpdated`. If
   `installPath` is a symlink, the install is **dev-linked**: source edits
   apply on the next session reload, so running and source versions cannot
   drift.

3. Compare against the source repo, when it is reachable. Find it from the
   marketplace record:

   ```
   cat ~/.claude/plugins/known_marketplaces.json
   ```

   Take the `agentile` marketplace's `installLocation`. If that path exists
   and is a git repo, read its `.claude-plugin/plugin.json` version and its
   `git log -1 --format=%h\ %s`, and note whether its HEAD sha differs from
   the installed `version` sha.

4. Report in three short lines, and nothing else:

   ```
   Agentile <version> (running)
   installed: <sha> · <lastUpdated date> · <dev-linked | snapshot>
   source:    <version> @ <sha> — <in sync | AHEAD: run `claude plugin update agentile@agentile` and restart>
   ```

   Drop the `source:` line entirely if the source repo is not on this machine.
   Never present the source version as the running one: if they differ, the
   running one is what this session's skills actually do.
