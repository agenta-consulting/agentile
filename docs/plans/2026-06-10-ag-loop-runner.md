# /ag-loop Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ag-loop`, a drain-mode runner that claims ready work, carries it through the cycle pausing for human checkpoints, and repeats — with watch mode via `/loop /ag-loop`.

**Architecture:** `/ag-loop` is an orchestration **skill** that composes existing skills (`ag-next`, `ag-plan`, build via `build.md`, `ag-reviewer`) — no new executable code. Behaviour is tuned by a `.agentile/loop.md` config (max_iterations, pause_before_ship, stop_on_gate_failure, verify_retry_limit, on_empty, watch).

**Tech Stack:** Markdown SKILL.md; YAML frontmatter config; `claude plugin validate` for verification. No Ruby — the runner only drives other skills.

**Spec:** `docs/agentile-loop-runner.md` (read it first).

**Repo:** the plugin at `company/internal_projects/lean_agentic_loop/` (own git repo, remote `agenta-consulting/agentile`, default branch `main`).

Commit after each task. Work in a git worktree of the **plugin** repo (create it manually: `git -C <plugin> worktree add <path> -b feat/ag-loop`; the native EnterWorktree grabs the outer agenta repo because the plugin is nested).

---

### Task 1: `loop.md` config stub

**Files:**
- Create: `templates/agentile/loop.md`

- [ ] **Step 1: Write the file with exactly this content:**

```
---
max_iterations: 5          # items per /ag-loop invocation — a runaway guard
pause_before_ship: true    # stop for human sign-off before each ship/merge
stop_on_gate_failure: true # halt/pause on a failing gate rather than continuing
verify_retry_limit: 1      # bounce a failed verify back to build this many times before pausing
on_empty: watch            # under /loop, an empty backlog: watch (keep waiting) | stop (end the loop)
watch: self-paced          # how to wait when idle: self-paced | a fixed interval like 10m
---

# Loop policy

How this project wants `/ag-loop` to behave. The runner also honours every
per-stage `human_checkpoint: true` regardless of these settings.

- `/ag-loop` alone drains the ready backlog then stops.
- `/loop /ag-loop` drains and then watches — waiting for new ready work and
  starting on it as it appears. `on_empty` and `watch` only apply under `/loop`.
```

- [ ] **Step 2: Verify frontmatter parses:**

```bash
cd <worktree> && ruby -ryaml -e 'd=YAML.load(File.read("templates/agentile/loop.md")[/\A---\n(.*?)\n---/m,1]); raise unless d["max_iterations"]==5 && d["on_empty"]=="watch"; puts "loop.md ok"'
```

- [ ] **Step 3: Commit:**

```bash
git add templates/agentile/loop.md && git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "Add loop.md config stub for /ag-loop"
```

### Task 2: `ag-loop` runner skill

**Files:**
- Create: `skills/ag-loop/SKILL.md`

Read `skills/ag-next/SKILL.md` and `skills/ag-prioritise/SKILL.md` first for house style (Australian/British spelling; blank line after headings and before lists).

- [ ] **Step 1: Write the skill.** Frontmatter exactly:

```
---
name: ag-loop
description: Run the Agentile loop as a runner — claim the next ready item, carry it through plan/build/verify, pause before ship (and at any human checkpoint), then repeat. Drains the backlog within one turn; wrap in /loop to also watch for new work. Trigger phrases include "/ag-loop", "run the loop", "start working through the backlog", "keep building ready items".
allowed-tools: AskUserQuestion, Bash, Read, Edit, Skill, Agent
---
```

Body — a `# ag-loop` heading, a one-line intro, then write these sections as proper skill instructions (not a pasted list). The body MUST specify this algorithm and guards:

**Load policy.** Read `.agentile/loop.md` for `max_iterations` (default 5), `pause_before_ship` (default true), `stop_on_gate_failure` (default true), `verify_retry_limit` (default 1), `on_empty` (default watch), `watch` (default self-paced). Missing file → use those defaults. Always also honour any per-stage `human_checkpoint: true`.

**The loop (repeat up to `max_iterations` times):**

