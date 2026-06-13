# Agentile — Per-Stage Customisation & Concurrent Loops

Design spec. Status: implemented 2026-06-10 — historical snapshot; the README and `methodology.md` are normative. Known drift: §5's "on abandon: back to ready" describes what is now called **releasing** a claim — abandoning moves a spec to `specs/abandoned/` (see agentile-backlog-layout-and-abandon.md); the status enum now includes `abandoned`; per-spec `priority:` frontmatter was replaced by `NNNN-` filename prefixes (see agentile-dependencies-and-prioritisation.md); the parked `auto_start` flag was superseded by `/ag-loop` (see agentile-loop-runner.md); specs may now be directories (`NNNN-<slug>/SPEC.md`).

## Context

Agentile ships a fixed methodology (skills, agents, hooks) and a per-project `.agentile/` config layer that the skills read at runtime. Today that layer customises a few things: `shaping.md` (Definition of Ready), `gates.json` (deterministic commands), `config.md` (paths + triage routes).

Two gaps motivated this work:

- **Customisation is ad hoc.** Only a handful of stages are customisable, each in its own bespoke way. We want a *uniform* rule so any stage of the loop can be tailored per project — e.g. "execute ready work via the `worktree-workflow` skill", "verify means this checklist plus a human sign-off".
- **The loop is single-threaded by assumption.** Nothing lets several loops run at once without two of them grabbing the same item. Concurrency (worktrees, background agents) is already encouraged by the methodology, so safe parallel pulling needs to be first-class.

This spec defines (1) a uniform per-stage customisation contract, (2) guided scaffolding for it, (3) prioritisation and pulling as distinct first-class acts, and (4) a concurrency model with mutex-protected, resumable claims.

## 1. The uniform customisation contract

**Principle.** Customisation is a property of the methodology, not a feature of particular stages. For *any* loop stage `X`, that stage's consumer checks for `.agentile/<X>.md`. Present → honour it. Absent → built-in baseline. Same rule everywhere; adding a new stage automatically makes it customisable.

**Canonical stage names** (the playbook filename always equals the stage name):

| Stage | Playbook | Consumer |
|-------|----------|----------|
| capture | `capture.md` | `ag-capture` skill |
| shape | `shape.md` | `ag-shape` skill |
| spec | `spec.md` | `ag-spec` skill |
| prioritise | `prioritise.md` | `ag-prioritise` skill |
| next | `next.md` | `ag-next` skill |
| plan | `plan.md` | `ag-plan` skill |
| build | `build.md` | `ag-builder` agent (dispatched by `ag-next`/`ag-plan`) |
| verify | `verify.md` | `ag-reviewer` agent |
| ship | `ship.md` | ship step |
| learn | `learn.md` | `ag-retro` skill |

The filename follows the **stage**; the *reader* may be a skill or an agent. The contract only says "that stage's consumer reads it".

**Playbook format — thin frontmatter + prose.** Optional YAML frontmatter for the deterministic directives; a markdown body for project policy/definition that the consumer follows.

```markdown
---
delegate_to: worktree-workflow   # run this stage by invoking the named skill
also_run: [some-other-skill]     # extra skills alongside the baseline
human_checkpoint: true           # pause for explicit human sign-off before handing off
---

Prose: the project's definition / conventions / policy for this stage.
Treated as policy layered on the baseline. (e.g. a Definition of Done.)
```

**Recognised directives (v1 vocabulary, extensible):**

- `delegate_to: <skill>` — execute the stage by invoking that skill, passing the spec/context. **Replaces** the baseline execution.
- `also_run: [<skill>…]` — additional skills to invoke **alongside** the baseline.
- `human_checkpoint: true|false` — **add** a gate: stop and require explicit human sign-off before the stage completes/hands off.

Unknown frontmatter keys are ignored (forward-compatible). The prose body is always free-text policy.

**Semantics / precedence:**

