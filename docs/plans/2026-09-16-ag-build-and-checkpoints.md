# `/ag-build` and the Checkpoint Protocol — Implementation Plan (Factory phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `/ag-loop` with `/ag-build` (one spec, claim to shipped, no iteration), make every pause a checkpoint file in the spec directory, and retire `.agentile/loop.md` into the stage playbooks, so a headless factory worker and a human at a terminal run the very same skill.

**Architecture:** Two small Ruby tools carry the deterministic parts (a targeted `claim`, and `bin/ag-checkpoint` for writing and reading checkpoint files); the `/ag-build` skill composes the existing `/ag-plan`, `ag-builder` and `ag-reviewer` exactly as `/ag-loop` did, minus the counter and watch mode. Policy that was in `loop.md` moves onto `plan.md`, `ship.md` and `verify.md` playbooks. `bin/ag-run` becomes the fallback driver that runs `/ag-build` per fresh process.

**Tech Stack:** Ruby 3.4 (no gems beyond stdlib: `yaml`, `json`, `fileutils`, `open3`), Claude Code plugin markdown (skills, agents, templates), the repo's `dev/test-*.rb` style (plain scripts that `raise` on failure and print `ALL PASS`).

**Spec:** `docs/agentile-factory.md`, sections 1, 3, 10 and 12 (phase 1). Sections 2, 4 to 9 are the daemon and console, which are later plans in a separate repo.

## Global Constraints

- Plugin version bumps to `0.13.0` in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (the `plugins[0].version` entry), in the same commit as the CHANGELOG entry.
- Every existing dev test keeps passing: `ruby dev/test-ag-claim.rb`, `ruby dev/test-ag-store-local.rb`, `ruby dev/test-ag-run.rb`, `ruby dev/test-ag-dependents.rb`.
- `claude plugin validate .` passes at the end of every task that touches skills, agents or manifests.
- Status lines are plain single lines: `AG_BUILD: shipped <slug>`, `AG_BUILD: paused <slug> <reason> <checkpoint-path>`, `AG_BUILD: failed <slug-or-'-'> <reason>`, `AG_BUILD: idle <NONE|WIP_FULL|BLOCKED|UNPRIORITISED>`.
- Checkpoint reasons are exactly: `plan_review`, `build_blocked`, `build_checkpoint`, `gate_failure`, `verify_checkpoint`, `ship_approval`, `question`.
- Checkpoint files live at `<spec-dir>/checkpoints/NNN-<reason>.md`, `NNN` zero-padded to three digits, numbered from `001` per spec.
- Claim result vocabulary gains two values for targeted claims: `NOT_FOUND` (no active spec has that slug) and `TAKEN` (it exists but is not `ready` with an empty `claimed_by`). `BLOCKED` and `WIP_FULL` keep their meaning for a targeted claim. A targeted claim ignores rank: an unprefixed spec can be claimed by name.
- Australian spelling in prose; no `---` horizontal rules in markdown bodies (frontmatter fences are not rules).
- Commits: one per task, message in the repo's style (`Factory: <what>`), ending with the attribution lines the session provides.

## File map

| File | Change | Responsibility |
|------|--------|----------------|
| `bin/ag-store-adapters/local.rb` | modify `claim` | targeted claim by slug |
| `bin/ag-store-adapters/airtable.rb` | modify `claim` | same, for the team store |
| `bin/ag-claim`, `bin/ag-store` | modify | `--spec <slug>` flag |
| `dev/test-ag-claim.rb`, `dev/test-ag-store-local.rb` | add cases | targeted claim |
| `bin/ag-checkpoint` | create | open / list / answer checkpoint files |
| `dev/test-ag-checkpoint.rb` | create | checkpoint tool tests |
| `skills/ag-build/SKILL.md` | create | the one-spec runner |
| `skills/ag-loop/SKILL.md` | rewrite | one-release alias |
| `skills/ag-plan/SKILL.md` | modify | `human_checkpoint: route`; build owns the pause |
| `agents/ag-builder.md`, `agents/ag-reviewer.md` | modify | `question` outcome |
| `templates/agentile/plan.md`, `templates/agentile/ship.md` | create | stage playbooks carrying the old loop keys |
| `templates/agentile/verify.md` | modify | `retry_limit`, `stop_on_gate_failure` |
| `templates/agentile/loop.md` | delete | retired |
| `templates/agentile/spec-template.md` | modify | optional `model:` |
| `templates/agentile/gates.json` | modify | optional `review` block |
| `templates/factory-worker.md` | create | appended system prompt for a headless worker |
| `templates/agentile/runs.md`, `next.md`, `deploy.md`, `playbooks.md` | modify | wording |
| `skills/ag-init/SKILL.md`, `skills/ag-version/SKILL.md`, `skills/ag-wip/SKILL.md`, `skills/ag-customise/SKILL.md` | modify | scaffold list, `loop.md` warning, factory runner ids |
| `bin/ag-run`, `dev/test-ag-run.rb` | modify | drive `/ag-build`, accept both status prefixes |
| `README.md`, `methodology.md`, `templates/CLAUDE.agentile-section.md` | modify | docs |
| `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | modify | 0.13.0 |
| `docs/agentile-factory.md` | modify | status line: phase 1 implemented |

## Task 1: Targeted claim in the local store

**Files:**
- Modify: `bin/ag-store-adapters/local.rb:91-140` (the `claim` method)
- Modify: `bin/ag-claim`
- Modify: `bin/ag-store:25`, `bin/ag-store:150`, `bin/ag-store:192`
- Test: `dev/test-ag-claim.rb`, `dev/test-ag-store-local.rb`

**Interfaces:**
- Produces: `Local.claim(specs_dir, session, label, wip, target = nil)` returning a path or one of `WIP_FULL | BLOCKED | UNPRIORITISED | NONE | NOT_FOUND | TAKEN`.
- Produces: `ag-claim <specs-dir> <session-id> [label] [wip-limit] [--spec <slug>]` and `ag-store claim <identity> [label] [wip] [--spec <slug>] --dir <dir>`.

- [ ] **Step 1: Add the failing tests to `dev/test-ag-claim.rb`**

Add a second helper beside `claim` (after line 15) and four cases before the final `puts "ALL PASS"`:

```ruby
def claim_spec(dir, slug, session: "s", wip: 0)
  out, err, st = Open3.capture3("ruby", HELP, dir, session, "", wip.to_s, "--spec", slug)
  raise "ag-claim --spec failed: #{err}" unless st.success?
  out.strip
end
```

```ruby
# 17. --spec claims the named slug even when it is not the top of the queue
Dir.mktmpdir do |d|
  spec(d, "0001-top.md", status: "ready")
  spec(d, "0002-wanted.md", status: "ready")
  path = claim_spec(d, "wanted")
  raise "targeted claim: #{path}" unless path.end_with?("0002-wanted.md")
  fm = YAML.safe_load(File.read(path)[/^---\n(.*?)\n---/m, 1], permitted_classes: [Time, Date])
  raise "targeted stamp" unless fm["status"] == "in_progress" && fm["claimed_by"] == "s"
  raise "top untouched" unless File.read(File.join(d, "0001-top.md")).include?("status: ready")
end

# 18. --spec on an unprefixed spec works (a named claim ignores rank)
Dir.mktmpdir do |d|
  spec(d, "unranked.md", status: "ready")
  raise "unranked target: #{claim_spec(d, 'unranked')}" unless claim_spec(d, "unranked").end_with?("unranked.md")
end

# 19. --spec vocabulary: NOT_FOUND, TAKEN, BLOCKED, WIP_FULL
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "in_progress")
  spec(d, "0002-b.md", status: "ready", depends_on: ["ghost"])
  spec(d, "0003-c.md", status: "ready")
  raise "not found" unless claim_spec(d, "nope") == "NOT_FOUND"
  raise "taken" unless claim_spec(d, "a") == "TAKEN"
  raise "blocked target" unless claim_spec(d, "b") == "BLOCKED"
  raise "wip target" unless claim_spec(d, "c", wip: 1) == "WIP_FULL"
end

# 20. --spec resolves a directory spec by its directory slug
Dir.mktmpdir do |d|
  dirspec(d, "0004-dir", status: "ready")
  raise "dir target: #{claim_spec(d, 'dir')}" unless claim_spec(d, "dir").end_with?("0004-dir/SPEC.md")
