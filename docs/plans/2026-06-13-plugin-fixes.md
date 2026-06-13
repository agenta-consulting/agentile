# Agentile Plugin Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the plugin-review findings (`docs/reviews/plugin-review.md`) — restore the dead gate hooks, fix the update story, replace stale doc-research mechanisms with verified Claude Code features, add the project-brief bootstrap, and apply the enhancement suggestions.

**Architecture:** Markdown skills + Ruby `bin/` helpers + Ruby hooks + JSON manifest + templates. The plugin ships fixed methodology; projects scaffold `.agentile/` content. Changes here keep that split: hooks read `.agentile/gates.json`; skills resolve helpers as bare `bin/` commands (on PATH when the plugin is enabled) and templates via `${CLAUDE_SKILL_DIR}`; the session id comes from the documented `${CLAUDE_SESSION_ID}` substitution.

**Tech Stack:** Ruby (helpers + hooks + tests, run as plain `ruby <file>`), Markdown, JSON.

**Worktree:** `.worktrees/plugin-fixes`, branch `plugin-fixes`. All paths relative to the worktree root.

**Verified Claude Code facts this plan relies on** (confirmed against current docs, 2026-06-13):

- Plugin `bin/` files are on the Bash PATH as bare commands while the plugin is enabled.
- Omitting `version` in `plugin.json` ⇒ git-SHA-based updates (every commit is a new version); pinning ⇒ manual bumps only.
- `${CLAUDE_SESSION_ID}` and `${CLAUDE_SKILL_DIR}` are documented substitution variables usable in skill bodies.
- `disable-model-invocation: true`, named `arguments: [name]` (`$name` placeholders), `context: fork` + `agent:`, and `` !`cmd` `` dynamic injection are valid skill frontmatter/body features.
- Subagents: `model: inherit` is the default; `isolation: worktree`, `memory: <user|project|local>`, and `skills:` preload are valid fields; precedence is project `.claude/agents/` > user `~/.claude/agents/` > plugin `agents/`.
- Plugin `settings.json` supports `subagentStatusLine`.

**Explicitly NOT used** (could not verify in current docs — do not build on these): `/goal`, `FileChanged` + `watchPaths`, `stop_hook_active` (treated as unreliable — replaced with an independent guard), `sessionTitle` from hooks, `${CLAUDE_PLUGIN_DATA}`, and the specific `/loop` facts (7-day expiry etc. — documented only in hedged, non-specific terms).

**Decisions already made (do not relitigate):** scope = all three tiers; bootstrap = `/ag-init` interview writing `docs/agentile/brief.md`, consumers read it, no inbox-seeding; loop = keep the two-command pattern, hedge the docs, no `/goal`/`FileChanged`/`.claude/loop.md` scaffold.

## Task 1: Fix the dead gate-hook path + add a hook test harness

**Files:**

- Modify: `hooks/format-on-edit.rb` (line 36)
- Modify: `hooks/test-gate.rb` (line 40)
- Create: `hooks/test-gates.rb`

- [ ] **Step 1: Write the failing hook test**

Create `hooks/test-gates.rb`:

```ruby
require "json"; require "open3"; require "tmpdir"; require "fileutils"
FORMAT = File.expand_path("format-on-edit.rb", __dir__)
TESTG  = File.expand_path("test-gate.rb", __dir__)

def run(hook, payload)
  Open3.capture3("ruby", hook, stdin_data: JSON.generate(payload))
end

# 1. test-gate fires on a configured failing test in .agentile/gates.json
Dir.mktmpdir do |d|
  FileUtils.mkdir_p(File.join(d, ".agentile"))
  File.write(File.join(d, ".agentile", "gates.json"), JSON.generate("test" => "false"))
  out, _e, st = run(TESTG, "cwd" => d)
  raise "test-gate should block on failing test: #{out.inspect}" unless out.include?('"decision":"block"')
  raise "exit #{st.exitstatus}" unless st.exitstatus.zero?
end

# 2. test-gate allows when the test passes
Dir.mktmpdir do |d|
  FileUtils.mkdir_p(File.join(d, ".agentile"))
  File.write(File.join(d, ".agentile", "gates.json"), JSON.generate("test" => "true"))
  out, _e, _st = run(TESTG, "cwd" => d)
  raise "should allow on passing test: #{out.inspect}" unless out.strip.empty?
end

# 3. test-gate no-ops when gates.json absent (unconfigured repo)
Dir.mktmpdir do |d|
  out, _e, _st = run(TESTG, "cwd" => d)
  raise "should no-op without gates.json: #{out.inspect}" unless out.strip.empty?
end

# 4. format-on-edit runs the format command (writes a marker), reads .agentile path
Dir.mktmpdir do |d|
  FileUtils.mkdir_p(File.join(d, ".agentile"))
  marker = File.join(d, "ran")
  File.write(File.join(d, ".agentile", "gates.json"), JSON.generate("format" => "touch #{marker}"))
  File.write(File.join(d, "f.rb"), "x = 1\n")
  run(FORMAT, "cwd" => d, "tool_input" => { "file_path" => File.join(d, "f.rb") })
  raise "format hook did not run from .agentile/gates.json" unless File.exist?(marker)
end

puts "ALL PASS"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby hooks/test-gates.rb`
Expected: FAIL at test 1 (`test-gate should block…`) — the hook reads `.lal/gates.json`, which doesn't exist, so it allows instead of blocking.

- [ ] **Step 3: Fix both hook paths**

In `hooks/test-gate.rb` line 40, change `File.join(cwd, '.lal', 'gates.json')` to `File.join(cwd, '.agentile', 'gates.json')`.

