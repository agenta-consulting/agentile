# Agentile

*Agile, with agency. A methodology for small teams who direct AI agents as their primary way of building software — applicable with any tool. Distilled from the Lean Agentic Loop synthesis of ten sources (see [docs/sources.md](docs/sources.md)); a Claude Code implementation ships as the Agentile plugin (see the binding section).*

When we automated the building, review became the bottleneck. Then review could be automated too. What's left — the thing that is now hardest and matters most — is describing what we actually want. **As the building becomes automatic, what you ask for becomes the most important.** Agentile is the methodology for that world: it puts the weight where the weight now is.

## Cross-cutting themes

Everything below follows from seven findings that recur across the sources:

- **The bottleneck moves upstream.** Faster coding exposes weak prioritization, validation, and ops (2, 4, 9).
- **The story *is* the prompt.** Specification quality is now the core engineering skill (3, 10).
- **Reduce agency with determinism.** Wrap repeatable steps as tools/gates; don't leave them to prose (3, 5).
- **Inject institutional knowledge into the agent.** ADRs, standards, and APIs belong in context, not buried wikis (3, 8).
- **Trust but verify.** Automated quality/security/E2E gates are the price of agent speed (1, 5, 9).
- **Accountability stays human.** Roles rebundle into a few "anchors"; the responsibility surface is constant (1, 9).
- **First be agile, then agentic.** Tooling amplifies a healthy loop and amplifies a broken one (2).

## The methodology

A methodology for **1–5 developers** who direct AI agents as their primary means of building software. It keeps the agile *spirit* (short loops, working software, respond to change) while dropping the ceremony that small teams can't justify. It is opinionated for small teams: low overhead, high determinism, human accountability.

### Governing principles

1. **One trunk, small batches.** Everyone (humans and agents) integrates to main continuously behind feature flags. Small diffs are reviewable; large ones aren't.
2. **The spec is the unit of work — but capture is free.** Work *builds* from a written spec, not a prompt typed from memory. But ideas *enter* as one-line stubs in an Inbox with zero ceremony, then get shaped into specs through a conversation. Never lose an idea for lack of a place to put it; never build from an unshaped one.
3. **Determinism over instruction.** Anything you'd repeat — build, test, lint, scan, deploy — is a script/command/gate, never a hopeful sentence in a prompt.
4. **Context is infrastructure.** Architecture decisions, conventions, and domain rules live where the agent reads them every time, and are versioned with the code.
5. **Trust but verify, automatically.** No agent output merges until it passes the same gates a senior reviewer would enforce: tests, static analysis, security scan, and a human skim.
6. **Name the anchors.** Even at one person, the seven load-bearing responsibilities (outcome, discovery, work design, engineering coherence, verification, delivery/ops, learning) need an owner — a person wearing a hat, not a job title.
7. **Measure flow, not output.** Track lead time and where work waits, not lines or "agent velocity." If lead time doesn't drop, your constraint is upstream.

### The two-axis triage (what to do with each piece of work)

Borrowed from danicat: score each task on **Business Value** and **Technical Certainty**, then route it.

| | High certainty | Low certainty |
|---|---|---|
| **High value** | Delegate to a **background/async agent**, review the PR | **Pair in foreground** — you drive, agent executes step by step |
| **Low value** | Batch to background agents; thin review | Spike first (timeboxed exploration) or drop |

The route is not advice that evaporates — it is **recorded on the spec itself** and travels with it: a `foreground` or `spike` spec pauses the loop at plan for human steering; a `background` spec runs through to the pre-ship gate. (How the route is stored is an implementation detail.)

### The Inbox: capture now, shape later

The friction in any small-team process is the moment an idea arrives. You're mid-build and you think "we should rate-limit the login endpoint" — too small to plan, too important to forget, not worth a full spec right now. So you don't want a blank page; you want a **one-line drop box**.

Agentile has a single capture surface, the **Inbox** — one place where any idea can land. Anything can go in it as a **stub** — a placeholder that is *not yet ready to build*. A stub is literally one line: a title, optionally a word about why. No acceptance criteria, no estimate, no triage. The only rule is that capture must be instant, so the cost of writing it down is lower than the cost of holding it in your head.

```
# Inbox (stubs awaiting shaping)
- [ ] Rate-limit the login endpoint — saw a brute-force attempt in logs
- [ ] "Export to CSV" somewhere on the reports page
- [ ] Migrate the jobs table off the shared DB? (not sure if worth it)
- [ ] Onboarding email feels too long
```

The Inbox **is** "the list of what needs shaping." A stub stays there until it's either shaped into a Ready spec, merged into another item, or dropped. Reviewing the Inbox is a deliberate act, not something that blocks your build loop.

### Shaping: the conversation that promotes a stub to a spec

**Shaping** is the bridge between a stub and step 1 (SPEC). It is explicitly a **conversation with the AI**, not a form to fill in. You pick a stub and the agent interviews you until the idea is concrete enough to be Ready. The agent's job is to ask the questions a good product owner + tech lead would ask, one or two at a time, and then write up the result.

A shaping conversation drives toward answering:

