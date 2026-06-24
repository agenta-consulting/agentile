# Agentile Methodology Review

Reviewer: methodology review pass (structure only — implementation reviewed separately). Date: 2026-06-13.

Sources reviewed: `lean-agentic-loop.md`, `README.md`, the four design docs in `docs/`, and the frontmatter of all 13 skills and 3 agents.

## Executive summary

The methodology is in good shape where it has been worked hardest. The capture → shape → spec spine is genuinely lean and well-reasoned; the playbook contract (frontmatter directives + prose policy) is an excellent dual-audience design; prioritise-vs-pull as distinct acts is a real insight; and the derived/stateless backlog model (state in filenames and frontmatter, computed each time) is robust and future-friendly. The "first be agile, then agentic" framing gives the whole thing a defensible centre of gravity.

The weaknesses cluster at the back of the loop (ship/learn are thin compared to the front), in documents that have drifted apart as the plugin evolved, and in a few places where a stated principle has no mechanism behind it.

Top 5 issues:

1. **The loop's default behaviour contradicts the methodology's own steering principle.** The essay calls plan approval "the cheapest place to steer", but `/ag-loop` only pauses at `human_checkpoint: true` playbooks and before ship — so under the default config the plan is never human-approved. (High)
2. **Part 3 of `lean-agentic-loop.md` is stale.** It describes a DIY setup (`/capture`, `/shape`, hand-built commands, a `spec-writer` and `release` subagent) that the shipped plugin has superseded and partly contradicts. (High)
3. **Flow metrics are destroyed at the moment they become measurable.** Ship clears the claim fields and stamps no `shipped_at`, so the lead-time data that principle 7 and `/ag-retro` depend on is erased on every ship. (High)
4. **Ship and production feedback are the thinnest stages.** No outcome metric is captured in the spec, nothing observes it after ship, and `/ag-retro` mines git/specs/PRs but not production signals — so "watch the metric that proves the outcome" is an aspiration with no mechanism. (Medium-high)
5. **Three competing enumerations of the loop, and overloaded verbs.** README says 8 stages, the essay numbers 0–6 with capture/shape bolted on as 1a/1b, the customisation contract canonicalises 10. "Abandon" means both "release a claim" (older doc) and "drop a spec forever" (current). (Medium)

## 1. Completeness

### 1.1 No outcome metric, no production feedback loop — Medium-high

Where: `lean-agentic-loop.md` Part 2 steps 5–6; README "ship" and "learn" bullets; `ag-retro` skill description.

SHIP says "watch the metric that proves the outcome from step 1", but the spec template has no outcome-metric field, no stage owns checking it, and `ag-retro`'s inputs are "git history, specs, and ADRs (and PRs when available)" — not telemetry, incidents, or the metric itself. The loop therefore closes on *process* learning (where work waited) but not *product* learning (did the change work). For a methodology whose sources stress that the bottleneck is upstream validation, this is the biggest genuine gap.

Recommendation (add): give the spec template an `outcome:` field (one observable metric or check, written at shaping); make the ship playbook's baseline include "record how the outcome will be observed"; extend `/ag-retro`'s remit to ask "for specs shipped since last retro, was the outcome observed?" and feed unmet outcomes back as inbox stubs. This stays lean — one frontmatter line and one retro question.

### 1.2 Shipped work that turns out wrong has no path — Medium

Where: README "Spec dependencies" / `/ag-abandon`; `docs/agentile-loop-runner.md` stop conditions.

The failure paths covered are: verify fails (bounce to build, then pause) and spec won't ship (abandon). Missing: a shipped spec that is wrong in production. Presumably it re-enters as a new stub, but nothing says so, and nothing links the fix back to the original spec (which sits in `done/` looking successful, and still satisfies dependencies).

Recommendation (refine): one paragraph in the README defining the rework path — production failure → `/ag-capture` a stub referencing the original slug; optionally a `superseded_by:` field on the done spec. Also document rollback expectations: ship is "flagged, reversible", but no stage owns flipping the flag off.

### 1.3 No way to release a claim without abandoning the spec — Medium

Where: `docs/agentile-customisation-and-concurrency.md` §5 and §9; `ag-wip` skill.

If a session dies mid-build and you want the item back in the ready queue, the only documented options are "edit the spec manually" (deferred decision) or `/ag-abandon` — which drops the spec entirely. That asymmetry will bite the first time a laptop dies mid-loop.

Recommendation (add): a small `/ag-release <slug>` (or an `ag-wip` action) that clears the claim and restores `status: ready`, reusing the existing lock helper. It is the natural counterpart of `/ag-next` and removes the only manual-frontmatter-surgery step in the whole system.

