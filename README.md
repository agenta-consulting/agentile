# Agentile for Claude — the Claude Code plugin

*Agile, with agency.*

**Agentile** is a low-ceremony methodology for **1–5 person teams** who direct AI agents as their primary way of building software. It keeps the agile *spirit* — short loops, working software, respond to change — while dropping the ceremony small teams can't justify.

**Agentile for Claude** is the Claude Code implementation of that methodology (which was itself distilled from the *Lean Agentic Loop* synthesis). The full methodology is in [`methodology.md`](./methodology.md); this README is the operating manual for the plugin, and the normative description of its current behaviour — the design notes in `docs/` are historical snapshots.

## The loop

```
capture → shape → spec → (prioritise → next) → plan → build → verify → ship → [deploy] → learn
```

- **capture** — `/ag-capture <idea>` drops a one-line stub in the project's Inbox in Agentile Projects, tidied and classified by the store; one confirmation (or `--yes`). Mid-build safe.
- **shape** — `/ag-shape` interviews a stub into a Ready spec, against your project's Definition of Ready.
- **spec** — shaped specs are records in the store, ranked by a field. `/ag-spec` writes one directly for trivial work.
- **plan** — `/ag-plan` creates the spec's directory in the repo and writes `plan.md` beside a read-only `SPEC.md` snapshot: files to touch, approach, test strategy, risks. The plan is a file you review and amend, not a chat message.
- **build** — the `ag-builder` agent implements on a branch/worktree, running your gates.
- **verify** — the `ag-reviewer` agent critiques the diff with fresh context; gates + `/security-review` + a human read.
- **ship** — small, flagged, reversible merges to trunk. The spec keeps its claim timestamps and gains `shipped_at`, and its run closes.
- **deploy** — `/ag-deploy` releases the batch of specs shipped since the last deploy, running the project's pre-deploy checklist (`.agentile/deploy.md`) and then the `deploy` gate. In brackets because it is **not part of the per-spec loop**: `/ag-build` never calls it, since a deploy batches many ships and runs on its own cadence.
- **learn** — `/ag-retro` compiles a flow digest and encodes lessons into `CLAUDE.md` and ADRs.

`prioritise` and `next` are the queue segment between a Ready spec and the work starting — ordering is editorial and human, pulling is transactional and atomic. They are stages like any other (each has a playbook), shown in brackets because they manage the queue rather than transform the work.

The backlog lives in **Agentile Projects** (`.agentile/store.md` links a repo to its project; see "Stores" below). What stays in the repo, under one configurable **Agentile directory** (`docs/agentile/` by default, set in `.agentile/config.md`), is the code-adjacent material:

```
docs/agentile/
  brief.md                 # read-only copy of the store's brief, refreshed by every /ag-* skill
  specs/
    <slug>/                # created when planning starts
      SPEC.md              #   read-only snapshot of the spec (frontmatter + body)
      plan.md              #   the reviewable plan
      ...                  #   supporting files: designs, notes, findings
  deploys.md               # append-only deploy log
```

## Fixed core vs. tailorable content

The plugin ships the **fixed implementation** — the skills, the agents, the hooks. You don't fork them. (The *methodology* they implement is tool-agnostic and lives in [`methodology.md`](./methodology.md).) Each project tailors its **content** through the `.agentile/` files that `/ag-init` scaffolds:

| File | What it controls |
|------|------------------|
| `.agentile/shape.md` | **What "Ready" means** — the questions a stub must answer before it's a spec. The prime tailoring surface. |
| `.agentile/config.md` | The **Agentile directory** (where the backlog lives, default `docs/agentile/`) and the Business Value × Technical Certainty triage routes. |
| `.agentile/gates.json` | The deterministic commands — format, lint, test, build, deploy — and protected branches. |
| `.agentile/store.md` | The link to this repo's project in Agentile Projects (`url` + `project`). See "Stores" below. |
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

### Concurrent builds

Four skills govern the transition from ready work to in-flight work, and they are deliberately separate acts:

- **`/ag-prioritise`** is an interactive ordering session: it proposes a rank order (Business Value × Technical Certainty, with any `depends_on` constraints respected), you reorder it, and it writes a dense rank onto each ready spec in the store (`ag-store rank`). An unranked spec is shaped and Ready but not yet prioritised, so it is not claimable. The `wip_limit` (falling back to the project's own setting when unset) and weighting live in `.agentile/prioritise.md`. Run it whenever the ready queue changes.
- **`/ag-next`** is a transactional pull: it atomically claims the top unclaimed ready spec in one store transaction, stamps it with `status: in_progress`, `claimed_by: <session-id>`, and `claimed_at`, then reports what was claimed. Two builds running concurrently can never grab the same item. If all prioritised work is blocked waiting on dependencies, `/ag-next` reports `BLOCKED`; if shaped work exists but none of it has been prioritised yet, it reports `UNPRIORITISED` — run `/ag-prioritise` to proceed.
- **`/ag-wip`** lists every in-progress claim with how to resume or answer each — a `claude --resume` line for a session, the console for a factory worker, re-run instructions for another named runner — plus any open checkpoint. Stale claims are surfaced for human judgement — Agentile flags them but does not auto-reclaim; **releasing** a claim (back to `ready`, claim fields cleared) is distinct from **abandoning** the spec (dropped for good).
- **`/ag-abandon <slug>`** drops a spec that won't ship (failed review, withdrawn, not worth doing). It records the reason, walks the dependency chain (`ag-store dependents`), and offers — per dependent — to cascade the abandonment (each cascaded dependent gets the *same* reason string as the target, verbatim — there is no auto-generated prefix) or to keep it active and strip the now-dead link so it isn't silently `BLOCKED`. Abandoned specs get `status: abandoned` in the store.

The session id is a resume handle, so a build that was interrupted mid-cycle can be picked back up exactly where it stopped. `claimed_by` is really a **claim identity**, resolved as `${AGENTILE_RUNNER_ID}` if set, else `${CLAUDE_SESSION_ID}`. A factory worker claims as `factory/<project>/<slug>`; the `bin/ag-run` fallback as `ag-run@host/pid`. `/ag-wip` tells them apart — a session id gets the `claude --resume` line, a factory worker points at the console, another named runner gets re-run instructions.

The claim is race-safe by construction — one transaction in Agentile Projects, not a local file lock — so it holds across machines, checkouts and worktrees alike: several `/ag-build` workers, a factory run, and an interactive session can all claim and ship specs in parallel with no coordination step of their own. Shipping is not automatically race-safe the same way: two sessions merging to the same trunk checkout at once can still collide, so a rejected merge because trunk moved is a losing race to retry once, not an error.

### Stores

Since 0.20.0 there is one store: **Agentile Projects**, a web app (multi-user, multi-project, with dashboards, Pundit roles, and the loop's business logic — transactional claim, rank, dependency walks, flow metrics, capture assist — server-side). Every skill that touches the backlog calls `bin/ag-store <op>`, a thin HTTP client over the app's JSON API, so the skills name one command and one output shape.

- `.agentile/store.md` holds `url` (the app; `AGENTILE_PROJECTS_URL` overrides it) and `project` (this repo's project slug). `/ag-init` writes it after asking which of your projects this repo is.
- `AGENTILE_PROJECTS_TOKEN` (an API token from the app's Settings) is an environment variable only, never a tracked file. It identifies you: captures, shapes, claims and answers are attributed from it, and your project role (owner / member / viewer) is what the API authorises against.
- Claim and rank are atomic — one transaction in the app — so two sessions can never take the same spec, and there is no file lock, `.pull.lock` or "pull before you touch the queue".
- `plan.md`, the `SPEC.md` snapshot, findings and ADRs stay in the repo; the brief is edited in the app and mirrored to `docs/agentile/brief.md` read-only.
- The API returns full resource objects (a spec, an Outcome, a run, …); `ag-store` unwraps each one down to the slug, id or ISO8601 stamp the skills actually need (documented per-op at the top of `bin/ag-store`), so a skill's "`-> slug`" or "`-> ISO8601`" contract holds regardless of how much detail the app's JSON response carries.
- Because `.agentile/store.md`'s `url` is a tracked file, `ag-store` refuses to send the bearer token to it unless it is `https`, or its host is `localhost`/`127.0.0.1`, or `AGENTILE_PROJECTS_ALLOW_HTTP=1` is set; `doctor` prints the resolved host so a redirected url is visible.

The `local` (files + git) and `airtable` stores were removed in 0.20.0; `/ag-version` flags a pre-0.20 `store.md`, and `/ag-init` re-links the project. Existing Airtable bases are imported by the app's `agentile:import` task.

### Spec dependencies

A spec can declare `depends_on: [slug, …]` in its frontmatter — a list of other specs (by slug) that must ship before this one can be claimed. Shaping asks about this by default, so dependencies are captured at the point of writing the spec rather than discovered mid-build. A spec isn't claimable until all its dependencies have shipped. When a spec ships its status is `shipped` and it satisfies dependencies. (Abandoning a dependency, by contrast, leaves its dependents `BLOCKED` — `/ag-abandon` walks that chain so nothing is stranded silently.)

### Outcomes

The layer above specs. An **Outcome** is a bet — a claim about what becomes
true, a measure a human judges it by, and a stop rule — kept flat and ranked.
A spec may `serve` one Outcome (frontmatter `serves: <slug>`) and carry
free-form `tags`; neither is ever required, and a spec with no Outcome is
claimable exactly as before. Everything you would want to *report* — progress,
what's blocked, what's grouped where — is computed by `ag-store map`, never
stored, so it cannot go stale. The layer earns its place as an *input*:
`/ag-decompose <slug>` turns an Outcome into candidate stubs. Design, and the
Jira-epic argument it rejects: `docs/agentile-outcomes.md`.

### When shipped work turns out wrong

A shipped spec that fails in production re-enters the loop as new work:
`/ag-capture` a stub referencing the original slug, shape it, ship the fix.
Optionally add `superseded_by: <new-slug>` to the original spec in `done/` so
the record shows what corrected it. Ship is flagged and reversible — turning
the flag off is part of the fix, not an afterthought. The original spec stays
in `done/` and still satisfies dependencies; abandonment is only for work that
never shipped.

### Running a build

**`/ag-build [slug]`** takes **one spec** from claim to shipped and stops: claim the top prioritised ready spec (or the named one) → plan (pauses for `foreground`/`spike` specs by default) → implement → verify → pause for your sign-off → ship. Running several specs at once means several sessions, or a machine set up as a factory.

Every pause is a **checkpoint record** in the store. In a session you answer by replying; anywhere else you answer on the project dashboard in Agentile Projects (or `printf 'reply' | ag-store checkpoint_answer <id> --by <you>`), and the next `/ag-build` with the same claim identity carries on from the answer. Every turn ends with a machine-readable `AG_BUILD: <shipped|paused|failed|idle> …` line.

Pause policy lives in the stage playbooks: `.agentile/plan.md` (`human_checkpoint: route | true | false`), `.agentile/build.md` (`human_checkpoint`, default false), `.agentile/ship.md` (`human_checkpoint`, default true — nothing merges without your approval), and `.agentile/verify.md` (`retry_limit`, `stop_on_gate_failure`). There is no separate loop config; `.agentile/loop.md` from earlier versions is retired and ignored: `/ag-version` says where its keys went.

For an unattended machine there are two drivers:

- **`bin/ag-run`** — zero infrastructure: runs `/ag-build` in a fresh `claude -p` process per item, sequentially, and stops at the first checkpoint. Takes an optional `--limit N`, and forwards anything after `--` to `claude` (e.g. `bin/ag-run -- --permission-mode acceptEdits`); a headless run needs a permission story since nothing can answer a prompt.
- **The Agentile Factory** — one daemon per machine that feeds off every registered project's backlog, runs parallel workers with a chosen model each, and gives you a console for everything waiting on you. Design: `docs/agentile-factory.md`.

`/ag-loop` remains for one release as an alias that runs `/ag-build` once.

## Glossary

- **stub** — a one-line idea in the inbox; not yet ready to build.
- **spec** — a shaped, Ready work item in the store; once planned it also has a directory `docs/agentile/specs/<slug>/` in the repo.
- **Ready** — satisfies the Definition of Ready in `.agentile/shape.md`; `status: ready`.
- **prioritised** — has a rank in the store; an unranked spec is Ready but not claimable.
- **claimable** — prioritised, `status: ready`, unclaimed, all `depends_on` shipped, WIP limit not hit.
- **claimed** — pulled by `/ag-next`: `status: in_progress` plus `claimed_by`/`claimed_at`. `claimed_by` is a session id (a `claude --resume` handle) for an interactive claim, or a named runner (`AGENTILE_RUNNER_ID`) for a headless one.
- **run** — one `/ag-build` session against one spec, recorded in the store with its events (claimed, paused, shipped, failed) — durable across a compaction or a fresh process.
- **release** — clear a claim and return the spec to `ready`; the spec stays live.
- **abandon** — drop a spec for good (`/ag-abandon`); `status: abandoned` in the store, with the reason.
- **shipped** — merged and stamped `shipped_at`; `status: shipped`; it satisfies dependencies.
- **spike** — a spec whose deliverable is an answer (`findings.md` or an ADR), not shipping code.
- **route** — the triage outcome (`foreground` / `background` / `spike`); decides pairing vs delegation and where the loop pauses.
- **playbook** — `.agentile/<stage>.md`: frontmatter directives + prose policy that tailor a stage.
- **gate** — a deterministic command in `.agentile/gates.json` (format, lint, test, build, deploy). The first four gate a *change*; `deploy` gates a *release* and is run only by `/ag-deploy`.
- **ship vs deploy** — ship merges one spec to trunk; deploy releases every spec shipped since the last deploy. Different cadence, different gates, different blast radius.
- **checkpoint** — a record a paused `/ag-build` leaves in the store holding what it needs decided; answered in a session, on the project dashboard, or with `ag-store checkpoint_answer`.

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
| ship | merges, stamps | approves the ship | `ship.md` `human_checkpoint` (default on) |
| learn | compiles the digest, proposes edits | approves what gets encoded | approval of context edits |

## Install (in a project)

1. Add the marketplace and install the plugin:

   ```
   claude plugin marketplace add agenta-consulting/agentile
   claude plugin install agentile@agentile
   ```
2. Restart the session, then export `AGENTILE_PROJECTS_TOKEN` (an API token from Agentile Projects) and run `/ag-init` in your target project: it asks which of your projects this repo is, writes `.agentile/store.md`, and scaffolds `.agentile/`, `docs/agentile/`, `docs/adr/`, and the `CLAUDE.md` standing-context section. If you prefer to keep your root `CLAUDE.md` lean, the Agentile section can instead live in `.claude/rules/agentile.md` — `/ag-init` offers this; the content is identical, just independently updatable.
   Starting from an empty directory? Run `/ag-new-project` instead — it interviews you for the brief and the stack, records the stack as an ADR, writes a starter `CLAUDE.md`, runs the same scaffold with the gates pre-filled from the stack, then offers stage customisations and the first inbox stubs.
3. Start the loop: `/ag-capture`, `/ag-inbox`, `/ag-shape`, …

## Skills

`/ag-new-project`, `/ag-init`, `/ag-capture`, `/ag-inbox`, `/ag-shape`, `/ag-outcome`, `/ag-decompose`, `/ag-map`, `/ag-spec`, `/ag-plan`, `/ag-prioritise`, `/ag-next`, `/ag-wip`, `/ag-abandon`, `/ag-build`, `/ag-loop` (retired alias), `/ag-deploy`, `/ag-customise`, `/ag-retro`, `/ag-version`.

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
**test-gate** (`hooks/test-gate.rb`) is **not wired to any event** as of 0.11.0. It previously ran `gates.json`'s `test` command on `Stop`/`SubagentStop` — that is, at the end of every assistant turn, including turns that changed no code. `Stop` fires when the assistant stops talking, not when work completes, so the gate ran the full suite on questions and status reports alike; its only escape was a clean git working tree, which a single untracked file defeats indefinitely. On a slow or infrastructure-dependent suite that cost minutes per turn.

The `test` gate belongs to **verify** and **ship**, which already run it — and run it against a spec that claims to be done, which is the right trigger. The script and its tests are kept for a redesign around a cheap, opt-in command and an edit-aware trigger.

For a `test`/`build` command that needs protecting from concurrent runs (a human and `ag-builder`, or parallel subagents, against shared file-based test state like SQLite), wrap it in `gates.json` with `bin/ag-lock` — a portable `File#flock` wrapper; add it by hand (see the `$comment` in `.agentile/gates.json`) — `/ag-init` no longer offers to wire it in.

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