- **What problem / who for / why now** — the business justification behind the stub.
- **Acceptance criteria** — what "done" observably looks like.
- **Edge cases and failure paths** — what the agent should *not* assume.
- **Scope boundary** — what's explicitly out, so it doesn't balloon.
- **Affected areas** — files, services, or data the change likely touches.
- **Open questions** — anything unknown becomes a timeboxed *spike* rather than a guess.

The agent should also do the **two-axis triage** during shaping: estimate Business Value × Technical Certainty and recommend a route (foreground pair, background agent, spike, or drop). Low-certainty stubs often leave shaping as a spike, not a build.

Outcome of a good shaping session: the stub graduates out of the Inbox and becomes a Ready spec (the input to step 1), **or** it's split into several stubs, merged, deferred, or deleted. Shaping is the cheapest place to kill or reshape an idea — do it here, in words, before any code exists.

A practical rhythm for 1–5 people: capture freely all day; shape in a short focused pass (e.g., once a day or before each build cycle) by walking the top of the Inbox with the agent. Don't let the Inbox become a graveyard — if a stub has sat unshaped for weeks, that's a signal to drop it.

A spike's deliverable is a written answer, not code: its build is the timeboxed exploration, its verify is "question answered within the timebox", and on ship its findings (a short write-up, or an ADR) are **archived alongside completed work** — satisfying dependencies like any spec.

### The spec artefact

A spec is a **written artefact**: a human-readable statement of the work, plus
a small set of machine-readable facts about it — when it was created, when it
was claimed, when it shipped — so flow metrics need no external tracker. Each
spec names an **outcome**: the one observable check that will prove the change
worked. When planning starts, the spec gains a **plan** kept beside it,
together with any supporting material (designs, data samples, spike findings).
Shipping **archives the whole artefact**, where it stays resolvable as a
fulfilled dependency and mineable for the learn step. (How the artefact is
stored — file formats, directory layout, where the metadata lives — is the
implementation's business.)

### Prioritisation and pulling as distinct acts

The ready queue needs two operations that are easy to conflate but must stay separate.

**Prioritisation** is an editorial act: you order the ready list by scoring each spec on Business Value × Technical Certainty and writing that score onto it. It answers "what should come next?" and can be re-run whenever the queue changes. It produces an ordered list; it does not start any work. Specs may declare dependencies on other specs; claiming a spec is gated until all its dependencies have shipped, and the prioritisation step respects those constraints when proposing an order. In practice, prioritisation is an interactive session — the tool proposes a rank, you adjust it, and the rank is **recorded on each spec so the ordered queue is visible at a glance**, without opening anything. (One implementation encodes the rank as a filename prefix; the methodology only requires that order be visible.)

**Pulling** is a transactional act: you claim the top unclaimed item, stamp it as in-progress, and begin a cycle. It answers "I am taking this one now" and must be **atomic** — two workers can never claim the same item, especially when multiple loops run concurrently. The claim records a **resumable worker handle**, so an interrupted cycle can be picked up exactly where it stopped. How atomicity and resumption are implemented belongs to the implementation (in Claude Code: a file lock and the session id).

Keeping them separate means prioritisation decisions (human, deliberate, editorial) never get tangled with execution mechanics (machine, concurrent, transactional).

### The loop (repeats per work item; a "cycle" is hours to a day, not a two-week sprint)

**0. Standing context (set up once, maintained always).**
A living project brief the agents always see: stack, conventions, architecture, "do/don't," and an ADR log. This is the load-bearing layer — it's what makes agents consistent.

**1. SPEC — write the work as a prompt-ready story.**
Capture intent, business justification, acceptance criteria, edge cases, and affected files. This is your Definition of Ready. A spec usually arrives here already **shaped** from the Inbox (see above); for anything non-trivial, shape first rather than building straight off a stub. No spec, no build.

**2. PLAN — let the agent propose, you approve.**
The agent reads the spec plus standing context and **writes the plan down** — files to touch, approach, test strategy, risks — *before* any code. You correct the plan **where it's written**; it is the cheapest place to steer. Whether the loop stops here for you is route-aware: low-certainty work pauses, high-certainty work proceeds. Big or risky specs get an ADR.

**3. BUILD — agent implements against deterministic tooling.**
The agent writes code and tests on a short-lived branch/worktree, running your packaged commands (build, test, lint) itself. For parallel work, give each agent its own worktree to preserve trunk concurrency without conflicts.

**4. VERIFY — the gate (trust but verify).**
Automated, non-negotiable: unit + **end-to-end** tests, static analysis/code-quality scan, security review, and a human read of the diff. A *separate* agent (a reviewer with fresh context) critiques the builder's output — agents are better at finding others' mistakes than their own. Failures bounce back to step 3. End-to-end coverage is part of the `test` gate's job — if your test command doesn't include it, that is a gap in the gate, not a different gate.

**5. SHIP — merge to trunk, deploy behind a flag, observe.**
Small, flagged, reversible. Watch the metric that proves the outcome from step 1. Shipping **records when the work shipped** and preserves the earlier claim times — the spec's own metadata is the flow record, so no external tracker is needed. Each spec names the **outcome** that proves it (one observable metric or check, written at shaping); watching that outcome is part of shipping, not a separate ceremony.

**6. LEARN — close the loop.**
A non-coding agent compiles a data-driven mini-retro from PRs, ticket transitions, and incidents: where did work wait? Which area needed the most rework? Update the standing context and ADRs so the lesson is *encoded*, not just discussed. The system gets smarter; the next cycle is cheaper. Learning covers product as well as process: for each spec shipped since the last retro, was its outcome observed? Shipped-but-wrong work re-enters as a new stub referencing the original.

### Runner modes: drain and watch

A runner has two modes. **Drain**: work the current queue, then stop.
**Watch**: keep waiting for new work and start on it as it appears. The
methodology owns these two modes; how a given harness implements them is the
implementation's business (in Claude Code today: `/ag-loop` drains; `/loop /ag-loop`
watches).