### 1.4 Multi-machine / multi-human concurrency limits are not surfaced to users — Medium

Where: `docs/agentile-customisation-and-concurrency.md` §8 (out of scope note); README "Concurrent loops".

The mutex is a local-filesystem flock, and claims live in spec frontmatter — but the docs never say whether claims are committed/pushed. If they aren't, a second human on another machine can't see them and will double-claim; if they are, every claim/release is a commit on trunk. The design doc parks cross-machine concurrency as out of scope, but the README sells "two loops running concurrently can never grab the same item" without the single-machine caveat.

Recommendation (refine): state the boundary in the README ("the claim lock is per-machine; for multi-human teams, push claims promptly / treat the repo host as the sync point") and decide explicitly whether claim stamps are committed.

### 1.5 "First be agile, then agentic" has no on-ramp — Low-medium

Where: `lean-agentic-loop.md` "The one rule"; README closing; `ag-init` skill.

The methodology's stated precondition (trunk, gates, tests exist and are healthy) is never checked or scaffolded. `/ag-init` scaffolds the Agentile layer but a project with no tests gets a `test-gate` that no-ops — i.e. the unhealthy loop is silently amplified, which is exactly what the one rule warns against.

Recommendation (add): `/ag-init` ends with a short readiness report — tests present? CI present? trunk-based? — phrased as observations, not blockers. Cheap, and it operationalises the methodology's most-quoted line.

### 1.6 Stakeholder communication and scaling — Low

Where: whole methodology.

For 1–5 person teams, dropping status ceremony is right. But the LEARN digest is one sentence away from also being the outward-facing report ("the digest doubles as your stakeholder update"). Cross-repo/team scaling is explicitly out of scope in the dependencies doc — fine, but the README should state that boundary so adopters don't assume it.

Recommendation (add, one line each): note the digest's dual use; note the single-repo boundary in the README.

## 2. Refinement

### 2.1 The two-axis triage route has no downstream consumer — Medium

Where: `lean-agentic-loop.md` "two-axis triage" and shaping section; README `.agentile/config.md` row ("triage routes").

Shaping scores Business Value × Technical Certainty and "recommends a route (foreground pair, background agent, spike, or drop)" — but nothing reads the route afterwards. `/ag-next` and `/ag-loop` claim purely by prefix order; a low-certainty "pair in foreground" spec will be happily claimed by an unattended loop. The triage is the methodology's main routing idea, and it currently terminates in prose.

Recommendation (refine): persist the route as frontmatter (e.g. `route: pair | async | spike`) and have `ag-claim` skip `route: pair` specs when running under `/ag-loop` (or have the loop pause on them). Alternatively, downgrade the triage honestly to "advice used during prioritisation". Either is fine; the half-state isn't.

### 2.2 "Spec" is both a stage and an artefact, and the spec stage is ambiguous — Medium

Where: customisation contract stage table (`docs/agentile-customisation-and-concurrency.md` §1); README loop diagram.

In the canonical table, stage `spec`'s consumer is `ag-spec` — but most specs are produced by `ag-shape`, which reads `shape.md`. So a `.agentile/spec.md` playbook governs only the trivial-work shortcut, while the artefact's shape lives in a third file (`spec-template.md`). A user asking "where do I customise what a spec is?" has three plausible answers.

Recommendation (refine): define it once — `shape.md` = what must be answered (DoR), `spec-template.md` = what the artefact looks like, `spec.md` = playbook for the shortcut path only — and say so in `playbooks.md`. Consider renaming the stage in the table to `spec (direct)` or folding it into shape (see 3.1).

### 2.3 Spikes are introduced and then dropped — Medium-low

Where: `lean-agentic-loop.md` shaping section ("open questions… become a timeboxed spike", `type: spike`).

A spike enters the queue as a spec, but nothing defines what plan/build/verify/ship mean for one. What does the reviewer gate check? What does "ship" mean (a written answer? an ADR?)? Does a spike satisfy a `depends_on`?

Recommendation (refine): three sentences somewhere canonical: a spike's deliverable is a written answer (ADR or note); its verify is "question answered within timebox"; on ship it moves to `done/` and satisfies dependencies like any spec.

### 2.4 Vocabulary needs one home — Low-medium

Where: across all docs.

