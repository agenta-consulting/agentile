# Agentile Customisation & Concurrency — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Agentile loop stage customisable via a per-project `.agentile/<stage>.md` playbook, and make concurrent loops safe via mutex-protected, resumable, session-stamped claims.

**Architecture:** A uniform contract — each stage's consumer (skill or agent) reads `.agentile/<stage>.md` (thin YAML frontmatter directives + prose) and layers it on its baseline. New skills (`ag-prioritise`, `ag-next`, `ag-wip`, `ag-customise`), a Ruby atomic-claim helper, and a `SessionStart` hook that surfaces the session id implement prioritisation, pulling, and concurrency.

**Tech Stack:** Markdown SKILL.md / agent files; Ruby (claim helper + hooks, using `File#flock` and `YAML`); JSON manifest/hooks; `claude plugin validate` for verification.

**Spec:** `docs/agentile-customisation-and-concurrency.md` (read it first).

**Repo:** the plugin at `company/internal_projects/lean_agentic_loop/` (its own git repo; remote `agenta-consulting/agentile`).

---

## Shared artifacts (defined once, reused by tasks)

### The standard playbook preamble

This exact block is inserted near the top of each stage skill/agent body, with `<STAGE>` replaced by that stage's canonical name (e.g. `shape`, `build`, `verify`, `plan`, `prioritise`, `next`):

```markdown
## Apply this project's playbook

Before doing anything else, check for `.agentile/<STAGE>.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.
```

### Phasing

- **Phase A — the customisation contract** (Tasks 1–8): playbooks, preamble in every stage, `/ag-customise`, init scaffolding, `shaping.md`→`shape.md`, the build & verify instances.
- **Phase B — concurrency + prioritise/next** (Tasks 9–16): claim fields, Ruby claim helper, `SessionStart` hook, `ag-prioritise`, `ag-next`, `ag-wip`, docs, validation.

Commit after every task. Work in a git worktree per `superpowers:using-git-worktrees`.

---

## Phase A — Customisation contract

### Task 1: `playbooks.md` template + directive vocabulary doc

**Files:**
- Create: `templates/agentile/playbooks.md`

- [ ] **Step 1: Write the template** — explains the contract for users. Content:

```markdown
# Playbooks — customise any stage

Agentile reads a `.agentile/<stage>.md` "playbook" for each loop stage. Present →
it customises that stage; absent → the built-in behaviour. The filename is the
stage name: `shape.md`, `plan.md`, `prioritise.md`, `next.md`, `build.md`,
`verify.md`, `ship.md`, `learn.md`, `capture.md`, `spec.md`.

Each playbook is optional YAML frontmatter + prose:

    ---
    delegate_to: worktree-workflow   # run this stage by invoking that skill
    also_run: [other-skill]          # extra skills alongside the baseline
    human_checkpoint: true           # pause for human sign-off before handing off
    ---
    Prose: this project's policy / definition for the stage.

