# From Agile to Agentic: A Methodology for Small Teams

*Synthesized from ten source articles, plus a concrete Claude Code playbook.*

---

## Part 1 — Source summaries

**1. CIO — "5 ways agentic engineering transforms agile practices" (Derek Ashmore).**
Agile survives the agentic era but must level up. Five shifts: (1) roles converge — every human becomes a "specifier"/product manager directing agents; (2) stories can be larger because agents do more per unit time; (3) concurrency matters more, so trunk-based development is essential to stop agents clobbering each other; (4) end-to-end testing becomes critical because agents hallucinate and lack whole-system context; (5) double down on metrics (DORA) because agents add moving parts and risk.

**2. INNOQ — "First Agile, Then Agentic" (Daniel Westheide).**
AI won't rescue an immature org. Agentic speed only pays off if you already have the agile/DevOps capabilities (short feedback loops, autonomous cross-functional teams, fast deploys). If your bottleneck is requirements, validation, or ops — not coding — giving developers agents just produces wrong work faster. "Agency" (autonomy + capability to act) must exist in the team before you delegate it to software agents.

**3. danicat.dev — "From Agile to Agentic" (Daniela Petruzalek).**
The most practitioner-concrete piece. Three core practices: (1) *story writing is prompting* — a good story = good context = Definition of Ready; (2) *prioritisation dictates workflow* — sort by Business Value × Technical Certainty to decide foreground pairing vs. background async agents; (3) *reduce the agent's agency* — package deterministic steps (build/test/lint/deploy) as tools, not prompts, so the agent can't "forget." Scale via ADRs and institutional knowledge injected into agents through MCP servers, non-coding agents that automate ceremonies (refinement, DoR/DoD audits, retros), and "agent managers" orchestrating fleets. Ends with a vision of "agentic kanban."

**4. Medium / Pablo Torre — "The Agentic Revolution: Beyond Agile."**
Proposes an agent-driven SDLC of iterative loops: generate Markdown specs → prototype in a flexible language (Python/JS) → reimplement in a high-performance language (TS/Rust/SQL) → continuous performance optimization → automated security hardening. The economic argument: when agents make refactoring and migration cheap, the cost of change collapses, technical debt stays low, and adaptability becomes the competitive edge. More visionary/economic than operational.

**5. Sonar — "AC/DC: Agent-Centric Development Cycle."** *(page is JS-rendered; summarized from title/positioning)*
Sonar's framing of a development cycle built around AI agents writing the code, with automated quality and security gates as the control layer. Consistent with Sonar's "trust but verify" stance: agent output must pass deterministic analysis (bugs, vulnerabilities, maintainability) before it earns release confidence. *Note: full body not retrievable; treat as directional.*

**6. Outsourced Staff — "Agile Development" blog.** *(JS-gated; not retrievable)*
General agency-style overview of agile development services/benefits. Could not extract substantive content; excluded from synthesis.

**7. Reddit r/ProductManagement — "Are full Agile processes becoming outdated for [AI teams]?"** *(URL blocklisted; not retrievable)*
Community debate thread on whether heavyweight agile ceremony still earns its keep when AI compresses delivery. Could not extract; the theme (ceremony fatigue vs. retained fundamentals) is well covered by sources 3, 9, and 10.

**8. Glean — "Glean Agents" whitepaper (landing page).** *(gated; summarized from abstract)*
Agents go beyond single LLM calls by combining tools, workflows, and memory to perform enterprise tasks reliably. Glean routes queries to "golden" workflows via search, designs around common query classes (data lookup, progress summarization, request handling), and evaluates agents at scale using task-specific LLM judges and real eval sets. Takeaway for us: reliability comes from *reusable workflows + memory/context + systematic evaluation*, not raw model power.

**9. Medium / Rethink Your Understanding — "Agile Isn't Dead and AI Isn't Killing It Either."**
AI isn't killing agile — it's exposing constraints that were always upstream of engineering. If coding gets faster but lead time doesn't, the bottleneck was prioritization, dependencies, validation, ops, or decision latency. Teams shrink and roles "rebundle," but the *load-bearing responsibilities* never disappear: outcome clarity, discovery/validation, work design, engineering coherence, verification/resilience, delivery/ops, and learning loops. AI redistributes work; it does not move accountability. Value Stream Management and flow metrics matter *more*, not less. What dies is "agile theater."

