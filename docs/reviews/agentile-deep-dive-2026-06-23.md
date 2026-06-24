---
title: Agentile deep dive — what's working, what to improve, and do we need separate loops?
status: current
author: Claude (Opus 4.8), commissioned by Keith Rowell
date: 2026-06-23
method: triangulated — Agentile source (methodology.md, 14 skills, 3 agents, bin/ag-claim), a live audit of the nimbus-1500 (Quote Kit 500) repo where Agentile has run ~33 specs since 2026-06-21, external theory (Shape Up, Theory of Constraints, DORA, AI-agent practice), and first-hand use of capture/shape/prioritise in this session
note: supersedes nothing; complements methodology-review.md and separation-audit.md, which are snapshots of an earlier state
---

# Agentile deep dive

## The answer first

Agentile is **ahead of the field on the two things most teams get wrong**: it correctly identifies that when building becomes cheap the bottleneck moves to *the ask*, and it separates plan / build / review into three independent agent contexts with a fresh-context reviewer. Both are right, and both are rare.

But the loop's **investment is distributed inversely to its own thesis**. The build middle — the cheap, automatable, two-way-door part — is the most polished stage (a 6.5 KB `build.md` hardened by real incidents). The two stages that sit on the human bottleneck — **shaping the ask** upstream and **verifying/trusting the result** downstream — are the thinnest. `verify.md` is an unbuilt stub. There is no `ship.md` or `learn.md`. There is no `brief.md`, which the design itself says makes value-scoring "guesswork". The shaping track has no cadence, no queue-health metrics, and no WIP discipline, while the build track has all three.

So, to the specific question — *does Agentile need separate loops for crafting-the-ask, building, and reviewing?* **You already have two of them**: shaping (capture → shape → prioritise) runs off-loop as a human conversation, and building (next → plan → build → verify → ship) runs as `ag-loop`. The problem is not a missing loop. It is that **the front loop was never instrumented as a loop**, and the constraint lives in the front loop. The highest-leverage move is not to add machinery to the middle — it is to give the shaping/decision front-end the same loop discipline (cadence, queue health, WIP limits, an appetite/circuit-breaker, metrics on where work waits *before* it is claimable) that the execution track already enjoys, and to turn `verify` from a stub into a real gate. **Rebalance toward the ends; stop polishing the middle.**

The rest of this document argues that case from four angles: what's genuinely working, the central irony, the separate-loops question in depth, and the human-as-bottleneck question — then a prioritised set of concrete changes.

## What's genuinely working (don't touch these)

These are strengths, evidenced, and worth protecting because the temptation in any redesign is to "improve" them.

**The bottleneck diagnosis is correct and explicit.** "As the building becomes automatic, what you ask for becomes the most important." Most teams discover this the hard way after drowning their reviewers; Agentile started from it. The whole front-loading instinct ("it makes the front of the loop — capture, shape, prioritise, plan — the real work") is the right instinct.

**Three hats with a fresh-context reviewer is the consensus best practice, well implemented.** `ag-planner` / `ag-builder` / `ag-reviewer`, each in its own context, with the reviewer explicitly told "you did not write this code, and that is the point." This is the single most reproduced finding in multi-agent practice — agents catch others' mistakes far better than their own — and Agentile has it as load-bearing structure, not a bolt-on. The separation rests on the right justification ("true at any capability level, not a context-window workaround").

**Determinism where it belongs.** `gates.json` makes build/test/lint/deploy commands, not "hopeful sentences." Gates run before the scarce human looks, which is exactly how you exploit a human constraint — no human minute is spent on a machine-catchable defect.

**Cheap kills happen in words, not code.** The `abandoned/` folder is *empty* — and that is the system working, not failing. Ideas died during shaping (`merge "site-wide aliases" into call-notes`, `dedupe duplicate stub`, `split nav-only; capture dark-theme`, `drop Build A stub`). Reshaping in prose before code exists is the cheapest possible place to kill an idea, and the evidence shows it happening routinely.

**Capture is genuinely free.** The one-line stub with "do not ask follow-up questions, do not estimate, do not triage" is correct discipline — the cost of writing an idea down is lower than the cost of holding it. In this session I captured four stubs mid-conversation without derailing anything.

**Flow-not-output is the stated measure**, and the loop self-corrects. When concurrent builders caused three split-brain git incidents on 2026-06-22, the lesson was encoded durably into `build.md` rather than lost. ADRs are written for the right things (integrations, data, external services — 6 of them) and not for UI tweaks. Commit grammar is disciplined enough that every spec traces cleanly from `spec:` → `plan(agentile):` → `feat:` → `ship(agentile): → done/`.