Build one out conversationally with `/ag-customise <stage>`.
```

- [ ] **Step 2: Commit**

```bash
git add templates/agentile/playbooks.md
git commit -m "Add playbooks.md template explaining the customisation contract"
```

### Task 2: Rename `shaping.md` → `shape.md`

**Files:**
- Rename: `templates/agentile/shaping.md` → `templates/agentile/shape.md`
- Modify: `skills/ag-shape/SKILL.md` (references to `shaping.md`)
- Modify: `templates/CLAUDE.agentile-section.md`, `README.md` (any `shaping.md` mentions)

- [ ] **Step 1: Rename via git**

```bash
git mv templates/agentile/shaping.md templates/agentile/shape.md
```

- [ ] **Step 2: Update references** — grep and replace `shaping.md` → `shape.md`:

```bash
grep -rIl 'shaping\.md' skills templates README.md | xargs sed -i '' 's/shaping\.md/shape.md/g'
grep -rI 'shaping\.md' . --exclude-dir=.git || echo "clean"
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Rename shaping.md -> shape.md so playbook name == stage name"
```

### Task 3: Insert the standard preamble into every stage skill/agent

**Files (modify each, inserting the Shared preamble with `<STAGE>` substituted):**
- `skills/ag-capture/SKILL.md` (`capture`)
- `skills/ag-shape/SKILL.md` (`shape`)
- `skills/ag-spec/SKILL.md` (`spec`)
- `skills/ag-plan/SKILL.md` (`plan`)
- `skills/ag-retro/SKILL.md` (`learn`)
- `agents/ag-builder.md` (`build`)
- `agents/ag-reviewer.md` (`verify`)

- [ ] **Step 1:** For each file, insert the preamble block (from Shared artifacts, `<STAGE>` replaced) immediately after the H1 title line and its following blank line, before the existing intro. Keep one blank line above and below.

- [ ] **Step 2: Verify** every file now contains its preamble and the right stage token:

```bash
for f in skills/ag-capture skills/ag-shape skills/ag-spec skills/ag-plan skills/ag-retro; do grep -q "Apply this project's playbook" "$f/SKILL.md" && echo "ok $f" || echo "MISSING $f"; done
grep -l "Apply this project's playbook" agents/ag-builder.md agents/ag-reviewer.md
grep -o '`.agentile/[a-z]*.md`' agents/ag-builder.md agents/ag-reviewer.md   # expect build / verify
```

- [ ] **Step 3: Commit**

```bash
git add skills agents
git commit -m "Every stage skill/agent reads its .agentile/<stage>.md playbook (uniform contract)"
```

### Task 4: Stub playbooks for high-touch stages

**Files:**
- Create: `templates/agentile/build.md`, `templates/agentile/verify.md`

- [ ] **Step 1: `build.md` stub** (commented, inert — shows the delegate_to pattern):

```markdown
---
# Uncomment to execute ready work by delegating to a skill:
# delegate_to: worktree-workflow
# human_checkpoint: false
---

# Build — how this project executes ready work

Document execution conventions here (commit granularity, branch naming, etc.).
With `delegate_to: worktree-workflow`, each ready spec is built as an isolated
worktree chunk and merged back to main. Run `/ag-customise build` to set this up.
```

- [ ] **Step 2: `verify.md` stub** (Definition of Done + optional human gate):

```markdown
---
# human_checkpoint: true   # uncomment to require a human sign-off before ship
---

# Verify — this project's Definition of Done