**10. Atlassian Community — "How AI is Quietly Reshaping Agile" (John D. Patton).**
Field notes: AI augments rather than replaces agile teams. Backlog intelligence (summarizing stale tickets, grouping issues, risk-flagging), human-in-the-loop workflows (AI drafts acceptance criteria/tickets, humans edit to keep ownership and trust), a shift from velocity to flow metrics (cycle time, flow efficiency, AI bottleneck summaries), and emerging hybrid roles ("the developer who codes *and* prompts"). Advice: start small, keep the human in the loop.

### Cross-cutting themes
- **The bottleneck moves upstream.** Faster coding exposes weak prioritization, validation, and ops (2, 4, 9).
- **The story *is* the prompt.** Specification quality is now the core engineering skill (3, 10).
- **Reduce agency with determinism.** Wrap repeatable steps as tools/gates; don't leave them to prose (3, 5).
- **Inject institutional knowledge into the agent.** ADRs, standards, and APIs belong in context, not buried wikis (3, 8).
- **Trust but verify.** Automated quality/security/E2E gates are the price of agent speed (1, 5, 9).
- **Accountability stays human.** Roles rebundle into a few "anchors"; the responsibility surface is constant (1, 9).
- **First be agile, then agentic.** Tooling amplifies a healthy loop and amplifies a broken one (2).

---

## Part 2 — The Lean Agentic Loop (LAL)

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

### The Inbox: capture now, shape later

The friction in any small-team process is the moment an idea arrives. You're mid-build and you think "we should rate-limit the login endpoint" — too small to plan, too important to forget, not worth a full spec right now. So you don't want a blank page; you want a **one-line drop box**.

LAL has a single capture surface, the **Inbox** (`inbox.md`). Anything can go in it as a **stub** — a placeholder that is *not yet ready to build*. A stub is literally one line: a title, optionally a word about why. No acceptance criteria, no estimate, no triage. The only rule is that capture must be instant, so the cost of writing it down is lower than the cost of holding it in your head.

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

Outcome of a good shaping session: the stub graduates out of `inbox.md` and becomes a Ready spec in `/specs/` (the input to step 1), **or** it's split into several stubs, merged, deferred, or deleted. Shaping is the cheapest place to kill or reshape an idea — do it here, in words, before any code exists.

A practical rhythm for 1–5 people: capture freely all day; shape in a short focused pass (e.g., once a day or before each build cycle) by walking the top of the Inbox with the agent. Don't let the Inbox become a graveyard — if a stub has sat unshaped for weeks, that's a signal to drop it.

### Prioritisation and pulling as distinct acts

The ready queue needs two operations that are easy to conflate but must stay separate.

**Prioritisation** is an editorial act: you order the ready list by scoring each spec on Business Value × Technical Certainty and writing that score onto it. It answers "what should come next?" and can be re-run whenever the queue changes. It produces an ordered list; it does not start any work.

**Pulling** is a transactional act: you claim the top unclaimed item, stamp it as in-progress, and begin a cycle. It answers "I am taking this one now" and must be atomic — especially when multiple loops run concurrently. A file lock ensures two loops can never claim the same item. The claim records the session id, so an interrupted loop can be resumed precisely where it stopped.

Keeping them separate means prioritisation decisions (human, deliberate, editorial) never get tangled with execution mechanics (machine, concurrent, transactional).

### The loop (repeats per work item; a "cycle" is hours to a day, not a two-week sprint)

**0. Standing context (set up once, maintained always).**
A living project brief the agents always see: stack, conventions, architecture, "do/don't," and an ADR log. This is the load-bearing layer — it's what makes agents consistent.

**1. SPEC — write the work as a prompt-ready story.**
Capture intent, business justification, acceptance criteria, edge cases, and affected files. This is your Definition of Ready. A spec usually arrives here already **shaped** from the Inbox (see above); for anything non-trivial, shape first rather than building straight off a stub. No spec, no build.

**2. PLAN — let the agent propose, you approve.**
The agent reads the spec + standing context and returns a plan (files to touch, approach, test strategy, risks) *before* writing code. You correct the plan here — it's the cheapest place to steer. Big or risky specs get an ADR.

**3. BUILD — agent implements against deterministic tooling.**
The agent writes code and tests on a short-lived branch/worktree, running your packaged commands (build, test, lint) itself. For parallel work, give each agent its own worktree to preserve trunk concurrency without conflicts.

