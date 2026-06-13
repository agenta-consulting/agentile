# Methodology Fixes + Spec-as-Directory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the high/medium findings of `docs/reviews/methodology-review.md` and introduce the spec-as-directory contract (SPEC.md + plan.md + supporting files), keeping docs and implementation consistent in one branch.

**Architecture:** A spec is either a flat file `NNNN-<slug>.md` (the lightweight starting form) or a directory `NNNN-<slug>/SPEC.md` (created when the plan stage promotes it to hold `plan.md` and supporting files). The claim pool is `specs/*.md` + `specs/*/SPEC.md`; `done/` and `abandoned/` hold either form one level deeper. The loop gains route-aware plan checkpoints (`route: foreground`/`spike` pause at plan); ship keeps `claimed_at` and stamps `shipped_at`. The essay is restructured into `methodology.md` (themes → methodology → Claude Code binding) with sources moved to `docs/sources.md`.

**Tech Stack:** Ruby (bin helpers + tests), Markdown (skills, templates, docs). Tests run with plain `ruby bin/test-ag-claim.rb`.

**Worktree:** `.worktrees/methodology-fixes`, branch `methodology-fixes`. All paths below are relative to the worktree root.

**Decisions already made by Keith (do not relitigate):**

- Spec-as-directory confirmed; flat `.md` stays legal as the pre-plan form; plan stage promotes flat → directory.
- Route-aware plan checkpoints (review finding 6.1 option b).
- Essay: full restructure AND rename to `methodology.md`.
- `/ag-release`, route enforcement in `ag-claim`, and all plugin-review findings (dead hooks, bootstrap brief, model pins) are OUT of scope — they belong to Plan 2.
- Folding `/ag-spec` into `/ag-shape` is OUT of scope (flagged for a later consolidation pass).

## Task 1: ag-claim — dir-spec support

**Files:**

- Modify: `bin/ag-claim`
- Test: `bin/test-ag-claim.rb`

- [ ] **Step 1: Add failing tests for directory specs**

Append to `bin/test-ag-claim.rb` (before the final `puts "ALL PASS"`), and add this helper after the existing `spec` helper:

```ruby
def dirspec(dir, dname, status:, depends_on: [])
  d = File.join(dir, dname)
  FileUtils.mkdir_p(d)
  spec(d, "SPEC.md", status: status, depends_on: depends_on)
end
```

New cases:

```ruby
# 7. directory spec: specs/0001-x/SPEC.md is claimable; path returned is the SPEC.md; stamped
Dir.mktmpdir do |d|
  dirspec(d, "0001-x", status: "ready")
  path = claim(d)
  raise "dir claim: #{path}" unless path.end_with?("0001-x/SPEC.md")
  fm = YAML.safe_load(File.read(path)[/^---\n(.*?)\n---/m, 1], permitted_classes: [Time, Date])
  raise "dir stamp" unless fm["status"] == "in_progress" && fm["claimed_by"] == "s"
end

# 8. mixed flat + dir specs order by prefix across both forms
Dir.mktmpdir do |d|
  spec(d, "0002-flat.md", status: "ready")
  dirspec(d, "0001-dir", status: "ready")
  raise "mixed order: #{claim(d)}" unless claim(d).end_with?("0001-dir/SPEC.md")
end

# 9. plan.md and other files beside SPEC.md are never specs
Dir.mktmpdir do |d|
  dirspec(d, "0001-x", status: "ready")
  File.write(File.join(d, "0001-x", "plan.md"), "---\nstatus: ready\n---\n# plan\n")
  first = claim(d)
  raise "spec not plan: #{first}" unless first.end_with?("0001-x/SPEC.md")
  raise "plan not claimable: #{claim(d)}" unless claim(d) == "NONE"
end

# 10. dependency shipped as a directory spec in done/ resolves
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready", depends_on: ["b"])
  dirspec(File.join(d, "done"), "0005-b", status: "shipped")
  raise "done dir dep: #{claim(d)}" unless claim(d).end_with?("0001-a.md")
end

# 11. a directory without SPEC.md is not a spec
Dir.mktmpdir do |d|
  FileUtils.mkdir_p(File.join(d, "0003-junk"))
  File.write(File.join(d, "0003-junk", "notes.md"), "---\nstatus: ready\n---\n")
  raise "junk dir: #{claim(d)}" unless claim(d) == "NONE"
end
```

- [ ] **Step 2: Run tests to verify the new cases fail**

Run: `ruby bin/test-ag-claim.rb`
Expected: FAIL at case 7 (`dir claim: NONE`) — current code only pools top-level `*.md`.

- [ ] **Step 3: Rewrite spec enumeration in `bin/ag-claim`**

Replace the `load_spec` function and the status-map/pool block (lines 16–38) with:

```ruby
RESERVED = %w[done abandoned].freeze

# A spec is a flat file <root>/NNNN-<slug>.md (identity from the filename) or a
# directory <root>/NNNN-<slug>/SPEC.md (identity from the directory name; plan.md
# and supporting files beside SPEC.md are never specs).
def load_spec(path, ident)
  raw = File.read(path)
  fm  = (YAML.safe_load(raw[/\A---\n(.*?)\n---/m, 1] || "", permitted_classes: [Time, Date]) || {})
  m   = ident.match(/\A(\d+)-(.+)\z/)
  { path: path, raw: raw, fm: fm, prefix: (m ? m[1].to_i : nil), slug: (m ? m[2] : ident) }
end

# Enumerate the specs directly under one root: flat *.md files plus */SPEC.md dirs.
def specs_in(root)
  flat = Dir.glob(File.join(root, "*.md")).map { |p| load_spec(p, File.basename(p, ".md")) }
  dirs = Dir.glob(File.join(root, "*", "SPEC.md"))
            .reject { |p| RESERVED.include?(File.basename(File.dirname(p))) }
            .map { |p| load_spec(p, File.basename(File.dirname(p))) }
  flat + dirs
end
```