List what "done" observably means here (the checklist the reviewer applies on top
of the baseline tests/scan/diff-read). Run `/ag-customise verify` to build it out.
```

- [ ] **Step 3: Commit**

```bash
git add templates/agentile/build.md templates/agentile/verify.md
git commit -m "Stub build.md and verify.md playbooks (delegate_to + human_checkpoint patterns)"
```

### Task 5: `/ag-customise <stage>` guided skill

**Files:**
- Create: `skills/ag-customise/SKILL.md`

- [ ] **Step 1: Write the skill.** Frontmatter:

```markdown
---
name: ag-customise
description: Build out an Agentile stage playbook conversationally — interview the user about how a given loop stage should run in this project, then write/update .agentile/<stage>.md. Trigger phrases include "/ag-customise", "customise a stage", "configure the build/verify/... stage", "set up worktree-workflow for build".
allowed-tools: AskUserQuestion, Bash, Read, Write, Edit
---
```

Body requirements (write these as numbered steps in the skill):

1. Resolve the stage name from `$ARGUMENTS` (e.g. `build`, `verify`, `prioritise`); if absent, ask which stage (offer the canonical list).
2. Read the existing `.agentile/<stage>.md` if present, and read `.agentile/playbooks.md` for the directive vocabulary.
3. Briefly describe the stage's baseline behaviour, then interview one or two questions at a time: should it delegate to a skill? (offer skill names) → sets `delegate_to`; should it pause for a human? → sets `human_checkpoint`; any extra skills → `also_run`; what's the project policy/definition (prose)?
4. Write `.agentile/<stage>.md` with the chosen frontmatter directives + prose. Create the file if missing.
5. Report what was written and that the change is live next time that stage runs.

- [ ] **Step 2: Verify** the skill validates as part of the plugin (Task 16) and its frontmatter parses:

```bash
ruby -ryaml -e 'p YAML.load_file("skills/ag-customise/SKILL.md".then{|f| File.read(f)[/^---\n(.*?)\n---/m,1]})' 2>/dev/null && echo "frontmatter ok"
```

- [ ] **Step 3: Commit**

```bash
git add skills/ag-customise
git commit -m "Add /ag-customise — guided skill to build out any stage playbook"
```

### Task 6: Update `/ag-init` to scaffold playbooks + rename

**Files:**
- Modify: `skills/ag-init/SKILL.md`

- [ ] **Step 1:** In the Step 3 "Scaffold files" list of `ag-init`, add: `playbooks.md`, `build.md`, `verify.md` (and, after Task 11, `prioritise.md`, `next.md`) copied from `templates/agentile/` into the project `.agentile/`. Change the existing `shaping.md` entry to `shape.md`. Keep idempotency (never overwrite).

- [ ] **Step 2:** Add a line to the closing report pointing at `/ag-customise <stage>` and `playbooks.md`.

- [ ] **Step 3: Verify** wording references the new files:

```bash
grep -E 'playbooks.md|build.md|verify.md|shape.md|ag-customise' skills/ag-init/SKILL.md
```

- [ ] **Step 4: Commit**

```bash
git add skills/ag-init/SKILL.md
git commit -m "ag-init scaffolds playbooks.md + stage stubs; uses shape.md"
```

### Task 7: Wire the BUILD instance (delegate_to worktree-workflow)

This is covered by Task 3 (preamble in `ag-builder`) + Task 4 (`build.md` stub) + the `ag-next`/`ag-plan` dispatch reading `build.md`. Add the explicit dispatch instruction.

**Files:**
- Modify: `skills/ag-plan/SKILL.md` (the hand-off-to-build step)

- [ ] **Step 1:** In `ag-plan`'s hand-off step, add: "When handing off to build, first read `.agentile/build.md`; if it sets `delegate_to`, invoke that skill to execute the work; otherwise dispatch the `ag-builder` agent. Pass the spec and plan."

- [ ] **Step 2: Commit**

```bash
git add skills/ag-plan/SKILL.md
git commit -m "ag-plan hands off to build via build.md (delegate_to-aware)"
```

### Task 8: Wire the VERIFY instance (human_checkpoint)

Covered by Task 3 (preamble in `ag-reviewer`) + Task 4 (`verify.md` stub). Add the explicit gate behaviour to the reviewer.

**Files:**
- Modify: `agents/ag-reviewer.md`

- [ ] **Step 1:** In `ag-reviewer`, add to the verdict step: "Apply the Definition of Done from `.agentile/verify.md` in addition to the baseline checks. If `human_checkpoint: true`, end with an explicit request for human sign-off and do not signal ready-to-ship until given."

- [ ] **Step 2: Commit**

```bash
git add agents/ag-reviewer.md
git commit -m "ag-reviewer applies verify.md DoD + honours human_checkpoint gate"
```

---

## Phase B — Concurrency + prioritise/next

### Task 9: Claim fields + value/certainty in the spec template

**Files:**
- Modify: `templates/agentile/spec-template.md`

- [ ] **Step 1:** Ensure the spec frontmatter includes (add if missing): `status: ready` (one of `ready|in_progress|shipped`), `priority:` (set by ag-prioritise; blank initially), `business_value:` and `technical_certainty:` (tagged by shape), and the claim fields `claimed_by:`, `label:`, `claimed_at:` (blank until claimed).

- [ ] **Step 2: Verify** the template parses as YAML frontmatter:

```bash
ruby -ryaml -e 'y=File.read("templates/agentile/spec-template.md")[/^---\n(.*?)\n---/m,1]; YAML.load(y); puts "ok"'
```

- [ ] **Step 3: Commit**

```bash
git add templates/agentile/spec-template.md
git commit -m "Spec template carries status/priority/claim fields + value×certainty tags"
```

### Task 10: Ruby atomic-claim helper `bin/ag-claim`

**Files:**
- Create: `bin/ag-claim`
- Test: `bin/test-ag-claim.rb`

- [ ] **Step 1: Write the failing test** (`bin/test-ag-claim.rb`):

```ruby
require "fileutils"; require "yaml"; require "tmpdir"; require "open3"
HELP = File.expand_path("ag-claim", __dir__)