**4. VERIFY — the gate (trust but verify).**
Automated, non-negotiable: unit + **end-to-end** tests, static analysis/code-quality scan, security review, and a human read of the diff. A *separate* agent (a reviewer with fresh context) critiques the builder's output — agents are better at finding others' mistakes than their own. Failures bounce back to step 3.

**5. SHIP — merge to trunk, deploy behind a flag, observe.**
Small, flagged, reversible. Watch the metric that proves the outcome from step 1.

**6. LEARN — close the loop.**
A non-coding agent compiles a data-driven mini-retro from PRs, ticket transitions, and incidents: where did work wait? Which area needed the most rework? Update the standing context and ADRs so the lesson is *encoded*, not just discussed. The system gets smarter; the next cycle is cheaper.

### What you deliberately drop
Story-point poker, status-meeting standups, fixed two-week sprints as the planning atom, and exhaustive wikis nobody reads. Replace standups with the LEARN digest, replace sprint planning with continuous two-axis triage, replace the wiki with versioned context the agents consume.

### Why it fits small teams
The whole loop is one trunk, one context file set, a handful of commands, and a gate. There's no coordination overhead to amortize across many people — the overhead lives in tooling you build once and the agents run forever. The human stays the accountable anchor while agents absorb the drafting, implementation, and grunt verification.

---

## Part 3 — Running the Lean Agentic Loop with Claude Code

Claude Code maps onto LAL almost one-to-one. Here's the concrete setup.

### 0. Standing context → `CLAUDE.md` + ADRs + MCP
- Put the project brief in a **`CLAUDE.md`** at repo root (and nested `CLAUDE.md` files in subdirectories for local rules). Run **`/init`** to bootstrap it from the existing codebase, then hand-edit. Include: stack, conventions, architecture overview, build/test/deploy commands, and "do/don't" rules.
- Keep an **`/docs/adr/`** folder of Architecture Decision Records. Reference it from `CLAUDE.md` so Claude reads the *why* behind the code.
- Expose shared/team knowledge or live APIs via **MCP servers** (`.mcp.json` checked into the repo) so every teammate's Claude — and CI — sees the same standards and schemas.
- Use **`#`** mid-session to append a learned fact straight into `CLAUDE.md`.

### 1a. CAPTURE → a `/capture` command that appends to `inbox.md`
- Add a tiny **custom slash command** `.claude/commands/capture.md` whose body is: "Append the following as a one-line stub (with today's date) to `inbox.md` under the Inbox heading. Do not ask follow-up questions. Do not start work." Then `/capture rate-limit the login endpoint` drops a stub in one move, even mid-build.
- `inbox.md` lives at repo root, versioned with the code, so the whole team shares one capture surface. (Optional: a `/capture-todo` variant that files to an external tracker instead.)
- `/inbox` (another one-liner command) lists the current stubs and nothing else, so you can review what needs shaping at a glance.

### 1b. SHAPE → a `/shape` command that runs the interview
- Add `.claude/commands/shape.md` that instructs Claude to: take a stub (by name or number) from `inbox.md`, **interview the user one or two questions at a time** to establish problem/why-now, acceptance criteria, edge cases, scope boundary, affected areas, and open questions; run the Business Value × Technical Certainty triage and recommend a route; then **write the result to `/specs/<slug>.md` and remove the stub from `inbox.md`** (or split/merge/drop it).
- Run this in normal (non-Plan) mode so it's a back-and-forth conversation; the agent shouldn't touch code, only produce the spec. This is your "non-coding refinement agent."
- For a heavier item, point the existing **`spec-writer` subagent** at the stub so the shaping conversation has its own focused context and tool limits.
- Open questions that survive shaping become a timeboxed spike — have Claude file that as its own spec marked `type: spike`.

### 1c. SPEC → the shaped output
- Shaped specs land as Markdown in `/specs/` and are the Definition of Ready / input to Plan Mode. For trivial changes you can still `/spec` straight from an idea, but anything non-trivial should pass through `/shape` first.

### 2. PLAN → Plan Mode + a planning subagent
- Start the work in **Plan Mode** (Claude proposes an approach and edits nothing until you approve). This is the cheapest steering point.
- Or invoke the **Plan subagent** / a custom `/plan` command to get files-to-touch, test strategy, and risks. Approve or correct before any code is written.
- For risky decisions, ask Claude to write a new ADR as part of the plan.