Inside the lock block, replace the `all`/`shipped`/`pool` computation with:

```ruby
  # Claim pool: specs directly under the specs root. done/ and abandoned/ hold
  # specs one level deeper, so they fall outside these globs by construction.
  pool = specs_in(specs_dir)

  # Status map includes done/ and abandoned/ so shipped specs resolve deps.
  # Abandoned specs keep status: abandoned, so they never count as shipped; a
  # dependent of an abandoned spec therefore stays BLOCKED.
  resolved = pool + specs_in(File.join(specs_dir, "done")) + specs_in(File.join(specs_dir, "abandoned"))
  shipped = {}
  resolved.each { |s| shipped[s[:slug]] = true if s[:fm]["status"] == "shipped" }
```

Change the tie-break (dir specs all have basename `SPEC.md`):

```ruby
  chosen = eligible.min_by { |s| [s[:prefix], s[:slug]] }
```

Update the header comment: the printed path is "the spec's .md file — for a directory spec, its SPEC.md".

- [ ] **Step 4: Run tests to verify all pass**

Run: `ruby bin/test-ag-claim.rb`
Expected: `ALL PASS` (all 11 groups).

- [ ] **Step 5: Commit**

```bash
git add bin/ag-claim bin/test-ag-claim.rb
git commit -m "ag-claim: support directory specs (NNNN-slug/SPEC.md) alongside flat files"
```

## Task 2: ag-dependents — dir-spec support

**Files:**

- Modify: `bin/ag-dependents`
- Test: `bin/test-ag-dependents.rb`

- [ ] **Step 1: Add failing tests**

Add the same `dirspec` helper as Task 1 to `bin/test-ag-dependents.rb`, then append before `puts "ALL PASS"`:

```ruby
# 6. directory-spec dependent is found, identified by its directory slug
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready")
  dirspec(d, "0002-b", status: "ready", depends_on: ["a"])
  got = dependents(d, "a")
  raise "dir dependent: #{got.inspect}" unless got == ["b"]
end

# 7. plan.md beside SPEC.md is not read as a spec
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready")
  dirspec(d, "0002-b", status: "ready", depends_on: ["a"])
  File.write(File.join(d, "0002-b", "plan.md"), "---\nstatus: ready\ndepends_on: [a]\n---\n")
  got = dependents(d, "a")
  raise "plan ignored: #{got.inspect}" unless got == ["b"]
end
```

- [ ] **Step 2: Run to verify failure**

Run: `ruby bin/test-ag-dependents.rb`
Expected: FAIL at case 6 (`dir dependent: []`).

- [ ] **Step 3: Update enumeration in `bin/ag-dependents`**

Replace the `slug_of` helper and the glob loop with:

```ruby
def each_active_spec(specs_dir)
  Dir.glob(File.join(specs_dir, "*.md")).each do |path|
    yield path, File.basename(path, ".md")
  end
  Dir.glob(File.join(specs_dir, "*", "SPEC.md")).each do |path|
    dname = File.basename(File.dirname(path))
    next if %w[done abandoned].include?(dname)
    yield path, dname
  end
end

reverse = Hash.new { |h, k| h[k] = [] } # dep slug -> [dependent slugs]
each_active_spec(specs_dir) do |path, ident|
  fm = (YAML.safe_load(File.read(path)[/\A---\n(.*?)\n---/m, 1] || "", permitted_classes: [Time, Date]) || {})
  next unless %w[ready in_progress].include?(fm["status"])
  m = ident.match(/\A(\d+)-(.+)\z/)
  s = m ? m[2] : ident
  Array(fm["depends_on"]).each { |dep| reverse[dep.to_s] << s }
end
```

Update the header comment: "Active = specs directly under the specs root — flat `*.md` or `*/SPEC.md` directories."

- [ ] **Step 4: Run both test files to verify pass**

Run: `ruby bin/test-ag-dependents.rb && ruby bin/test-ag-claim.rb`
Expected: `ALL PASS` twice.

- [ ] **Step 5: Commit**

```bash
git add bin/ag-dependents bin/test-ag-dependents.rb
git commit -m "ag-dependents: recognise directory specs in the reverse-dependency walk"
```

## Task 3: Templates — spec contract v2

**Files:**

- Modify: `templates/agentile/spec-template.md`
- Create: `templates/agentile/plan-template.md`
- Modify: `templates/agentile/loop.md`
- Modify: `templates/agentile/config.md`
- Modify: `templates/agentile/playbooks.md`

- [ ] **Step 1: spec-template.md — outcome, shipped_at, claim-field wording**

In the frontmatter block:

After the `created:` line, add:

```yaml
outcome: <one observable metric or check that will prove the change worked in production>
```

Replace the claim-fields comment line with:

```yaml
# Claim fields — set by /ag-next when the item is pulled; KEPT after ship so the
# claim→ship interval (cycle time) survives for /ag-retro:
```