1. **Resume check.** First look for a spec in the specs dir with `status: in_progress` and `claimed_by` equal to *this* session's id (the SessionStart hook surfaces it; otherwise check for any in_progress item this loop created). If found, continue that item from where it left off — do NOT claim a new one. Otherwise run `/ag-next` (invoke the ag-next skill) to claim the top ready item.
2. **If `/ag-next` reports `NONE`** → the backlog is drained: stop the loop and report what was completed this run (watch behaviour is handled by `/loop`, see below).
3. **If `/ag-next` reports `WIP_FULL`** → stop and report that the WIP limit is held; suggest `/ag-wip`.
4. **Run the claimed item:** invoke `/ag-plan <spec>` → build (read `.agentile/build.md`; if it sets `delegate_to`, invoke that skill, else dispatch the `ag-builder` agent) → verify (dispatch the `ag-reviewer` agent; it applies `.agentile/verify.md`).
5. **On a failing gate or verify:** bounce back to build up to `verify_retry_limit` times. If still failing (and `stop_on_gate_failure`), **pause**: end the turn reporting the failure and the spec it's on. Do not advance to the next item on red.
6. **Before ship:** if `pause_before_ship` is true OR a stage set `human_checkpoint: true`, **pause**: end the turn with a concise summary of the item and ask for explicit sign-off ("approve to ship `<slug>`?"). Otherwise continue.
7. **Ship:** on approval (or when no pause applies), ship/merge per the project's conventions, set the spec `status: shipped`, clear the claim fields, and continue the loop.

**Pausing.** "Pause" means end the turn; all state lives in the spec (`in_progress` + claim), so re-invoking `/ag-loop` (or the user replying "continue"/"approved") resumes via the resume check. Never claim new work while an item is paused awaiting a human checkpoint.

**Stop conditions** (report and halt): `NONE`, `WIP_FULL`, gate failure past retry with `stop_on_gate_failure`, `max_iterations` reached, any unrecoverable error.

**Watch mode (when run under `/loop`).** A bare `/ag-loop` drains then stops. To watch, the user runs `/loop /ag-loop`. Make this behave well: an empty backlog reports "idle — nothing ready" cheaply (so `/loop` waits rather than churning); if `on_empty: stop`, tell `/loop` the loop is complete; when self-paced, wait longer when idle and return promptly after doing work. Document both invocations.

- [ ] **Step 2: Verify frontmatter + key behaviours present:**

```bash
cd <worktree> && ruby -ryaml -e 'YAML.load(File.read("skills/ag-loop/SKILL.md")[/\A---\n(.*?)\n---/m,1]); puts "frontmatter ok"'
grep -qi 'resume check' skills/ag-loop/SKILL.md && grep -qi 'pause_before_ship' skills/ag-loop/SKILL.md && grep -qi 'max_iterations' skills/ag-loop/SKILL.md && grep -q '/ag-next' skills/ag-loop/SKILL.md && grep -qi 'on_empty' skills/ag-loop/SKILL.md && echo "behaviours present"
```

- [ ] **Step 3: Commit:**

```bash
git add skills/ag-loop && git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "Add /ag-loop runner: drain-mode cycle, pause before ship, bounded, resumable; watch via /loop"
```

### Task 3: Scaffold loop.md + retire the `auto_start` note

**Files:**
- Modify: `skills/ag-init/SKILL.md`
- Modify: `templates/agentile/next.md`

- [ ] **Step 1:** In `ag-init`'s scaffold list, add `loop.md` (copied into the project `.agentile/`). In the closing report, add a line: "Run the loop with `/ag-loop` (drains the backlog); `/loop /ag-loop` to also watch for new work."

- [ ] **Step 2:** In `templates/agentile/next.md`, replace the commented `auto_start` line/note with a pointer to the runner. New `next.md` content:

```
---
# wip_limit is read from prioritise.md; next.md is the pull policy.
---

# Next — this project's pull policy

`/ag-next` atomically claims the highest-priority unclaimed ready spec and reports
it. WIP is capped by `wip_limit` in prioritise.md. To run claims continuously (claim
→ build → verify → ship → repeat), use `/ag-loop`.
```

- [ ] **Step 3: Verify:**

