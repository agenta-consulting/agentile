## Agentile

This project runs the **Agentile loop** (via Agentile for Claude): capture → shape → spec → plan → build → verify → ship → deploy → learn. Work builds from a written, shaped spec — never from a prompt typed from memory.

### Where things live

The backlog lives in **Agentile Projects**, the web app this repo is linked to by `.agentile/store.md` (`url` + `project`; the token is `AGENTILE_PROJECTS_TOKEN` in the environment). Every skill reads and writes it through `ag-store`; nothing in the loop reads backlog files.

- **Brief** — the living project context: who it's for, the prioritised outcomes, constraints, non-goals. Edited in the app; `docs/agentile/brief.md` is a read-only copy every `/ag-*` skill refreshes, imported below so it loads every session. Business Value in triage is scored against it.
- **Outcomes** — the falsifiable bets above specs: a claim, a measure, a stop rule, ranked. A spec may `serve` one; none is required. Create with `/ag-outcome`, propose the work for one with `/ag-decompose <slug>`, see the whole picture with `/ag-map`.
- **Inbox** — one-line stubs awaiting shaping. Capture freely with `/ag-capture`; the store tidies and classifies, you confirm.
- **Specs** — shaped, Ready-to-build specs (`ready` / `in_progress`). Rank is a field; `shipped` and `abandoned` are statuses. Once a spec starts planning, its `plan.md`, a read-only `SPEC.md` snapshot and supporting files live in this repo at `docs/agentile/specs/<slug>/`. The Definition of Ready is `.agentile/shape.md`.
- **Runs and checkpoints** — every `/ag-build` is a run in the store; every pause is a checkpoint record you can answer in a session, from another machine, or on the project dashboard.
- **Deploy log** (`docs/agentile/deploys.md`) — append-only record of what `/ag-deploy` released, by git sha.
- **ADRs** (`docs/adr/`) — the *why* behind significant decisions.
- **Config** (`.agentile/`) — this project's tailoring: `store.md` (the link), `config.md` (paths + triage), `shape.md` (what Ready means), `gates.json` (deterministic build/test/lint/deploy commands; `deploy` is run only by `/ag-deploy`), and the spec/ADR templates. Any loop stage can be further customised via `.agentile/<stage>.md` (playbook frontmatter: `delegate_to`, `also_run`, `human_checkpoint`).

### How to work

- An idea arrives → `/ag-capture <one line>` (add `--yes` to skip the confirmation). Never lose an idea for lack of a place to put it.
- Thinking above the spec level → `/ag-outcome` to state a bet, `/ag-decompose <slug>` to turn it into stubs, `/ag-map` to see what serves what. Outcomes are ranked by `/ag-prioritise` before specs are.
- Ready to develop something → `/ag-shape` to interview it into a spec, then `/ag-plan` before any code — it writes `plan.md` beside the `SPEC.md` snapshot; review or amend that file, it is the approved plan. Shaping asks about `depends_on` by default — list any specs (by slug) that must ship before this one can be claimed.
- Order the ready queue with `/ag-prioritise` — an interactive session that proposes a rank (Business Value × Technical Certainty, dependencies respected), you adjust it, and it writes the rank to the store. An unranked spec is not claimable. Pull the top item with `/ag-next` — the claim is one transaction in the store and is session-stamped so it can be resumed with `claude --resume <id>`. WIP is capped by `wip_limit`, a project setting the app enforces on claim (an explicit `0` in a playbook means unlimited). If the queue is blocked on dependencies or has no ranked specs, `/ag-next` tells you which. Check what's in flight with `/ag-wip` or the dashboard.
- Drop work that won't ship with `/ag-abandon <slug>` — it records why, walks the dependency chain, and offers to cascade-abandon (or unblock) anything that depended on it.
- Build the next spec with **`/ag-build`** (or a named one, `/ag-build <slug>`) — it takes one spec from claim to shipped and stops. It pauses at plan for `foreground`/`spike` specs (review `plan.md`, reply approved) and for your sign-off before ship; each pause is a checkpoint in the store, answerable in the app's web UI or at the terminal. For many specs at once, use the Agentile Factory or the **`bin/ag-run`** fallback, each of which runs `/ag-build` in a fresh process per item.
- Build on a short-lived branch/worktree; run the gates in `.agentile/gates.json`; a fresh-context reviewer critiques the diff before merge.
- Integrate to trunk in small, reversible, flagged batches. Close the loop with `/ag-retro`.

### Concurrent sessions

Several sessions can run this loop against the same backlog at once — multiple
`/ag-build` workers, a factory run, and an interactive session all claiming and
shipping specs in parallel. That is a supported, expected mode, not an
anomaly:

- Another spec showing `in_progress` under a `claimed_by` that is not you, a
  worktree under `.claude/worktrees/` you did not create, or — in a shared
  checkout — uncommitted changes elsewhere in the tree that belong to
  someone else's build in flight, are all normal. Do not flag any of this to
  the user as if something is wrong, and do not stop to ask about it; just
  proceed with your own claimed work. `/ag-wip` shows exactly what is in
  flight and by whom, if you genuinely need to check.
- The claim itself is race-safe (one transaction in the store). Shipping is
  not automatically race-safe: two sessions merging to the same trunk
  checkout at once can collide. If a merge is rejected because trunk moved
  since you branched, pull/rebase and retry once before treating it as a
  failure — a losing race is expected under concurrency, not an error.

### Rules

- Determinism over instruction: repeatable steps (build, test, lint, deploy) are commands in `.agentile/gates.json`, not hopeful sentences.
- Trust but verify: no agent output merges until it passes tests, static analysis, a security skim, and a human read of the diff.
- Measure flow, not output: if lead time does not drop, the constraint is upstream — fix that, not the agents.

@docs/agentile/brief.md