After the abandon-fields comment block, add:

```yaml
# Ship fields — set by the ship stage; absent until shipped:
# shipped_at:                 # ISO8601
```

After the frontmatter, before `# <Title>`, add this note:

```markdown
<!-- A spec may be a flat file (specs/NNNN-<slug>.md) or a directory
     (specs/NNNN-<slug>/SPEC.md). The plan stage promotes a flat spec to a
     directory so plan.md and supporting files (designs, notes, findings)
     can live beside it. -->
```

- [ ] **Step 2: Create plan-template.md**

Write `templates/agentile/plan-template.md`:

```markdown
# Plan — <spec title>

Written by the plan stage into the spec's directory as `plan.md`. Review and
amend this file directly — the build stage follows what it says.

## Files to touch

<The files this change creates or modifies, and why each.>

## Approach

<The implementation approach, in enough detail that a fresh-context builder
cannot misread the intent.>

## Test strategy

<Which gates from `.agentile/gates.json` prove this work, plus any new tests
to write.>

## Risks and unknowns

<What could go wrong; what is assumed; what to check before merging.>

## ADR

<Link any ADR drafted for this plan, or "none".>
```

- [ ] **Step 3: loop.md — pause_at_plan key**

Add to the frontmatter after `pause_before_ship`:

```yaml
pause_at_plan: route       # pause for plan review: always | route (foreground & spike specs) | never
```

Add to the body list:

```markdown
- `pause_at_plan: route` pauses after `plan.md` is written when the spec's
  `route` is `foreground` or `spike` — the cheapest place to steer. Review or
  amend `plan.md` in place, then reply "approved". `background` specs run
  through without a plan pause.
```

- [ ] **Step 4: config.md — routes now consumed downstream**

In the `## Routes` section, replace the `foreground` and `spike` bullet lines with:

```markdown
- **foreground** — pair in real time; you steer step by step. Under `/ag-loop`,
  a foreground spec pauses after planning so you can review `plan.md` before
  any code is written.
- **spike** — timeboxed exploration to resolve unknowns; produces findings
  (`findings.md` or an ADR in the spec's directory), not shipping code. Pauses
  at plan like foreground work.
```

- [ ] **Step 5: playbooks.md — record the dual-audience design rule**

Append:

```markdown
Design rule for any future config surface: **frontmatter keys are for the
machine** (deterministic, forward-compatible — unknown keys are ignored);
**prose is for judgement** (policy the agent weighs in context). Keep the two
separate, the way every playbook above does.
```

- [ ] **Step 6: Commit**

```bash
git add templates/agentile/
git commit -m "Templates: spec contract v2 — outcome + shipped_at fields, plan-template, route-aware loop pausing"
```

## Task 4: ag-plan — promote to directory, write plan.md

**Files:**

- Modify: `skills/ag-plan/SKILL.md`

- [ ] **Step 1: Rewrite the Steps section**

Replace steps 3–6 in `skills/ag-plan/SKILL.md` with:

```markdown
3. Produce the plan. Prefer one of:
   - **Plan Mode** — propose the approach and edit nothing until the user approves. This is the default for foreground work.
   - **ag-planner subagent** — dispatch the `ag-planner` agent (fresh context) for a focused plan when the spec is sizable or you want an independent read.
4. The plan must cover: **files to touch**, **approach**, **test strategy** (which gates from `.agentile/gates.json` prove it), and **risks / unknowns**.
5. **Persist the plan.** Promote the spec to its directory form if it is still a flat file, then write the plan beside it:
   - If the spec is `<specs>/NNNN-<slug>.md`: `mkdir <specs>/NNNN-<slug>/` then `git mv <specs>/NNNN-<slug>.md <specs>/NNNN-<slug>/SPEC.md`.
   - Write the plan to `<specs>/NNNN-<slug>/plan.md` using `.agentile/plan-template.md` as the structure.
   - Supporting material gathered while planning (sketches, notes) belongs in the same directory.
6. **ADR check** — if the spec makes a far-reaching or hard-to-reverse decision, draft a new ADR in `docs/adr/` from `.agentile/adr-template.md` (next number in sequence) as part of the plan, link it from `plan.md`'s ADR section, and have the user accept it.
7. Present the plan for approval, pointing at `plan.md` so the user can amend it directly — an edited `plan.md` is the approved plan. On approval, hand off to the build step: first read `.agentile/build.md`; if it sets `delegate_to: <skill>`, invoke that skill with the spec and `plan.md` **instead**; otherwise dispatch the `ag-builder` agent (ideally in a worktree), passing the spec path and `plan.md`. Do not write implementation code in this skill.
```

- [ ] **Step 2: Update the description frontmatter**

Replace the `description:` with:

```yaml
description: Turn a Ready spec into a written, reviewable plan before any code — promotes the spec to its directory form and writes plan.md (files to touch, approach, test strategy, risks) beside SPEC.md, using the ag-planner subagent or Plan Mode. Recommends an ADR for risky specs. Trigger phrases include "/ag-plan", "plan this spec", "plan the work", "propose an approach".
```

- [ ] **Step 3: Commit**

```bash
git add skills/ag-plan/SKILL.md
git commit -m "ag-plan: promote spec to directory form and persist the plan as plan.md"
```

## Task 5: ag-loop — route-aware plan pause, ship keeps flow data

**Files:**

- Modify: `skills/ag-loop/SKILL.md`