Terms that drift: "Ready" (DoR-satisfied) vs `status: ready` vs claimable (ready + prefixed + deps shipped + under WIP limit); "archive" vs "done" (the dependencies doc still says `specs/archive/` in §`ag-claim` and §prioritise, post-rename); `wip_limit` lives in `prioritise.md` (README, essay) or "`prioritise.md`/`next.md`" (customisation doc §5). None of these is individually serious; together they make the system harder to hold in your head — for agents as much as humans.

Recommendation (add): a short glossary section in the README (stub, spec, Ready, prioritised, claimable, claimed, shipped, abandoned, spike, route, playbook, gate) and a one-line "Superseded by…" header on outdated design docs (see 6.4).

## 3. Reduction

### 3.1 `/ag-spec` vs `/ag-shape` — two doors to one artefact — Low

Where: README skills list; `ag-spec` skill description.

The only thing preventing `/ag-spec` from becoming the shaping-bypass everyone uses is a sentence of advice. The distinction "trivial vs non-trivial" is exactly the judgement the methodology says to make *during* shaping.

Recommendation (reduce, optionally): fold `/ag-spec` into `/ag-shape` as a fast path ("this looks trivial — skip the interview? y/n"). One command, one door, and the triage happens at the door. Not urgent; flag for the next consolidation pass.

### 3.2 Part 1 of `lean-agentic-loop.md` is a literature review inside the methodology — Low-medium

Where: `lean-agentic-loop.md` Part 1 (~45 lines of source summaries, including three sources that couldn't be retrieved).

Valuable provenance, wrong place. A third of the core methodology document is summaries of other people's articles, including entries that say "could not extract content; excluded". Any agent (or new human) pointed at "the methodology document" wades through this first.

Recommendation (reduce): move Part 1 to `docs/sources.md`, keep the seven cross-cutting themes in the main doc as the bridge. The methodology doc should lead with the methodology.

### 3.3 What's *not* over-specified — credit where due

The methodology resists ceremony well: no estimates, no sprints, stubs are one line, the Inbox has exactly one rule (capture must be instant), hooks no-op when unconfigured, deferred decisions are explicitly parked with rationale (§9 of the customisation doc is a model of restraint). `ag-inbox` being trivially "cat the inbox" is fine — it's an affordance, not ceremony. Nothing currently in the loop needs deleting.

## 4. Future-proofing

### 4.1 Turn-based-harness assumptions are baked into the methodology layer — Medium

Where: README "Running the loop" ("Claude Code is turn-based — there is no always-on process…"); `docs/agentile-loop-runner.md` Context.

The `/ag-loop` vs `/loop /ag-loop` split is a workaround for a 2026 harness limitation, presented as if it were part of the methodology. When harnesses grow resident background agents (already emerging), the two-command UX becomes an anachronism that the docs explain at length.

Recommendation (refine): state the invariant abstractly — *a runner has two modes: drain (work the current queue, stop) and watch (wait for work)* — then bind it: "in Claude Code today, watch = `/loop /ag-loop`". The methodology owns the modes; the harness owns the mechanism. One paragraph of restructuring future-proofs the whole section.

### 4.2 Same pattern for session/resume mechanics in Part 2 — Medium

Where: `lean-agentic-loop.md` Part 2 "Prioritisation and pulling as distinct acts" (file lock, session id, `claude --resume`).

Part 2 is supposed to be the tool-agnostic methodology (Part 3 is the Claude Code binding), but it now contains file locks, session ids and resume handles. The abstract claims are: *pull must be atomic; a claim must identify a resumable worker*. Those survive any future harness; the flock and UUID don't.

Recommendation (refine): in Part 2, keep "atomic claim + resumable worker handle" and push flock/session-UUID details down to Part 3. Similarly, `claimed_by: <session-id>` should be documented as "a worker handle (today: the Claude Code session id)" so multi-agent orchestrators or other tools can slot in.

### 4.3 Single-worker-per-loop assumption — Low

Where: `docs/agentile-loop-runner.md` out of scope ("Parallel fan-out within one /ag-loop — sequential per session").

Parallelism today = N sessions. When one session can supervise N builders, the claim model still works (each fan-out claims under the lock) — but only if `claimed_by` is a worker handle, not strictly a session id (see 4.2). The explicit out-of-scope note is good; just don't let the session-id assumption ossify in the spec frontmatter contract.

### 4.4 What future-proofs well — credit

The derived/stateless backlog (no blocked flags, no priority fields, everything computed from filenames + frontmatter), slug-based dependencies, plain-markdown artefacts, the playbook contract with forward-compatible unknown keys, and the fresh-context reviewer rationale ("independent context catches the builder's mistakes" — true at any capability level, not a context-window workaround) are all durable design. The Ruby-on-PATH requirement for hooks is a minor coupling, already documented.

## 5. Dual audience

### 5.1 Human responsibility per stage is scattered — Medium

Where: across README and essay.

Agents get a precise contract per stage (skill + playbook + tokens like `BLOCKED`/`UNPRIORITISED`). Humans get their responsibilities by inference: approve plans (essay), reorder priorities (README), sign off before ship (loop config), judge stale claims (`ag-wip`), answer shaping interviews. No single place says "at each stage, the human's job is X; the agent's job is Y".

Recommendation (add): one table in the README — stage | agent does | human does | default checkpoint? It would also have exposed finding 6.1 (the plan-approval gap) before this review did.

### 5.2 Artefact machine/human readability — strong

Specs (YAML frontmatter + markdown body), the inbox (checkbox lines), playbooks (directives + prose), `gates.json`, and rank-as-filename-prefix ("visible from `ls` without opening files") all serve both audiences well. The playbook split — deterministic keys for the machine, policy prose for judgement — is the best dual-audience pattern in the system and worth calling out explicitly in `playbooks.md` as a design rule for future config surfaces.

### 5.3 The methodology essay itself serves only humans — Low

`lean-agentic-loop.md` is the canonical statement of the methodology, but agents consume the methodology via skill bodies and `CLAUDE.agentile-section.md`. That's correct (don't stuff a 220-line essay into agent context) — but it means drift between essay and skills is invisible to agents. The fix is process, not artefact: a retro/release checklist item "essay, README, and skills still agree" (see 6.4).

