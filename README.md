# Agentile for Claude — the Claude Code plugin

*Agile, with agency.*

**Agentile** is a low-ceremony methodology for **1–5 person teams** who direct AI agents as their primary way of building software. It keeps the agile *spirit* — short loops, working software, respond to change — while dropping the ceremony small teams can't justify.

**Agentile for Claude** is the Claude Code implementation of that methodology (which was itself distilled from the *Lean Agentic Loop* synthesis). The full methodology is in [`methodology.md`](./methodology.md); this README is the operating manual for the plugin, and the normative description of its current behaviour — the design notes in `docs/` are historical snapshots.

## The loop

```
capture → shape → spec → (prioritise → next) → plan → build → verify → ship → [deploy] → learn
```

- **capture** — `/ag-capture <idea>` drops a one-line stub in `docs/agentile/inbox.md`. Instant, mid-build safe.
- **shape** — `/ag-shape` interviews a stub into a Ready spec, against your project's Definition of Ready.
- **spec** — shaped specs land in `docs/agentile/specs/`. `/ag-spec` writes one directly for trivial work.
- **plan** — `/ag-plan` promotes the spec to its directory form and writes `plan.md` beside `SPEC.md`: files to touch, approach, test strategy, risks. The plan is a file you review and amend, not a chat message.
- **build** — the `ag-builder` agent implements on a branch/worktree, running your gates.
- **verify** — the `ag-reviewer` agent critiques the diff with fresh context; gates + `/security-review` + a human read.
- **ship** — small, flagged, reversible merges to trunk. The spec keeps its claim timestamps and gains `shipped_at`, then moves — directory and all — to `specs/done/`.
- **deploy** — `/ag-deploy` releases the batch of specs shipped since the last deploy, running the project's pre-deploy checklist (`.agentile/deploy.md`) and then the `deploy` gate. In brackets because it is **not part of the per-spec loop**: `/ag-loop` never calls it, since a deploy batches many ships and runs on its own cadence.
- **learn** — `/ag-retro` compiles a flow digest and encodes lessons into `CLAUDE.md` and ADRs.

`prioritise` and `next` are the queue segment between a Ready spec and the work starting — ordering is editorial and human, pulling is transactional and atomic. They are stages like any other (each has a playbook), shown in brackets because they manage the queue rather than transform the work.

The whole backlog lives under one configurable **Agentile directory** (`docs/agentile/` by default, set in `.agentile/config.md`), with a fixed internal layout:

```
docs/agentile/
  inbox.md                 # captured stubs awaiting shaping
  specs/                   # active specs (ready / in_progress)
    0001-<slug>.md         # flat form — shaped, not yet planned
    0002-<slug>/           # directory form — created when planning starts
      SPEC.md              #   the spec (frontmatter + body)
      plan.md              #   the reviewable plan
      ...                  #   supporting files: designs, notes, findings
    done/                  # shipped specs (whole file or directory moves here)
    abandoned/             # dropped specs (via /ag-abandon), reason recorded
```

A spec starts as a flat file and is **promoted to a directory by the plan stage** (`git mv` to `NNNN-<slug>/SPEC.md`, `plan.md` written beside it). Flat and directory forms are both legal everywhere; a directory simply means the spec has a plan or supporting material. The rank prefix sits on the file or directory name, so `ls specs/` is still the queue.

## Fixed core vs. tailorable content

The plugin ships the **fixed implementation** — the skills, the agents, the hooks. You don't fork them. (The *methodology* they implement is tool-agnostic and lives in [`methodology.md`](./methodology.md).) Each project tailors its **content** through the `.agentile/` files that `/ag-init` scaffolds:

| File | What it controls |
|------|------------------|
| `.agentile/shape.md` | **What "Ready" means** — the questions a stub must answer before it's a spec. The prime tailoring surface. |
| `.agentile/config.md` | The **Agentile directory** (where the backlog lives, default `docs/agentile/`) and the Business Value × Technical Certainty triage routes. |
| `.agentile/gates.json` | The deterministic commands — format, lint, test, build, deploy — and protected branches. |
| `.agentile/store.md` | Where the Inbox and specs live — `local` (default, files+git) or `team` (a shared datastore, `airtable` by default). See "Stores" below. |
| `.agentile/spec-template.md` | The shape of a Ready spec. |
| `.agentile/plan-template.md` | The shape of a plan (`plan.md` in the spec's directory). |
| `.agentile/adr-template.md` | The shape of an ADR. |

The fixed skills *read* these at runtime, so content flexes while the loop's structure holds. To change what a shaped item must answer, edit one file — `.agentile/shape.md` — and every future `/ag-shape` asks accordingly.

### Customising any stage

Every loop stage can be further tailored through a **playbook**: a `.agentile/<stage>.md` file with optional YAML frontmatter and prose policy. The frontmatter keys are:

- `delegate_to: <skill>` — run this stage by invoking a named skill instead of the built-in behaviour.
- `also_run: [skill-a, skill-b]` — run additional skills alongside the built-in.
- `human_checkpoint: true` — pause for human sign-off before the stage completes.

Absent a playbook, the built-in baseline applies. Use `/ag-customise <stage>` to build one out conversationally — it interviews you about your project's needs and writes the file.

### Concurrent loops

Two skills govern the transition from ready work to in-flight work, and they are deliberately separate acts:

- **`/ag-prioritise`** is an interactive ordering session: it proposes a rank order (Business Value × Technical Certainty, with any `depends_on` constraints respected), you reorder it, and it renames the ready specs densely to `docs/agentile/specs/0001-<slug>.md`, `0002-…` — the number is the rank, visible in `ls`. An unprefixed spec (`specs/<slug>.md`) is shaped and Ready but not yet prioritised, so it is not claimable. The old `priority:` frontmatter field is retired; the filename prefix is the single source of truth. The `wip_limit` and weighting live in `.agentile/prioritise.md`. Run it whenever the ready queue changes.
- **`/ag-next`** is a transactional pull: it atomically claims the top unclaimed ready spec under a file lock (`bin/ag-claim`), stamps it with `status: in_progress`, `claimed_by: <session-id>`, and `claimed_at`, then reports what was claimed. Two loops running concurrently can never grab the same item. If all prioritised work is blocked waiting on dependencies, `/ag-next` reports `BLOCKED`; if shaped work exists but none of it has been prioritised yet, it reports `UNPRIORITISED` — run `/ag-prioritise` to proceed.
- **`/ag-wip`** lists every in-progress claim and prints the resume command (`claude --resume <session-id>`) for each. Stale claims are surfaced for human judgement — Agentile flags them but does not auto-reclaim; **releasing** a claim (back to `ready`, claim fields cleared) is distinct from **abandoning** the spec (dropped for good).
- **`/ag-abandon <slug>`** drops a spec that won't ship (failed review, withdrawn, not worth doing). It records the reason, walks the dependency chain with `bin/ag-dependents`, and offers — per dependent — to cascade the abandonment (with an auto-reason referencing the top-level one) or to keep it active and strip the now-dead link so it isn't silently `BLOCKED`. Abandoned specs move to `specs/abandoned/` with `status: abandoned`.

The session id is a resume handle, so a loop that was interrupted mid-cycle can be picked back up exactly where it stopped. That only holds for an interactive session, though: `claimed_by` is really a **claim identity**, resolved as `${AGENTILE_RUNNER_ID}` if set, else `${CLAUDE_SESSION_ID}`. The headless `bin/ag-run` driver (see "Running the loop" below) sets `AGENTILE_RUNNER_ID` to a stable name of its own, since it drains one item per fresh process and has no single session to resume. `/ag-wip` tells the two apart — a session id gets the `claude --resume` line, a named runner gets instructions for re-running it instead.

The claim lock is a **per-machine** file lock: it serialises concurrent loops on one machine. Across machines, the repository is the sync point — commit and push claim stamps promptly, and treat a pushed claim as authoritative. Agentile is single-repo by design; cross-repo or cross-team coordination is out of scope.

One sharp edge: the claim lock lives in the specs directory, so it only
serialises loops that **share one checkout**. Two loops in two different git
worktrees each have their own copy of the backlog and can claim the same spec.
Keep the **backlog in the main checkout** — claim and prioritise there; send
*builders* to worktrees (the `ag-builder` agent already isolates itself). Don't
run `/ag-next` or `/ag-loop` from inside a builder's worktree.

### Stores

The Inbox and every spec go through one **store**, selected by
`.agentile/store.md`'s `store:` key — absent file, or `store: local`, means
today's files+git behaviour, unchanged. Every skill that touches the backlog
calls `bin/ag-store <op> --dir <agentile-dir> --store <local|airtable>`
instead of reading/writing files directly, so the choice of backend is
invisible to the skill's own instructions.

- **`local`** (default) — files + git. Prioritising and claiming are
  atomic within one checkout (a `flock`-based lock); across machines it's a
  social contract (pull before you touch the queue, push right after), not
  a guarantee.
- **`airtable`** — the Inbox and every spec live in an Airtable base
  instead, fully decomposed into real fields (one per frontmatter key and
  one per spec-template body section — no blob field anywhere), so
  prioritising and claiming are visible live to everyone with the base
  open. `Rank` (a number field) replaces the `local` store's `NNNN-`
  filename prefix; `Claimed By (Member)`/`Captured By`/`Shaped By` are
  linked records into a `Members` table (attribution, not permissions —
  `ag-store whoami` resolves the acting person from `git config
  user.email`). Claim/rank are *not* atomic here (Airtable has no
  server-side conditional write) — see `templates/stores/airtable/README.md`
  for the honest concurrency notes and setup (a personal access token, a
  base, `ag-store provision`).

`/ag-init` asks Solo vs. Team once (Team walks through creating or attaching
a base, provisioning, and verifying with `doctor`); `/ag-customise store`
switches later, and offers to copy an existing local backlog into a
freshly-configured store on confirmation (nothing is deleted locally).
`plan.md`, supporting files, and ADRs stay in the repo in **both** modes —
only the Inbox and spec content move to a shared store. Adding a future
backend (Jira, Azure DevOps, …) is one new file under
`bin/ag-store-adapters/` implementing the same op contract, plus a
`templates/stores/<name>/` pack — no change to any skill.

### Spec dependencies

A spec can declare `depends_on: [slug, …]` in its frontmatter — a list of other specs (by slug) that must ship before this one can be claimed. Shaping asks about this by default, so dependencies are captured at the point of writing the spec rather than discovered mid-build. A spec isn't claimable until all its dependencies have shipped. When a spec ships it moves to `specs/done/`, keeping the active numbered list clean while remaining resolvable as a fulfilled dependency. (Abandoning a dependency, by contrast, leaves its dependents `BLOCKED` — `/ag-abandon` walks that chain so nothing is stranded silently.)

### When shipped work turns out wrong

A shipped spec that fails in production re-enters the loop as new work:
`/ag-capture` a stub referencing the original slug, shape it, ship the fix.
Optionally add `superseded_by: <new-slug>` to the original spec in `done/` so
the record shows what corrected it. Ship is flagged and reversible — turning
the flag off is part of the fix, not an afterthought. The original spec stays
in `done/` and still satisfies dependencies; abandonment is only for work that
never shipped.

### Running the loop

There are **three ways** to run it:

- **`/ag-loop`** — runs **one pass**. It loops through the *currently ready* backlog (claim → plan [pauses for `foreground`/`spike` specs] → build → verify → pause for your sign-off before ship → repeat, up to `max_iterations`), then **stops**. If nothing is ready, it stops straight away. Use it to clear a queue in one go.
- **`/loop /ag-loop`** — runs **continuously**, all in one long-lived session. It keeps going, **waits** when the backlog is empty, and starts on new work the moment it's shaped and prioritised. This is the "standing worker" you probably picture when you hear "loop".
- **`/ag-loop --once`** — processes **exactly one item**, then stops. Every stop or pause ends with a machine-readable `AG_LOOP: <shipped|paused|failed|idle> …` line. On its own it's a tighter version of a single pass; its main purpose is being driven from outside a session — see `bin/ag-run` below.

**Why the first two, and why doesn't `/ag-loop` just keep running?** Claude Code's loop primitive re-runs a command rather than holding an always-on process, so a single command can't sit idle waiting for new work; when it runs out of things to do, the turn ends. `/loop` is Claude Code's built-in "keep re-running this" primitive, so wrapping `/ag-loop` in it is what makes a loop that never stops. In short:

- `/ag-loop` → *work the queue now, then stop*
- `/loop /ag-loop` → *keep working as items appear*

Either way, **pause-before-ship is the default** (nothing merges without your approval), and the behaviour is configurable in `.agentile/loop.md`. Note the loop only has anything to do once there are **prioritised, dependency-satisfied** ready specs — so `/ag-shape` and `/ag-prioritise` something first.

Steering happens at two points. **Plan** is the cheap one: with the default `pause_at_plan: route`, the loop pauses after writing `plan.md` for any spec routed `foreground` or `spike` — you review or amend the plan file, reply "approved", and code gets written to the amended plan. High-certainty `background` specs run through without the plan pause. **Ship** is the final gate: nothing merges without your sign-off unless you loosen `pause_before_ship` deliberately.

**Keeping the loop's own context from filling up.** `/ag-loop` is an orchestrator, not a reader — it dispatches `/ag-plan`, `ag-builder`, and `ag-reviewer` to do the actual reading (spec body, `plan.md`, the diff) in their own context, and reads back only a short verdict (`BUILD: done|blocked`, `VERDICT: pass|fail`) plus a terse summary. It also keeps a durable **run log** (`docs/agentile/runs.md` by default, alongside the specs) of every claim, ship, pause, and failure, so a long drain's progress survives a context compaction rather than depending on a counter held only in that turn. For a genuinely long unattended drain — more items than one session should sit through — reach for **`bin/ag-run`**: it repeatedly runs `/ag-loop --once` in a fresh `claude -p` process per item, so each item gets a clean context rather than one session's context growing across the whole run. It stops (without error) the moment a pause needs a human, and prints how to pick that item back up. It takes an optional `--limit N`, and forwards anything after `--` to `claude` (e.g. `bin/ag-run -- --permission-mode acceptEdits`) — a headless run needs *some* permission story, since nothing can answer a prompt.

Running watch mode unattended has caveats — a watch loop is tied to the session
that started it and inherits that session's permission prompts, so it pauses at
the first tool call it isn't pre-authorised for. For long unattended runs, seed
`permissions.allow` (the `gates.json` commands are the obvious allowlist) and
consult Claude Code's own loop/scheduling docs for current session-lifetime and
expiry behaviour rather than assuming a loop runs forever.

## Glossary

- **stub** — a one-line idea in the inbox; not yet ready to build.
- **spec** — a shaped, Ready work item: a flat `NNNN-<slug>.md` or a `NNNN-<slug>/SPEC.md` directory.
- **Ready** — satisfies the Definition of Ready in `.agentile/shape.md`; `status: ready`.
- **prioritised** — carries an `NNNN-` rank prefix; an unprefixed spec is Ready but not claimable.
- **claimable** — prioritised, `status: ready`, unclaimed, all `depends_on` shipped, WIP limit not hit.
- **claimed** — pulled by `/ag-next`: `status: in_progress` plus `claimed_by`/`claimed_at`. `claimed_by` is a session id (a `claude --resume` handle) for an interactive claim, or a named runner (`AGENTILE_RUNNER_ID`) for a headless one.
- **run log** — `docs/agentile/runs.md`: an append-only history of what `/ag-loop` claimed, shipped, paused, or failed on — durable across a compaction or a fresh process.
- **release** — clear a claim and return the spec to `ready`; the spec stays live.
- **abandon** — drop a spec for good (`/ag-abandon`); it moves to `specs/abandoned/` with the reason.
- **shipped** — merged and stamped `shipped_at`; the spec moves to `specs/done/` and satisfies dependencies.
- **spike** — a spec whose deliverable is an answer (`findings.md` or an ADR), not shipping code.
- **route** — the triage outcome (`foreground` / `background` / `spike`); decides pairing vs delegation and where the loop pauses.
- **playbook** — `.agentile/<stage>.md`: frontmatter directives + prose policy that tailor a stage.
- **gate** — a deterministic command in `.agentile/gates.json` (format, lint, test, build, deploy). The first four gate a *change*; `deploy` gates a *release* and is run only by `/ag-deploy`.
- **ship vs deploy** — ship merges one spec to trunk; deploy releases every spec shipped since the last deploy. Different cadence, different gates, different blast radius.
- **drain / watch** — the runner's two modes: work the current queue then stop (`/ag-loop`) vs keep waiting for new work (`/loop /ag-loop`).

## Who does what

| Stage | The agent | The human | Default checkpoint |
|-------|-----------|-----------|--------------------|
| capture | appends the stub verbatim | has the idea | none — capture is instant |
| shape | interviews, triages, writes the spec | answers, decides the stub's fate | the conversation itself |
| spec (direct) | writes the trivial spec | confirms it really is trivial | none |
| prioritise | proposes an order | decides the order | interactive by design |
| next (pull) | claims atomically | — | none |
| plan | writes `plan.md` | reviews/amends `plan.md` | route-aware: `foreground`/`spike` pause |
| build | implements against the gates | available for questions | playbook opt-in |
| verify | fresh-context review + gates | reads the diff | playbook opt-in |
| ship | merges, stamps, archives | approves the ship | pause-before-ship (default on) |
| learn | compiles the digest, proposes edits | approves what gets encoded | approval of context edits |

## Install (in a project)

1. Add the marketplace and install the plugin:

   ```
   claude plugin marketplace add agenta-consulting/agentile
   claude plugin install agentile@agentile
   ```
2. Restart the session, then in your target project run `/ag-init` to scaffold `docs/agentile/` (inbox + specs tree), `.agentile/`, `docs/adr/`, and the `CLAUDE.md` standing-context section. It also asks Solo (files+git, the default) or Team (a shared store, Airtable by default — see "Stores" below) for the backlog. On a project that used the old root-level layout (`inbox.md`, `specs/`, `specs/archive/`), `/ag-init` detects it and offers to migrate everything into `docs/agentile/` with `git mv`. If you prefer to keep your root `CLAUDE.md` lean, the Agentile section can instead live in `.claude/rules/agentile.md` — `/ag-init` offers this; the content is identical, just independently updatable.
   Starting from an empty directory? Run `/ag-new-project` instead — it interviews you for the brief and the stack, records the stack as an ADR, writes a starter `CLAUDE.md`, runs the same scaffold with the gates pre-filled from the stack, then offers stage customisations and the first inbox stubs.
3. Start the loop: `/ag-capture`, `/ag-inbox`, `/ag-shape`, …

## Skills

`/ag-new-project`, `/ag-init`, `/ag-capture`, `/ag-inbox`, `/ag-shape`, `/ag-spec`, `/ag-plan`, `/ag-prioritise`, `/ag-next`, `/ag-wip`, `/ag-abandon`, `/ag-loop`, `/ag-deploy`, `/ag-customise`, `/ag-retro`, `/ag-version`.

## Agents (the "hats")

`ag-planner` (architecture & approach), `ag-builder` (implementation), `ag-reviewer` (verification & security). Each runs in its own context so the reviewer catches what the builder missed.

The plugin ships these three at the lowest precedence, so you can **override any
of them per project** without forking the plugin: create `.claude/agents/ag-builder.md`
(or `ag-planner`/`ag-reviewer`) and Claude Code uses yours instead — change the
model, tools, effort, or prompt. User-level `~/.claude/agents/` works the same
across projects. The loop's structure stays fixed; the agent definitions are
yours to tune.

## Hooks

Config-driven and **opt-in safe** — they read `.agentile/gates.json` and no-op when a command is blank, so installing the plugin never disrupts an unconfigured repo:

- **format-on-edit** (`PostToolUse`) — runs your formatter after each edit. If the `format` command contains `{file}`, the edited path is substituted.
- **test-gate** (`Stop` / `SubagentStop`) — blocks "done" until your `test` command passes. Also serializes its own runs per project directory (`File#flock`, no config needed), since parallel subagents can each fire this hook around the same moment — the collision that matters for a stack with shared file-based test state, like SQLite. For a `test`/`build` command that also needs protecting when run directly (by a human or `ag-builder`, outside this hook), wrap it in `gates.json` with `bin/ag-lock` — the same portable `File#flock` primitive `ag-claim` uses for its spec-claim lock; `/ag-init` offers to wire it in.

The hook scripts are Ruby (`hooks/*.rb`), so Ruby must be on `PATH`.

## Developing the plugin while it's installed

Claude Code freezes an installed plugin as a snapshot, so source edits aren't seen until you reinstall. Two layered modes over this one repo:

### Versioning

The plugin carries a pinned semver `version` in
[`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json), mirrored in the
marketplace entry beside it — `claude plugin tag` refuses a release where the
two disagree.

**Every change to the plugin bumps it, in the same commit as the change.** Patch
for a fix or a wording change, minor for a new skill, a new store field, or any
change to what a skill instructs. The version is how anyone — you on another
machine, a teammate, an agent reading a transcript — can tell which behaviour
they are actually running, and a change that ships without a bump is invisible:
two machines report the same version and behave differently.

Run `/ag-version` to see the running version, the installed snapshot, and
whether this repo is ahead of it.


- **Live (your machine):** run [`dev/ag-dev-link`](./dev/ag-dev-link) once (after a first `dev/ag-sync`) to symlink the install location to this repo. Edits to skills/agents/hooks then apply on the next session reload — no reinstall.
- **Snapshot (distribution / fresh machine / CI):** [`dev/ag-sync`](./dev/ag-sync) validates, registers the marketplace, and installs/updates. This is the path everyone else uses, so what you test equals what ships.

## The one rule

**First be agile, then agentic.** Agents multiply whatever loop you give them: a healthy loop gets faster, a broken one breaks faster. Get the trunk, the gates, and the written spec right first — agents make a good loop fast; they do not make a bad loop safe. (`/ag-init` ends with a readiness report so you can see where you stand.)