- [ ] **Step 1: Load policy — add pause_at_plan**

In the policy field list add (after `pause_before_ship`):

```markdown
- `pause_at_plan` — when to pause for plan review: `always`, `route` (pause when the spec's `route` is `foreground` or `spike`), or `never` (default `route`)
```

- [ ] **Step 2: Step 1 resume check — dir specs**

In Step 1, replace "scan the specs directory … for any spec whose frontmatter" with "scan the specs directory — both flat `*.md` files and `*/SPEC.md` directory specs at its top level — for any spec whose frontmatter".

- [ ] **Step 3: Step 4 (Plan) — route-aware pause**

Replace Step 4's body with:

```markdown
Invoke `/ag-plan <spec-path>`. It writes the plan to `plan.md` inside the spec's directory (promoting a flat spec to its directory form first).

Then decide whether to pause for plan review:

- If `.agentile/plan.md` (the stage playbook) sets `human_checkpoint: true` — always pause.
- Else if `pause_at_plan` is `always` — pause.
- Else if `pause_at_plan` is `route` and the spec's `route` is `foreground` or `spike` — pause. This is the methodology's "cheapest place to steer": low-certainty work gets a human eye on the plan before any code exists; `background` (high-certainty) work runs through.
- Else continue to Step 5.

On a pause: end the turn with a one-paragraph summary of the plan and the line "Plan written to `<spec-dir>/plan.md` — review or amend it, then reply 'approved'." An amended `plan.md` is the approved plan; do not advance until approval is given.
```

- [ ] **Step 4: Step 8 (Ship) — keep claim fields, stamp shipped_at, move the whole spec**

Replace Step 8's numbered list items 2–4 with:

```markdown
2. Set `status: shipped` in the spec's frontmatter and add `shipped_at:` (ISO8601 — `date -u +%Y-%m-%dT%H:%M:%SZ`).
3. **Keep** `claimed_by`, `claimed_at`, and `label` — the claim→ship interval is the cycle-time data `/ag-retro` mines; never erase it at the finish line.
4. Move the spec into `<dir>/specs/done/` (create the directory if it does not exist) using `git mv` — the whole `NNNN-<slug>/` directory for a directory spec (plan and supporting files travel with it), or the `NNNN-<slug>.md` file for a flat spec. This removes it from the active numbered list while keeping it resolvable as a shipped dependency by `ag-claim`.
```

- [ ] **Step 5: Step 5 (Build) — pass plan.md**

In Step 5, change "passing the spec path and the build playbook as context" to "passing the spec path, its `plan.md`, and the build playbook as context".

- [ ] **Step 6: Commit**

```bash
git add skills/ag-loop/SKILL.md
git commit -m "ag-loop: route-aware plan checkpoint; ship keeps claim data and stamps shipped_at"
```

## Task 6: Queue skills — dir-aware (ag-prioritise, ag-next, ag-wip, ag-abandon)

**Files:**

- Modify: `skills/ag-prioritise/SKILL.md`
- Modify: `skills/ag-next/SKILL.md`
- Modify: `skills/ag-wip/SKILL.md`
- Modify: `skills/ag-abandon/SKILL.md`

- [ ] **Step 1: ag-prioritise — enumerate and rename both forms**

In Step 1, replace "List every `*.md` file at the top level of that directory" with "List every spec at the top level of that directory — flat `*.md` files and `NNNN-<slug>/` directories containing a `SPEC.md` (skip `done/` and `abandoned/`)". Replace the slug definition sentence with: "A spec's **slug** is its filename (flat form) or directory name (directory form) with any leading `NNNN-` prefix and the `.md` extension stripped."

In Step 5, after the first paragraph add: "For a directory spec, rename the **directory** (`git mv <specs>/0003-<slug>/ <specs>/0001-<slug>/`) — never the `SPEC.md` inside it. The collision-safe two-step applies to directories exactly as to files."

- [ ] **Step 2: ag-next — report dir claims**

In Step 5's file-path bullet, append: "The path is the spec's `.md` file — for a directory spec, its `SPEC.md`; the spec's working set (`plan.md`, supporting files) lives in the same directory."

- [ ] **Step 3: ag-wip — list both forms, release vocabulary**

In Step 2, replace "List the spec files at the top level" with "List the specs at the top level — flat `*.md` files and `*/SPEC.md` directory specs".

In Step 4, replace the stale-claim warning text with:

```markdown
> Likely stale — **release the claim** (set `status: ready` and clear `claimed_by`, `claimed_at`, and `label`) to put it back in the queue, or resume it with the command above. Releasing a claim is not abandoning: the spec stays live.
```

- [ ] **Step 4: ag-abandon — move whole directories**

In Step 2, replace the slug definition with the same dual-form sentence as Step 1 above, and change the active-spec listing to "(`<dir>/specs/*.md` and `<dir>/specs/*/SPEC.md`, `status: ready` or `in_progress`)".

In Step 6 item 5, replace with: "`git mv` the spec into `<dir>/specs/abandoned/` (create the directory if it does not exist) — the whole `NNNN-<slug>/` directory for a directory spec, or the `NNNN-<slug>.md` file for a flat spec — preserving its name as a record."

- [ ] **Step 5: Commit**

```bash
git add skills/ag-prioritise/SKILL.md skills/ag-next/SKILL.md skills/ag-wip/SKILL.md skills/ag-abandon/SKILL.md
git commit -m "Queue skills: handle directory specs; release-vs-abandon vocabulary in ag-wip"
```