- Absent playbook → pure baseline behaviour.
- Prose → **augments** the baseline (project policy on top).
- `delegate_to` → **replaces** the stage's execution with the named skill.
- `human_checkpoint` → **adds** a gate.

**How every consumer reads it.** Each stage skill/agent gains one standard preamble:

> Read `.agentile/<stage>.md` if it exists. If `delegate_to` is set, run this stage by invoking that skill with the current spec/context. If `human_checkpoint: true`, stop and require explicit human sign-off before proceeding. Run any `also_run` skills. Treat the prose body as project policy layered on the baseline below.

## 2. Scaffolding + guided customisation

**`/ag-init`** additions:

- Write `.agentile/playbooks.md` — a short README explaining the contract, the directive vocabulary, and that *any* stage name can get a `<stage>.md`.
- Drop **commented stub playbooks** for the high-touch stages — `build.md`, `verify.md`, `prioritise.md`, `next.md` — inert until edited, self-documenting. (Not all stages, to avoid clutter; the rest are created on demand.)
- Rename the existing `shaping.md` template → `shape.md` (see §4).

**`/ag-customise <stage>`** — a new guided skill (shaping, but for config):

- Reads the stage's baseline behaviour and any existing playbook.
- Interviews the user ("how should this project run `<stage>`?") — e.g. "execute ready work how? → wire `build.md` to `delegate_to: worktree-workflow`".
- Writes/updates `.agentile/<stage>.md` (creating the stub if missing), setting frontmatter directives and prose from the conversation.
- Works for any stage name uniformly.

## 3. Prioritise and Next — distinct first-class acts

These are **two different acts** and must not be collapsed:

- **Prioritise** (`ag-prioritise`) — reasons over the *whole* ready list and imposes an order (assigns/updates a priority). Mutates ordering; claims nothing. Reads `prioritise.md` for the scheme. The two-axis **Business Value × Technical Certainty** is the default scheme (shape still *tags* value/certainty on each spec; prioritise *orders* by them). `prioritise.md` also holds `wip_limit`.
- **Next / Pull** (`ag-next`) — a thin, transactional act: take the top **unclaimed** ready item, atomically claim it, and start its cycle (plan → build → verify → ship). Mutates one item's state. Reads `next.md` for pull policy.

**Next is not part of build.** It is the entry that *feeds* the work cycle; folding it into build would hide the claim — exactly the thing concurrency needs to control. Flow:

```
ready specs (tagged value×certainty by shape)
  → ag-prioritise  (orders the list)
  → ag-next        (atomically claims top unclaimed, stamps it, kicks off the cycle)
  → plan → build → verify → ship
```

A read-only **`/ag-wip`** scans specs and shows what is in flight, who holds each, and how to resume it.

## 4. Cleanup

- Rename `.agentile/shaping.md` → `.agentile/shape.md` so the playbook name equals the canonical stage name. Update `ag-shape` and any references. (Low cost — the plugin is only installed locally.)
- Bring `shape.md` under the uniform contract (it gains optional frontmatter; its prose remains the Definition of Ready).

## 5. Concurrency model

**The race.** Two loops both read the ordered list, both see item X on top, both claim it. Fix: make **select-and-claim a single atomic critical section** under a mutex.

**The mutex.** Wrap "scan ready specs → pick top unclaimed within `wip_limit` → mark it claimed" in an exclusive lock. `flock(1)` is absent on stock macOS, so the plugin ships a small **Ruby claim helper** (`File#flock(File::LOCK_EX)` — works on macOS + Linux, consistent with the Ruby hooks), with an atomic `mkdir` lock-dir as the zero-dependency conceptual fallback. Only one loop is ever inside the critical section, so there is no double-pick.

**The claim record.** Each spec owns its state in its own frontmatter (no central ledger to go stale):

```yaml
status: in_progress          # ready | in_progress | shipped
claimed_by: 550e8400-…       # session UUID — the resume handle (see §6)
label: billing-loop          # optional human-readable tag
claimed_at: 2026-06-10T12:04:00Z
```