def spec(dir, name, status:, priority:)
  File.write(File.join(dir, "#{name}.md"),
    "---\nstatus: #{status}\npriority: #{priority}\nclaimed_by:\nlabel:\nclaimed_at:\n---\n# #{name}\n")
end

def claim(dir, session:, wip:)
  out, _err, st = Open3.capture3("ruby", HELP, dir, session, "", wip.to_s)
  [out.strip, st.exitstatus]
end

Dir.mktmpdir do |dir|
  spec(dir, "low",  status: "ready", priority: 5)
  spec(dir, "high", status: "ready", priority: 1)   # lower number = higher priority
  # 1) claims highest-priority ready spec, marks it in_progress with the session
  path, code = claim(dir, session: "sess-A", wip: 2)
  raise "exit #{code}" unless code == 0
  raise "picked #{path}" unless path.end_with?("high.md")
  fm = YAML.load_file(path).then { |_| YAML.load(File.read(path)[/^---\n(.*?)\n---/m, 1]) }
  raise "status" unless fm["status"] == "in_progress"
  raise "claimed_by" unless fm["claimed_by"] == "sess-A"
  raise "claimed_at" if fm["claimed_at"].to_s.empty?
  # 2) second claim takes the next ready spec
  path2, = claim(dir, session: "sess-B", wip: 2)
  raise "second #{path2}" unless path2.end_with?("low.md")
  # 3) wip limit reached -> prints NONE
  path3, = claim(dir, session: "sess-C", wip: 2)
  raise "wip not enforced: #{path3}" unless path3 == "WIP_FULL"
  puts "ALL PASS"
end
```

- [ ] **Step 2: Run it — must fail** (helper absent):

```bash
ruby bin/test-ag-claim.rb
```

Expected: error (cannot run `ag-claim`).

- [ ] **Step 3: Write `bin/ag-claim`:**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# Atomically claim the highest-priority unclaimed ready spec.
# Usage: ag-claim <specs-dir> <session-id> [label] [wip-limit]
# Prints the claimed spec path, or "NONE" (no ready specs) / "WIP_FULL".
require "yaml"

specs_dir, session, label, wip = ARGV
abort "usage: ag-claim <specs-dir> <session-id> [label] [wip-limit]" if specs_dir.nil? || session.to_s.empty?
wip = (wip.to_s.empty? ? 0 : wip.to_i) # 0 => unlimited

lock_path = File.join(specs_dir, ".pull.lock")
File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
  lock.flock(File::LOCK_EX)

  specs = Dir.glob(File.join(specs_dir, "*.md")).map do |path|
    raw = File.read(path)
    fm  = (YAML.safe_load(raw[/\A---\n(.*?)\n---/m, 1] || "", permitted_classes: [Time]) || {})
    { path: path, raw: raw, fm: fm }
  end

  in_progress = specs.count { |s| s[:fm]["status"] == "in_progress" }
  if wip.positive? && in_progress >= wip
    puts "WIP_FULL"; next
  end

  ready = specs.select { |s| s[:fm]["status"] == "ready" && s[:fm]["claimed_by"].to_s.empty? }
  if ready.empty?
    puts "NONE"; next
  end

  # lower priority number = higher priority; nil sorts last; tie-break by filename
  chosen = ready.min_by { |s| [s[:fm]["priority"] || Float::INFINITY, File.basename(s[:path])] }

  fm = chosen[:fm]
  fm["status"]     = "in_progress"
  fm["claimed_by"] = session
  fm["label"]      = label.to_s
  fm["claimed_at"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  body = chosen[:raw].sub(/\A---\n.*?\n---\n/m, "---\n#{fm.to_yaml.sub(/\A---\n/, "")}---\n")
  File.write(chosen[:path], body)
  puts chosen[:path]
end
```

