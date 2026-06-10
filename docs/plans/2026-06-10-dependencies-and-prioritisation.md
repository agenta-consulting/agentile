# Spec Dependencies & Prefix Prioritisation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Specs can declare `depends_on` (gating claim until deps ship), and priority is encoded in the filename prefix (`0001-…`) set by an interactive `/ag-prioritise`.

**Architecture:** Derived/stateless. `bin/ag-claim` is rewritten to select by filename prefix among `ready` + dependency-satisfied specs, emitting new `BLOCKED`/`UNPRIORITISED` signals. The rest (shaping, prioritise, next/loop, docs) is prose/config.

**Tech Stack:** Ruby (`ag-claim` + test, `YAML`, `flock`); Markdown skills; `claude plugin validate`.

**Spec:** `docs/agentile-dependencies-and-prioritisation.md` (read it first).

**Repo:** plugin at `company/internal_projects/lean_agentic_loop/` (own repo, remote `agenta-consulting/agentile`, default branch `main`). Work in a manually-created worktree of the **plugin** repo: `git -C <plugin> worktree add <path> -b feat/deps-priority` (native EnterWorktree grabs the outer agenta repo — don't use it).

Commit after every task.

---

### Task 1: Spec template + shaping ask about dependencies

**Files:**
- Modify: `templates/agentile/spec-template.md`
- Modify: `templates/agentile/shape.md`
- Modify: `skills/ag-shape/SKILL.md`

- [ ] **Step 1: spec template** — in the frontmatter of `templates/agentile/spec-template.md`, **remove** the `priority:` line, and **add** a `depends_on` line:

```
depends_on: []                # slugs of specs that must ship first (by slug, not filename); blank = none
```

Place it near `status:`. Verify it still parses:

```bash
cd <worktree> && ruby -ryaml -e 'd=YAML.load(File.read("templates/agentile/spec-template.md")[/\A---\n(.*?)\n---/m,1]); raise if d.key?("priority"); raise unless d.key?("depends_on"); puts "template ok"'
```

- [ ] **Step 2: shape.md DoR** — in `templates/agentile/shape.md`, add a bullet to the "Required" list (the Definition of Ready): "**Dependencies** — does this need another spec shipped first? List those specs' slugs in `depends_on` (or none)."

- [ ] **Step 3: ag-shape** — in `skills/ag-shape/SKILL.md`, in the interview step, add: "Ask whether the item depends on any other specs being shipped first; offer existing spec slugs (the part of a spec filename after any `NNNN-` prefix, minus `.md`) as candidates. Write the chosen slugs to the spec's `depends_on` (default `[]`). New specs are written unprefixed (Ready but unprioritised)."

- [ ] **Step 4: commit**

```bash
git add templates/agentile/spec-template.md templates/agentile/shape.md skills/ag-shape/SKILL.md
git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "Specs declare depends_on; shaping asks about dependencies; retire priority field"
```

### Task 2: `ag-claim` — prefix ordering + dependency gate (TDD)

**Files:**
- Modify: `bin/ag-claim`
- Modify: `bin/test-ag-claim.rb`

- [ ] **Step 1: replace `bin/test-ag-claim.rb` with the new suite** (the old priority-based test no longer matches the model):

```ruby
require "yaml"; require "tmpdir"; require "open3"; require "fileutils"
HELP = File.expand_path("ag-claim", __dir__)

def spec(dir, fname, status:, depends_on: [])
  dep = depends_on.empty? ? "[]" : "[#{depends_on.join(", ")}]"
  File.write(File.join(dir, fname),
    "---\nstatus: #{status}\nclaimed_by:\nlabel:\nclaimed_at:\ndepends_on: #{dep}\n---\n# #{fname}\n")
end

def claim(dir, session: "s", wip: 0)
  out, _e, _st = Open3.capture3("ruby", HELP, dir, session, "", wip.to_s)
  out.strip
end

# 1. picks the lowest prefix among eligible, and stamps it
Dir.mktmpdir do |d|
  spec(d, "0002-low.md",  status: "ready")
  spec(d, "0001-high.md", status: "ready")
  path = claim(d)
  raise "prefix order: #{path}" unless path.end_with?("0001-high.md")
  fm = YAML.load(File.read(path)[/^---\n(.*?)\n---/m, 1])
  raise "stamp" unless fm["status"] == "in_progress" && fm["claimed_by"] == "s" && !fm["claimed_at"].to_s.empty?
end

# 2. ready but unprefixed -> UNPRIORITISED
Dir.mktmpdir do |d|
  spec(d, "rate-limit.md", status: "ready")
  raise "unprioritised: #{claim(d)}" unless claim(d) == "UNPRIORITISED"
end

# 3. nothing ready -> NONE
Dir.mktmpdir do |d|
  spec(d, "0001-done.md", status: "shipped")
  raise "none: #{claim(d)}" unless claim(d) == "NONE"
end

# 4. a depends on b: with both ready, b (no deps) is the only eligible -> claims b
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready", depends_on: ["b"])
  spec(d, "0002-b.md", status: "ready")
  raise "claims b: #{claim(d)}" unless claim(d).end_with?("0002-b.md")
end

# 4b. only a ready, dep b not shipped -> BLOCKED
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready", depends_on: ["b"])
  spec(d, "0002-b.md", status: "in_progress")
  raise "blocked: #{claim(d)}" unless claim(d) == "BLOCKED"
end

# 4c. dep shipped in archive/ -> a becomes claimable
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready", depends_on: ["b"])
  FileUtils.mkdir_p(File.join(d, "archive"))
  spec(File.join(d, "archive"), "0005-b.md", status: "shipped")
  raise "archived dep: #{claim(d)}" unless claim(d).end_with?("0001-a.md")
end

# 5. missing/typo'd dep -> BLOCKED (never silently satisfied)
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready", depends_on: ["ghost"])
  raise "missing dep: #{claim(d)}" unless claim(d) == "BLOCKED"
end

# 6. WIP limit
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "in_progress")
  spec(d, "0002-b.md", status: "ready")
  raise "wip: #{claim(d, wip: 1)}" unless claim(d, wip: 1) == "WIP_FULL"
end

puts "ALL PASS"
```

- [ ] **Step 2: run the test, confirm it FAILS** (old helper doesn't know prefixes/deps/tokens):

```bash
cd <worktree> && ruby bin/test-ag-claim.rb   # expect a raise / mismatch
```

- [ ] **Step 3: replace `bin/ag-claim` with:**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# Atomically claim the lowest-prefix ready spec whose dependencies are all shipped.
# Usage: ag-claim <specs-dir> <session-id> [label] [wip-limit]
# Prints the claimed spec path, or one of: WIP_FULL | BLOCKED | UNPRIORITISED | NONE.
#  - NONE          no ready specs at all
#  - UNPRIORITISED ready specs exist but none have an NNNN- prefix
#  - BLOCKED       prioritised ready specs exist but all have an unshipped dependency
require "yaml"

specs_dir, session, label, wip = ARGV
abort "usage: ag-claim <specs-dir> <session-id> [label] [wip-limit]" if specs_dir.nil? || session.to_s.empty?
wip = (wip.to_s.empty? ? 0 : wip.to_i) # 0 => unlimited

def load_spec(path)
  raw  = File.read(path)
  fm   = (YAML.safe_load(raw[/\A---\n(.*?)\n---/m, 1] || "", permitted_classes: [Time]) || {})
  base = File.basename(path, ".md")
  m    = base.match(/\A(\d+)-(.+)\z/)
  { path: path, raw: raw, fm: fm, prefix: (m ? m[1].to_i : nil), slug: (m ? m[2] : base) }
end

lock_path = File.join(specs_dir, ".pull.lock")
File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
  lock.flock(File::LOCK_EX)

  # Status map across ALL specs (recursive, so archived shipped specs resolve deps).
  all = Dir.glob(File.join(specs_dir, "**", "*.md")).map { |p| load_spec(p) }
  shipped = {}
  all.each { |s| shipped[s[:slug]] = true if s[:fm]["status"] == "shipped" }

  # Claim pool: top-level specs only (exclude specs/archive/**).
  archive_prefix = File.join(File.expand_path(specs_dir), "archive") + File::SEPARATOR
  pool = all.reject { |s| File.expand_path(s[:path]).start_with?(archive_prefix) }

  in_progress = pool.count { |s| s[:fm]["status"] == "in_progress" }
  if wip.positive? && in_progress >= wip
    puts "WIP_FULL"; next
  end

  ready = pool.select { |s| s[:fm]["status"] == "ready" && s[:fm]["claimed_by"].to_s.empty? }
  if ready.empty?
    puts "NONE"; next
  end

  prioritised = ready.select { |s| s[:prefix] }
  if prioritised.empty?
    puts "UNPRIORITISED"; next
  end

  eligible = prioritised.select do |s|
    Array(s[:fm]["depends_on"]).all? { |dep| shipped[dep.to_s] }
  end
  if eligible.empty?
    puts "BLOCKED"; next
  end

  chosen = eligible.min_by { |s| [s[:prefix], File.basename(s[:path])] }

  fm = chosen[:fm]
  fm["status"]     = "in_progress"
  fm["claimed_by"] = session
  fm["label"]      = label.to_s
  fm["claimed_at"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  body = chosen[:raw].sub(/\A---\n.*?\n---\n/m, "---\n#{fm.to_yaml.sub(/\A---\n/, "")}---\n")
  if body == chosen[:raw]
    warn "ag-claim: could not rewrite frontmatter for #{chosen[:path]}"
    exit 1
  end
  File.write(chosen[:path], body)
  puts chosen[:path]
end
```

- [ ] **Step 4: run the test, confirm PASS; syntax-check:**

```bash
cd <worktree> && ruby -c bin/ag-claim && ruby bin/test-ag-claim.rb   # expect: Syntax OK / ALL PASS
```

- [ ] **Step 5: commit**

```bash
git add bin/ag-claim bin/test-ag-claim.rb
git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "ag-claim: claim by filename prefix among dependency-satisfied specs; BLOCKED/UNPRIORITISED signals"
```

### Task 3: `/ag-prioritise` — interactive prefix rename

**Files:**
- Modify: `skills/ag-prioritise/SKILL.md`

Rewrite the body (keep the frontmatter; update its `description` to mention interactive ordering and `allowed-tools` must include `AskUserQuestion, Bash, Read, Write, Edit`). The new baseline (keep the standard playbook preamble for `prioritise`) must instruct:

- [ ] **Step 1:** Read the active set: top-level `specs/*.md`. Separate **prioritised** (filename has an `NNNN-` prefix; sort by number), **unprioritised ready** (no prefix, `status: ready`), and note **in-progress** specs (do not reorder/rename these — they are being worked).
- [ ] **Step 2:** Show the user the current order and the unprioritised specs. **Propose** a starting order — value × certainty as a suggestion, with each spec suggested *after* its `depends_on` slugs. Use `AskUserQuestion` or a plain numbered list the user edits.
- [ ] **Step 3:** Interactively reorder with the user until they confirm the order.
- [ ] **Step 4:** Apply it: densely rename the **ready** specs to `0001-<slug>.md`, `0002-<slug>.md`, … via `git mv` (derive `<slug>` by stripping any existing `NNNN-` prefix). **Do not rename in-progress specs.** `depends_on` is slug-based so links are unaffected.
- [ ] **Step 5:** Report the final ordered list, annotating each as claimable or `blocked — waiting on <slug>` (a slug whose spec is not yet shipped), and **warn** on dependency tension (a spec ordered above one of its `depends_on`) and on cycles (specs that transitively depend on each other).

- [ ] **Step 6: commit**

```bash
cd <worktree> && ruby -ryaml -e 'YAML.load(File.read("skills/ag-prioritise/SKILL.md")[/\A---\n(.*?)\n---/m,1]); puts "frontmatter ok"'
grep -q 'git mv' skills/ag-prioritise/SKILL.md && grep -qi 'interactive\|reorder' skills/ag-prioritise/SKILL.md && grep -qi 'blocked' skills/ag-prioritise/SKILL.md && echo "behaviours present"
git add skills/ag-prioritise/SKILL.md
git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "ag-prioritise: interactive ordering that assigns dense NNNN- filename prefixes"
```

### Task 4: token handling in next/loop + archive on ship

**Files:**
- Modify: `skills/ag-next/SKILL.md`
- Modify: `skills/ag-loop/SKILL.md`

- [ ] **Step 1: `ag-next`** — in the step that interprets `ag-claim`'s output, add the two new tokens: `BLOCKED` → "all prioritised work is waiting on dependencies — run `/ag-prioritise` to see what's blocked"; `UNPRIORITISED` → "there is shaped work but it isn't prioritised — run `/ag-prioritise`". Keep `NONE`/`WIP_FULL`/path.
- [ ] **Step 2: `ag-loop`** — (a) in the claim-result step, treat `BLOCKED` and `UNPRIORITISED` like an empty backlog: stop in drain mode (reporting the reason); under `/loop`, idle-wait (a dependency may ship, or the human may prioritise). (b) In the **ship** step, after setting `status: shipped`, **move the spec file into `specs/archive/`** (create the dir if needed; keep its `NNNN-<slug>.md` name) via `git mv`, so it leaves the active list but still resolves as a shipped dependency.
- [ ] **Step 3: verify + commit**

```bash
cd <worktree> && grep -q 'UNPRIORITISED' skills/ag-next/SKILL.md && grep -q 'BLOCKED' skills/ag-next/SKILL.md && echo "next ok"
grep -q 'archive' skills/ag-loop/SKILL.md && grep -q 'UNPRIORITISED' skills/ag-loop/SKILL.md && echo "loop ok"
git add skills/ag-next/SKILL.md skills/ag-loop/SKILL.md
git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "next/loop handle BLOCKED/UNPRIORITISED; loop archives shipped specs to specs/archive/"
```

### Task 5: Docs

**Files:**
- Modify: `README.md`, `lean-agentic-loop.md`, `templates/CLAUDE.agentile-section.md`

- [ ] **Step 1:** `README.md` — update the Concurrent-loops / prioritise material: specs carry `depends_on` (claim is gated until deps ship); priority is the filename prefix `NNNN-`, set by an interactive `/ag-prioritise` (unprefixed = not yet prioritised); shipped specs are archived to `specs/archive/`.
- [ ] **Step 2:** `lean-agentic-loop.md` — note dependencies and prefix-based prioritisation in the relevant part.
- [ ] **Step 3:** `templates/CLAUDE.agentile-section.md` — one line: specs may `depends_on` others; `/ag-prioritise` orders the queue by renaming to `NNNN-<slug>.md`.
- [ ] **Step 4: verify + commit**

```bash
cd <worktree> && for f in README.md lean-agentic-loop.md templates/CLAUDE.agentile-section.md; do grep -qi 'depends_on\|prioriti' "$f" && echo "ok $f"; done
git add README.md lean-agentic-loop.md templates/CLAUDE.agentile-section.md
git -c user.name="Keith Rowell" -c user.email="keith@keithrowell.com" commit -m "Docs: spec dependencies + prefix-based prioritisation"
```

### Task 6: Validate, sync, exercise

- [ ] **Step 1: static validation:**

```bash
cd <worktree>
claude plugin validate .
ruby -c bin/ag-claim && ruby bin/test-ag-claim.rb
ruby -ryaml -e 'Dir.glob("skills/*/SKILL.md").each{|f| YAML.load(File.read(f)[/\A---\n(.*?)\n---/m,1])}; puts "skills ok"'
```

Expected: validation passes; `ALL PASS`; `skills ok`.

- [ ] **Step 2: merge to main + verify (controller, from main tree):**

```bash
git merge --ff-only feat/deps-priority
claude plugin validate .
```

- [ ] **Step 3: behavioural walkthrough (manual, after reload).** In a scratch repo: shape two specs A and B with A `depends_on: [b]`; `/ag-prioritise` ranks them `0001-…`/`0002-…`; `/ag-next` claims B (A blocked); ship B (archived); `/ag-next` now claims A. Confirm an unprefixed spec yields the "not prioritised" message.

---

## Self-review

- **Spec coverage:** depends_on field + shaping → Task 1; ag-claim gate + tokens + archive-aware status map → Task 2; interactive prefix prioritise → Task 3; next/loop tokens + archive-on-ship → Task 4; docs → Task 5; validate → Task 6. All spec sections covered.
- **Placeholders:** none — ag-claim and its test are complete code; the prose tasks give exact behaviour + verify commands.
- **Consistency:** tokens `WIP_FULL`/`BLOCKED`/`UNPRIORITISED`/`NONE`, the `depends_on` slug semantics, the `NNNN-<slug>.md` naming, and `specs/archive/` are used identically across Tasks 2, 3, 4. The `priority:` field is removed (Task 1) and no later task references it.
