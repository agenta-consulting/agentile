---
url: https://agentile-projects.agentaconsulting.com
project: <project-slug>
---

# Store

Where the Inbox, specs, Outcomes, checkpoints and runs live: **Agentile
Projects**, the web app. `url` is the app; `project` is this repo's project
slug there. `/ag-init` writes both; `AGENTILE_PROJECTS_URL` in the environment
overrides `url` (handy for a locally running app).

Credentials are never written here — `AGENTILE_PROJECTS_TOKEN` is an
environment variable only (create one under Settings → API tokens in the app),
set wherever you keep local secrets for tools you run, never in a tracked file.

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