### What you deliberately drop

Story-point poker, status-meeting standups, fixed two-week sprints as the planning atom, and exhaustive wikis nobody reads. Replace standups with the LEARN digest, replace sprint planning with continuous two-axis triage, replace the wiki with versioned context the agents consume. And estimates: **we don't estimate, we just do it** — when the doing is this cheap, estimating it can take longer than the doing.

### Why it fits small teams

The whole loop is one trunk, one context file set, a handful of commands, and a gate. There's no coordination overhead to amortize across many people — the overhead lives in tooling you build once and the agents run forever. The human stays the accountable anchor while agents absorb the drafting, implementation, and grunt verification.

## Binding: Claude Code and the Agentile plugin

The methodology above is tool-agnostic; the **Agentile plugin** ("Agentile for Claude") is its Claude Code binding. Everything the loop needs — the capture surface, the shaping interview, the atomic claim, the three agents, the gates — ships as installable skills, agents, and hooks, so install the plugin rather than hand-building the pieces:

```
claude plugin marketplace add agenta-consulting/agentile
claude plugin install agentile@agentile
```

Then run `/ag-init` in your project: it scaffolds the backlog and configuration and ends with a report on your loop's readiness. The binding, concept by concept:

| Methodology concept | Plugin implementation |
|---|---|
| Standing context | `CLAUDE.md` section scaffolded by `/ag-init`, plus `docs/adr/` and optional MCP servers |
| Capture & Inbox | `/ag-capture` and `/ag-inbox`, writing to `docs/agentile/inbox.md` |
| Shaping & DoR | `/ag-shape`, interviewing against `.agentile/shape.md` |
| Direct spec for trivial work | `/ag-spec` |
| The spec artefact | `docs/agentile/specs/NNNN-<slug>.md`, promoted at planning to `NNNN-<slug>/SPEC.md` + `plan.md` |
| Prioritise — editorial | `/ag-prioritise`; the rank is the filename prefix |
| Pull — transactional | `/ag-next` → `bin/ag-claim`: a file lock; the session id is the worker handle (`claude --resume <id>`) |
| Plan | `/ag-plan` writes `plan.md`, via Plan Mode or the `ag-planner` agent |
| Build | the `ag-builder` agent on a branch/worktree, running the gates from `.agentile/gates.json` |
| Verify | the `ag-reviewer` agent with fresh context, plus `/security-review` and the hooks |
| Ship | orchestrated by `/ag-loop` — a step, not an agent: merge, stamp `shipped_at`, move to `specs/done/` |
| Learn | `/ag-retro` |
| Drain & watch | `/ag-loop` vs `/loop /ag-loop` |
| Tailoring | `.agentile/` playbooks, built conversationally with `/ag-customise` |

The "hats" are exactly three agents: `ag-planner` (architecture and approach), `ag-builder` (implementation), and `ag-reviewer` (verification and security). Each runs in its own context, which is the point — the reviewer catches what the builder missed because it never saw the builder's reasoning. Shaping is not an agent but a skill-run conversation with you; ship is not an agent but a skill-orchestrated step. The human stays the accountable anchor who approves plans and owns outcomes.

Deterministic enforcement comes from two hooks: **format-on-edit** (`PostToolUse`) runs your formatter after every edit, and **test-gate** (`Stop`/`SubagentStop`) blocks "done" until your test command passes. Both read `.agentile/gates.json` and no-op until commands are configured, so installation never disrupts an unconfigured repo. The same gates belong in CI — Claude Code's GitHub Actions integration can run them (and `/security-review`) on every PR, so the gate holds whether a human, an agent, or nobody is watching the terminal.

Getting started:

1. Install the plugin (marketplace add + install, as above).
2. Run `/ag-init` — scaffolds the backlog, `.agentile/`, ADRs, the `CLAUDE.md` section, and ends with a readiness report.
3. Fill in `.agentile/gates.json`.
4. `/ag-capture` an idea, `/ag-shape` it, `/ag-prioritise`, then `/ag-loop`.

## The one rule

**First be agile, then agentic** (INNOQ's phrase, and the methodology's precondition). Agents multiply whatever loop you give them: a healthy loop gets faster, a broken one breaks faster. Get the trunk, the gates, and the written spec right first — agents make a good loop fast; they do not make a bad loop safe.