## 6. Internal consistency

### 6.1 `/ag-loop` defaults contradict "plan is the cheapest place to steer" — High

Where: `lean-agentic-loop.md` Part 2 step 2 ("You correct the plan here — it's the cheapest place to steer") and Part 3 §2; vs `docs/agentile-loop-runner.md` (checkpoints only at `human_checkpoint: true` playbooks and before ship).

Under the shipped defaults, an `/ag-loop` run takes a spec through plan → build → verify with zero human contact and pauses only before merge — at which point the cheapest steering moment has already been spent on built code. The methodology and the runner disagree about where human judgement enters.

Recommendation (refine — pick one and say it everywhere): either (a) default `human_checkpoint: true` in the scaffolded `plan.md` playbook (humans loosen deliberately, matching the loop doc's "defaults are conservative" stance), or (b) make it route-aware — low-certainty specs pause at plan, high-certainty ones don't (this would also give finding 2.1's `route:` field its consumer) — or (c) amend the essay: "in loop mode you trade plan steering for throughput; the pre-ship checkpoint is your control". Any is coherent; the current state is not.

### 6.2 Part 3 of the essay describes a system that no longer exists — High

Where: `lean-agentic-loop.md` Part 3, §§1a–2 and "Roles" and "Minimal starter checklist".

Part 3 tells the reader to hand-build `.claude/commands/capture.md`, use `/capture`, `/shape`, `/spec`, point at a `spec-writer` subagent, and define five agents (`spec-writer`, `planner`, `builder`, `reviewer`, `release`). The plugin ships `/ag-*` commands and exactly three agents (`ag-planner`, `ag-builder`, `ag-reviewer`); `spec-writer`'s job is now the `ag-shape` skill and `release` doesn't exist. Meanwhile §3b is fully up to date — so the document is internally half-migrated, which is worse than uniformly old: a reader can't tell which parts are current.

Recommendation (refine): rewrite Part 3 as the *binding* of Part 2 to the shipped plugin (each stage → its `/ag-*` skill/agent/playbook), or explicitly retitle it "Appendix: building it by hand without the plugin". Reconcile the hats: either ship a release hat or state that ship is a skill-orchestrated step, not an agent. Update the starter checklist to "install the plugin, run `/ag-init`".

### 6.3 Ship erases the data that LEARN needs — High

Where: `docs/agentile-customisation-and-concurrency.md` §5 ("Release on ship: `status: shipped` and clear the claim"); `docs/agentile-loop-runner.md` step 4; vs governing principle 7 ("Measure flow, not output. Track lead time and where work waits") and `ag-retro`'s remit ("where work waited").

Clearing `claimed_at`/`claimed_by` on ship deletes the claim→ship interval — the core flow metric — from the artefact that `/ag-retro` mines. Stubs carry capture dates and specs presumably carry shaped dates, but the in-progress duration is destroyed at the finish line; recovering it from git archaeology contradicts the "state lives in the spec's own frontmatter" principle.

Recommendation (refine): on ship, *keep* `claimed_at` and add `shipped_at` (and on abandon, `abandoned_at` already exists — good precedent). Optionally add `shaped_at` at spec creation. Three timestamps give `/ag-retro` capture→ready, ready→claim (queue wait), claim→ship (cycle time) with zero extra ceremony.

### 6.4 The design docs disagree with each other and aren't marked as superseded — Medium

Where: `docs/agentile-customisation-and-concurrency.md` vs `docs/agentile-backlog-layout-and-abandon.md` and `docs/agentile-dependencies-and-prioritisation.md`.

Specifics: the customisation doc's status enum omits `abandoned` and says abandoning returns a spec to `ready` (the later abandon doc contradicts both); the dependencies doc still references `specs/archive/` after the rename to `done/`; the customisation doc still describes "assigns/updates a priority" frontmatter, retired by the prefix scheme; the parked `auto_start` flag is superseded by `/ag-loop`. Each doc is a dated snapshot — legitimate — but only the abandon doc carries a status line ("implemented"), and none says what supersedes what. An agent (or consultant) reading `docs/` cannot determine current truth.

Recommendation (refine): add a status header to every design doc (`Status: implemented / superseded by <doc> §n / current`), and adopt the rule that the README is the single normative description — design docs are history. Add "docs still agree" to the release checklist.

### 6.5 "Abandon" is overloaded — Medium

Where: customisation doc §5 ("On abandon: back to ready, claim cleared") vs README/abandon doc (abandon = drop forever, `status: abandoned`).

Two distinct operations share one verb: *releasing a claim* (work pauses, spec stays alive) and *abandoning a spec* (work is dropped). The first currently has no command at all (finding 1.3).

Recommendation (refine): fix the vocabulary — **release** (claim cleared, back to ready) vs **abandon** (spec dropped) — and correct the customisation doc's §5 wording when adding the status header.

### 6.6 Smaller inconsistencies — Low

- The loop is enumerated three ways: README (8 stages), essay Part 2 (steps 0–6 plus 1a/1b), customisation contract (10 canonical names including `prioritise`/`next`, which the README diagram omits). Pick the 10-stage canonical list as truth; show prioritise/next in the README diagram as the queue segment between spec and plan.
- Project/doc naming: the repo and core doc are `lean_agentic_loop`/`lean-agentic-loop.md`, the brand is Agentile. The README states the relationship once (good); consider renaming the essay to `methodology.md` with the LAL name kept in the body, so newcomers don't see two brands.
- Essay Part 2 says verify includes "**end-to-end** tests" as non-negotiable, but the gate vocabulary (`gates.json`: format, lint, test, build, deploy) has no e2e slot — either add an `e2e` key or note that `test` is expected to include it.

## Prioritised recommendations

1. **Resolve the plan-checkpoint contradiction (6.1).** Decide where human steering happens in loop mode and state it in the essay, README, and `loop.md`/`plan.md` defaults. Highest leverage: it's the methodology's own headline principle.
2. **Stop erasing flow data on ship (6.3).** Keep `claimed_at`, add `shipped_at` (and ideally `shaped_at`). Tiny change; rescues principle 7 and makes `/ag-retro` real.
3. **Rewrite essay Part 3 against the shipped plugin (6.2)** and move Part 1 to `docs/sources.md` (3.2). The core doc should be: themes → methodology → plugin binding.
4. **Give ship/learn a product feedback mechanism (1.1, 1.2).** `outcome:` field in the spec template, a retro question about shipped outcomes, and a documented rework path for shipped-but-wrong work.
5. **Add `/ag-release` (1.3)** and fix the release-vs-abandon vocabulary (6.5).
6. **Wire the triage route to a consumer or demote it to advice (2.1)** — option (b) under 6.1 solves both at once.
7. **Canonicalise the stage list and vocabulary (6.6, 2.4).** One 10-stage list, one glossary, README as normative truth; status headers on all design docs (6.4).
8. **Abstract the harness-specific mechanics (4.1, 4.2).** Drain/watch as methodology modes; flock/session-id/`/loop` as the Claude Code binding; `claimed_by` documented as a generic worker handle.
9. **Surface the concurrency boundary (1.4)** — single-machine lock, claim-commit policy — in the README.
10. **Add the human/agent responsibility table (5.1)** and the `/ag-init` readiness report (1.5). Both are small and serve the dual audience directly.
11. **Define spikes end-to-end (2.3)** and consider folding `/ag-spec` into `/ag-shape` (3.1) on the next consolidation pass.