- [ ] **Step 4: Run the test — must pass:**

```bash
chmod +x bin/ag-claim
ruby bin/test-ag-claim.rb
```

Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add bin/ag-claim bin/test-ag-claim.rb
git commit -m "Add bin/ag-claim: flock-protected atomic select-and-claim of the top ready spec (+ test)"
```

### Task 11: `SessionStart` hook surfacing the session id

**Files:**
- Create: `hooks/session-id.rb`
- Test: `hooks/test-session-id.rb`
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Write the failing test** (`hooks/test-session-id.rb`):

```ruby
require "json"; require "open3"
HOOK = File.expand_path("session-id.rb", __dir__)
out, _e, st = Open3.capture3("ruby", HOOK, stdin_data: { "session_id" => "abc-123" }.to_json)
raise "exit #{st.exitstatus}" unless st.exitstatus.zero?
data = JSON.parse(out)
ctx = data.dig("hookSpecificOutput", "additionalContext").to_s
raise "id not surfaced: #{out}" unless ctx.include?("abc-123")
# missing session_id => no crash, no-op (empty) output
out2, _e2, st2 = Open3.capture3("ruby", HOOK, stdin_data: "{}")
raise "exit2 #{st2.exitstatus}" unless st2.exitstatus.zero?
puts "ALL PASS"
```

- [ ] **Step 2: Run it — must fail.**

```bash
ruby hooks/test-session-id.rb
```

- [ ] **Step 3: Write `hooks/session-id.rb`:**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# SessionStart hook: surface the Claude Code session id into the session context
# so Agentile skills (ag-next) can stamp claims with a resumable handle.
require "json"
raw = $stdin.read
sid = (JSON.parse(raw)["session_id"] rescue nil)
exit 0 if sid.nil? || sid.to_s.empty?
puts JSON.generate(
  "hookSpecificOutput" => {
    "hookEventName"     => "SessionStart",
    "additionalContext" => "Agentile: this session's id is #{sid}. " \
      "When you claim work with /ag-next, stamp it claimed_by: #{sid} so the " \
      "loop can be resumed later with `claude --resume #{sid}`."
  }
)
```

- [ ] **Step 4: Run the test — must pass.**

```bash
chmod +x hooks/session-id.rb
ruby hooks/test-session-id.rb
```

Expected: `ALL PASS`.

- [ ] **Step 5: Register the hook** in `hooks/hooks.json` — add a `SessionStart` array:

```json
"SessionStart": [
  { "hooks": [ { "type": "command", "command": "ruby \"${CLAUDE_PLUGIN_ROOT}/hooks/session-id.rb\"", "timeout": 10 } ] }
]
```

Validate JSON: `ruby -rjson -e 'JSON.parse(File.read("hooks/hooks.json")); puts "ok"'`.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-id.rb hooks/test-session-id.rb hooks/hooks.json
git commit -m "Add SessionStart hook surfacing session id for resumable claims (+ test)"
```

### Task 12: `ag-prioritise` skill

**Files:**
- Create: `skills/ag-prioritise/SKILL.md`
- Create: `templates/agentile/prioritise.md`