- On release: back to `ready`, claim cleared (abandoning — dropping the spec entirely — came later; see the backlog-layout doc). On ship: `status: shipped`; claim fields are kept and `shipped_at` is stamped (the claim→ship interval is the cycle-time record).
- **Multiple WIP is first-class**, bounded by `wip_limit` in `prioritise.md`/`next.md`. `ag-next` refuses to pull past the limit.
- **Stale-claim recovery.** A claim whose session is long dead with no progress (e.g. no commits, `claimed_at` older than a configurable TTL) can be reclaimed; `/ag-wip` surfaces stale claims.

## 6. Resumable, session-stamped claims

The claim is not just "who holds it" — it is a **handle back to the work**, so an exited loop can be resumed with its full context.

**Confirmed Claude Code capabilities** (verified against the docs):

- There is **no programmatic way to set the session name** (`/rename` is interactive-only). So we do not name sessions.
- The **session UUID is stable across resume** and is the durable, resumable handle: `claude --resume <uuid>` returns to the exact session and appends to its transcript. (Forking mints a new id; plain resume does not.)
- A skill running bash **cannot read its own session id** (no `CLAUDE_SESSION_ID` env var), **but a hook can** — hooks receive `session_id` in their JSON input.

**Mechanism:**

- The plugin adds a **`SessionStart` hook** that reads `session_id` and surfaces it into the session as injected context, so the loop knows its own id when it runs `ag-next`.
- `ag-next` stamps the claimed spec with `claimed_by: <session-uuid>` (+ optional `label`).
- `/ag-wip` prints, per in-flight item, the exact resume command:

```
rate-limit-login   in_progress   billing-loop
  → resume:  claude --resume 550e8400-…
```

- Optional sugar: after pulling, `ag-next` may remind the user to `/rename` the session for readability — but resume-by-id always works regardless.

## 7. Changes to the plugin

New:

- `skills/ag-prioritise/SKILL.md`, `skills/ag-next/SKILL.md`, `skills/ag-wip/SKILL.md`, `skills/ag-customise/SKILL.md`
- A Ruby claim helper (atomic select-and-claim under a lock), e.g. `bin/ag-claim`
- A `SessionStart` hook (surfaces `session_id`) added to `hooks/hooks.json`
- Templates: `templates/agentile/playbooks.md`, and stub `build.md`, `verify.md`, `prioritise.md`, `next.md`

Modified:

- Every stage skill/agent: add the standard "read your playbook" preamble
- `ag-init`: scaffold the new stubs + `playbooks.md`; rename `shaping.md` → `shape.md`
- `ag-shape`: read `shape.md` (renamed), still tags value×certainty for prioritise
- Spec template / spec-writing: include the claim fields (`status`, `claimed_by`, `label`, `claimed_at`) and the value×certainty tags
- README + the methodology essay: document prioritise vs next, concurrency, customisation

## 8. Out of scope (for now)

- Cross-machine concurrency (the mutex is local-filesystem; multiple machines on one repo over a network FS is not guaranteed). Note it as a limitation.
- A central kanban UI; `/ag-wip` text view is enough for v1.
- Auto-running loops (a background runner that calls `ag-next` on a schedule) — the pieces enable it, but the runner itself is a later piece.

## 9. Deferred decisions (build the certain core; revisit later)

These are intentionally **not** decided now. v1 takes the minimal, safe, forward-compatible default for each, so nothing is blocked and nothing is foreclosed.

- **`ag-next` behaviour → claim + report (v1).** It atomically claims the top unclaimed item, stamps it, and reports what it pulled — it does **not** auto-start the cycle. Auto-start is a future `next.md` policy flag; "claim + report" is its prerequisite, so no rework.
- **Stale claims → surfaced, not auto-reclaimed (v1).** `/ag-wip` shows each claim's age and flags likely-stale ones; reclaiming is **manual** (edit the spec / a small command). The TTL + auto-reclaim policy is parked.
- **Confirmed now:** the claim helper is Ruby in `bin/` (matches the existing hooks).