## Task 7: ag-shape + ag-spec — outcome field, spike deliverable

**Files:**

- Modify: `skills/ag-shape/SKILL.md`
- Modify: `skills/ag-spec/SKILL.md`

- [ ] **Step 1: ag-shape Step 3 — interview for the outcome**

In the Step 3 interview checklist sentence, after "acceptance criteria," insert "the observable **outcome** (the one metric or check that will prove the change worked — written to the `outcome:` frontmatter field),".

- [ ] **Step 2: ag-shape Step 5 — spike deliverable and directory note**

In the **Spike** bullet, append: "A spike's deliverable is a written answer, not code: its build is the timeboxed exploration, its verify is 'question answered within the timebox', and on ship its findings (`findings.md` in the spec's directory, or an ADR) move to `done/` — satisfying dependencies like any spec."

In the **Graduate to a spec** bullet, append: "Write the spec as a flat file; the plan stage promotes it to a directory (`NNNN-<slug>/SPEC.md`) when `plan.md` is written. If the shaping session itself produced supporting material (a sketch, a data sample), create the directory form now and put the material beside `SPEC.md`."

- [ ] **Step 3: ag-spec — outcome field**

In step 4, after "filling every field" insert ", including `outcome:` (the observable check that proves it worked)".

- [ ] **Step 4: Commit**

```bash
git add skills/ag-shape/SKILL.md skills/ag-spec/SKILL.md
git commit -m "ag-shape/ag-spec: capture the outcome metric; define the spike deliverable"
```

## Task 8: ag-retro + ag-init — outcome follow-up, flow timestamps, readiness report

**Files:**

- Modify: `skills/ag-retro/SKILL.md`
- Modify: `skills/ag-init/SKILL.md`

- [ ] **Step 1: ag-retro Step 1 — read done/ with timestamps**

In Step 1's `specs/` bullet, replace with: "`specs/` and `specs/done/` — which specs shipped, which stalled, which became spikes. Shipped specs keep `created`, `claimed_at`, and `shipped_at` in frontmatter: compute ready→claim (queue wait) and claim→ship (cycle time) from them directly."

- [ ] **Step 2: ag-retro Step 2 — outcome question**

Add a bullet to Step 2:

```markdown
- **Did shipped work actually work?** For each spec shipped since the last retro, check its `outcome:` field — was the outcome observed? Unverified or unmet outcomes become new inbox stubs (`/ag-capture`), referencing the original slug.
```

- [ ] **Step 3: ag-init Step 4 — scaffold plan-template**

In the Step 4 file list, after the `.agentile/spec-template.md` line add:

```markdown
- `.agentile/plan-template.md`
```

- [ ] **Step 4: ag-init — readiness report**

Add a new step between Step 6 and Step 7 (renumber the report step):

```markdown
## Step 7 — Readiness report (observations, not blockers)

The methodology's precondition is "first be agile, then agentic" — a working
trunk, gates, and tests. Check and report, without blocking:

- **Tests** — does `gates.json` have a `test` command? Does the repo have a test directory/framework?
- **CI** — is there a CI config (`.github/workflows/`, etc.)?
- **Trunk** — is there a default branch the team integrates to? Any long-lived divergent branches?

Phrase each as an observation ("No test command configured — the test-gate hook
will no-op until one exists"), so an unhealthy loop is visible rather than
silently amplified.
```

- [ ] **Step 5: Commit**

```bash
git add skills/ag-retro/SKILL.md skills/ag-init/SKILL.md
git commit -m "ag-retro: mine flow timestamps and shipped outcomes; ag-init: readiness report + plan-template"
```

## Task 9: README overhaul

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Opening — cut the quip, retitle the link**

Line 5: delete the sentence "We replaced the standup with a digest, so you can stand down."

Line 7: replace with: "Agentile is the implementation of the **Lean Agentic Loop** methodology — the full statement is in [`methodology.md`](./methodology.md). This README is the operating manual for the plugin, and the normative description of its current behaviour; the design notes in `docs/` are historical snapshots."

- [ ] **Step 2: Loop diagram — show the queue segment**

Replace the loop code block with:

```
capture → shape → spec → (prioritise → next) → plan → build → verify → ship → learn
```

Add after the stage bullets: "`prioritise` and `next` are the queue segment between a Ready spec and the work starting — ordering is editorial and human, pulling is transactional and atomic. They are stages like any other (each has a playbook), shown in brackets because they manage the queue rather than transform the work."

Update the **plan** bullet to: "**plan** — `/ag-plan` promotes the spec to its directory form and writes `plan.md` beside `SPEC.md`: files to touch, approach, test strategy, risks. The plan is a file you review and amend, not a chat message."

Update the **ship** bullet to: "**ship** — small, flagged, reversible merges to trunk. The spec keeps its claim timestamps and gains `shipped_at`, then moves — directory and all — to `specs/done/`."

- [ ] **Step 3: Backlog layout — directory specs**

Replace the layout code block with:

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

Add after it:

```markdown
A spec starts as a flat file and is **promoted to a directory by the plan
stage** (`git mv` to `NNNN-<slug>/SPEC.md`, `plan.md` written beside it). Flat
and directory forms are both legal everywhere; a directory simply means the
spec has a plan or supporting material. The rank prefix sits on the file or
directory name, so `ls specs/` is still the queue.
```

- [ ] **Step 4: Tailoring table — plan-template row**