- [ ] **Step 1: `prioritise.md` stub:**

```markdown
---
wip_limit: 2
---

# Prioritise — this project's ordering scheme

Default scheme: order ready specs by **Business Value × Technical Certainty**
(high value + high certainty first). Edit this prose to change the scheme.
`wip_limit` caps how many items may be in_progress at once.
```

- [ ] **Step 2: Write `ag-prioritise`.** Frontmatter:

```markdown
---
name: ag-prioritise
description: Order the ready Agentile specs by this project's scheme, writing a priority onto each. Read-only over content; only sets the priority field. Trigger phrases include "/ag-prioritise", "prioritise the backlog", "order the ready work", "re-rank specs".
allowed-tools: Bash, Read, Edit
---
```

Body (numbered steps): read `.agentile/prioritise.md` for the scheme + `wip_limit`; read the specs dir from `.agentile/config.md`; list specs with `status: ready`; rank them per the scheme (default Business Value × Technical Certainty as tagged on each spec); write a `priority:` integer (1 = highest) into each ready spec's frontmatter; report the ordered list. Apply the standard playbook preamble for `prioritise` at the top.

- [ ] **Step 3: Commit**

```bash
git add skills/ag-prioritise templates/agentile/prioritise.md
git commit -m "Add ag-prioritise: order ready specs by the project scheme (default value×certainty)"
```

### Task 13: `ag-next` skill (claim + report)

**Files:**
- Create: `skills/ag-next/SKILL.md`
- Create: `templates/agentile/next.md`

- [ ] **Step 1: `next.md` stub:**

```markdown
---
# auto_start: false   # v1: ag-next claims + reports; it does not auto-run the cycle
---

# Next — this project's pull policy

`/ag-next` atomically claims the highest-priority unclaimed ready spec and reports
it. WIP is capped by `wip_limit` in prioritise.md. (auto_start is reserved for a
future version.)
```

- [ ] **Step 2: Write `ag-next`.** Frontmatter:

```markdown
---
name: ag-next
description: Pull the next piece of Agentile work — atomically claim the highest-priority unclaimed ready spec, stamp it with this session so it is resumable, and report it. Safe for concurrent loops. Trigger phrases include "/ag-next", "what's next", "pull the next item", "give me the next thing to work on".
allowed-tools: Bash, Read
---
```

Body (numbered steps):
1. Apply the standard playbook preamble for `next`.
2. Determine the session id from the context surfaced by the SessionStart hook; if not present, mint a fallback id `$(whoami)@$(hostname -s)/$(date +%s)` and note it.
3. Read the specs dir (from `.agentile/config.md`) and `wip_limit` (from `.agentile/prioritise.md`).
4. Run the helper: `ruby "${CLAUDE_PLUGIN_ROOT}/bin/ag-claim" <specs-dir> <session-id> "<optional label from $ARGUMENTS>" <wip_limit>`.
5. Interpret output: a path → report "claimed `<path>` as `<session-id>`; resume later with `claude --resume <session-id>`"; `NONE` → "no ready work"; `WIP_FULL` → "WIP limit reached (`<n>`); ship something first".
6. **v1: claim + report only — do not auto-start the cycle.** Tell the user they can now `/ag-plan <path>`.

- [ ] **Step 3: Commit**

```bash
git add skills/ag-next templates/agentile/next.md
git commit -m "Add ag-next: mutex-safe claim+report of the next ready spec, session-stamped"
```

### Task 14: `ag-wip` skill (read-only WIP + resume)

**Files:**
- Create: `skills/ag-wip/SKILL.md`

- [ ] **Step 1: Write `ag-wip`.** Frontmatter:

```markdown
---
name: ag-wip
description: Show Agentile work in progress — which specs are claimed, by which session/label, since when, and the exact command to resume each. Read-only. Trigger phrases include "/ag-wip", "what's in progress", "what's being worked on", "show work in flight".
allowed-tools: Bash, Read
---
```