The decision to drop estimates ("we don't estimate, we just do it") is also correct *as far as it goes* — but see the appetite discussion below, because "no estimate" threw out something useful along with the waste.

## The central finding: effort is inverse to the constraint

Hold three facts from the nimbus-1500 audit next to each other.

1. `build.md` is 6.5 KB of hard-won operational rules. It is the most developed playbook in the project.
2. `verify.md` is an unbuilt stub: `human_checkpoint: true` plus "Run `/ag-customise verify` to build it out." There is no `ship.md` and no `learn.md`.
3. There is no `brief.md` at all — so every Business-Value score the loop has ever produced was, by the design's own admission, "scored against nothing."

Now hold them next to the thesis: *the constraint is the ask (upstream) and trust (downstream), not the building (middle)*. The effort went into the middle. The build stage got rich precisely because concurrency incidents **forced** it to — pain drove investment. The shaping and verification stages stayed thin because nothing forced them, and their failures are quieter and slower to surface.

And those quiet failures are real. This session surfaced two of them in production within an hour:

- The **`hardwire-drafts-folder`** spec changed data *semantics* (a per-user folder choice became a fixed folder) but shipped with — in the commit message's own words — "**no migration**." `resolve_draft_folder_id` trusts a stale cached id, so production users keep getting drafts in the *old* folder ("Pool Price Drafts") and will until a 404 forces a self-heal. A thin `verify` stage with no Definition of Done that asks "did this change data semantics? is there a migration/backfill?" let an operational tail ship undone.
- **Production had zero Depot records**, silently breaking distance lookup, because seeding is a manual afterthought rather than part of `ship`. The "delivery/ops" anchor is named in the principles but not mechanised anywhere.

