---
name: ag-customise
description: Build out an Agentile stage playbook conversationally — interview the user about how a given loop stage should run in this project, then write/update .agentile/<stage>.md. Trigger phrases include "/ag-customise", "customise a stage", "configure the build/verify/... stage", "set up worktree-workflow for build".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
---

# ag-customise

Customisation is how a project makes Agentile its own. Interview the user about a single loop stage, then write or update its playbook so *this project's loop* reflects how *this* project actually works.

## Step 1 — Resolve the stage

Read `$ARGUMENTS` for the stage name. Valid stages are:

- `build`, `verify`, `prioritise`, `shape`, `plan`, `next`, `ship`, `learn`, `capture`, `spec`

If no stage was provided, ask the user which stage to customise and offer that list. Accept the answer before continuing.

## Step 2 — Load existing context

- If `.agentile/<stage>.md` already exists, read it so you can show the user what is currently set and offer to update rather than overwrite.
- Read `.agentile/playbooks.md` to remind yourself of the directive vocabulary (`delegate_to`, `also_run`, `human_checkpoint`) and the prose convention.

For the build and verify stages you can also **override the agent itself** —
`/ag-customise` offers to scaffold `.claude/agents/ag-builder.md` (or
`ag-reviewer.md`) seeded from the plugin's definition, which takes precedence
over the bundled agent. Use this to change an agent's model, tools, or prompt;
use a `.agentile/<stage>.md` playbook to change how the *stage* runs around the
agent.

## Step 3 — Interview

Briefly describe what the stage does by default (one or two sentences), then ask the user about each directive in turn. Ask **one or two questions at a time**; use `AskUserQuestion` where choices are discrete.

Cover these in order:

1. **Delegation** — should this stage hand off entirely to a skill instead of running the baseline? If yes, which skill? Offer plausible candidates based on the stage (for example: `worktree-workflow` for `build`, `verify`, or `ship`; `ag-spec` for `spec`; the user may name any skill). This sets `delegate_to`.

2. **Human checkpoint** — should the stage pause and require an explicit "approved" from a human before handing off to the next stage? This sets `human_checkpoint: true`. Default is no.

3. **Extra skills** — any additional skills that should run alongside the baseline? (These run in addition to, not instead of, normal behaviour.) This sets `also_run`. The user may list zero or more skill names.

4. **Stage policy** — what is this project's definition or policy for this stage? Prompt for the prose body: conventions, constraints, acceptance standards, or anything the running agent should know. This becomes the prose below the frontmatter. It is fine to leave this blank.

## Step 4 — Write the playbook

Write `.agentile/<stage>.md`, creating the file if it does not exist. Structure it as:

- A YAML frontmatter block (between `---` markers) containing only the directives that were set — omit any key that was left blank or defaulted to no.
- Followed by the prose body (if any).

If frontmatter would be empty, omit it entirely and write only prose (or a brief note that defaults apply).

## Step 5 — Report

Confirm the file path written, list the directives that were set, and note that the customisation takes effect the next time that stage runs. If no directives were set and no prose was added, tell the user the file was written but the stage will still use baseline behaviour — they can run `/ag-customise <stage>` again to add directives later.
