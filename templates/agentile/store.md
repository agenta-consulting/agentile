---
url: https://agentile-projects.agentaconsulting.com
project: <project-slug>
---

# Store

Where the Inbox, specs, Outcomes, checkpoints and runs live. Any store that
implements the Agentile Store Protocol (`docs/store-protocol.md` in the plugin)
works; `url` says which one, `project` is this repo's project slug in it.
`/ag-init` writes both; `AGENTILE_STORE_URL` (or `AGENTILE_PROJECTS_URL`) in
the environment overrides `url`.

| `url` | Store |
|---|---|
| `https://…` | an HTTP store, e.g. Agentile Projects (the default above) |
| `http://localhost…`, `http://*.localhost…` | an HTTP store on this machine |
| `local` or `local:<dir>` | the bundled local store: one JSON file per project in `~/.local/share/agentile/stores/` (or `<dir>`), for one person on one machine |
| `exec:<command line>` | any program speaking the protocol's process binding |

Any other key here (e.g. `wip_limit: 2` for the local store) is passed to a
process store as configuration.

Credentials are never written here. An HTTP store's token is an environment
variable only, `AGENTILE_STORE_TOKEN` or `AGENTILE_PROJECTS_TOKEN` (create one
under Settings → API tokens in Agentile Projects). Because `url` above *is*
tracked, `bin/ag-store` refuses to send the token to it unless it is https, or
a loopback host (`localhost`, `127.0.0.1`, `::1`, `*.localhost`), or
`AGENTILE_STORE_ALLOW_HTTP=1` is set, so a change to this file can't silently
redirect the token to a host you don't control.

The split is **events vs artefacts**:

- **Events go to the store**: stubs, specs, Outcomes, the brief, checkpoints
  and run events. A checkpoint is a question addressed to a human who may be at
  another machine or on a dashboard; the run log is the record of what ran
  where.
- **Artefacts stay in this repo**: `plan.md`, the `SPEC.md` snapshot,
  findings, supporting files (all under `docs/agentile/specs/<slug>/`) and
  ADRs (`docs/adr/`). They are things you review and amend, and they belong
  beside the diff they describe. `docs/agentile/brief.md` is a read-only copy
  of the store's brief, refreshed by every `/ag-*` skill; edit the brief in
  the store.