Neither is a build defect. The builder built what the spec said. Both are **front-and-back-of-loop defects**: an under-specified ask (the spec didn't carry its operational tail) and an under-built verify/ship gate (nothing checked for it). They are exactly the failures the thesis predicts, landing exactly where the thesis says the constraint is — and the tooling is thinnest there.

This is the core recommendation in one line: **move the care from where it is cheap to where it is the constraint.**

## The "separate loops" question, answered

You asked whether Agentile needs distinct loops for crafting-the-ask, for building, and for reviewing. The precise answer requires separating two ideas that the word "loop" blurs: **separation of concerns** (distinct phases, distinct contexts) versus **separate cadences** (distinct runners, each with its own rhythm, queue, and WIP).

On **separation of concerns**, Agentile is already right and already done. Shape, build, and review are distinct contexts; the reviewer is fresh. The theory is unambiguous that this is correct, so do not collapse them.

On **separate cadences**, the truth is subtler — and it is the real insight:

**You already run two loops; they are just wildly asymmetric.** The build loop (`ag-loop`: claim → plan → build → verify → ship) is a fully instrumented runner — atomic claims, WIP limit, retry limits, resume handles, and a retro that mines its claim→ship cycle time. The shaping loop (capture → shape → prioritise) is a set of one-shot conversational skills with **no runner, no cadence, no queue-health view, no WIP limit on human-touch stages, and no metrics on pre-claim wait time.** Shape Up's central structural claim is that shaping and building must run on *separate tracks with separate rhythms*, and that building only ever consumes already-shaped work. Agentile has the separation but has only built the machinery for one of the two tracks — the wrong one, given the bottleneck.

So the recommendation is **not "add a third loop."** Adding ceremony would betray Agentile's low-ceremony ethos. It is:

1. **Name and instrument the shaping loop as a first-class track.** Give it a cadence (a recurring "shaping/betting session"), a queue-health view (inbox depth, oldest unshaped stub, ready-but-unprioritised count), and a WIP limit on *items awaiting a human decision* — because that queue, not the build queue, is where lead time hides. Today the retro measures claim→ship and is blind to idea→claimable; the `created` date is stamped at shaping, so every "sub-day lead time" in the audit is really *shape-to-ship*, and the weeks an idea waits in the inbox are invisible. Instrument the invisible part.

2. **Keep the build loop as it is.** It works. Subordinate its throughput to human review capacity (below), but do not add to it.

3. **Promote review from stub to real gate — but not necessarily its own runner.** Review is the downstream constraint, so it needs a genuine Definition of Done (`verify.md`), and human review should be treated as its own *queue* with its own WIP limit, because unreviewed diffs are the classic place AI throughput piles up. Whether that queue gets a dedicated runner or stays a checkpoint inside `ag-loop` matters less than that it stops being empty prose.

In short: **three concerns, two loops, one trust-gate** — and the loop that needs building is the one you haven't built, the front one.

## The human-as-bottleneck question (the crux)

Your framing is right: Agentile should serve humans and agents, but the human is the constraint, so the human gets the help. When building is nearly free, the constraint does not vanish — it *splits and moves to the two ends*: deciding **what** to build, and verifying **that** what was built is trustworthy. Everything between should be agent plus deterministic gates. Four consequences follow.

**1. Spend human attention on decisions and acceptance criteria, not authoring or monitoring.** The most expensive defect in an agent loop is a vague acceptance criterion: the agent builds the wrong thing fast and confidently, and the entire cost lands on the now-constraining reviewer, who must reverse-engineer intent from code. Precise, testable acceptance criteria are the **highest-leverage human artifact in the whole loop**, because they convert expensive judgment-review into cheap evidence-checking ("does the test for criterion 3 pass?" instead of "is this right?"). Shaping should therefore treat acceptance criteria as a first-class, testability-scored output — not a section to fill in.

**2. Shaping should be agent-drafts-human-approves, not human-authors.** Here is a live data point from this very session: when you said "shape them yourself, ask if you need to," I produced four full specs — problem statements, acceptance criteria, scope boundaries, edge cases, de-risked open questions — by reading the codebase, and needed you for only four genuine product decisions (surfaced as one `AskUserQuestion`). That is the bottleneck-relieving pattern. The default `/ag-shape` interview ("one or two questions at a time") puts the *authoring* burden on the human; the cheaper pattern puts the human in the *deciding* seat and lets the agent draft, research, and de-risk. **Authoring is not deciding.** The human must still own the decisions — but they should red-line a draft, not compose from blank. This is the single biggest unrealised relief for the human bottleneck, and it costs nothing but a change of default posture in the shape skill.

**3. Review must be evidence-first ("grey-box"), because line-by-line does not survive agent throughput.** The data is stark: AI-heavy teams produce ~98% more PRs but spend ~91% more time in review (~4.3 min on an AI diff vs ~1.2 on a human one). You cannot line-read your way out of that. The reviewer's doctrine should be: verify against acceptance criteria and *evidence* (gate output, tests, screenshots, a reproduction), not against every line. Gates run first so the human only ever sees what gates cannot catch — intent-fit, taste, the subtly-wrong-thing. Agentile's reviewer is told to "say what you verified, not just 'looks good'," which is the right instinct; the missing piece is a `verify.md` that makes "verified" mean *evidence checked against criteria*, including the operational-tail checklist that would have caught the draft-folder migration.

**4. Respect the Ironies of Automation.** Bainbridge's 1983 result is uncomfortably exact here: automating the easy parts leaves the human with an arbitrary residue of the *hardest* judgment, plus a monitoring role humans are biologically bad at, plus skill atrophy from lack of practice. Agentile's human is left with precisely this — shaping taste and trust-verification, the two hardest things to do well and stay sharp at. The design implication is to **support that residual judgment actively**: small diffs (so vigilance is feasible), evidence-first review (so the human is checking, not staring), and shaping prompts that *help the human think* (offer the rabbit-holes, propose the criteria, name the appetite) rather than just transcribe what they already know. Do not assume that removing the typing made the human's job easier. It made it rarer and harder.

## Angle-by-angle improvements

**Shape.** Make the Definition of Ready a *de-risking* checklist, not just a completeness checklist (Shape Up: unshaped = unresolved rabbit-holes, and unshaped work must not reach a builder). Add two questions that would have caught today's bugs: *"Does this change data semantics or storage? If so, name the migration/backfill,"* and *"What operational step does shipping require (migration, seed, deploy, flag flip)?"* Shift the default posture to agent-drafts-human-approves.

**Brief.** Write the missing `brief.md`. Until it exists, every Business-Value score — including the four "medium"s I assigned in this session's prioritisation — is, by the design's own words, guesswork. This is the cheapest high-leverage fix available: the triage instrument at the front of the loop is currently running on vapour.

**Prioritise / appetite.** "We don't estimate" correctly kills story points, but it threw out *appetite* with the estimate. Appetite is not "how long" — it is "how much is this worth," and it doubles as a circuit-breaker: if a spec blows its appetite in rework, it kicks back to shaping rather than grinding. `verify_retry_limit: 1` is a partial circuit-breaker already; generalise the idea. Appetite in an agent loop should bound the **human-review budget** ("worth one reviewer pass, not three"), since review is the scarce resource.

**Build.** Leave it. It is the one stage that does not need help. If anything, the lesson of `build.md` is that the loop *will* invest where pain forces it — so the meta-fix is to make the front-and-back-of-loop failures *hurt visibly* (via metrics) so they attract the same investment.

**Verify.** Build the playbook. This is where the draft-folder tail shipped. A real `verify.md` with an operational-tail checklist and an evidence-first doctrine is the highest-value single artifact you could add. Treat awaiting-review as a WIP-limited queue.

**Ship / ops.** The thinnest stage in the system has no skill, no `ship.md`, and no mechanism for the "flagged, reversible" half of its own stated rule — the audit found *no feature flags anywhere*, and seeding/migration tails are manual. The delivery/ops anchor is named but not mechanised. At minimum, ship should run a deterministic post-merge checklist (migrations applied, seeds present, deploy step, flag state) — the equivalent of `gates.json` for the release, not the build.

**Learn / retro.** The retro mines claim→ship cycle time but is blind to the front-of-loop queues where the human constraint actually sits. Add inbox-dwell and ready-queue-age to the digest. Also have the retro reconcile **context drift**: the audit found CLAUDE.md still describing two parallel QuickSet implementations when the frontend half was deleted. "Context is infrastructure" is violated when the loop produces code faster than it updates its own standing context; the retro is the place to catch that.

**Concurrency.** The design is honest that the claim lock is per-machine and the worktree/backlog split is a footgun guarded only by prose. For the human-bottleneck framing the relevant scaling is many agents feeding one reviewer — so the most useful guardrail is a WIP limit on *awaiting-review*, not more locking. (The cross-machine multi-human problem is real but secondary; park it as the design already does.)

**The `/ag-spec` bypass.** Spec-acceptance is a one-way door; `/ag-spec` lets work reach a builder without the shaping interview, guarded only by a sentence of advice. Given that the ask is the constraint, the one place worth adding a small structural guard is here — a triage self-check that *refuses* (not just advises against) the direct path when certainty is not high or the blast radius is non-trivial.

## Prioritised recommendations

Ordered by leverage-on-the-constraint per unit effort.

1. **Write `brief.md`.** Tiny effort; un-fakes every value score at the front of the loop. (Relieves: upstream decision quality.)
2. **Add the operational-tail questions to `shape.md`'s Definition of Ready** (data-semantics → migration; ship → ops step). Tiny effort; directly prevents the class of bug that hit prod today. (Relieves: downstream trust.)
3. **Build `verify.md` as an evidence-first gate with an operational-tail checklist**, and treat awaiting-review as a WIP-limited queue. Medium effort; this is the downstream constraint made real. (Relieves: downstream trust — the new bottleneck.)
4. **Flip shaping's default to agent-drafts-human-approves.** Low effort (a posture change in the skill); the biggest single relief for human authoring load. (Relieves: upstream human cost.)
5. **Instrument the front-of-loop queues in the retro** (inbox dwell, ready-queue age) and reconcile context drift. Medium effort; makes the invisible constraint visible so it attracts investment. (Relieves: measurement honesty — you cannot manage the bottleneck you cannot see.)
6. **Add appetite as a circuit-breaker bounded by review budget.** Medium effort; protects the scarce reviewer from rework grind. (Relieves: downstream trust.)
7. **Mechanise `ship` ops** (post-merge checklist: migrations/seeds/deploy/flags). Medium effort; closes the delivery/ops gap the principles name but don't enforce. (Relieves: downstream delivery.)
8. **Turn the `/ag-spec` guard from advice into a refusal.** Small effort; protects the one-way door at the front. (Relieves: upstream decision quality.)

Note that **six of the eight are front-or-back-of-loop** — which is the whole point.

## What not to do

Do not add ceremony in the name of "more loops." The instinct behind the question is right, but the fix is rebalancing and instrumentation, not new machinery — Agentile's low-ceremony ethos is a feature.

Do not optimise the build stage further. It is not the constraint, and effort there is, in Theory-of-Constraints terms, an illusion of improvement that just builds inventory in front of the human.

Do not let "agent velocity" or diffs-per-day become a reported metric. It is the canonical vanity number of an agentic loop; the audit's flat "sub-day lead times" already flatter the system by measuring shape-to-ship while hiding idea-to-claimable. Measure the baton's wait states, not the runners' busyness — Agentile already says this; the work is to actually instrument it at the front of the loop, where the human, and therefore the constraint, lives.