In `hooks/format-on-edit.rb` line 36, change `File.join(cwd, '.lal', 'gates.json')` to `File.join(cwd, '.agentile', 'gates.json')`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `ruby hooks/test-gates.rb`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add hooks/format-on-edit.rb hooks/test-gate.rb hooks/test-gates.rb
git commit -m "hooks: read .agentile/gates.json (was dead .lal/ path); add gate-hook test"
```

## Task 2: test-gate robustness — clean-tree skip + independent re-block guard

**Files:**

- Modify: `hooks/test-gate.rb`
- Modify: `hooks/test-gates.rb`
- Modify: `hooks/hooks.json` (timeout)

Rationale: with gates live (Task 1), the suite runs on every Stop, including idle `/loop` ticks; and `stop_hook_active` is undocumented so its re-block guard is unreliable. Add (a) a clean-working-tree skip so idle ticks and already-green trees don't re-run, and (b) an independent consecutive-block counter so a never-passing suite can't loop forever.

- [ ] **Step 1: Add failing tests**

Append to `hooks/test-gates.rb` before `puts "ALL PASS"`:

```ruby
# 5. test-gate allows on a clean git working tree (nothing to test / idle tick)
Dir.mktmpdir do |d|
  Open3.capture3("git", "init", "-q", d)
  FileUtils.mkdir_p(File.join(d, ".agentile"))
  File.write(File.join(d, ".agentile", "gates.json"), JSON.generate("test" => "false"))
  Open3.capture3("git", "-C", d, "add", "-A")
  Open3.capture3("git", "-C", d, "-c", "user.email=a@b.c", "-c", "user.name=t", "commit", "-qm", "x")
  out, _e, _st = run(TESTG, "cwd" => d)
  raise "clean tree should allow without running tests: #{out.inspect}" unless out.strip.empty?
end

# 6. after N consecutive blocks for the same session, the gate gives up (allows) rather than looping
Dir.mktmpdir do |d|
  Open3.capture3("git", "init", "-q", d)
  FileUtils.mkdir_p(File.join(d, ".agentile"))
  File.write(File.join(d, ".agentile", "gates.json"), JSON.generate("test" => "false"))
  File.write(File.join(d, "dirty.txt"), "uncommitted\n") # dirty tree so the clean-tree skip doesn't fire
  sid = "sess-guard-#{Process.pid}"
  results = (1..6).map { run(TESTG, "cwd" => d, "session_id" => sid)[0] }
  raise "first attempt should block: #{results.first.inspect}" unless results.first.include?('"decision":"block"')
  raise "should eventually stop blocking: #{results.last.inspect}" unless results.last.strip.empty?
end
```

- [ ] **Step 2: Run to verify failure**

Run: `ruby hooks/test-gates.rb`
Expected: FAIL at test 5 (clean tree still runs `false` and blocks).

- [ ] **Step 3: Implement the guards in `hooks/test-gate.rb`**

After the existing `allow if data['stop_hook_active']` line, add the clean-tree skip and counter. Replace the block from `cwd = data['cwd'] || Dir.pwd` through the final `block(...)` call with:

```ruby
require 'tmpdir'
require 'digest'

cwd = data['cwd'] || Dir.pwd
gates_path = File.join(cwd, '.agentile', 'gates.json')
allow unless File.exist?(gates_path)

gates = begin
  JSON.parse(File.read(gates_path))
rescue JSON::ParserError
  allow
end

cmd = gates['test'].to_s.strip
allow if cmd.empty?

# Skip when the working tree is clean: an idle loop tick or an already-green
# commit has nothing new to test. Only applies inside a git repo.
porcelain, _pe, pst = Open3.capture3('git', '-C', cwd, 'status', '--porcelain')
allow if pst.success? && porcelain.strip.empty?

# Independent re-block guard (stop_hook_active is unreliable): cap consecutive
# blocks per session so a suite that can never pass can't loop forever.
MAX_CONSECUTIVE_BLOCKS = 5
sid = (data['session_id'] || 'nosession').to_s
counter = File.join(Dir.tmpdir, "agentile-stopgate-#{Digest::SHA1.hexdigest(sid + cwd)}")

stdout, stderr, status = Open3.capture3(cmd, chdir: cwd)
if status.success?
  File.delete(counter) if File.exist?(counter)
  allow
end

count = (File.read(counter).to_i rescue 0) + 1
File.write(counter, count.to_s)
if count >= MAX_CONSECUTIVE_BLOCKS
  File.delete(counter) if File.exist?(counter)
  allow
end