Add a row after `spec-template.md`:

```markdown
| `.agentile/plan-template.md` | The shape of a plan (`plan.md` in the spec's directory). |
```

- [ ] **Step 5: Running the loop — route-aware steering**

In the "Running the loop" section, after the "Either way, pause-before-ship is the default" sentence, add:

```markdown
Steering happens at two points. **Plan** is the cheap one: with the default
`pause_at_plan: route`, the loop pauses after writing `plan.md` for any spec
routed `foreground` or `spike` — you review or amend the plan file, reply
"approved", and code gets written to the amended plan. High-certainty
`background` specs run through without the plan pause. **Ship** is the final
gate: nothing merges without your sign-off unless you loosen
`pause_before_ship` deliberately.
```

- [ ] **Step 6: Concurrent loops — boundary + release vocabulary**

In the `/ag-wip` bullet, replace "Stale claims are surfaced for human judgement — Agentile flags them, but does not auto-reclaim." with "Stale claims are surfaced for human judgement — Agentile flags them but does not auto-reclaim; **releasing** a claim (back to `ready`, claim fields cleared) is distinct from **abandoning** the spec (dropped for good)."

Add at the end of the section:

```markdown
The claim lock is a **per-machine** file lock: it serialises concurrent loops
on one machine. Across machines, the repository is the sync point — commit and
push claim stamps promptly, and treat a pushed claim as authoritative. Agentile
is single-repo by design; cross-repo or cross-team coordination is out of scope.
```

- [ ] **Step 7: Rework path subsection**

After the "Spec dependencies" section add:

```markdown
### When shipped work turns out wrong

A shipped spec that fails in production re-enters the loop as new work:
`/ag-capture` a stub referencing the original slug, shape it, ship the fix.
Optionally add `superseded_by: <new-slug>` to the original spec in `done/` so
the record shows what corrected it. Ship is flagged and reversible — turning
the flag off is part of the fix, not an afterthought. The original spec stays
in `done/` and still satisfies dependencies; abandonment is only for work that
never shipped.
```

- [ ] **Step 8: Glossary**

Add before "## Install (in a project)":

```markdown
## Glossary

- **stub** — a one-line idea in the inbox; not yet ready to build.
- **spec** — a shaped, Ready work item: a flat `NNNN-<slug>.md` or a `NNNN-<slug>/SPEC.md` directory.
- **Ready** — satisfies the Definition of Ready in `.agentile/shape.md`; `status: ready`.
- **prioritised** — carries an `NNNN-` rank prefix; an unprefixed spec is Ready but not claimable.
- **claimable** — prioritised, `status: ready`, unclaimed, all `depends_on` shipped, WIP limit not hit.
- **claimed** — pulled by `/ag-next`: `status: in_progress` plus `claimed_by`/`claimed_at` (the resume handle).
- **release** — clear a claim and return the spec to `ready`; the spec stays live.
- **abandon** — drop a spec for good (`/ag-abandon`); it moves to `specs/abandoned/` with the reason.
- **shipped** — merged and stamped `shipped_at`; the spec moves to `specs/done/` and satisfies dependencies.
- **spike** — a spec whose deliverable is an answer (`findings.md` or an ADR), not shipping code.
- **route** — the triage outcome (`foreground` / `background` / `spike`); decides pairing vs delegation and where the loop pauses.
- **playbook** — `.agentile/<stage>.md`: frontmatter directives + prose policy that tailor a stage.
- **gate** — a deterministic command in `.agentile/gates.json` (format, lint, test, build, deploy).
- **drain / watch** — the runner's two modes: work the current queue then stop (`/ag-loop`) vs keep waiting for new work (`/loop /ag-loop`).
```

- [ ] **Step 9: Stage responsibility table**

Add after the Glossary:

```markdown
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
```

- [ ] **Step 10: The one rule — reword**

Replace the final section's body with:

```markdown
**First be agile, then agentic.** Agents multiply whatever loop you give them:
a healthy loop gets faster, a broken one breaks faster. Get the trunk, the
gates, and the written spec right first — agents make a good loop fast; they
do not make a bad loop safe. (`/ag-init` ends with a readiness report so you
can see where you stand.)
```

- [ ] **Step 11: Commit**

```bash
git add README.md
git commit -m "README: spec-dir contract, route-aware steering, glossary, who-does-what table, rework path; cut quip"
```

## Task 10: methodology.md restructure + docs/sources.md

**Files:**

- Create: `docs/sources.md` (content moved from Part 1)
- Rename + rewrite: `lean-agentic-loop.md` → `methodology.md`

- [ ] **Step 1: Move Part 1 to docs/sources.md**

Create `docs/sources.md` with the heading `# Lean Agentic Loop — source notes`, an intro line ("The ten sources the methodology was synthesised from, summarised at the time of writing (2026-06). The cross-cutting themes live in `../methodology.md`."), and the ten source summaries from Part 1 verbatim (items 1–10, including the not-retrievable notes).

- [ ] **Step 2: git mv and restructure**

`git mv lean-agentic-loop.md methodology.md`, then rework it to this structure:

1. Title: `# The Lean Agentic Loop` with the subtitle line: `*A methodology for small teams who direct AI agents as their primary way of building software. Synthesised from ten sources (see docs/sources.md); shipped as the Agentile Claude Code plugin.*`
2. `## Cross-cutting themes` — the seven theme bullets from the old Part 1, kept verbatim, with source numbers replaced by a single pointer line to `docs/sources.md`.
3. `## The methodology` — the old Part 2, amended per Step 3 below.
4. `## Binding: Claude Code and the Agentile plugin` — fully rewritten per Step 4 below.
5. `## The one rule` — same reworded text as README Task 9 Step 10 (minus the `/ag-init` parenthetical).

- [ ] **Step 3: Amendments inside "The methodology" (old Part 2)**

Make exactly these changes, keeping everything else:

- **Triage section**: after the table add: "The route is not advice that evaporates — it is written to the spec's frontmatter and consumed downstream: a `foreground` or `spike` spec pauses the loop at plan for human steering; a `background` spec runs through to the pre-ship gate."
- **New section "The spec artefact"** after the Shaping section: a spec is a flat file (`NNNN-<slug>.md`) until planning, then a directory (`NNNN-<slug>/`) holding `SPEC.md`, `plan.md`, and any supporting files; the rank prefix is on the name; shipping moves the whole artefact to `done/`; the artefact carries its own history — `created`, `claimed_at`, `shipped_at` — so flow metrics need no external tracker.
- **Prioritisation and pulling**: keep the editorial/transactional distinction; replace the flock/session-id sentences with the abstract invariants: "Pulling must be **atomic** — two workers can never claim the same item — and a claim must record a **resumable worker handle**, so an interrupted cycle can be picked up exactly where it stopped. How atomicity and resumption are implemented belongs to the binding (in Claude Code: a file lock and the session id)."
- **PLAN step (2)**: replace the body with: "The agent reads the spec plus standing context and writes the plan as a file beside the spec — files to touch, approach, test strategy, risks — *before* any code. You correct the plan by editing the file; it is the cheapest place to steer. Whether the loop stops here for you is route-aware: low-certainty work pauses, high-certainty work proceeds. Big or risky specs get an ADR."
- **VERIFY step (4)**: append: "End-to-end coverage is part of the `test` gate's job — if your test command doesn't include it, that is a gap in the gate, not a different gate."
- **SHIP step (5)**: append: "Shipping stamps `shipped_at` and keeps the claim timestamps — the artefact's own frontmatter is the flow record. Each spec names the **outcome** that proves it (one observable metric or check, written at shaping); watching that outcome is part of shipping, not a separate ceremony."
- **LEARN step (6)**: append: "Learning covers product as well as process: for each spec shipped since the last retro, was its outcome observed? Shipped-but-wrong work re-enters as a new stub referencing the original."
- **Spikes**: in the Shaping section where spikes are introduced, append the spike definition sentence from Task 7 Step 2.
- **New short section "Runner modes: drain and watch"** before "What you deliberately drop": "A runner has two modes. **Drain**: work the current queue, then stop. **Watch**: keep waiting for new work and start on it as it appears. The methodology owns these two modes; how a given harness implements them is the binding's business (in Claude Code today: `/ag-loop` drains; `/loop /ag-loop` watches)."

- [ ] **Step 4: Rewrite the binding (old Part 3)**

Replace the whole of old Part 3 with a section that binds each methodology concept to the shipped plugin. Required content:

- Opening: "The plugin ships the methodology — install it rather than hand-building these pieces" + the install commands from the README.
- A binding table:

| Methodology concept | In the plugin |
|---|---|
| Standing context | `CLAUDE.md` section (scaffolded by `/ag-init`), `docs/adr/`, optional MCP servers |
| Capture / Inbox | `/ag-capture`, `/ag-inbox`, `docs/agentile/inbox.md` |
| Shaping / DoR | `/ag-shape` against `.agentile/shape.md` |
| Direct spec (trivial work) | `/ag-spec` |
| The spec artefact | `specs/NNNN-<slug>.md` → promoted to `NNNN-<slug>/SPEC.md` + `plan.md` |
| Prioritise (editorial) | `/ag-prioritise` — rank as filename prefix |
| Pull (transactional) | `/ag-next` → `bin/ag-claim` (file lock; session id is the worker handle; `claude --resume <id>`) |
| Plan | `/ag-plan` → `plan.md` via Plan Mode or the `ag-planner` agent |
| Build | `ag-builder` agent, branch/worktree, gates from `.agentile/gates.json` |
| Verify | `ag-reviewer` agent (fresh context) + `/security-review` + hooks |
| Ship | orchestrated by `/ag-loop` (a step, not an agent) — merge, stamp, move to `done/` |
| Learn | `/ag-retro` |
| Drain / watch | `/ag-loop` / `/loop /ag-loop` |
| Tailoring | `.agentile/` playbooks via `/ag-customise` |

- The hats: exactly three agents — `ag-planner`, `ag-builder`, `ag-reviewer`; shaping is a skill-run conversation, ship is a skill-orchestrated step. The human stays the accountable anchor.
- Deterministic enforcement: hooks (`format-on-edit`, `test-gate`) read `gates.json` and no-op until configured.
- Starter checklist replaced with: 1. install the plugin; 2. `/ag-init` (scaffolds everything, reports readiness); 3. configure `gates.json`; 4. `/ag-capture` → `/ag-shape` → `/ag-prioritise` → `/ag-loop`.

- [ ] **Step 5: Fix stale references repo-wide**

