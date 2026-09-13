---
human_checkpoint: true   # set false ONLY for a deploy you trust unattended
---

# Deploy — this project's pre-deploy checklist

`/ag-deploy` reads this file, runs everything listed below **in order**, and
stops on the first failure. Then it runs the `deploy` command from
`.agentile/gates.json`.

Deploy is not ship. `/ag-loop` ships specs one at a time (merge to trunk,
`shipped_at` stamped); this stage batches everything shipped since the last
recorded deploy and puts it somewhere a user can reach. So the checks here are
the **slow, evidentiary** ones — the kind you would never run on every merge,
and exactly the kind a merge-time gate is too fast to include.

## Pre-deploy checks

List each as a named check with the exact command or skill that runs it. Delete
these examples and write the real ones.

- **Full test suite** — `make test-e2e` (the per-merge gate runs unit tests
  only).
- **Phase or release sign-off** — `/verify-phase <phase>`, or whatever proves
  the release's requirements are covered.
- **Security review** — `/security-review` over the range since the last
  deployed sha.

## What blocks a deploy

`/ag-deploy` already refuses a dirty tree, a non-trunk branch, and a trunk
behind its remote. Add anything else that must be true here — an open incident,
a freeze window, a migration that has to run first.

## Rollback

Write down how to undo this deploy, and who decides. `/ag-deploy` records the
deployed sha in `runs.md` precisely so the previous one is always recoverable —
but the command to go back is project-specific, so put it here.