```bash
cd <worktree> && grep -q 'loop.md' skills/ag-init/SKILL.md && grep -q 'ag-loop' skills/ag-init/SKILL.md && echo "ag-init ok"
grep -qv 'auto_start' templates/agentile/next.md && grep -q 'ag-loop' templates/agentile/next.md && echo "next.md ok"
ruby -ryaml -e 'YAML.load(File.read("templates/agentile/next.md")[/\A---\n(.*?)\n---/m,1]); puts "next.md frontmatter ok"'
```

- [ ] **Step 4: Commit:**

```bash
git add skills/ag-init/SKILL.md templates/agentile/next.md && git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "ag-init scaffolds loop.md; next.md points iteration at /ag-loop (retire auto_start note)"
```

### Task 4: Docs

**Files:**
- Modify: `README.md`, `lean-agentic-loop.md`, `templates/CLAUDE.agentile-section.md`

- [ ] **Step 1:** `README.md` — add `/ag-loop` to the Skills list. Add a short **"Running the loop"** subsection: `/ag-loop` drains the ready backlog (claim → build → verify → pause before ship → repeat); `/loop /ag-loop` drains and watches (waits for new work, starts on it); the default pause-before-ship posture; configurable in `.agentile/loop.md`.
- [ ] **Step 2:** `lean-agentic-loop.md` — in Part 3, add a short note that `/ag-loop` runs the loop as a runner (drain mode) and `/loop /ag-loop` makes it a standing watcher, pausing for human sign-off before merges.
- [ ] **Step 3:** `templates/CLAUDE.agentile-section.md` — add one line: "Run the loop with `/ag-loop` (or `/loop /ag-loop` to keep watching for work); it pauses for your sign-off before each ship."
- [ ] **Step 4: Verify + commit:**

```bash
cd <worktree> && grep -q 'ag-loop' README.md && grep -q 'ag-loop' lean-agentic-loop.md && grep -q 'ag-loop' templates/CLAUDE.agentile-section.md && echo "docs ok"
git add README.md lean-agentic-loop.md templates/CLAUDE.agentile-section.md && git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "Docs: /ag-loop runner + watch via /loop"
```

### Task 5: Validate, sync, exercise

- [ ] **Step 1: Static validation:**

```bash
cd <worktree>
claude plugin validate .
ruby -ryaml -e 'Dir.glob("skills/*/SKILL.md").each{|f| YAML.load(File.read(f)[/\A---\n(.*?)\n---/m,1])}; puts "all skill frontmatter ok (#{Dir.glob("skills/*/SKILL.md").size} skills)"'
```

Expected: validation passes; 12 skills (the 11 existing + `ag-loop`).

- [ ] **Step 2: Merge to main + verify live inventory** (done by the controller after review, from the main plugin tree, not the worktree):

```bash
# in the main plugin working tree:
git merge --ff-only feat/ag-loop
claude plugin details agentile 2>&1 | sed -n '/Component inventory/,/MCP servers/p'   # expect ag-loop among 12 skills
```

- [ ] **Step 3: Behavioural walkthrough (manual, after session reload).** In a scratch project: `/ag-init` scaffolds `loop.md`; shape two trivial specs; `/ag-loop` claims the top item, runs plan/build/verify, then **pauses** asking to ship; on "approve" it ships and moves to the second; with `max_iterations: 1` it stops after one. Confirm `/loop /ag-loop` drains then reports idle when empty.

---

## Self-review

- **Spec coverage:** runner algorithm → Task 2; loop.md config → Task 1; scaffolding + auto_start retirement → Task 3; watch mode → Task 2 (behaviour) + Task 4 (docs); docs → Task 4; validation → Task 5. All spec sections covered.
- **Placeholders:** none — loop.md and next.md are exact content; the skill body is a precise algorithm spec (the deliverable is prose, so the plan specifies required behaviour + exact frontmatter rather than duplicating the whole narrative).
- **Consistency:** config keys `max_iterations / pause_before_ship / stop_on_gate_failure / verify_retry_limit / on_empty / watch` are identical across loop.md (Task 1) and the ag-loop body (Task 2); skill count 11→12 consistent.