tail = (stdout.to_s + stderr.to_s).split("\n").last(20).join("\n")
block(
  "Agentile gate: tests are failing, so the work is not done. Run the project test " \
  "command (`#{cmd}`), fix the failures, and try again.\n\nLast output:\n#{tail}"
)
```

Update the header comment block (lines 8–13) to describe the new behaviour: no-op on a clean working tree, and a per-session consecutive-block cap replacing reliance on `stop_hook_active` (which is kept as a first-line allow but no longer the sole guard).

- [ ] **Step 4: Run to verify pass**

Run: `ruby hooks/test-gates.rb`
Expected: `ALL PASS`.

- [ ] **Step 5: Raise the Stop timeout**

In `hooks/hooks.json`, change both `test-gate.rb` `"timeout": 180` values to `"timeout": 600` (the documented hook default; 180s could kill a real suite mid-run).

- [ ] **Step 6: Commit**

```bash
git add hooks/test-gate.rb hooks/test-gates.rb hooks/hooks.json
git commit -m "test-gate: skip clean trees, add independent consecutive-block cap, raise timeout to 600s"
```

## Task 3: Adopt `${CLAUDE_SESSION_ID}`; retire the session-id hook

**Files:**

- Modify: `skills/ag-next/SKILL.md`
- Modify: `skills/ag-loop/SKILL.md`
- Modify: `hooks/hooks.json`
- Delete: `hooks/session-id.rb`, `hooks/test-session-id.rb`

- [ ] **Step 1: ag-next — use the substitution variable**

In `skills/ag-next/SKILL.md` Baseline step 1, replace the whole step (the "Determine this session's id from the context the SessionStart hook injected … minted locally rather than injected by the hook." block) with:

```markdown
1. This session's id is `${CLAUDE_SESSION_ID}` — Claude Code substitutes the real session id here when the skill runs. Use it directly as the claim's `claimed_by` handle; it is what `claude --resume <id>` needs. (If for any reason it is empty, fall back to `echo "$(whoami)@$(hostname -s)/$(date +%s)"` and note that this fallback is not a resume handle.)
```

- [ ] **Step 2: ag-next — pass it to the helper**

In step 4's command, the `<session-id>` placeholder is now `${CLAUDE_SESSION_ID}`. Update the example to:

```
ruby "<helper>" "<specs-dir>" "${CLAUDE_SESSION_ID}" "<optional label from $ARGUMENTS>" "<wip_limit>"
```

(Task 4 changes `ruby "<helper>"` to a bare command; keep them consistent — if Task 4 lands first this already reads `ag-claim …`.)

- [ ] **Step 3: ag-loop — resume check uses the variable**

In `skills/ag-loop/SKILL.md` Step 1 (Resume check), replace the phrase "equal to this session's id (surfaced by the SessionStart hook as "Agentile: this session's id is …")" with "equal to this session's id (`${CLAUDE_SESSION_ID}`)".

- [ ] **Step 4: Remove the hook and its test**

```bash
git rm hooks/session-id.rb hooks/test-session-id.rb
```

In `hooks/hooks.json`, delete the entire `"SessionStart"` array entry (the object with `session-id.rb`), leaving `PostToolUse`, `Stop`, and `SubagentStop`.

- [ ] **Step 5: Verify hooks.json is valid JSON**

Run: `ruby -rjson -e 'JSON.parse(File.read("hooks/hooks.json")); puts "ok"'`
Expected: `ok`.

- [ ] **Step 6: Commit**

```bash
git add skills/ag-next/SKILL.md skills/ag-loop/SKILL.md hooks/hooks.json
git commit -m "Use \${CLAUDE_SESSION_ID} substitution directly; retire the session-id SessionStart hook"
```

## Task 4: Resolve helpers as bare commands; relocate dev/test scripts out of bin/

**Files:**

- Modify: `skills/ag-next/SKILL.md`, `skills/ag-abandon/SKILL.md`, `skills/ag-init/SKILL.md`
- Move: `bin/test-ag-claim.rb`, `bin/test-ag-dependents.rb` → `dev/`; `bin/ag-dev-link`, `bin/ag-sync` → `dev/`
- Modify: `dev/ag-dev-link`, `dev/ag-sync` (path-relative references), `README.md`, `hooks/test-gates.rb` if it references bin paths (it doesn't)

Rationale: every file in `bin/` becomes a bare command on the user's PATH; only `ag-claim` and `ag-dependents` are runtime helpers — dev/test scripts should not ship onto PATH. And bare commands remove the brittle cache-glob fallback.

- [ ] **Step 1: Move the scripts**

```bash
mkdir -p dev
git mv bin/test-ag-claim.rb dev/test-ag-claim.rb
git mv bin/test-ag-dependents.rb dev/test-ag-dependents.rb
git mv bin/ag-dev-link dev/ag-dev-link
git mv bin/ag-sync dev/ag-sync
```

- [ ] **Step 2: Fix the moved tests' helper path**

In `dev/test-ag-claim.rb` and `dev/test-ag-dependents.rb`, the line `HELP = File.expand_path("ag-claim", __dir__)` (resp. `ag-dependents`) now points at `dev/`. Change each to point at `../bin/`:

```ruby
HELP = File.expand_path("../bin/ag-claim", __dir__)
```
```ruby
HELP = File.expand_path("../bin/ag-dependents", __dir__)
```

Run both to confirm they still pass:

Run: `ruby dev/test-ag-claim.rb && ruby dev/test-ag-dependents.rb`
Expected: `ALL PASS` twice.

- [ ] **Step 3: ag-next — bare command**

In `skills/ag-next/SKILL.md`, replace step 3 (the `${CLAUDE_PLUGIN_ROOT}/bin/ag-claim` resolution with the `~/.claude/plugins/cache/...` glob fallback) with:

```markdown
3. The claim helper ships in this plugin's `bin/`, which is on your PATH while the plugin is enabled — call it as the bare command `ag-claim`. (Fallback only if it is not found: `"${CLAUDE_PLUGIN_ROOT}/bin/ag-claim"`.)
```

In step 4, change the command to:

```
ag-claim "<specs-dir>" "${CLAUDE_SESSION_ID}" "<optional label from $ARGUMENTS>" "<wip_limit>"
```

- [ ] **Step 4: ag-abandon — bare command**

In `skills/ag-abandon/SKILL.md` Step 3, replace the `${CLAUDE_PLUGIN_ROOT}/bin/ag-dependents` + cache-glob resolution paragraph and the `ruby "<helper>" …` invocation with:

```markdown
Call the dependents helper as the bare command `ag-dependents` (it ships in this plugin's `bin/`, on your PATH while the plugin is enabled; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-dependents"` only if not found):

```
ag-dependents "<specs-dir>" "<target-slug>"
```
```

- [ ] **Step 5: ag-init — template resolution via `${CLAUDE_SKILL_DIR}`**

In `skills/ag-init/SKILL.md` Step 1, replace the two-bullet resolution (the `$CLAUDE_PLUGIN_ROOT` then `~/.claude/plugins/cache/...` glob) with:

```markdown
The files to copy live in this plugin's `templates/` directory, one level up from this skill: `${CLAUDE_SKILL_DIR}/../../templates/`. (`${CLAUDE_SKILL_DIR}` is the directory containing this `SKILL.md`; it resolves to `…/skills/ag-init/`, so `../../templates/` is the plugin's templates root. Fallback: `"${CLAUDE_PLUGIN_ROOT}/templates/"`.)
```

- [ ] **Step 6: Update dev script internals**

`dev/ag-dev-link` and `dev/ag-sync` compute `REPO` as `"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`. Now that they live in `dev/`, `..` still resolves to the repo root — verify by reading; no change needed unless a script references `bin/` siblings. (Task 5 revisits `ag-dev-link`'s version logic.)

