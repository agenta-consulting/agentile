---
url: https://agentile-projects.agentaconsulting.com
project: agentile
---

# Store

Where the Inbox, specs, Outcomes, checkpoints and runs live: **Agentile
Projects**, the web app. `url` is the app; `project` is this repo's project
slug there. `/ag-init` writes both; `AGENTILE_PROJECTS_URL` in the environment
overrides `url` (handy for a locally running app).

Credentials are never written here — `AGENTILE_PROJECTS_TOKEN` is an
environment variable only (create one under Settings → API tokens in the app),
set wherever you keep local secrets for tools you run, never in a tracked file.
Because `url` above *is* tracked, `bin/ag-store` refuses to send the token to
it unless it is https, or a loopback host (`localhost`, `127.0.0.1`, `::1`,
`*.localhost`), or `AGENTILE_PROJECTS_ALLOW_HTTP=1` is set — so a change to
this file can't silently redirect the token to a host you don't control.

The split is **events vs artefacts**:

- **Events go to the store** — stubs, specs, Outcomes, the brief, checkpoints
  and run events. A checkpoint is a question addressed to a human who may be at
  another machine or on the app's dashboard; the run log is the team's record
  of what ran where.
- **Artefacts stay in this repo** — `plan.md`, the `SPEC.md` snapshot,
  findings, supporting files (all under `docs/agentile/specs/<slug>/`) and
  ADRs (`docs/adr/`). They are things you review and amend, and they belong
  beside the diff they describe. `docs/agentile/brief.md` is a read-only copy
  of the store's brief, refreshed by every `/ag-*` skill; edit the brief in
  the app.
