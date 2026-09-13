---
name: ag-deploy
description: Release the shipped specs sitting on trunk — run the project's pre-deploy checks and its deploy gate, then record what went out. Deploy is batched and separate from ship (which merges one spec). Trigger phrases include "/ag-deploy", "cut a release", "deploy to production", "release what's on trunk", "what's undeployed".
allowed-tools: Bash, Read, Skill, AskUserQuestion
---

# ag-deploy

Ship and deploy are different things, and this skill is the second one.

**Ship** is per-spec: `/ag-loop` merges one spec to trunk and stamps
`shipped_at`. It happens many times a day and is reversible with a revert.

**Deploy** is per-release: the code on trunk reaches an environment where
someone outside the team can run it. It batches every spec shipped since the
last deploy, and it earns heavier checks than a merge does — the slow,
evidentiary ones you would never run on every commit.

Because deploy is batched and outward-facing, it is **never** part of the
per-spec loop. `/ag-loop` does not call this skill. A human runs it, or a
schedule does.

## Apply this project's playbook

Read `.agentile/deploy.md` (resolve `.agentile/` from the project root). If it
exists, honour it:

- `delegate_to: <skill>` — run this stage by invoking that skill instead of the
  baseline below.
- `also_run: [skill, ...]` — invoke those alongside the baseline.
- `human_checkpoint: false` — only then may this skill deploy without asking.
  **The default here is `true` even when the file is absent**, the opposite of
  every other stage: a deploy is outward-facing and often not cleanly
  reversible.
- Its prose body is this project's **pre-deploy checklist** — the named checks
  that must pass before the deploy gate runs. Treat each as mandatory.

If the file is absent, run the baseline below and say that no pre-deploy
checklist is configured (`/ag-customise deploy` writes one).

## Steps

1. **Establish what would go out.** Read the run log (`<Agentile
   directory>/runs.md`) for the most recent `event=deployed` line; every
   `event=shipped` line after it is in this batch. If there is no
   `event=deployed` line, say so — this is the first recorded deploy, so list
   the shipped specs and let the user confirm the starting point rather than
   claiming the whole history is undeployed.

   Cross-check against the store (`ag-store spec_list --status shipped ...`) so
   a spec shipped outside the loop is not silently missed.

2. **Refuse to deploy something you cannot name.** Stop and report, rather than
   continuing, when:
   - the working tree is dirty (`git status --porcelain` is non-empty) — deploy
     what is committed, never what is merely on disk;
   - the current branch is not the trunk in `gates.json`'s
     `protected_branches`, or trunk is behind its remote;
   - a spec is `in_progress` and its branch is already merged — that is work
     that shipped without being recorded, and the batch list would be wrong.

3. **Run the pre-deploy checklist** from `.agentile/deploy.md`, in the order
   written. These are the project's own heavy checks — a phase sign-off, a
   determinism gate, a full end-to-end campaign, a security review. Run each,
   and report each by name with PASS/FAIL. **Any failure stops the deploy**;
   never continue past one because the rest looks green.

4. **Run the standard gates** from `.agentile/gates.json` — `lint`, `test`, and
   `build` where each is non-blank — unless the pre-deploy checklist already
   ran a superset of them (say which, rather than running them twice).

5. **Confirm with the human.** Unless the playbook sets `human_checkpoint:
   false`, present the batch and wait for explicit approval:

   ```
   Deploy <n> shipped specs to <target>:
     <slug> — <title>
     ...
   Pre-deploy: <check> PASS · <check> PASS
   Gates:      lint PASS · test PASS
   Approve deploy?
   ```

   Do not proceed on anything short of a clear yes.

6. **Run the deploy gate** — the `deploy` command in `.agentile/gates.json`. If
   it is blank, say so plainly: the checks ran and passed, but nothing was
   deployed because the project has not configured a deploy command. Do not
   invent one, and do not substitute a build or a push you found in a Makefile.

7. **Record it.** Append one line to `<Agentile directory>/runs.md`:

   ```
   ts=<ISO8601> event=deployed runner=<identity> detail=<n> specs target=<target> ref=<git sha>
   ```

   The sha is what makes this auditable: the next deploy's batch is computed
   from this line, and a rollback needs to know exactly what went out. Commit
   `runs.md` as part of the deploy.

8. **Report** what went out, the sha, and — if the project's specs name an
   `outcome` — the outcomes now worth watching. Shipping records that work
   landed; deploying is when its outcome becomes observable, so name the ones
   this batch just put in front of users.

## When something fails after deploy

Do not improvise a fix forward. Report the failing signal, name the sha and the
previous deployed sha from `runs.md`, and let the human choose between revert
and roll forward. Record whichever happens as a new `event=deployed` line — the
log is a history of what was live, not a list of successes.