- [ ] **Step 7: README — dev script paths**

In `README.md`, the "Developing the plugin while it's installed" section references `bin/ag-dev-link` and `bin/ag-sync`. Change those to `dev/ag-dev-link` and `dev/ag-sync`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Call ag-claim/ag-dependents as bare bin/ commands; move dev+test scripts to dev/ (off users' PATH); resolve templates via \${CLAUDE_SKILL_DIR}"
```

## Task 5: Fix the update story — omit `version`, make dev-link version-agnostic

**Files:**

- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- Modify: `dev/ag-dev-link`
- Modify: `README.md`

- [ ] **Step 1: Remove the version pin**

In `.claude-plugin/plugin.json`, delete the `"version": "0.1.0",` line. In `.claude-plugin/marketplace.json`, delete the plugin entry's `"version": "0.1.0",` line (keep `metadata.version` — that versions the marketplace doc, not the plugin; or remove it too for consistency — remove the plugin-entry one at minimum).

- [ ] **Step 2: Make ag-dev-link resolve the cache dir without a version**

In `dev/ag-dev-link`, the `VERSION=…` derivation and `TARGET="$CACHE/$VERSION"` break when `version` is absent. Replace the `VERSION=…` line and `TARGET=…` line with cache-dir discovery:

```bash
# With version omitted, the cache dir is named by git SHA (or "latest"); link
# whichever version dir currently exists, creating one if the cache is empty.
TARGET="$(ls -d "$CACHE"/*/ 2>/dev/null | head -1)"
TARGET="${TARGET%/}"
if [ -z "$TARGET" ]; then
  TARGET="$CACHE/dev"
fi
```

- [ ] **Step 3: README — document the dev update model**

In `README.md`'s "Developing the plugin while it's installed" section, add a sentence: "The plugin omits a pinned `version`, so git-distributed installs pick up every pushed commit as a new version — there is no field to bump during development. Tag a semver release when cutting a stable version."

- [ ] **Step 4: Verify both manifests still parse**

Run: `ruby -rjson -e 'JSON.parse(File.read(".claude-plugin/plugin.json")); JSON.parse(File.read(".claude-plugin/marketplace.json")); puts "ok"'`
Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json dev/ag-dev-link README.md
git commit -m "Update story: omit version for SHA-based dev updates; make ag-dev-link version-agnostic"
```

## Task 6: Manifest polish

**Files:**

- Modify: `.claude-plugin/plugin.json`
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Drop the redundant skills key, add UI metadata**

In `.claude-plugin/plugin.json`: remove the `"skills": "./skills/"` line (the default `skills/` directory is always scanned). Add these keys (after `keywords`):

```json
  "displayName": "Agentile",
  "homepage": "https://github.com/agenta-consulting/agentile",
  "repository": "https://github.com/agenta-consulting/agentile"
```

(Ensure JSON comma correctness — the line that was last before the closing brace gets a trailing comma as needed.)

- [ ] **Step 2: Fix the PostToolUse matcher**

In `hooks/hooks.json`, change `"matcher": "Edit|Write|MultiEdit"` to `"matcher": "Edit|Write|NotebookEdit"` (`MultiEdit` is no longer a current tool name).

- [ ] **Step 3: Verify JSON + skills still resolve**

Run: `ruby -rjson -e 'JSON.parse(File.read(".claude-plugin/plugin.json")); JSON.parse(File.read("hooks/hooks.json")); puts "ok"'`
Expected: `ok`. Also confirm `ls skills/` still lists all 13 skill dirs (they load from the default scan).

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json hooks/hooks.json
git commit -m "Manifest: drop redundant skills key, add displayName/homepage/repository; matcher MultiEdit->NotebookEdit"
```

## Task 7: ag-claim comment-preserving stamp + friendly missing-dir errors

**Files:**

- Modify: `bin/ag-claim`, `bin/ag-dependents`
- Modify: `dev/test-ag-claim.rb`, `dev/test-ag-dependents.rb`

- [ ] **Step 1: Add failing tests**

In `dev/test-ag-claim.rb`, add before `puts "ALL PASS"`:

```ruby
# 14. claiming preserves frontmatter comments and key order (no full re-serialise)
Dir.mktmpdir do |d|
  File.write(File.join(d, "0001-x.md"),
    "---\n# a leading comment\nstatus: ready\ncreated: 2026-06-10\n# claim fields below\nclaimed_by:\nlabel:\nclaimed_at:\ndepends_on: []\n---\n# body\n")
  path = claim(d)
  body = File.read(path)
  raise "comment lost" unless body.include?("# a leading comment") && body.include?("# claim fields below")
  raise "not stamped" unless body.include?("status: in_progress") && body.include?("claimed_by: s")
end

# 15. friendly error on a missing specs dir (no raw stack trace)
Dir.mktmpdir do |d|
  missing = File.join(d, "nope")
  out, err, st = Open3.capture3("ruby", HELP, missing, "s", "", "0")
  raise "should fail cleanly: #{st.exitstatus} #{err.inspect}" if st.success?
  raise "want friendly message, got: #{err.inspect}" unless err.include?("no such specs dir") && !err.include?("(irb)") && !err.downcase.include?("errno")
end
```

In `dev/test-ag-dependents.rb`, add before `puts "ALL PASS"`:

```ruby
# 8. friendly error on a missing specs dir
Dir.mktmpdir do |d|
  missing = File.join(d, "nope")
  out, err, st = Open3.capture3("ruby", HELP, missing, "x")
  raise "should fail cleanly: #{st.exitstatus} #{err.inspect}" if st.success?
  raise "want friendly message, got: #{err.inspect}" unless err.include?("no such specs dir")
end
```

- [ ] **Step 2: Run to verify failure**

Run: `ruby dev/test-ag-claim.rb`
Expected: FAIL at test 14 (comments stripped by `fm.to_yaml`) — and test 15 fails because the lock-file open raises `Errno::ENOENT`.

- [ ] **Step 3: ag-claim — guard + targeted stamp**

In `bin/ag-claim`, after the `wip = (...)` line and before opening the lock, add:

```ruby
abort "ag-claim: no such specs dir: #{specs_dir}" unless File.directory?(specs_dir)
```

Replace the frontmatter-rewrite block (the `fm["status"] = …` assignments through `File.write(chosen[:path], body)`) with a comment-preserving line edit of just the four claim fields:

```ruby
  stamp = {
    "status"     => "in_progress",
    "claimed_by" => session,
    "label"      => label.to_s,
    "claimed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
  }
  fm_text = chosen[:raw][/\A---\n(.*?)\n---/m, 1]
  new_fm = fm_text.dup
  stamp.each do |key, val|
    if new_fm =~ /^#{Regexp.escape(key)}:.*$/
      new_fm = new_fm.sub(/^#{Regexp.escape(key)}:.*$/, "#{key}: #{val}")
    else
      new_fm = "#{new_fm}\n#{key}: #{val}"
    end
  end
  body = chosen[:raw].sub(/\A---\n.*?\n---/m, "---\n#{new_fm}\n---")
  if body == chosen[:raw]
    warn "ag-claim: could not rewrite frontmatter for #{chosen[:path]}"
    exit 1
  end
  File.write(chosen[:path], body)
  puts chosen[:path]
```

(This edits existing lines in place — preserving comments, blank lines, and key order — and appends any of the four keys that were missing. `status` and `claimed_by` are always present in the template; `label`/`claimed_at` likewise.)

- [ ] **Step 4: ag-dependents — guard**

In `bin/ag-dependents`, after the `abort "usage…"` line, add:

```ruby
abort "ag-dependents: no such specs dir: #{specs_dir}" unless File.directory?(specs_dir)
```

- [ ] **Step 5: Run both suites to verify pass**

Run: `ruby dev/test-ag-claim.rb && ruby dev/test-ag-dependents.rb`
Expected: `ALL PASS` twice.

- [ ] **Step 6: Commit**

```bash
git add bin/ag-claim bin/ag-dependents dev/test-ag-claim.rb dev/test-ag-dependents.rb
git commit -m "ag-claim: preserve frontmatter comments/order on stamp; friendly missing-dir errors in both helpers"
```

## Task 8: Agents — inherit the model, isolate the builder, give memory

**Files:**

- Modify: `agents/ag-builder.md`, `agents/ag-planner.md`, `agents/ag-reviewer.md`

- [ ] **Step 1: Model inherit on all three**

In each of `agents/ag-builder.md`, `agents/ag-planner.md`, `agents/ag-reviewer.md`, change `model: opus` to `model: inherit` (the documented default; stops pinning the most expensive model with no per-project control — projects that want a specific model set it in a `.claude/agents/` override, see Task 12).

- [ ] **Step 2: Worktree isolation + memory on the builder**

In `agents/ag-builder.md` frontmatter, after `model: inherit` add:

```yaml
isolation: worktree
memory: project
```

In the "How you work" section, change the first bullet from prose about "use an isolated worktree if other agents may be working in parallel" to: "You run in your own **git worktree** (`isolation: worktree`), so your work never collides with other agents — implement freely on a short-lived branch there, never directly on a protected branch (see `protected_branches` in `.agentile/gates.json`)." Add a note: "If `.agentile/build.md` delegates to the `worktree-workflow` skill, that skill owns worktree creation — do not nest a second worktree; follow the playbook."

- [ ] **Step 3: Memory on the reviewer**

In `agents/ag-reviewer.md` frontmatter, after `model: inherit` add `memory: project` (so recurring review findings and codebase patterns accumulate across sessions — the methodology's "the system gets smarter").

- [ ] **Step 4: Verify frontmatter parses**

Run: `for f in agents/*.md; do ruby -ryaml -e 'YAML.safe_load(File.read(ARGV[0])[/\A---\n(.*?)\n---/m,1])' "$f" && echo "$f ok"; done`
Expected: three `ok` lines.

- [ ] **Step 5: Commit**

```bash
git add agents/
git commit -m "Agents: model inherit (was pinned opus); ag-builder isolation: worktree; project memory on builder+reviewer"
```

## Task 9: Skill invocation control — disable-model-invocation + named arguments

**Files:**

- Modify: `skills/ag-init/SKILL.md`, `skills/ag-abandon/SKILL.md`, `skills/ag-prioritise/SKILL.md`, `skills/ag-plan/SKILL.md`, `skills/ag-spec/SKILL.md`

- [ ] **Step 1: Gate the side-effectful skills**

Add `disable-model-invocation: true` to the frontmatter of `skills/ag-init/SKILL.md`, `skills/ag-abandon/SKILL.md`, and `skills/ag-prioritise/SKILL.md` (these write/move/mass-rename files; their trigger phrases — e.g. "kill this work item" — are conversationally common, so they should run only when the user types the command). Do NOT add it to ag-capture/ag-inbox/ag-wip/ag-shape/ag-next/ag-loop — auto-invocation is the point there.

Note in each: this also excludes the skill from subagent `skills:` preloading (a documented side effect), which is fine — none of these three is preloaded.

- [ ] **Step 2: Named argument for slug/spec-taking skills**

To the frontmatter of `skills/ag-abandon/SKILL.md` add `arguments: [slug]`; in its body, where it reads `$ARGUMENTS` for the target, also accept `$slug` (state: "The target is `$slug` (or `$ARGUMENTS`)"). Do the same for `skills/ag-plan/SKILL.md` and `skills/ag-spec/SKILL.md` with `arguments: [spec]` and `$spec`. Keep `$ARGUMENTS` working as the fallback so existing usage is unaffected.

- [ ] **Step 3: Verify frontmatter parses**

Run: `for f in skills/ag-init/SKILL.md skills/ag-abandon/SKILL.md skills/ag-prioritise/SKILL.md skills/ag-plan/SKILL.md skills/ag-spec/SKILL.md; do ruby -ryaml -e 'YAML.safe_load(File.read(ARGV[0])[/\A---\n(.*?)\n---/m,1])' "$f" && echo "$f ok"; done`
Expected: five `ok` lines.

- [ ] **Step 4: Commit**

```bash
git add skills/
git commit -m "Skills: disable-model-invocation on init/abandon/prioritise; named arguments for abandon/plan/spec"
```

## Task 10: Bootstrap A — the project brief artefact + /ag-init interview

**Files:**

- Create: `templates/agentile/brief-template.md`
- Modify: `skills/ag-init/SKILL.md`
- Modify: `templates/CLAUDE.agentile-section.md`

- [ ] **Step 1: Create the brief template**

Write `templates/agentile/brief-template.md`:

```markdown
# Project Brief — <project name>

The living context the loop steers by. `/ag-shape`, `/ag-spec`, `/ag-prioritise`,
and the `ag-planner` read this; Business Value in triage is scored against the
**prioritised outcomes** below. Keep it short (it loads into context) and update
it as the project learns — `/ag-retro` treats it as an update target.

## Who it's for

<The users / customer. Who feels the pain this project removes.>

## The outcome that matters first

<The single most important outcome right now, stated observably. This is the
yardstick for "high business value".>

## Prioritised outcomes

1. <outcome>
2. <outcome>
3. <outcome>

## Constraints

<Stack, platform, budget, timeline, compliance — the fixed walls the work lives within.>

## Non-goals

<What this project explicitly will NOT do, so scope can't creep into it.>

## What "shipped v1" looks like

<A concrete description of the first releasable slice.>
```

- [ ] **Step 2: ag-init — scaffold the brief in the file list**

In `skills/ag-init/SKILL.md` Step 4's file list, after the `<dir>/inbox.md` line add:

```markdown
- `<dir>/brief.md` (from `templates/agentile/brief-template.md`) — only if it does not exist; populated by the interview in Step 2a below.
```

- [ ] **Step 3: ag-init — add the fresh-project interview**

Add a new Step 2a immediately after Step 2 (Confirm setup choices):

```markdown
## Step 2a — Project brief (fresh projects)

Detect a fresh project: no `CLAUDE.md` of substance (absent, or only the Agentile
section) AND a near-empty repo (no significant source tree). If it looks
established, skip this step — the brief is optional for existing code, and
`/ag-retro` can seed it later.

For a fresh project, offer a short interview (decline-able — accept defaults and
leave the brief a template to fill in later). Ask, a couple at a time
(`AskUserQuestion` where discrete): who is this for; the one outcome that matters
first; the next two or three outcomes; hard constraints (stack, platform,
timeline); explicit non-goals; what "shipped v1" looks like. Write the answers
into `<dir>/brief.md` from `templates/agentile/brief-template.md`, replacing every
`<…>` placeholder. If a stack decision emerges, offer to capture it as
`docs/adr/0001-…` from the ADR template.

The brief is what makes triage real: without it, `/ag-shape` and `/ag-prioritise`
score Business Value against nothing. With it, they score against the brief's
prioritised outcomes.
```

- [ ] **Step 4: ag-init — point CLAUDE.md at the brief, gitignore the lock, reframe the hooks question**

In Step 5 (Standing context), add: "Ensure the appended Agentile section imports the brief so it loads every session — confirm the line `@docs/agentile/brief.md` (adjust to the configured Agentile directory) is present in the section (it ships in the template)."

In Step 4, after creating the specs tree, add: "Add `**/specs/.pull.lock` to the project's `.gitignore` (create `.gitignore` if absent; skip if the entry is already there) — the claim lock is a runtime file, not source."

In Step 2's "Enable hooks?" bullet, replace the question framing with: "**Configure gate commands now?** — the format/test/lint/build/deploy commands for `.agentile/gates.json`. The plugin's hooks are active whenever the plugin is enabled; they simply no-op until these commands are filled in, so this is about *enabling the gates*, not the hooks themselves." Update Step 6 (Hooks) to match: the hooks register automatically with the plugin; there is no per-project enable/disable, only whether `gates.json` has commands.

- [ ] **Step 5: CLAUDE template — import the brief**

In `templates/CLAUDE.agentile-section.md`, under "### Where things live", add a bullet before the Inbox bullet:

```markdown
- **Brief** (`docs/agentile/brief.md`) — the living project context: who it's for, the prioritised outcomes, constraints, non-goals. Business Value in triage is scored against it. Imported below so it loads every session.
```

At the end of the section (after the Rules list), add:

```markdown
@docs/agentile/brief.md
```

(If the configured Agentile directory differs from `docs/agentile/`, `/ag-init` rewrites this path to match.)

- [ ] **Step 6: Commit**

```bash
git add templates/agentile/brief-template.md skills/ag-init/SKILL.md templates/CLAUDE.agentile-section.md
git commit -m "Bootstrap: project brief artefact + /ag-init interview; import brief into CLAUDE.md; gitignore the lock; reframe the gates question"
```

## Task 11: Bootstrap B — consumers read the brief

**Files:**

- Modify: `skills/ag-shape/SKILL.md`, `skills/ag-spec/SKILL.md`, `skills/ag-prioritise/SKILL.md`, `skills/ag-retro/SKILL.md`
- Modify: `agents/ag-planner.md`
- Modify: `templates/agentile/config.md`

- [ ] **Step 1: ag-shape reads the brief**

In `skills/ag-shape/SKILL.md` Step 1, add a bullet: "Read `<dir>/brief.md` if present — the project's prioritised outcomes, users, and constraints. Score Business Value in the triage against the brief's outcomes, and let it inform the shaping questions." (Resolve `<dir>` as the already-established Agentile directory.)

- [ ] **Step 2: ag-spec reads the brief**

In `skills/ag-spec/SKILL.md` step 2, append to the read list: "and `<dir>/brief.md` if present (for the project's outcomes and constraints, so the triage self-check has a reference)."

- [ ] **Step 3: ag-prioritise reads the brief**

In `skills/ag-prioritise/SKILL.md` Step 1, add: "Read `<dir>/brief.md` if present — rank Business Value against its prioritised outcomes rather than gut feel."

- [ ] **Step 4: ag-planner reads the brief**

In `agents/ag-planner.md` "What to read first", add a bullet: "`docs/agentile/brief.md` if present — the project's outcomes, constraints, and non-goals, so the plan serves the actual goal and respects the walls."

- [ ] **Step 5: config.md triage references the brief**

In `templates/agentile/config.md`, in the "### Scoring guidance" section, change the Business Value line "Score High / Medium / Low against current priorities, not gut feel." to "Score High / Medium / Low against the project brief's prioritised outcomes (`brief.md`), not gut feel. No brief yet? Run `/ag-init`'s interview (or write one) — otherwise this score is guesswork."

- [ ] **Step 6: ag-retro keeps the brief living**

In `skills/ag-retro/SKILL.md` Step 3 (Encode the lessons), add a bullet: "A **`brief.md`** update when the project's outcomes, constraints, or non-goals have shifted — keep the brief living rather than a launch document."

- [ ] **Step 7: Commit**

```bash
git add skills/ag-shape/SKILL.md skills/ag-spec/SKILL.md skills/ag-prioritise/SKILL.md skills/ag-retro/SKILL.md agents/ag-planner.md templates/agentile/config.md
git commit -m "Bootstrap: shape/spec/prioritise/planner read the brief; triage scores against it; retro keeps it living"
```

## Task 12: Docs — agent overrides, worktree claim gap, loop reality, rules-file option

**Files:**

- Modify: `README.md`, `skills/ag-customise/SKILL.md`

- [ ] **Step 1: README — document the native agent-override path**

In `README.md`, in "## Agents (the "hats")", after the agent list add:

```markdown
The plugin ships these three at the lowest precedence, so you can **override any
of them per project** without forking the plugin: create `.claude/agents/ag-builder.md`
(or `ag-planner`/`ag-reviewer`) and Claude Code uses yours instead — change the
model, tools, effort, or prompt. User-level `~/.claude/agents/` works the same
across projects. The methodology core stays fixed; the agent definitions are
yours to tune.
```

- [ ] **Step 2: README — worktree claim gap**

In the "### Concurrent loops" section, after the per-machine-lock paragraph (added in Plan 1), add:

```markdown
One sharp edge: the claim lock lives in the specs directory, so it only
serialises loops that **share one checkout**. Two loops in two different git
worktrees each have their own copy of the backlog and can claim the same spec.
Keep the **backlog in the main checkout** — claim and prioritise there; send
*builders* to worktrees (the `ag-builder` agent already isolates itself). Don't
run `/ag-next` or `/ag-loop` from inside a builder's worktree.
```

- [ ] **Step 3: README — soften the turn-based claim + unattended caveat**

In "### Running the loop", the "Why two commands…" paragraph asserts "Claude Code is turn-based — there is no always-on process". Soften to: "Claude Code's loop primitive re-runs a command rather than holding an always-on process". Add a short caveat paragraph:

```markdown
Running watch mode unattended has caveats — a watch loop is tied to the session
that started it and inherits that session's permission prompts, so it pauses at
the first tool call it isn't pre-authorised for. For long unattended runs, seed
`permissions.allow` (the `gates.json` commands are the obvious allowlist) and
consult Claude Code's own loop/scheduling docs for current session-lifetime and
expiry behaviour rather than assuming a loop runs forever.
```

(Note: deliberately no specific expiry figure — that fact could not be verified.)

- [ ] **Step 4: README — rules-file option for the standing section**

In "## Install (in a project)", step 2 mentions the `CLAUDE.md` standing-context section. Add a sentence: "If you prefer to keep your root `CLAUDE.md` lean, the Agentile section can instead live in `.claude/rules/agentile.md` — `/ag-init` offers this; the content is identical, just independently updatable."

(Pair with: in `skills/ag-init/SKILL.md` Step 5, add a one-line option — "Offer to write the section to `.claude/rules/agentile.md` instead of appending to `CLAUDE.md`, for users who keep `CLAUDE.md` short." Keep the default as appending to `CLAUDE.md`.)

- [ ] **Step 5: ag-customise — offer the agent-override path**

In `skills/ag-customise/SKILL.md`, where it describes what can be customised, add: "For the build and verify stages you can also **override the agent itself** — `/ag-customise` offers to scaffold `.claude/agents/ag-builder.md` (or `ag-reviewer.md`) seeded from the plugin's definition, which takes precedence over the bundled agent. Use this to change an agent's model, tools, or prompt; use a `.agentile/<stage>.md` playbook to change how the *stage* runs around the agent."

- [ ] **Step 6: Commit**

```bash
git add README.md skills/ag-customise/SKILL.md skills/ag-init/SKILL.md
git commit -m "Docs: native agent-override path, worktree claim gap, hedged unattended-loop caveat, rules-file option"
```

## Task 13: Enhancements — statusline, retro fork, inbox fast-path

**Files:**

- Create: `.claude-plugin/settings.json` (or `settings.json` at plugin root per docs — verify location)
- Modify: `skills/ag-retro/SKILL.md`, `skills/ag-inbox/SKILL.md`

- [ ] **Step 1: Subagent statusline**

Create a plugin `settings.json` (place it where the plugin docs specify the plugin settings file lives — repo root `settings.json` unless the manifest expects `.claude-plugin/settings.json`; check `plugin.json`/docs and use the documented location). Content:

```json
{
  "subagentStatusLine": "echo \"agentile · ${CLAUDE_AGENT_NAME:-agent}\""
}
```

If the exact substitution token for the running subagent's name is not documented/available, fall back to a static line `"echo agentile\""` rather than inventing a variable. Keep this minimal — it is a nicety, not load-bearing. If the plugin settings location or `subagentStatusLine` shape can't be confirmed, report DONE_WITH_CONCERNS and skip the file rather than ship a guess.

- [ ] **Step 2: ag-retro runs forked**

In `skills/ag-retro/SKILL.md` frontmatter, add `context: fork` and `agent: general-purpose` (the retro reads heavy git history; forking keeps that out of the main context, matching its own "run heavy log commands so only your summary lands in context" instruction). Verify this composes with the existing playbook preamble — the fork wraps the whole skill run.

- [ ] **Step 3: ag-inbox dynamic fast-path**

In `skills/ag-inbox/SKILL.md`, add a dynamic-context injection for the common default-path case so the stubs arrive pre-read. After the frontmatter, before the steps, add:

```markdown
Current inbox (default path; the steps below resolve the real path for non-default layouts):

!`cat docs/agentile/inbox.md 2>/dev/null || echo "(no inbox at docs/agentile/inbox.md — resolve the configured Agentile directory)"`
```

(Keep the existing steps — they handle the configurable path; this is only a zero-round-trip fast path for the default layout, and degrades to a note when the path differs.)

- [ ] **Step 4: Verify**

Run: `ruby -rjson -e 'JSON.parse(File.read("settings.json")) rescue JSON.parse(File.read(".claude-plugin/settings.json")); puts "settings ok"'` (whichever path was used). Confirm ag-retro and ag-inbox frontmatter still parse with the YAML check from earlier tasks.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Enhancements: subagent statusline, ag-retro runs forked, ag-inbox default-path fast-path"
```

## Task 14: Final sweep + verification

**Files:** none new — verification, fixes as found.

- [ ] **Step 1: Run every test suite**

Run: `ruby dev/test-ag-claim.rb && ruby dev/test-ag-dependents.rb && ruby hooks/test-gates.rb`
Expected: `ALL PASS` three times.

- [ ] **Step 2: Validate the plugin if the CLI is available**

Run: `claude plugin validate --strict . 2>/dev/null || echo "validate unavailable — skip"`
If it runs and reports errors, fix them. If unavailable, note it.

- [ ] **Step 3: Stale-reference and consistency greps**

Run and fix any contradicting hits (exclude `docs/reviews/`, `docs/plans/`, historical `docs/agentile-*.md` bodies):

```bash
grep -rn "\.lal" hooks/ skills/ templates/ bin/ agents/ README.md
grep -rn "session-id\|stop_hook_active\|Agentile: this session's id" skills/ hooks/ README.md
grep -rn "cache/agentile/agentile" skills/
grep -rn "bin/ag-dev-link\|bin/ag-sync\|bin/test-ag" README.md skills/ dev/
grep -rn "model: opus" agents/
grep -rn '"version"' .claude-plugin/
grep -rn "MultiEdit" hooks/
```

`.lal` → zero. `session-id`/`stop_hook_active`/injected-id phrasing → zero in skills (hooks/test-gate may keep a `stop_hook_active` first-line allow — that's fine). cache-glob → zero. `bin/ag-dev-link` etc → only `dev/` paths. `model: opus` → zero. `"version"` in plugin.json → zero (marketplace metadata.version optional). `MultiEdit` → zero.

- [ ] **Step 4: Markdown house style on changed docs**

Confirm new/edited markdown: blank line after every heading, blank line before top-level lists, no `---` rules in prose. Check README, the new brief template, and CLAUDE template.

- [ ] **Step 5: Commit any sweep fixes**

```bash
git add -A
git commit -m "Plugin fixes: final consistency sweep"
```
