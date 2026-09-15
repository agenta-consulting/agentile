# Playbooks — customise any stage

Agentile reads a `.agentile/<stage>.md` "playbook" for each loop stage. Present →
it customises that stage; absent → the built-in behaviour. The filename is the
stage name: `shape.md`, `plan.md`, `prioritise.md`, `next.md`, `build.md`,
`verify.md`, `ship.md`, `deploy.md`, `learn.md`, `capture.md`, `spec.md`.

Each playbook is optional YAML frontmatter + prose:

    ---
    delegate_to: worktree-workflow   # run this stage by invoking that skill
    also_run: [other-skill]          # extra skills alongside the baseline
    human_checkpoint: true           # pause for human sign-off before handing off
    ---
    Prose: this project's policy / definition for the stage.

Build one out conversationally with `/ag-customise <stage>`.

Three playbooks also carry machine keys beyond the common three: `plan.md`
(`human_checkpoint: route`), `ship.md` (`human_checkpoint`) and `verify.md`
(`retry_limit`, `stop_on_gate_failure`). Together they are the whole of a
project's build policy; there is no separate loop config.

Design rule for any future config surface: **frontmatter keys are for the
machine** (deterministic, forward-compatible — unknown keys are ignored);
**prose is for judgement** (policy the agent weighs in context). Keep the two
separate, the way every playbook above does.