### 3. BUILD → deterministic commands + git worktrees
- Package every repeatable step as a **custom slash command** or a script Claude calls: `/test`, `/lint`, `/build`, `/deploy`. This is "reducing the agent's agency" — Claude runs the gate, it doesn't improvise it.
- Enforce process with **hooks** (`.claude/settings.json`): e.g. a `PostToolUse` hook that auto-runs formatter/linter after every edit, or a `PreToolUse` hook that blocks edits to protected paths. Hooks make the rules deterministic instead of relying on Claude to remember.
- For parallel agents, give each its own **git worktree** (or use the agent tool's `isolation: "worktree"`) so concurrent work doesn't collide — this is how you keep trunk-based concurrency safe.

### 3b. PRIORITISE, NEXT, WIP → queue management for concurrent loops

Before a build cycle begins, the ready queue should be ordered. `/ag-prioritise` scores each spec and writes a `priority` value; the weighting and WIP limit live in `.agentile/prioritise.md` so you can tune the scheme per project. Run it whenever new specs arrive or priorities shift.

`/ag-next` is the pull step: it runs `bin/ag-claim` under a file lock, atomically stamps the top unclaimed spec with `status: in_progress`, `claimed_by: <session-id>`, and `claimed_at`, then reports what was claimed. Because the lock is at the filesystem level, two Claude Code sessions running concurrently will never grab the same item — this is the safety primitive that makes multiple loops viable.

The session id doubles as a resume handle: `claude --resume <id>` restores the loop to the exact point it was interrupted, so a cycle is never silently lost. `/ag-wip` lists all in-flight claims and prints the resume command for each; stale claims (claimed but idle) are surfaced for human judgement rather than auto-reclaimed.

### 4. VERIFY → a reviewer subagent + `/security-review` + CI
- Spin up a **separate review subagent** with fresh context to critique the builder's diff ("trust but verify" — the second agent catches what the first missed). The Agent tool / subagents make this a one-call step.
- Run the built-in **`/security-review`** (or the security-review GitHub Action on every PR) for vulnerability scanning.
- Wire your test + static-analysis gates into **CI**; use **Claude Code GitHub Actions** (`@claude` on a PR) so the agent can respond to review comments and fix failures automatically.
- A **`Stop`/`SubagentStop` hook** can block "done" until tests actually pass — the gate enforces itself.

### 5. SHIP → small flagged PRs
- Have Claude open small PRs (`gh` CLI works inside Claude Code), keep diffs reviewable, and ship behind feature flags. Claude can wire the flag and the rollback path as part of the spec.

### 6. LEARN → a scheduled digest that updates context
- Use a **scheduled task** (or a `/retro` command) to have a non-coding Claude session compile a weekly flow digest: cycle time, where PRs stalled, which modules needed rework. Feed the lessons back into `CLAUDE.md` and ADRs so the standing context compounds.

### Roles → "hats," powered by subagents
Define **custom subagents** (`.claude/agents/`) for the recurring anchors so a 1–5 person team punches above its weight:
- `spec-writer` (refinement / DoR), `planner` (architecture & approach), `builder` (implementation), `reviewer` (verification & security), `release` (deploy/observe).
Each gets its own system prompt and tool permissions. You stay the human anchor who approves plans and owns accountability; the subagents do the drafting and grunt work.

### Minimal starter checklist
1. `/init` → flesh out `CLAUDE.md`; add `/docs/adr/` and an empty `inbox.md`.
2. Add slash commands: `/capture`, `/inbox`, `/shape`, `/spec`, `/plan`, `/test`, `/lint`, `/security-review` (built-in), `/retro`.
3. Add hooks: auto-format/lint on edit; block "done" until tests pass.
4. Add subagents: `planner`, `builder`, `reviewer`.
5. Adopt trunk-based dev + worktrees for parallel agents.
6. Turn on Claude Code GitHub Actions for PR review/fix.
7. Schedule the weekly LEARN digest.

### The one rule that makes it work
**First be agile, then agentic** (INNOQ). LAL amplifies a healthy loop — and amplifies a broken one. Get the trunk, the gates, and the written spec right *first*; the agents make a good loop fast, not a bad loop safe.