Body: read the specs dir; list specs with `status: in_progress`; for each print `<slug>  in_progress  <label or claimed_by>  (claimed <relative age>)` and a `→ resume: claude --resume <claimed_by>` line. Flag any whose `claimed_at` is older than ~24h as "likely stale — reclaim by setting status: ready". No mutation.

- [ ] **Step 2: Commit**

```bash
git add skills/ag-wip
git commit -m "Add ag-wip: read-only work-in-progress view with resume commands"
```

### Task 15: Docs — README, essay, CLAUDE section

**Files:**
- Modify: `README.md`, `lean-agentic-loop.md`, `templates/CLAUDE.agentile-section.md`

- [ ] **Step 1:** README: add `/ag-prioritise`, `/ag-next`, `/ag-wip`, `/ag-customise` to the skills list; add a "Customisation" subsection (the playbook contract) and a "Concurrent loops" subsection (claims + resume).
- [ ] **Step 2:** `lean-agentic-loop.md`: in Part 2/3, add prioritise-vs-next as distinct acts and the concurrency/claims model.
- [ ] **Step 3:** `templates/CLAUDE.agentile-section.md`: mention prioritise/next/wip + that any stage is customisable via `.agentile/<stage>.md`.
- [ ] **Step 4: Commit**

```bash
git add README.md lean-agentic-loop.md templates/CLAUDE.agentile-section.md
git commit -m "Docs: customisation contract, prioritise vs next, concurrent resumable loops"
```

### Task 16: Validate, sync, exercise

- [ ] **Step 1: Static + unit checks:**

```bash
claude plugin validate .
ruby -c bin/ag-claim && ruby bin/test-ag-claim.rb
ruby -c hooks/session-id.rb && ruby hooks/test-session-id.rb
ruby -rjson -e 'JSON.parse(File.read("hooks/hooks.json")); JSON.parse(File.read(".claude-plugin/plugin.json")); puts "json ok"'
```

Expected: validation passes; both tests print `ALL PASS`; `json ok`.

- [ ] **Step 2: Confirm component inventory** picks up the four new skills (and that the dev symlink is live):

```bash
./bin/ag-sync >/dev/null 2>&1; ./bin/ag-dev-link >/dev/null 2>&1
claude plugin details agentile 2>&1 | sed -n '/Component inventory/,/MCP servers/p'
```

Expected: Skills now include `ag-prioritise`, `ag-next`, `ag-wip`, `ag-customise`; Hooks include `SessionStart`.

- [ ] **Step 3: End-to-end in a scratch repo (manual, after session reload):** `/ag-init` scaffolds the new stubs + `shape.md`; `/ag-customise build` wires `delegate_to: worktree-workflow`; create two ready specs; `/ag-prioritise` orders them; `/ag-next` claims the top and prints a resume command; a second `/ag-next` claims the other; `/ag-wip` lists both with resume commands; a third `/ag-next` reports `WIP_FULL` at `wip_limit: 2`.

- [ ] **Step 4: Merge the worktree back to main and push** (`agenta-consulting/agentile`).

---

## Self-review (completed)

- **Spec coverage:** §1 contract → Tasks 1,3; §2 scaffolding/customise → Tasks 5,6; §3 prioritise/next → Tasks 12,13; §4 rename → Task 2; §5 concurrency → Tasks 9,10; §6 resumable claims → Tasks 11,13,14; instances → Tasks 7,8; deferred defaults (claim+report, surface-stale) → Tasks 13,14. No uncovered section.
- **Placeholders:** none — Ruby helper, hook, and their tests are complete; markdown tasks give exact frontmatter + the shared preamble + required sections.
- **Type/name consistency:** claim fields `status|priority|claimed_by|label|claimed_at` and helper output tokens `NONE|WIP_FULL|<path>` are used identically across Tasks 9, 10, 13, 14.