end
```

- [ ] **Step 2: Run the claim tests to verify they fail**

Run: `cd ~/projects/agentile && ruby dev/test-ag-claim.rb`
Expected: FAIL at case 17 (the `--spec` argument is treated as a positional `wip` value today, so the claim returns the top spec or aborts).

- [ ] **Step 3: Implement the targeted branch in `Local.claim`**

Replace the `claim` method in `bin/ag-store-adapters/local.rb` (lines 91 to 140) with:

```ruby
  # Prints/returns the claimed spec path, or one of:
  #   WIP_FULL | BLOCKED | UNPRIORITISED | NONE          (queue claim)
  #   WIP_FULL | BLOCKED | NOT_FOUND | TAKEN            (targeted claim, `target` = slug)
  # A targeted claim ignores rank — the caller chose the spec — but still
  # respects the WIP limit and unshipped dependencies.
  def claim(specs_dir, session, label, wip, target = nil)
    abort "ag-store: no such specs dir: #{specs_dir}" unless File.directory?(specs_dir)
    wip = (wip.to_s.empty? ? 0 : wip.to_i)
    target = nil if target.to_s.empty?

    result = nil
    lock_path = File.join(specs_dir, ".pull.lock")
    File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
      lock.flock(File::LOCK_EX)

      pool = specs_in(specs_dir)
      dupes = pool.group_by { |s| s[:slug] }.select { |_, v| v.size > 1 }.keys
      abort "ag-store: duplicate slug(s) in claim pool: #{dupes.join(', ')}" if dupes.any?

      shipped = shipped_map(specs_dir)

      in_progress = pool.count { |s| s[:fm]["status"] == "in_progress" }
      if wip.positive? && in_progress >= wip
        result = "WIP_FULL"
        next
      end

      chosen = nil
      if target
        chosen = pool.find { |s| s[:slug] == target }
        if chosen.nil?
          result = "NOT_FOUND"
          next
        end
        unless chosen[:fm]["status"] == "ready" && chosen[:fm]["claimed_by"].to_s.empty?
          result = "TAKEN"
          next
        end
        unless Array(chosen[:fm]["depends_on"]).all? { |dep| shipped[dep.to_s] }
          result = "BLOCKED"
          next
        end
      else
        ready = pool.select { |s| s[:fm]["status"] == "ready" && s[:fm]["claimed_by"].to_s.empty? }
        if ready.empty?
          result = "NONE"
          next
        end

        prioritised = ready.select { |s| s[:prefix] }
        if prioritised.empty?
          result = "UNPRIORITISED"
          next
        end

        eligible = prioritised.select { |s| Array(s[:fm]["depends_on"]).all? { |dep| shipped[dep.to_s] } }
        if eligible.empty?
          result = "BLOCKED"
          next
        end

        chosen = eligible.min_by { |s| [s[:prefix], s[:slug]] }
      end

      stamp!(chosen, {
        "status" => "in_progress",
        "claimed_by" => session,
        "label" => label.to_s,
        "claimed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      })
      result = chosen[:path]
    end
    result
  end
```

- [ ] **Step 4: Teach `bin/ag-claim` the `--spec` flag**

Replace the body of `bin/ag-claim` from line 10 down with:

```ruby
# Usage: ag-claim <specs-dir> <session-id> [label] [wip-limit] [--spec <slug>]
# Prints the claimed spec path, or one of: WIP_FULL | BLOCKED | UNPRIORITISED | NONE,
# or for --spec: WIP_FULL | BLOCKED | NOT_FOUND | TAKEN.
require_relative "ag-store-adapters/local"

args = ARGV.dup
target = nil
if (i = args.index("--spec"))
  target = args[i + 1]
  abort "usage: ag-claim <specs-dir> <session-id> [label] [wip-limit] [--spec <slug>]" if target.to_s.empty?
  args.slice!(i, 2)
end

specs_dir, session, label, wip = args
abort "usage: ag-claim <specs-dir> <session-id> [label] [wip-limit] [--spec <slug>]" if specs_dir.nil? || session.to_s.empty?

puts Local.claim(specs_dir, session, label, wip, target)
```

- [ ] **Step 5: Teach `bin/ag-store` the `--spec` flag**

In `bin/ag-store` change the usage line 25 to:

```
#   claim        <identity> [label] [wip] [--spec <slug>]  --dir <dir>
```

Change line 150 to:

```ruby
    when "claim" then adapter.claim(positional[0], positional[1], positional[2], flags["spec"])
```

Change line 192 to:

```ruby
    Local.claim(specs_dir, positional[0], positional[1], positional[2], flags["spec"])
```

- [ ] **Step 6: Add the targeted case to `dev/test-ag-store-local.rb`**

After case 5 (the block ending around line 91), add:

```ruby
# 5b. claim --spec goes through ag-store with the same vocabulary
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0001-a.md")
  write_spec(specs_dir, "0002-b.md")
  claimed = store("claim", "sess-1", "", "0", "--spec", "b", dir: dir)
  raise "targeted claim: #{claimed}" unless claimed.end_with?("0002-b.md")
  raise "taken: #{store('claim', 'sess-2', '', '0', '--spec', 'b', dir: dir)}" unless store("claim", "sess-2", "", "0", "--spec", "b", dir: dir) == "TAKEN"
  raise "not found" unless store("claim", "sess-2", "", "0", "--spec", "zzz", dir: dir) == "NOT_FOUND"
end
```

- [ ] **Step 7: Run both test files to verify they pass**

Run: `cd ~/projects/agentile && ruby dev/test-ag-claim.rb && ruby dev/test-ag-store-local.rb`
Expected: `ALL PASS` twice.

- [ ] **Step 8: Mirror the targeted branch in the Airtable adapter**

In `bin/ag-store-adapters/airtable.rb` change the `claim` signature (line 312) to `def claim(identity, label, wip, target = nil)` and replace the body from `ready = pool.select ...` (line 320) through `return "BLOCKED" if eligible.empty?` and the `chosen = ...` line with:

```ruby
      target = nil if target.to_s.empty?
      shipped_slugs = pool.select { |r| r["fields"]["Status"] == "shipped" }.map { |r| r["fields"]["Slug"] }.to_set
      deps_shipped = ->(r) { (r["fields"]["Depends On"] || []).all? { |dep_id| shipped_slugs.include?(slug_of(dep_id)) } }

      if target
        chosen = pool.find { |r| r["fields"]["Slug"] == target }
        return "NOT_FOUND" if chosen.nil?
        return "TAKEN" unless chosen["fields"]["Status"] == "ready" && chosen["fields"]["Claimed By (Session)"].to_s.empty?
        return "BLOCKED" unless deps_shipped.call(chosen)
      else
        ready = pool.select { |r| r["fields"]["Status"] == "ready" && r["fields"]["Claimed By (Session)"].to_s.empty? }
        return "NONE" if ready.empty?

        prioritised = ready.select { |r| r["fields"]["Rank"] }
        return "UNPRIORITISED" if prioritised.empty?

        eligible = prioritised.select { |r| deps_shipped.call(r) }
        return "BLOCKED" if eligible.empty?

        chosen = eligible.min_by { |r| [r["fields"]["Rank"], r["fields"]["Slug"]] }
      end
```

Leave the `@client.update_record ... chosen["fields"]["Slug"]` tail as it is. The Airtable path has no automated test (`dev/smoke-airtable.rb` needs a live base); run `ruby -c bin/ag-store-adapters/airtable.rb` and expect `Syntax OK`.

- [ ] **Step 9: Commit**

```bash
cd ~/projects/agentile
git add bin/ag-store-adapters/local.rb bin/ag-store-adapters/airtable.rb bin/ag-claim bin/ag-store dev/test-ag-claim.rb dev/test-ag-store-local.rb
git commit -m "Factory: targeted claim by slug (--spec) with NOT_FOUND and TAKEN"
```

## Task 2: `bin/ag-checkpoint`

**Files:**
- Create: `bin/ag-checkpoint`
- Test: `dev/test-ag-checkpoint.rb`

**Interfaces:**
- Produces: `ag-checkpoint open <spec-dir> <reason> [--session <id>]`, ask text on stdin, prints the new file path.
- Produces: `ag-checkpoint list <spec-dir>` prints a JSON array of `{path, reason, status, asked_at, answered_at, answered_by, session_id, ask, answer}`, oldest first.
- Produces: `ag-checkpoint answer <path> [--by <who>]`, answer text on stdin, marks the file answered.
- Produces: `ag-checkpoint open_count <spec-dir>` prints the number of `open` checkpoints (the skill's resume check uses it).

- [ ] **Step 1: Write the failing tests**

Create `dev/test-ag-checkpoint.rb`:

```ruby
require "tmpdir"; require "open3"; require "json"; require "fileutils"; require "yaml"; require "date"
TOOL = File.expand_path("../bin/ag-checkpoint", __dir__)

def cp(*args, stdin: nil)
  out, err, st = Open3.capture3("ruby", TOOL, *args, stdin_data: stdin.to_s)
  [out.strip, err, st]
end

def spec_dir(root)
  d = File.join(root, "docs", "agentile", "specs", "0007-thing")
  FileUtils.mkdir_p(d)
  File.write(File.join(d, "SPEC.md"), "---\nslug: thing\nstatus: in_progress\n---\n# Thing\n")
  d
end

# 1. open writes 001-<reason>.md with frontmatter and the ask; prints the path
Dir.mktmpdir do |root|
  d = spec_dir(root)
  path, err, st = cp("open", d, "plan_review", "--session", "abc-123", stdin: "Plan written. Review or amend plan.md.")
  raise "open failed: #{err}" unless st.success?
  raise "path: #{path}" unless path == File.join(d, "checkpoints", "001-plan_review.md")
  body = File.read(path)
  fm = YAML.safe_load(body[/\A---\n(.*?)\n---/m, 1], permitted_classes: [Time, Date])
  raise "reason" unless fm["reason"] == "plan_review"
  raise "status" unless fm["status"] == "open"
  raise "session" unless fm["session_id"] == "abc-123"
  raise "asked_at" unless fm["asked_at"].to_s.match?(/\A\d{4}-\d{2}-\d{2}T/)
  raise "ask body" unless body.include?("## Ask\n\nPlan written. Review or amend plan.md.")
  raise "answer section" unless body.include?("## Answer\n")
end

# 2. a second open numbers 002; list returns both oldest first with parsed fields
Dir.mktmpdir do |root|
  d = spec_dir(root)
  cp("open", d, "plan_review", stdin: "first")
  path2, _e, _s = cp("open", d, "question", stdin: "Which auth scheme?\n\n1. cookie\n2. token\n\nRecommend 2.")
  raise "second number: #{path2}" unless path2.end_with?("002-question.md")
  out, err, st = cp("list", d)
  raise "list failed: #{err}" unless st.success?
  rows = JSON.parse(out)
  raise "count: #{rows.size}" unless rows.size == 2
  raise "order" unless rows[0]["reason"] == "plan_review" && rows[1]["reason"] == "question"
  raise "ask parsed" unless rows[1]["ask"].start_with?("Which auth scheme?")
  raise "answer empty" unless rows[1]["answer"].to_s.empty?
  raise "open_count" unless cp("open_count", d)[0] == "2"
end

# 3. answer fills ## Answer, flips status, stamps answered_at/answered_by
Dir.mktmpdir do |root|
  d = spec_dir(root)
  path, _e, _s = cp("open", d, "question", stdin: "Which?")
  _o, err, st = cp("answer", path, "--by", "keith", stdin: "Option 2, and keep the old route for a release.")
  raise "answer failed: #{err}" unless st.success?
  body = File.read(path)
  fm = YAML.safe_load(body[/\A---\n(.*?)\n---/m, 1], permitted_classes: [Time, Date])
  raise "answered status" unless fm["status"] == "answered"
  raise "answered_by" unless fm["answered_by"] == "keith"
  raise "answered_at" unless fm["answered_at"].to_s.match?(/\A\d{4}-\d{2}-\d{2}T/)
  raise "answer body" unless body.include?("## Answer\n\nOption 2, and keep the old route for a release.")
  rows = JSON.parse(cp("list", d)[0])
  raise "list answer" unless rows[0]["answer"] == "Option 2, and keep the old route for a release."
  raise "open_count after answer" unless cp("open_count", d)[0] == "0"
end

# 4. answer with empty stdin still marks answered (plan_review approval carries no prose)
Dir.mktmpdir do |root|
  d = spec_dir(root)
  path, _e, _s = cp("open", d, "plan_review", stdin: "Review plan.md")
  _o, err, st = cp("answer", path, stdin: "")
  raise "empty answer failed: #{err}" unless st.success?
  raise "empty answer status" unless File.read(path).include?("status: answered")
end

# 5. an unknown reason aborts cleanly; a missing spec dir aborts cleanly; list on no checkpoints is []
Dir.mktmpdir do |root|
  d = spec_dir(root)
  _o, err, st = cp("open", d, "coffee", stdin: "x")
  raise "bad reason should fail" if st.success?
  raise "bad reason message: #{err}" unless err.include?("unknown reason")
  _o, err, st = cp("open", File.join(root, "nope"), "question", stdin: "x")
  raise "missing dir should fail" if st.success?
  raise "missing dir message: #{err}" unless err.include?("no such spec dir")
  raise "empty list" unless cp("list", d)[0] == "[]"
end

puts "ALL PASS"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/projects/agentile && ruby dev/test-ag-checkpoint.rb`
Expected: FAIL with `open failed:` and a "No such file" error from Ruby, since `bin/ag-checkpoint` does not exist.

- [ ] **Step 3: Write `bin/ag-checkpoint`**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# ag-checkpoint — the files a paused /ag-build leaves in a spec's directory so a
# human (or the factory console) can answer without the worker waiting.
#
#   ag-checkpoint open <spec-dir> <reason> [--session <id>]   ask text on stdin; prints the path
#   ag-checkpoint list <spec-dir>                              JSON array, oldest first
#   ag-checkpoint open_count <spec-dir>                        number of open checkpoints
#   ag-checkpoint answer <path> [--by <who>]                   answer text on stdin; marks answered
#
# Files: <spec-dir>/checkpoints/NNN-<reason>.md — frontmatter (reason, asked_at,
# session_id, status, answered_at, answered_by) then "## Ask" and "## Answer".
# The file is the record: it lives in the repo beside SPEC.md and plan.md.
require "json"
require "fileutils"
require "yaml"
require "date"

REASONS = %w[plan_review build_blocked build_checkpoint gate_failure verify_checkpoint ship_approval question].freeze
USAGE = "usage: ag-checkpoint open <spec-dir> <reason> [--session <id>] | list <spec-dir> | open_count <spec-dir> | answer <path> [--by <who>]"

def now_utc
  Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
end

def take_flag(args, name)
  i = args.index(name)
  return nil unless i
  val = args[i + 1]
  args.slice!(i, 2)
  val
end

def parse(path)
  raw = File.read(path)
  fm_text = raw[/\A---\n(.*?)\n---/m, 1] or abort "ag-checkpoint: #{path} has no frontmatter"
  fm = YAML.safe_load(fm_text, permitted_classes: [Time, Date]) || {}
  ask = raw[/^## Ask\n\n?(.*?)(?=^## Answer|\z)/m, 1].to_s.strip
  answer = raw[/^## Answer\n\n?(.*)\z/m, 1].to_s.strip
  {
    "path" => path,
    "reason" => fm["reason"],
    "status" => fm["status"],
    "asked_at" => fm["asked_at"].to_s,
    "answered_at" => fm["answered_at"].to_s,
    "answered_by" => fm["answered_by"].to_s,
    "session_id" => fm["session_id"].to_s,
    "ask" => ask,
    "answer" => answer,
  }
end

def checkpoint_files(spec_dir)
  Dir.glob(File.join(spec_dir, "checkpoints", "[0-9][0-9][0-9]-*.md")).sort
end

def open_checkpoint(args)
  session = take_flag(args, "--session")
  spec_dir, reason = args
  abort USAGE if spec_dir.nil? || reason.nil?
  abort "ag-checkpoint: no such spec dir: #{spec_dir}" unless File.directory?(spec_dir)
  abort "ag-checkpoint: unknown reason #{reason.inspect} (one of: #{REASONS.join(', ')})" unless REASONS.include?(reason)

  ask = $stdin.read.to_s.strip
  dir = File.join(spec_dir, "checkpoints")
  FileUtils.mkdir_p(dir)
  n = checkpoint_files(spec_dir).size + 1
  path = File.join(dir, format("%03d-%s.md", n, reason))
  File.write(path, <<~MD)
    ---
    reason: #{reason}
    asked_at: "#{now_utc}"
    session_id: #{session}
    status: open
    answered_at:
    answered_by:
    ---

    ## Ask

    #{ask}

    ## Answer

  MD
  puts path
end

def answer_checkpoint(args)
  by = take_flag(args, "--by")
  path = args[0]
  abort USAGE if path.nil?
  abort "ag-checkpoint: no such checkpoint: #{path}" unless File.file?(path)

  answer = $stdin.read.to_s.strip
  raw = File.read(path)
  fm_text = raw[/\A---\n(.*?)\n---/m, 1] or abort "ag-checkpoint: #{path} has no frontmatter"
  new_fm = fm_text.sub(/^status:.*$/, "status: answered")
                  .sub(/^answered_at:.*$/) { "answered_at: \"#{now_utc}\"" }
                  .sub(/^answered_by:.*$/) { "answered_by: #{by}" }
  body = raw.sub(/\A---\n.*?\n---/m) { "---\n#{new_fm}\n---" }
  body = body.sub(/^## Answer\n.*\z/m) { "## Answer\n\n#{answer}\n" }
  File.write(path, body)
end

op = ARGV.shift
args = ARGV.dup
case op
when "open" then open_checkpoint(args)
when "list"
  abort USAGE if args[0].nil?
  puts JSON.generate(checkpoint_files(args[0]).map { |p| parse(p) })
when "open_count"
  abort USAGE if args[0].nil?
  puts checkpoint_files(args[0]).count { |p| parse(p)["status"] == "open" }
when "answer" then answer_checkpoint(args)
else abort USAGE
end
```

Then `chmod +x bin/ag-checkpoint`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/projects/agentile && ruby dev/test-ag-checkpoint.rb`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/agentile
git add bin/ag-checkpoint dev/test-ag-checkpoint.rb
git commit -m "Factory: bin/ag-checkpoint writes, lists and answers pause checkpoints"
```

## Task 3: Stage playbooks absorb `loop.md`

**Files:**
- Create: `templates/agentile/plan.md`, `templates/agentile/ship.md`
- Modify: `templates/agentile/verify.md`, `templates/agentile/playbooks.md`, `templates/agentile/next.md:9`, `templates/agentile/deploy.md:11-12`, `templates/agentile/runs.md:3-4`
- Delete: `templates/agentile/loop.md`
- Modify: `skills/ag-init/SKILL.md:128`, `skills/ag-init/SKILL.md:138`, `skills/ag-init/SKILL.md:186`
- Modify: `skills/ag-version/SKILL.md` (new step 4)
- Modify: `skills/ag-customise/SKILL.md:42`
- Modify: `skills/ag-plan/SKILL.md:20-21`, `skills/ag-plan/SKILL.md:35`

**Interfaces:**
- Produces: `.agentile/plan.md` frontmatter key `human_checkpoint: true | false | route`; `.agentile/ship.md` frontmatter key `human_checkpoint: true | false`; `.agentile/verify.md` frontmatter keys `retry_limit: <int>` and `stop_on_gate_failure: true | false`. Task 4's skill reads exactly these.

- [ ] **Step 1: Create `templates/agentile/plan.md`**

```markdown
---
human_checkpoint: route   # pause for plan review: true (always) | false (never) | route (foreground and spike specs only)
---

# Plan — how this project wants plans reviewed

`/ag-plan` writes `plan.md` beside `SPEC.md`. `human_checkpoint` decides whether
`/ag-build` stops for you to read it before any code is written:

- `route` (default) pauses when the spec's `route` is `foreground` or `spike`.
  That is the cheapest place to steer low-certainty work. `background` specs run
  straight through to build.
- `true` pauses for every spec; `false` never pauses.

Review or amend `plan.md` in place, then answer the checkpoint (reply "approved"
in a session, or answer it on the factory console). An amended `plan.md` is the
approved plan.
```

- [ ] **Step 2: Create `templates/agentile/ship.md`**

```markdown
---
human_checkpoint: true   # pause for sign-off before each ship/merge; false ships on a passing verify
---

# Ship — how this project integrates finished work

Ship is the merge to trunk plus the store bookkeeping: `status: shipped`,
`shipped_at` stamped, the spec moved to `specs/done/` (local store). Describe
this project's merge conventions here (squash or merge commit, branch naming,
flags for incomplete features). `/ag-build` follows them.

With `human_checkpoint: true` (default) nothing merges without your approval:
`/ag-build` writes a `ship_approval` checkpoint with the reviewer's verdict and
the diff summary, and waits for your answer.
```

- [ ] **Step 3: Extend `templates/agentile/verify.md`**

Replace the whole file with:

```markdown
---
# human_checkpoint: true   # uncomment to require a human sign-off after a passing verify
retry_limit: 1             # bounce a failed verify back to build this many times before pausing
stop_on_gate_failure: true # pause on a failing gate past the retry limit (false: fail the item and move on)
---

# Verify — this project's Definition of Done

List what "done" observably means here (the checklist the reviewer applies on top
of the baseline tests/scan/diff-read). Run `/ag-customise verify` to build it out.
```

- [ ] **Step 4: Delete `templates/agentile/loop.md` and fix the wording that pointed at it**

```bash
cd ~/projects/agentile && git rm templates/agentile/loop.md
```

In `templates/agentile/playbooks.md` line 5 to 6, the stage list already names `plan.md`, `ship.md` and `verify.md`; append this paragraph after line 17:

```markdown
Three playbooks also carry machine keys beyond the common three: `plan.md`
(`human_checkpoint: route`), `ship.md` (`human_checkpoint`) and `verify.md`
(`retry_limit`, `stop_on_gate_failure`). Together they are the whole of a
project's build policy; there is no separate loop config.
```

In `templates/agentile/next.md` replace line 9 with:

```markdown
→ build → verify → ship), use `/ag-build`, which claims for itself.
```

In `templates/agentile/deploy.md` replace `/ag-loop` on line 11 with `/ag-build`.

In `templates/agentile/runs.md` replace lines 3 to 4 with:

```markdown
Append-only. One line per event, oldest first. Written by `/ag-build`; read by
`/ag-wip` and by `/ag-build` itself to reconstruct progress when resuming in a fresh process.
```

- [ ] **Step 5: Update `skills/ag-init/SKILL.md`**

Line 128: replace `` the durable run log `/ag-loop` appends to `` with `` the durable run log `/ag-build` appends to ``.

Line 138: replace `- `.agentile/loop.md`` with two lines:

```markdown
- `.agentile/plan.md`
- `.agentile/ship.md`
```

Line 186: replace the sentence `Run the loop with `/ag-loop` (drains the backlog); `/loop /ag-loop` to also watch for new work.` with:

```markdown
Build the next ready spec with `/ag-build` (or a named one with `/ag-build <slug>`); for an unattended machine, see the Agentile Factory (`docs/agentile-factory.md`) or the `bin/ag-run` fallback.
```

- [ ] **Step 6: Add the `loop.md` warning to `skills/ag-version/SKILL.md`**

Insert before step 4 (the report) a new step, and renumber the report to 5:

```markdown
4. Check for retired configuration in the current project: if `.agentile/loop.md`
   exists, the project predates 0.13.0. Its keys moved: `pause_at_plan` →
   `human_checkpoint` on `.agentile/plan.md`, `pause_before_ship` →
   `human_checkpoint` on `.agentile/ship.md`, `verify_retry_limit` and
   `stop_on_gate_failure` → `.agentile/verify.md`; `max_iterations`, `on_empty`
   and `watch` have no replacement (scheduling belongs to the factory). Add a
   fourth line to the report when this applies.
```

And add the fourth line to the report block:

```
   retired:   .agentile/loop.md is no longer read — move its keys to plan.md / ship.md / verify.md and delete it
```

- [ ] **Step 7: Update `skills/ag-customise/SKILL.md` line 42**

Replace the human checkpoint question with:

```markdown
2. **Human checkpoint** — should the stage pause and require an explicit "approved" from a human before handing off to the next stage? This sets `human_checkpoint: true`. Default is no, except `ship` (default yes) and `plan`, which also accepts `route` (pause only for `foreground` and `spike` specs; the default). For `verify`, also ask for `retry_limit` (default 1) and `stop_on_gate_failure` (default true).
```

- [ ] **Step 8: Update `skills/ag-plan/SKILL.md`**

Replace lines 20 to 21 with:

```markdown
- If `human_checkpoint` is `true`, or is `route` and the spec's `route` is
  `foreground` or `spike`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
```

On line 35, replace `**If invoked from `/ag-loop`, stop here and return** — the loop owns the pause decision and the build handoff.` with `**If invoked from `/ag-build`, stop here and return** — `/ag-build` owns the pause decision (it writes the checkpoint) and the build handoff.`. Also on line 30 replace `**Invoked from `/ag-loop`**` with `**Invoked from `/ag-build`**`.

- [ ] **Step 9: Verify nothing else reads `loop.md`**

Run: `cd ~/projects/agentile && grep -rn "loop\.md" skills agents templates hooks bin | grep -v "ag-loop/SKILL.md"`
Expected: only the ag-version warning text from Step 6 and the ag-init scaffold list changes. Fix any other hit by pointing it at the playbook that now carries the key.

- [ ] **Step 10: Commit**

```bash
cd ~/projects/agentile
git add -A templates skills/ag-init skills/ag-version skills/ag-customise skills/ag-plan
git commit -m "Factory: retire loop.md; plan.md, ship.md and verify.md carry the pause and retry policy"
```

## Task 4: The `/ag-build` skill

**Files:**
- Create: `skills/ag-build/SKILL.md`
- Rewrite: `skills/ag-loop/SKILL.md`

**Interfaces:**
- Consumes: `ag-store claim ... --spec <slug>` (Task 1), `ag-checkpoint open|list|open_count` (Task 2), playbook keys (Task 3), `BUILD: question` / `VERDICT: question` (Task 5).
- Produces: the `AG_BUILD:` status line and the run-log events `started`, `claimed`, `shipped`, `paused`, `failed`, `idle`.

- [ ] **Step 1: Create `skills/ag-build/SKILL.md`**

```markdown
---
name: ag-build
description: Take one Agentile spec from claim to shipped — claim the top prioritised ready spec (or a named one), plan it, implement it, verify it, ship it, and stop. Every pause is a checkpoint file in the spec's directory, so a factory worker and a person at a terminal run the same skill. Trigger phrases include "/ag-build", "build the next spec", "build <slug>", "work the next item".
allowed-tools: AskUserQuestion, Bash, Read, Edit, Skill, Agent
arguments: [slug]
---

# ag-build

Take **one** spec through plan → implement → verify → ship, then stop. There is no iteration here: several specs at once means several sessions or several factory workers, each running this skill on its own spec.

**Stay thin.** This skill is an orchestrator, not a reader. Never `Read` a spec body, `plan.md`, a diff, or gate output yourself: `/ag-plan`, `ag-builder` and `ag-reviewer` read those in their own context and hand back a one-line verdict plus a terse summary. If you are about to `Read` a spec or plan file "just to check", stop — that check belongs in the subagent.

## Identity

Resolve the claim identity once: `${AGENTILE_RUNNER_ID}` if set, otherwise `${CLAUDE_SESSION_ID}`. A factory worker arrives with `AGENTILE_RUNNER_ID=factory/<project>/<NNNN-slug>` and a claim already stamped with it; an interactive session claims for itself under its session id. A fresh process meant to resume a paused item must carry the same `AGENTILE_RUNNER_ID` the claim was made under; a session resumes itself with `claude --resume <session-id>`.

## Run log

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`); the run log is `<dir>/runs.md` (create it from `templates/agentile/runs.md` if missing). Append one line per event, format `- <ISO8601 from `date -u +%Y-%m-%dT%H:%M:%SZ`> runner=<id> event=<started|claimed|shipped|paused|failed|idle> spec=<slug|-> detail=<free text>`.

## Policy

Read the frontmatter of these playbooks (absent file or key means the default):

- `.agentile/plan.md` — `human_checkpoint`: `true` | `false` | `route` (default `route`).
- `.agentile/build.md` — `delegate_to`, `human_checkpoint` (default `false`).
- `.agentile/verify.md` — `human_checkpoint` (default `false`), `retry_limit` (default `1`), `stop_on_gate_failure` (default `true`).
- `.agentile/ship.md` — `human_checkpoint` (default `true`).

If a project still has the retired `.agentile/loop.md`, ignore it and say once that `/ag-version` explains where its keys went.

## Tools

`ag-store` and `ag-checkpoint` ship in this plugin's `bin/`, on `PATH` while the plugin is enabled (fallback `"${CLAUDE_PLUGIN_ROOT}/bin/<tool>"`). Every `ag-store` call takes `--dir "<dir>" --store "<store>"`, with `store:` from `.agentile/store.md` (default `local`). Every `ag-checkpoint open` call passes `--session "${CLAUDE_SESSION_ID}"`, so the factory console can tie a pause back to the session that wrote it; it prints the checkpoint file it wrote, and that path is the `<checkpoint-path>` in the status line.

A headless run must pre-authorise these tools and the gates: `--permission-prompts none` denies anything not on the allowlist rather than asking, so pass e.g. `--allowedTools "Bash(ag-store:*)" "Bash(ag-checkpoint:*)" "Bash(git:*)"` plus each command in `.agentile/gates.json`.

The **spec directory** for checkpoints is the directory holding `plan.md`: for the `local` store the directory of the claimed `SPEC.md`; for `airtable`, `<dir>/specs/<slug>/`. It exists once `/ag-plan` has run (it promotes a flat spec); every pause in this skill happens after that.

## Steps

### Step 0 — Resume check

Run `ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"`. If no entry's `claimed_by` equals this identity, nothing of yours is in flight: append `event=started` and go to Step 1. Otherwise that entry is your spec and you claim nothing this run — take its `slug` (the `<slug>` every run-log line and status line uses) and its `route` from the listing, and derive `<spec-dir>` from its identifier (see **Tools**). Then:

- If `<spec-dir>/plan.md` does not exist, go to Step 2.
- Otherwise run `ag-checkpoint list "<spec-dir>"`. If it lists no checkpoints, go to Step 3.
- If the newest checkpoint is `answered`, read its `answer` field from the `list` output — that is the human's decision — and resume by the checkpoint's reason, which is the only rule for where to go:
  - `plan_review` → Step 3.
  - `build_blocked` → Step 3, re-dispatching the builder with the answer as its instruction.
  - `build_checkpoint` → Step 3, re-dispatching the builder with the answer as its instruction; if the answer is a bare approval, go to Step 4 instead of rebuilding.
  - `question` → the step that asked (Step 3 if the builder asked, Step 4 if the reviewer asked), passing the answer to the agent you re-dispatch.
  - `gate_failure` → Step 3 with the answer as the builder's instruction — unless the answer says to release or abandon the spec, in which case run `ag-store release "<id>" --dir "<dir>" --store "<store>"` or point at `/ag-abandon <slug>`, append `event=failed detail=gate_failure`, and end with `AG_BUILD: failed <slug> gate_failure`.
  - `verify_checkpoint` → Step 5 on approval; otherwise Step 3 with the answer as the builder's instruction.
  - `ship_approval` → Step 6 on approval; otherwise Step 3 with the answer as the builder's instruction.
- If the newest checkpoint is still `open`, do not re-ask: report that it is waiting, and end with `AG_BUILD: paused <slug> <reason> <path>`.

### Step 1 — Claim

Read `wip_limit` from `.agentile/prioritise.md` (default unlimited). Run:

```
ag-store claim "<identity>" "" "<wip_limit>" [--spec "<slug from $ARGUMENTS>"] --dir "<dir>" --store "<store>"
```

- A spec identifier → the claim succeeded. What comes back is an **identifier** (a path to the spec's `SPEC.md` under the `local` store, a bare slug under `airtable`): use it verbatim as `<id>` for other `ag-store` calls and as the argument to `/ag-plan`, never in a run-log line or a status line. Establish the spec's own fields now — run `ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"` and take the entry whose `claimed_by` is this identity: its `slug` is the `<slug>` every run-log line and status line uses, its `route` is what Step 2 reads, and `<spec-dir>` is derived from its identifier (see **Tools**). Append `event=claimed`, continue.
- `NONE`, `WIP_FULL`, `BLOCKED`, `UNPRIORITISED` → append `event=idle detail=<code>`, explain in one line (`/ag-prioritise` for `UNPRIORITISED` or `BLOCKED`, `/ag-wip` for `WIP_FULL`, `/ag-shape` for `NONE`), and end with `AG_BUILD: idle <code>`.
- `NOT_FOUND` or `TAKEN` (targeted claim only) → append `event=failed detail=<code>`, say which slug, and end with `AG_BUILD: failed <slug> <code>`.

### Step 2 — Plan

Invoke `/ag-plan <id>`. Invoked from `/ag-build`, it dispatches the `ag-planner` subagent, writes `<spec-dir>/plan.md`, and returns a short confirmation. Under the `local` store this is where a flat spec becomes a directory, so re-read the entry for this identity from `ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"` afterwards: `<spec-dir>` and the `<id>` used from here on come from that refreshed listing.

Pause for plan review when the stage playbook `.agentile/plan.md`'s `human_checkpoint` is `true`, or is `route` and the spec's `route` (from the Step 1 listing, or the Step 0 listing on a resumed run) is `foreground` or `spike`. To pause: write the checkpoint with the plan summary `/ag-plan` returned as the ask,

```
printf '%s' "<summary>. Review or amend plan.md in place, then answer this checkpoint." | ag-checkpoint open "<spec-dir>" plan_review --session "${CLAUDE_SESSION_ID}"
```

append `event=paused detail=plan_review`, and end the turn: one paragraph, the line "Plan written to `<spec-dir>/plan.md` — review or amend it, then reply 'approved'.", and the status line `AG_BUILD: paused <slug> plan_review <checkpoint-path>`. An amended `plan.md` is the approved plan.

### Step 3 — Implement

Read `.agentile/build.md`'s frontmatter. If `delegate_to: <skill>` is set, invoke that skill; otherwise dispatch the `ag-builder` agent with the spec identifier, its `plan.md` path, the build playbook path, and, when resuming from an answered `question` checkpoint, the answer text. The builder's first line is one of:

- `BUILD: done` → continue.
- `BUILD: blocked` → checkpoint `build_blocked` with the builder's reason as the ask; `event=paused detail=build_blocked`; end with `AG_BUILD: paused <slug> build_blocked <path>`.
- `BUILD: question` → checkpoint `question` with the builder's question block (question, options, recommendation) as the ask; `event=paused detail=question`; end with `AG_BUILD: paused <slug> question <path>`.

If `build.md` sets `human_checkpoint: true`: checkpoint `build_checkpoint` with the builder's summary; `event=paused detail=build_checkpoint`; end with `AG_BUILD: paused <slug> build_checkpoint <path>`.

### Step 4 — Verify

Dispatch the `ag-reviewer` agent. Its first line is one of:

- `VERDICT: pass` → continue.
- `VERDICT: question` → checkpoint `question` exactly as in Step 3.
- `VERDICT: fail` → re-run Steps 3 and 4 up to `retry_limit` more times, passing the reviewer's must-fix findings to the builder. Still failing: if `stop_on_gate_failure` is `true`, checkpoint `gate_failure` with the findings as the ask, `event=paused detail=gate_failure`, and end with `AG_BUILD: paused <slug> gate_failure <path>` (mention `/ag-abandon <slug>` as the way to drop it). If `false`, `event=failed detail=gate_failure` and end with `AG_BUILD: failed <slug> gate_failure`.

If `verify.md` sets `human_checkpoint: true`: checkpoint `verify_checkpoint` with the reviewer's findings summary; `event=paused detail=verify_checkpoint`; end with `AG_BUILD: paused <slug> verify_checkpoint <path>`.

### Step 5 — Ship approval

If `ship.md`'s `human_checkpoint` is `true` (default): checkpoint `ship_approval` whose ask has three lines — the spec slug and title, what was built (one sentence from the builder's report), and the verify outcome (one sentence from the reviewer's) — then `event=paused detail=ship_approval`, end the turn with those three lines, "Approve to ship `<slug>`?", and `AG_BUILD: paused <slug> ship_approval <path>`.

An answered `ship_approval` whose answer says anything other than approval (a note, "send back") is a bounce: go to Step 3 with the answer as the builder's instruction.

### Step 6 — Ship

1. Merge per `.agentile/ship.md`'s prose (or repository convention), never onto a `protected_branches` entry from a builder branch without the merge step itself.
2. `ag-store ship "<id>" --dir "<dir>" --store "<store>"` — sets `status: shipped`, stamps `shipped_at`, keeps the claim fields, moves the spec to `specs/done/` (local).
3. Append `event=shipped` and commit `runs.md` (and, for the local store, the spec move and its `checkpoints/`) with the ship.
4. End with `AG_BUILD: shipped <slug>`.

## Unrecoverable errors

Any error you cannot recover from — a required file missing, an agent that returns no verdict line, a tool that fails repeatedly, a denied permission you cannot work around — ends the run: append `event=failed detail=<short-code>` and end with `AG_BUILD: failed <slug-or-'-'> <short-code>`. The code is one lowercase snake_case word or short phrase naming the cause (`no_verdict_line`, `checkpoint_write_denied`); use `-` for the slug when no spec was claimed. Do not invent new checkpoint reasons for these — the seven reasons are fixed, and an error is a failure, not a pause.

## Exit contract

The **very last line** of every turn this skill ends is exactly one of:

```
AG_BUILD: shipped <slug>
AG_BUILD: paused <slug> <reason> <checkpoint-path>
AG_BUILD: failed <slug-or-'-'> <reason>
AG_BUILD: idle <NONE|WIP_FULL|BLOCKED|UNPRIORITISED>
```

`<reason>` is the checkpoint reason or the failure code. A plain single line, no markdown, so the factory daemon and `bin/ag-run` can match it.

## Questions instead of guesses

A worker cannot prompt. When the builder or reviewer needs a human decision the spec, plan, `CLAUDE.md` and ADRs cannot settle, it returns `question` and this skill writes the checkpoint. Prefer a recorded assumption in `plan.md` when the stakes are low; ask once, with options and a recommendation, when they are not. In an interactive session you may also relay the question with `AskUserQuestion` — but still write the checkpoint first, so the item shows on the factory console.

## Interactive use beside the factory

`/ag-build <slug>` claims a specific spec and leaves the top of the queue to the workers. The builder already works in its own worktree; the ship step merges to trunk in the main checkout, which is where the backlog lives — never run `/ag-build` from inside a builder's worktree.
```

- [ ] **Step 2: Rewrite `skills/ag-loop/SKILL.md` as the alias**

```markdown
---
name: ag-loop
description: Retired alias for /ag-build (since 0.13.0). Runs /ag-build once and points at the replacement. Trigger phrases include "/ag-loop", "run the loop".
allowed-tools: AskUserQuestion, Bash, Read, Edit, Skill, Agent
arguments: [--once]
---

# ag-loop (retired)

`/ag-loop` drained a backlog inside one session, which is what filled a session's context and stopped at `max_iterations`. Since 0.13.0 the unit of work is one spec and the skill is `/ag-build`; scheduling belongs to the Agentile Factory (`docs/agentile-factory.md`) or the `bin/ag-run` fallback.

1. Invoke `/ag-build` with `$ARGUMENTS` minus any `--once`.
2. After it returns, add one line before its status line: "`/ag-loop` is retired — use `/ag-build [slug]` for one spec, `bin/ag-run` or the factory for many."

Do not loop. Do not read `.agentile/loop.md`.
```

- [ ] **Step 3: Validate the plugin**

Run: `cd ~/projects/agentile && claude plugin validate .`
Expected: validation passes with both skills listed.

- [ ] **Step 4: Dry-run the skill against a scratch project**

The plugin cache is already dev-linked to this repo (`~/.claude/plugins/cache/agentile/agentile/<sha> -> ~/projects/agentile`), so a fresh `claude -p` process sees the new skill with no reinstall. Create a throwaway project and check the claim, checkpoint and status line mechanics without spending a real build:

```bash
cd "$(mktemp -d)" && git init -q . && mkdir -p .agentile docs/agentile/specs/done docs/agentile/specs/abandoned
cp ~/projects/agentile/templates/agentile/{config.md,plan.md,ship.md,verify.md,build.md,prioritise.md,gates.json,runs.md} .agentile/ 2>/dev/null; mv .agentile/runs.md docs/agentile/
printf -- '---\ntitle: Hello\nslug: hello\nstatus: ready\nroute: foreground\ndepends_on: []\ncreated: 2026-09-16\nclaimed_by:\nlabel:\nclaimed_at:\n---\n# Hello\n\n## Acceptance criteria\n\n- [ ] prints hello\n' > docs/agentile/specs/0001-hello.md
git add -A && git commit -qm init
AGENTILE_RUNNER_ID=dryrun claude -p "/ag-build hello" --model sonnet --permission-mode acceptEdits --permission-prompts none --allowedTools "Bash(ag-store:*)" "Bash(ag-checkpoint:*)" "Bash(git:*)" "Bash(printf:*)" "Bash(ls:*)" "Bash(tail:*)" "Bash(cat:*)" "Bash(date:*)" "Bash(mkdir:*)" --max-turns 40 | tail -5
ls docs/agentile/specs/0001-hello/checkpoints/ && tail -3 docs/agentile/runs.md
```

Expected: the last line printed is `AG_BUILD: paused hello plan_review docs/agentile/specs/0001-hello/checkpoints/001-plan_review.md`, the checkpoint file exists with `status: open`, and `runs.md` shows `started`, `claimed`, `paused`. Then answer it and resume:

```bash
printf '' | ~/projects/agentile/bin/ag-checkpoint answer docs/agentile/specs/0001-hello/checkpoints/001-plan_review.md --by keith
AGENTILE_RUNNER_ID=dryrun claude -p "/ag-build" --model sonnet --permission-mode acceptEdits --permission-prompts none --allowedTools "Bash(ag-store:*)" "Bash(ag-checkpoint:*)" "Bash(git:*)" "Bash(printf:*)" "Bash(ls:*)" "Bash(tail:*)" "Bash(cat:*)" "Bash(date:*)" "Bash(mkdir:*)" --max-turns 60 | tail -3
```

Expected: the run resumes without re-claiming (no second `claimed` line in `runs.md`) and ends with `AG_BUILD: paused hello ship_approval …` because `ship.md` defaults to a checkpoint. Delete the scratch directory afterwards.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/agentile
git add skills/ag-build skills/ag-loop
git commit -m "Factory: /ag-build takes one spec from claim to shipped; /ag-loop becomes its alias"
```

## Task 5: Builder and reviewer can return a question

**Files:**
- Modify: `agents/ag-builder.md:33`, `agents/ag-builder.md:37-44`
- Modify: `agents/ag-reviewer.md:38-45`

**Interfaces:**
- Produces: first-line outcomes `BUILD: question` and `VERDICT: question`, each followed by a `## Question` block. Task 4 consumes them.

- [ ] **Step 1: Edit `agents/ag-builder.md`**

Replace line 33 with:

```markdown
- Stay inside the spec's **scope boundary**. If the spec is wrong or underspecified, stop and report `blocked` rather than guessing or expanding scope — that is a shaping problem, not an implementing one. If the spec is sound but one decision genuinely needs a human (two defensible designs with different consequences, a product call, an irreversible data change), record a low-stakes choice as an assumption in `plan.md` and carry on; for a high-stakes one, return `question`.
```

Replace lines 37 to 44 with:

```markdown
Your **first line**, verbatim, must be one of:

```
BUILD: done
BUILD: blocked
BUILD: question
```

`blocked` means you stopped because the spec was wrong or underspecified — say why in the report that follows. `question` means the spec is sound but you need one human decision to continue: follow the line with a `## Question` block containing the question in one sentence, two to four numbered options with a one-line consequence each, and `Recommendation: <n>` on its own line. Ask once; do not return `question` for something `plan.md` or an ADR already settles. An orchestrating `/ag-build` turns `question` into a checkpoint the human answers, then re-dispatches you with the answer; it does not otherwise inspect your diff.
```

- [ ] **Step 2: Edit `agents/ag-reviewer.md`**

Replace lines 38 to 45 with:

```markdown
Your **first line**, verbatim, must be one of:

```
VERDICT: pass
VERDICT: fail
VERDICT: question
```

`question` is for the rare case where pass or fail turns on a human decision (an acceptance criterion that can be read two ways, a behaviour change that may or may not be intended): follow the line with a `## Question` block — the question in one sentence, two to four numbered options, and `Recommendation: <n>`. An orchestrating `/ag-build` reads the first line to decide whether to ship, bounce back to the builder, or write a checkpoint for the human; it does not otherwise inspect the diff itself.
```

- [ ] **Step 3: Validate and commit**

Run: `cd ~/projects/agentile && claude plugin validate .`
Expected: passes.

```bash
git add agents/ag-builder.md agents/ag-reviewer.md
git commit -m "Factory: builder and reviewer can return a question for the human"
```

## Task 6: Spec `model:`, `review` gate block, and the worker prompt

**Files:**
- Modify: `templates/agentile/spec-template.md:8-12`
- Modify: `templates/agentile/gates.json`
- Create: `templates/factory-worker.md`

**Interfaces:**
- Produces: optional spec frontmatter key `model: <alias or full model name>`; optional `gates.json` key `review` with `start`, `url`, `ready`, `login.user`, `login.password_env`. The factory daemon (later plan) reads both; nothing in this plan reads them.

- [ ] **Step 1: Add `model:` to the spec template**

After line 12 (`outcome: …`) in `templates/agentile/spec-template.md` insert:

```markdown
# model:                      # optional — the Claude model a factory worker should use for this spec (an alias like sonnet or opus, or a full model name); absent = the project's route table
```

- [ ] **Step 2: Add the `review` block to `templates/agentile/gates.json`**

Replace the file with:

```json
{
  "$comment": "Deterministic gates for Agentile. The /ag-* skills, the ag-builder/ag-reviewer agents, and the plugin hooks read these commands instead of improvising them. Leave a value as an empty string to disable that gate — hooks no-op when a command is empty or missing, so an unconfigured repo is never blocked. Fill these in with /ag-init or by hand. The deploy command is different from the others: nothing runs it on a change — only /ag-deploy runs it, after the pre-deploy checklist in .agentile/deploy.md passes. Leave it blank and /ag-deploy still runs those checks, it just reports that there is nothing to deploy with. If test/build touch shared state that two concurrent runs would corrupt (a file-based DB like SQLite, a fixed dev port, a single build cache), wrap the command with the plugin's ag-lock, e.g. \"test\": \"ag-lock storage/.test.lock 'bin/rails test'\" — point the lockfile at an already-gitignored runtime path. The optional review block is read only by the Agentile Factory: how to start this app in a worker's worktree for a human to look at before approving a ship ({port} is substituted), the URL to open, a readiness URL to poll, and the login to show — the password is named by environment variable, never written here.",
  "format": "",
  "lint": "",
  "test": "",
  "build": "",
  "deploy": "",
  "review": {
    "start": "",
    "url": "http://localhost:{port}",
    "ready": "http://localhost:{port}/up",
    "login": { "user": "", "password_env": "" }
  },
  "protected_paths": [],
  "protected_branches": ["main", "master"]
}
```

Run: `ruby -rjson -e 'JSON.parse(File.read("templates/agentile/gates.json")); puts "json ok"'`
Expected: `json ok`.

- [ ] **Step 3: Create `templates/factory-worker.md`**

```markdown
# You are a factory worker

You are a headless Claude Code process started by the Agentile Factory to take exactly one spec from claim to shipped with `/ag-build`. Your claim is already stamped with your `AGENTILE_RUNNER_ID`; `/ag-build`'s resume check finds it.

- You cannot prompt. `AskUserQuestion` is unavailable and any tool call that would need permission is denied, not waited on. Treat a denial as a fact about this project's posture and work within it; if the work cannot proceed without that permission, return `blocked` with the reason.
- Every human decision is a checkpoint file written with `ag-checkpoint`, followed by ending your turn with the `AG_BUILD: paused …` status line. Never wait, poll, or sleep for an answer.
- Messages may arrive between your turns on stdin: an answered checkpoint ("Checkpoint <path> is answered. Read it and continue."), or a note from the person watching the console. Act on them at the start of your next turn.
- Work only inside your worktree. The ship step merges to trunk under the repo lock; nothing else touches trunk.
- Finish every turn with exactly one `AG_BUILD:` status line as the last line, and nothing after it.
```

- [ ] **Step 4: Commit**

```bash
cd ~/projects/agentile
git add templates/agentile/spec-template.md templates/agentile/gates.json templates/factory-worker.md
git commit -m "Factory: optional spec model, gates.json review block, and the worker system prompt"
```

## Task 7: `bin/ag-run` drives `/ag-build`

**Files:**
- Modify: `bin/ag-run:1-7`, `bin/ag-run:49`, `bin/ag-run:63-64`, `bin/ag-run:73-77`, `bin/ag-run:85-97`
- Test: `dev/test-ag-run.rb`

**Interfaces:**
- Consumes: the `AG_BUILD:` status line; still accepts `AG_LOOP:` during the alias release.

- [ ] **Step 1: Update the tests**

In `dev/test-ag-run.rb` replace every `AG_LOOP:` in a plan line with `AG_BUILD:` (cases 1, 3, 4, 5, 8, 9 and the stub default on line 20), replace `"no AG_LOOP status line found"` in case 7 with `"no AG_BUILD status line found"`, update the stub comment on line 5 to say `/ag-build`, and add before `puts "ALL PASS"`:

```ruby
# 10. the retired AG_LOOP prefix is still accepted for one release
with_stub_claude do |bindir|
  out, _err, status, log = run_ag_run(bindir, ["AG_LOOP: shipped 0001-old", "AG_BUILD: idle NONE"])
  raise "expected success: #{status.exitstatus}" unless status.success?
  raise "expected 2 invocations, got #{log.size}" unless log.size == 2
  raise "old prefix not reported" unless out.include?("AG_LOOP: shipped 0001-old")
end

# 11. a pause line carries the checkpoint path through to the report
with_stub_claude do |bindir|
  out, _err, status, _log = run_ag_run(bindir, ["AG_BUILD: paused 0003-c plan_review docs/agentile/specs/0003-c/checkpoints/001-plan_review.md"])
  raise "pause should exit 0" unless status.success?
  raise "checkpoint path missing from report" unless out.include?("001-plan_review.md")
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/projects/agentile && ruby dev/test-ag-run.rb`
Expected: FAIL at case 1 (`no AG_LOOP status line found` on stderr, since the stub now prints `AG_BUILD:`).

- [ ] **Step 3: Update `bin/ag-run`**

Replace lines 1 to 7 with:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# ag-run — the zero-infrastructure driver. Runs `/ag-build` in a fresh
# `claude -p` process per item, so a long unattended drain never lets one
# session's context fill up across many items. Stops cleanly at the first
# pause a human needs to answer — a detached process can't answer a
# checkpoint; answer it with `ag-checkpoint answer <path>` and re-run with
# the same AGENTILE_RUNNER_ID. For parallel workers, chosen models, and a
# console for what needs you, see docs/agentile-factory.md.
```

Replace line 49 with:

```ruby
STATUS_LINE = /^AG_(?:BUILD|LOOP):\s*(\S+)(?:\s+(\S+))?(?:\s+(.*))?$/
```

Replace lines 63 to 64 with:

```ruby
  puts "[ag-run] item #{item}: running claude -p \"/ag-build\"..."
  out, err, status = Open3.capture3("claude", "-p", "/ag-build", *claude_args)
```

Replace line 73 with:

```ruby
  line = out.lines.map(&:strip).reverse.find { |l| l.start_with?("AG_BUILD:", "AG_LOOP:") }
```

Replace line 75 with:

```ruby
    warn "[ag-run] no AG_BUILD status line found in output — showing the tail:"
```

Replace lines 85 to 97 (the `shipped` through `failed` branches) with:

```ruby
  when "shipped"
    next
  when "idle"
    puts "[ag-run] backlog idle (#{arg2}) — nothing more to do. Stopping."
    exit 0
  when "paused"
    reason, checkpoint = arg3.to_s.split(/\s+/, 2)
    puts "[ag-run] paused on #{arg2} (#{reason}) — a human checkpoint needs an answer."
    puts "[ag-run] checkpoint: #{checkpoint}" unless checkpoint.to_s.empty?
    puts "[ag-run] to resume: answer it (ag-checkpoint answer <path>, or reply in a session with"
    puts "[ag-run] AGENTILE_RUNNER_ID=#{runner_id} and /ag-build), then re-run ag-run with the same AGENTILE_RUNNER_ID."
    exit 0
  when "failed"
    warn "[ag-run] failed on #{arg2} (#{arg3}). Stopping."
    exit 1
```

Replace line 99 (`unrecognised AG_LOOP status`) with `warn "[ag-run] unrecognised AG_BUILD status: #{line.inspect}"`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/projects/agentile && ruby dev/test-ag-run.rb`
Expected: `ALL PASS`. Case 4's assertion `paused on 0003-c (gate_failure)` still holds because `reason` is the first token of `arg3`.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/agentile
git add bin/ag-run dev/test-ag-run.rb
git commit -m "Factory: bin/ag-run drives /ag-build and reports the checkpoint path"
```

## Task 8: `/ag-wip` knows factory workers

**Files:**
- Modify: `skills/ag-wip/SKILL.md:17-33`

- [ ] **Step 1: Add the factory branch**

Replace step 3 (lines 17 to 33) with:

```markdown
3. For each in-progress spec, classify `claimed_by`: a Claude session id (a UUID), a factory worker (starts with `factory/`), or another named runner (anything else, e.g. `ag-run@host/12345`, set via `AGENTILE_RUNNER_ID`). Then run `ag-checkpoint list "<spec-dir>"` (the spec's directory under `<dir>/specs/`; skip if it has no directory yet) and note the newest checkpoint's `reason` and `status`. Print:

   ```
   <slug>  in_progress  <label if present, otherwise claimed_by>  (claimed <relative age>)  [waiting: <reason> since <asked_at> | answered: <reason>]
     → resume: claude --resume <claimed_by>
   ```

   for a session id;

   ```
   <slug>  in_progress  factory worker <claimed_by>  (claimed <relative age>)  [waiting: <reason> | running]
     → managed by the Agentile Factory — answer it on the console, or `ag-checkpoint answer <path>`
   ```

   for a factory worker; and

   ```
   <slug>  in_progress  <label if present, otherwise claimed_by>  (claimed <relative age>)
     → not a session — claimed by runner "<claimed_by>". Re-run its driver with the
       same AGENTILE_RUNNER_ID to continue it, or export AGENTILE_RUNNER_ID=<claimed_by>
       and run /ag-build interactively to pick it up.
   ```

   for any other named runner. Compute the relative age from `claimed_at` (e.g. "2 h ago", "3 d ago").
```

- [ ] **Step 2: Validate and commit**

Run: `cd ~/projects/agentile && claude plugin validate .`

```bash
git add skills/ag-wip/SKILL.md
git commit -m "Factory: /ag-wip shows factory workers and open checkpoints"
```

## Task 9: Documentation, changelog, version

**Files:**
- Modify: `README.md:22`, `README.md:70`, `README.md:79`, `README.md:88`, `README.md:152-169`, `README.md:186`, `README.md:195`, `README.md:226`
- Modify: `methodology.md:158`, `methodology.md:192`, `methodology.md:194`, `methodology.md:208`
- Modify: `templates/CLAUDE.agentile-section.md:15`, `templates/CLAUDE.agentile-section.md:26`
- Modify: `CHANGELOG.md`, `.claude-plugin/plugin.json:3`, `.claude-plugin/marketplace.json:14`
- Modify: `docs/agentile-factory.md:3`

- [ ] **Step 1: README**

Line 22: replace `` `/ag-loop` never calls it `` with `` `/ag-build` never calls it ``.

Line 70: rename the heading `### Concurrent loops` to `### Concurrent builds`.

Line 79: replace the paragraph with:

```markdown
The session id is a resume handle, so a build that was interrupted mid-cycle can be picked back up exactly where it stopped. `claimed_by` is really a **claim identity**, resolved as `${AGENTILE_RUNNER_ID}` if set, else `${CLAUDE_SESSION_ID}`. A factory worker claims as `factory/<project>/<NNNN-slug>`; the `bin/ag-run` fallback as `ag-run@host/pid`. `/ag-wip` tells them apart — a session id gets the `claude --resume` line, a factory worker points at the console, another named runner gets re-run instructions.
```

Line 88: replace `` run `/ag-next` or `/ag-loop` from inside a builder's worktree. `` with `` run `/ag-next` or `/ag-build` from inside a builder's worktree. ``.

Replace the whole `### Running the loop` section (lines 152 to 169, up to but not including `## Glossary`) with:

```markdown
### Running a build

**`/ag-build [slug]`** takes **one spec** from claim to shipped and stops: claim the top prioritised ready spec (or the named one) → plan (pauses for `foreground`/`spike` specs by default) → implement → verify → pause for your sign-off → ship. Running several specs at once means several sessions, or a machine set up as a factory.

Every pause is a **checkpoint file** in the spec's directory (`specs/NNNN-<slug>/checkpoints/001-plan_review.md` and so on), written with `bin/ag-checkpoint`. In a session you answer by replying; anywhere else you answer with `ag-checkpoint answer <path>` or on the factory console, and the next `/ag-build` with the same claim identity carries on from the answer. Every turn ends with a machine-readable `AG_BUILD: <shipped|paused|failed|idle> …` line.

Pause policy lives in the stage playbooks: `.agentile/plan.md` (`human_checkpoint: route | true | false`), `.agentile/ship.md` (`human_checkpoint`, default true — nothing merges without your approval), and `.agentile/verify.md` (`retry_limit`, `stop_on_gate_failure`). There is no separate loop config; `.agentile/loop.md` from earlier versions is ignored and `/ag-version` says where its keys went.

For an unattended machine there are two drivers:

- **`bin/ag-run`** — zero infrastructure: runs `/ag-build` in a fresh `claude -p` process per item, sequentially, and stops at the first checkpoint. Forwards anything after `--` to `claude` (e.g. `bin/ag-run -- --permission-mode acceptEdits`); a headless run needs a permission story since nothing can answer a prompt.
- **The Agentile Factory** — one daemon per machine that feeds off every registered project's backlog, runs parallel workers with a chosen model each, and gives you a console for everything waiting on you. Design: `docs/agentile-factory.md`.

`/ag-loop` remains for one release as an alias that runs `/ag-build` once.
```

Line 186: replace `` what `/ag-loop` claimed `` with `` what `/ag-build` claimed ``.

Line 195: replace the `drain / watch` glossary entry with:

```markdown
- **checkpoint** — a file a paused `/ag-build` leaves in the spec's directory (`checkpoints/NNN-<reason>.md`) holding what it needs decided; answered in a session, with `ag-checkpoint answer`, or on the factory console.
```

Line 226: replace `` `/ag-loop` `` with `` `/ag-build`, `/ag-loop` (retired alias) ``.

- [ ] **Step 2: methodology.md**

Lines 155 to 159: replace the paragraph with:

```markdown
A runner has two modes. **Drain**: work the current queue, then stop.
**Watch**: keep waiting for new work and start on it as it appears. The
methodology owns these two modes; how a given harness implements them is the
implementation's business (in Claude Code today: `/ag-build` takes one spec
through; draining and watching belong to the Agentile Factory or the
`bin/ag-run` fallback, outside any one session).
```

Line 192: replace `` orchestrated by `/ag-loop` `` with `` orchestrated by `/ag-build` ``.

Line 194: replace the `Drain & watch` row with `| Build one, or many | `/ag-build` per spec; parallel workers via the factory or `bin/ag-run` |`.

Line 208: replace `` then `/ag-loop`. `` with `` then `/ag-build`. ``.

- [ ] **Step 3: `templates/CLAUDE.agentile-section.md`**

Line 15: replace `` history `/ag-loop` writes `` with `` history `/ag-build` writes ``.

Line 26: replace the bullet with:

```markdown
- Build the next spec with **`/ag-build`** (or a named one, `/ag-build <slug>`) — it takes one spec from claim to shipped and stops. It pauses at plan for `foreground`/`spike` specs (review `plan.md`, reply approved) and for your sign-off before ship; each pause is a checkpoint file in the spec's directory. For many specs at once, use the Agentile Factory or the **`bin/ag-run`** fallback, each of which runs `/ag-build` in a fresh process per item.
```

- [ ] **Step 4: Changelog and version**

Prepend to `CHANGELOG.md` after the intro paragraph:

```markdown
## 0.13.0 — 2026-09-16

- **`/ag-build` replaces `/ag-loop`.** One spec from claim to shipped, then
  stop; no skill iterates any more. `/ag-build <slug>` claims a named spec
  (`ag-store claim --spec`, with `NOT_FOUND` and `TAKEN`). `/ag-loop` stays
  for one release as an alias.
- **Checkpoints.** Every pause writes `specs/NNNN-<slug>/checkpoints/NNN-<reason>.md`
  via the new `bin/ag-checkpoint` (open, list, open_count, answer). The status
  line carries the path: `AG_BUILD: paused <slug> <reason> <path>`. New reason
  `question`: `ag-builder` and `ag-reviewer` may return `BUILD: question` /
  `VERDICT: question` with options and a recommendation.
- **`.agentile/loop.md` retired.** `pause_at_plan` → `human_checkpoint` on
  `plan.md` (new playbook, accepts `route`); `pause_before_ship` →
  `human_checkpoint` on `ship.md` (new playbook); `verify_retry_limit` and
  `stop_on_gate_failure` → `verify.md`. `/ag-version` warns when a project
  still has `loop.md`.
- Spec template gains optional `model:`; `gates.json` gains an optional
  `review` block; `templates/factory-worker.md` is the system prompt for a
  headless factory worker. `bin/ag-run` drives `/ag-build`. Design:
  `docs/agentile-factory.md`.
```

Set `"version": "0.13.0"` in `.claude-plugin/plugin.json` line 3 and `.claude-plugin/marketplace.json` line 14.

In `docs/agentile-factory.md` line 3, change `Status: proposed 2026-09-16, revised the same day after discussion, not yet built.` to `Status: phase 1 (protocol and \`/ag-build\`, plugin 0.13.0) implemented 2026-09-16 — see \`docs/plans/2026-09-16-ag-build-and-checkpoints.md\`; daemon and console not yet built.`

- [ ] **Step 5: Final sweep and validation**

Run:

```bash
cd ~/projects/agentile
grep -rn "ag-loop\|AG_LOOP\|loop\.md\|max_iterations\|pause_before_ship\|pause_at_plan" README.md methodology.md templates skills agents bin hooks | grep -v "skills/ag-loop/SKILL.md\|skills/ag-version/SKILL.md\|CHANGELOG\|retired\|alias\|AG_(?:BUILD|LOOP)\|AG_BUILD:\", \"AG_LOOP:\""
```

Expected: no output. Every remaining mention of the old names is in the alias skill, the version warning, the changelog, or a sentence that says it is retired.

Then:

```bash
claude plugin validate . && ruby dev/test-ag-claim.rb && ruby dev/test-ag-store-local.rb && ruby dev/test-ag-checkpoint.rb && ruby dev/test-ag-run.rb && ruby dev/test-ag-dependents.rb
```

Expected: validation passes and five `ALL PASS` lines.

- [ ] **Step 6: Commit and re-link the dev install**

```bash
cd ~/projects/agentile
git add README.md methodology.md templates/CLAUDE.agentile-section.md CHANGELOG.md .claude-plugin/plugin.json .claude-plugin/marketplace.json docs/agentile-factory.md
git commit -m "Factory: docs, changelog and 0.13.0"
dev/ag-dev-link
```

The dev link makes the new skills available on the next session reload, which is how Task 4's dry run gets repeated against the installed plugin if it was first run from the source checkout.