Run: `grep -rn "lean-agentic-loop" --include="*.md" --include="*.json" . | grep -v ".worktrees" | grep -v "docs/reviews" | grep -v "docs/plans"`
Update every hit (README link already done in Task 9; check `.claude-plugin/`, `bin/ag-sync`, `bin/ag-dev-link`, skills) to point at `methodology.md`. Keep the repo name and any historical mentions in `docs/` design notes as-is.

- [ ] **Step 6: Commit**

```bash
git add methodology.md docs/sources.md
git rm lean-agentic-loop.md 2>/dev/null || true
git add -A
git commit -m "Essay → methodology.md: themes → methodology → plugin binding; sources to docs/sources.md; Part 3 rewritten against the shipped plugin"
```

## Task 11: Design-doc status headers + CLAUDE template

**Files:**

- Modify: `docs/agentile-customisation-and-concurrency.md`
- Modify: `docs/agentile-dependencies-and-prioritisation.md`
- Modify: `docs/agentile-loop-runner.md`
- Modify: `docs/agentile-backlog-layout-and-abandon.md`
- Modify: `templates/CLAUDE.agentile-section.md`

- [ ] **Step 1: Status headers**

Replace each doc's status line (line 3) as follows. Customisation doc:

```markdown
Design spec. Status: implemented 2026-06-10 — historical snapshot; the README and `methodology.md` are normative. Known drift: §5's "on abandon: back to ready" describes what is now called **releasing** a claim — abandoning moves a spec to `specs/abandoned/` (see agentile-backlog-layout-and-abandon.md); the status enum now includes `abandoned`; per-spec `priority:` frontmatter was replaced by `NNNN-` filename prefixes (see agentile-dependencies-and-prioritisation.md); the parked `auto_start` flag was superseded by `/ag-loop` (see agentile-loop-runner.md); specs may now be directories (`NNNN-<slug>/SPEC.md`).
```

Dependencies doc:

```markdown
Design spec. Status: implemented 2026-06-10 — historical snapshot; the README and `methodology.md` are normative. `specs/archive/` was later renamed `specs/done/` (see agentile-backlog-layout-and-abandon.md); specs may now be directories (`NNNN-<slug>/SPEC.md`).
```

Loop-runner doc:

```markdown
Design spec. Status: implemented 2026-06-11 — historical snapshot; the README and `methodology.md` are normative. Amended since: plan checkpoints are route-aware (`pause_at_plan: route` — foreground/spike specs pause at plan), and ship keeps claim timestamps, stamping `shipped_at`.
```

Backlog doc — append to its existing status line:

```markdown
 Historical snapshot; the README and `methodology.md` are normative.
```

- [ ] **Step 2: Inline corrections**

In the dependencies doc, replace each remaining `specs/archive/` with `specs/done/` (the §ag-claim and §prioritise mentions).

In the customisation doc §5, change "On abandon: back to ready, claim cleared" to "On release: back to ready, claim cleared (abandoning — dropping the spec entirely — came later; see the backlog-layout doc)". Also in §5, change "Release on ship: `status: shipped` and clear the claim" to "On ship: `status: shipped`; claim fields are kept and `shipped_at` is stamped (the claim→ship interval is the cycle-time record)".

- [ ] **Step 3: CLAUDE.agentile-section.md**

In "Where things live", replace the Specs bullet with:

```markdown
- **Specs** (`docs/agentile/specs/`) — shaped, Ready-to-build specs (`ready` / `in_progress`). A spec is a flat `NNNN-<slug>.md` until planning, then a directory `NNNN-<slug>/` holding `SPEC.md`, `plan.md`, and supporting files. The Definition of Ready is `.agentile/shape.md`.
```

In "How to work", in the `/ag-shape` bullet change "then `/ag-plan` before any code" to "then `/ag-plan` before any code — it writes `plan.md` beside the spec; review or amend that file, it is the approved plan".

In the `/ag-loop` bullet, replace "Either way it pauses for your sign-off before each ship." with "It pauses at plan for `foreground`/`spike` specs (review `plan.md`, reply approved) and for your sign-off before each ship."

- [ ] **Step 4: Commit**

```bash
git add docs/ templates/CLAUDE.agentile-section.md
git commit -m "Design docs: status headers + drift notes (README/methodology normative); CLAUDE section: spec-dir + plan.md flow"
```

## Task 12: Consistency sweep + verification

**Files:** none new — verification only, fixes as found.

- [ ] **Step 1: Run the test suite**

Run: `ruby bin/test-ag-claim.rb && ruby bin/test-ag-dependents.rb`
Expected: `ALL PASS` twice.

- [ ] **Step 2: Vocabulary and stale-reference greps**

Run and fix any hits that contradict the new contract (excluding `docs/reviews/`, `docs/plans/`, and the historical design docs' own bodies):

```bash
grep -rn "lean-agentic-loop.md" --include="*.md" . | grep -v reviews | grep -v plans
grep -rn "clear the claim" skills/ templates/ README.md
grep -rn "specs/archive" skills/ templates/ README.md bin/
grep -rn "spec-writer\|release subagent" README.md methodology.md skills/
```

- [ ] **Step 3: Markdown style check**

Confirm new/edited markdown follows house style: blank line after every heading, blank line before top-level lists, no `---` horizontal rules in prose docs (YAML frontmatter delimiters are fine). Remove the two `---` rules that lean-agentic-loop.md used as part separators if they survived into methodology.md.

- [ ] **Step 4: Commit any sweep fixes**

```bash
git add -A
git commit -m "Consistency sweep: vocabulary, stale references, markdown style"
```
