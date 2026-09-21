# Agentile plugin `store/agentile-projects` branch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Agentile Projects (the Rails app) the plugin's only backlog store: `bin/ag-store` becomes a thin HTTP client with the same subcommands and JSON output, the local and Airtable adapters are deleted, and every skill, template and doc describes the single store.

**Architecture:** `bin/ag-store` is one Ruby file (`Net::HTTP` + `json` + `yaml`, no gems) reading `url`/`project` from `.agentile/store.md` and the token from `AGENTILE_PROJECTS_TOKEN`; each subcommand maps 1:1 to a `/api/v1` endpoint from the design spec §5 and prints the API's JSON unchanged. Run ids are resolved inside the client (by spec + runner identity), so skills keep calling `checkpoint_open <slug> <reason>` and `run_event <event> --spec <slug> --runner <id>` exactly as they do today. Skills lose their store-mode branches (`--store`, `local` vs `airtable`, file moves, `.pull.lock`, `ag-lock` wrapping at init) and gain a one-paragraph brief-refresh preamble.

**Tech Stack:** Ruby 3.x standard library only (`net/http`, `json`, `yaml`, `fileutils`, `open3`, `socket` in tests). Claude Code plugin skills are Markdown.

**Spec:** `docs/superpowers/specs/2026-09-21-agentile-projects-design.md` — §3 (branch), §5 (client contract), §6 (plugin changes), §11 (cut-over). The Rails app is a separate plan (`2026-09-21-agentile-projects-app.md`); this plan assumes its API exists exactly as spec §5 describes.

## Global Constraints

- Branch is `store/agentile-projects`, cut from `main`; plugin version becomes **0.20.0** in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (the repo's Versioning rule: same commit as the change).
- `bin/ag-store` output contract is unchanged: **one JSON value on stdout**; errors to stderr with non-zero exit (1 = API/usage error, 2 = configuration/connectivity error). Skills parse stdout with a JSON parser, never scrape text.
- The API returns list/read payloads in **today's CLI key shape** (spec §5: "same JSON keys as today" for `spec_list`, `checkpoint_list`, etc.); the client passes them through unchanged. If the app returns a differently named key, the fix goes in the app, not in this client.
- `spec_read`/`outcome_read` return canonical markdown (a JSON string); `spec_create`/`outcome_create`/`inbox_shape` send markdown on stdin, `checkpoint_open`/`checkpoint_answer` send the ask/answer on stdin — exactly as today.
- Config: `.agentile/store.md` frontmatter is exactly `url:` and `project:`; `AGENTILE_PROJECTS_URL` (env) overrides `url`; `AGENTILE_PROJECTS_TOKEN` (env only, never a tracked file) authenticates. `--store` and `--airtable-*` flags are gone (`--store` prints an "obsolete" warning to stderr and is otherwise ignored).
- Runs belong to a spec (spec §4): `run_event`/`run_close` require `--spec <slug>`; a spec-less `started`/`idle`/`failed` event is no longer logged by `/ag-build` (the `AG_BUILD:` exit line still reports idle/failed).
- The `AG_BUILD:` exit contract in `skills/ag-build/SKILL.md` is unchanged verbatim; `bin/ag-run` still parses it.
- `plan.md`, the `SPEC.md` snapshot, findings and ADRs stay git-tracked at `<dir>/specs/<slug>/`; `docs/agentile/brief.md` is a read-only copy written by `ag-store brief_sync`; `runs.md`, `inbox.md`, `specs/done/`, `specs/abandoned/`, `.pull.lock` no longer exist.
- Deploy records move to `<dir>/deploys.md` (a repo file — a deploy is a per-repo release act tied to a git sha); the API has no deploy endpoint in this release.
- Every task ends with the plugin's own tests green: `ruby dev/test-ag-store-http.rb` (offline cases always run; online cases run when `AGENTILE_PROJECTS_URL` + `AGENTILE_PROJECTS_TOKEN` are set, else print `SKIP`), `ruby hooks/test-gates.rb`, `ruby dev/test-ag-run.rb`.
- Do not touch `~/projects/agentile_projects` (the app) from this plan.

---

## File map

| Path | Fate | Responsibility after this plan |
|---|---|---|
| `bin/ag-store` | rewrite | single-file HTTP client, all subcommands |
| `bin/ag-store-adapters/` (4 files) | delete | — |
| `bin/ag-claim`, `bin/ag-checkpoint`, `bin/ag-dependents` | delete | — |
| `bin/ag-run` | edit | hint text no longer names `ag-checkpoint` |
| `bin/ag-lock` | edit | comment no longer names `ag-claim` |
| `dev/test-ag-store-http.rb` | create | offline (fake server) + online tests for every subcommand |
| `dev/test-ag-store-local.rb`, `dev/test-ag-store-airtable.rb`, `dev/test-ag-claim.rb`, `dev/test-ag-checkpoint.rb`, `dev/test-ag-dependents.rb`, `dev/smoke-airtable.rb` | delete | — |
| `hooks/test-gate.rb` | edit | comments only |
| `templates/agentile/store.md` | rewrite | `url` + `project` template |
| `templates/agentile/deploys.md` | create | deploy log template |
| `templates/inbox.md`, `templates/agentile/runs.md`, `templates/stores/` | delete | — |
| `templates/agentile/config.md`, `ship.md`, `deploy.md`, `shape.md`, `spec-template.md`, `adr-template.md`, `brief-template.md`, `gates.json` | edit | remove file-layout / `ag-claim` wording |
| `templates/CLAUDE.agentile-section.md` | rewrite | single-store standing context |
| `templates/factory-worker.md` | edit | checkpoints are store records via `ag-store` |
| `skills/*/SKILL.md` (17 files), `agents/ag-planner.md` | edit | single store, brief preamble |
| `README.md`, `methodology.md`, `docs/agentile-workspaces-participants-and-stores.md`, `docs/agentile-factory.md`, `CHANGELOG.md` | edit | docs |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | edit | 0.20.0 |

---

### Task 1: Branch, set the interim scaffold aside, bump to 0.20.0

**Files:**
- Modify: `.claude-plugin/plugin.json:3`, `.claude-plugin/marketplace.json:14`
- Modify: `skills/ag-version/SKILL.md:52-58`
- Commit (already in working tree): `skills/ag-build/SKILL.md` ("Head every message with the slug" section)

**Interfaces:**
- Consumes: nothing.
- Produces: branch `store/agentile-projects` with version `0.20.0`; the pre-existing `skills/ag-build/SKILL.md` edit committed so later tasks build on it.

- [ ] **Step 1: Check the working tree and preserve the interim `/ag-init` scaffold**

The working tree holds an `/ag-init` scaffold from earlier today (`.agentile/`, `CLAUDE.md`, `docs/agentile/`, `docs/adr/`, a `.gitignore` line) written against the Airtable store this branch retires, plus `docs/webapp_brief.md` (Keith's brief text, leave it untouched) and a modification to `skills/ag-build/SKILL.md` (keep). We do **not** `git stash` — a stash is easy to forget and the scaffold is superseded, not in-progress work. Move it to a dated folder outside the repo instead, and restore the one tracked file it touched:

```bash
git status --short
ASIDE="$HOME/projects/agentile-aside-2026-09-21"
mkdir -p "$ASIDE"
mv .agentile "$ASIDE/agentile-dot"
mv CLAUDE.md "$ASIDE/CLAUDE.md"
mv docs/agentile "$ASIDE/docs-agentile"
mv docs/adr "$ASIDE/docs-adr"
cp .gitignore "$ASIDE/gitignore.with-pull-lock"
git restore .gitignore
git status --short
```

Expected `git status --short` afterwards: only ` M skills/ag-build/SKILL.md` and `?? docs/webapp_brief.md`.

- [ ] **Step 2: Create the branch and commit the pending ag-build edit**

```bash
git checkout -b store/agentile-projects main
git add skills/ag-build/SKILL.md
git commit -m "ag-build: head every message with the spec slug"
```

- [ ] **Step 3: Bump the version in both manifests**

`.claude-plugin/plugin.json` line 3: change `"version": "0.19.0",` to `"version": "0.20.0",`.

`.claude-plugin/marketplace.json` line 14: change `"version": "0.19.0",` to `"version": "0.20.0",`.

Verify they agree:

```bash
grep -n '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json
```

Expected: both print `0.20.0` (the marketplace `metadata.version` `0.1.0` on line 9 is the marketplace's own version and stays).

- [ ] **Step 4: Teach `/ag-version` to flag a pre-0.20 `store.md`**

In `skills/ag-version/SKILL.md`, replace step 4 (lines 52–58) with:

```markdown
4. Check for retired configuration in the current project:
   - If `.agentile/loop.md` exists, the project predates 0.13.0. Its keys moved:
     `pause_at_plan` → `human_checkpoint` on `.agentile/plan.md`,
     `pause_before_ship` → `human_checkpoint` on `.agentile/ship.md`,
     `verify_retry_limit` and `stop_on_gate_failure` → `.agentile/verify.md`;
     `max_iterations`, `on_empty` and `watch` have no replacement (scheduling
     belongs to the factory).
   - If `.agentile/store.md` has a `store:` key (`local` or `airtable`) instead
     of `url:` and `project:`, the project predates 0.20.0, when Agentile
     Projects became the only store. Run `/ag-init` to link it.
   Add a fourth line to the report for each that applies.
```

And in the report block (lines 63–68) add one line after the `retired:` line:

```
   store:     .agentile/store.md still selects a local/airtable store — run /ag-init to link this project to Agentile Projects
```

- [ ] **Step 5: Run the plugin tests that still apply, then commit**

```bash
ruby hooks/test-gates.rb
ruby dev/test-ag-run.rb
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json skills/ag-version/SKILL.md
git commit -m "Start 0.20.0: Agentile Projects becomes the only store"
```

Expected: both test scripts print `ALL PASS`.

---

### Task 2: Rewrite `bin/ag-store` as the HTTP client, with `dev/test-ag-store-http.rb`

**Files:**
- Rewrite: `bin/ag-store`
- Create: `dev/test-ag-store-http.rb`

**Interfaces:**
- Consumes: the API in spec §5 under `<url>/api/v1/projects/<project>/...` with `Authorization: Bearer <token>`; `GET /api/v1/me`.
- Produces: the CLI contract below. Every later task's skill text calls these signatures.

| Subcommand | Args | HTTP | stdout |
|---|---|---|---|
| `inbox_list` | `[--status open\|shaped\|dropped]` | `GET /inbox?status=` | array (pass-through) |
| `inbox_add <text>` | `[--title t] [--type k] [--serves slug]` | `POST /inbox {text,title,kind,serves}` | `true` |
| `inbox_drop <id>` | | `POST /inbox/:id/drop` | `true` |
| `inbox_assist <text>` | | `POST /inbox/assist {text}` | object (pass-through) |
| `inbox_shape <id>` | markdown on stdin | `POST /inbox/:id/shape` (text/markdown) | slug string |
| `spec_list` | `[--status s] [--pool active\|done\|abandoned]` | `GET /specs?status=&pool=` | array |
| `spec_read <slug>` | | `GET /specs/:slug.md` | markdown string |
| `spec_create <slug>` | markdown on stdin | `POST /specs` (text/markdown) | slug string |
| `spec_write <slug> --set k=v…` | | `PATCH /specs/:slug {k: v}` (`depends_on`,`tags`,`shaped_by` → arrays) | pass-through |
| `rank <slug>…` | | `PUT /specs/rank {slugs}` | pass-through |
| `claim <identity> [label] [wip] [--spec slug]` | | `POST /specs/claim {identity,label,wip,slug}` | the `result` string (slug or `WIP_FULL`…) |
| `release <slug>` / `ship <slug>` | | `POST /specs/:slug/release` / `/ship` | pass-through |
| `abandon <slug> --reason r` | `[--cascade "[a, b]"]` | `POST /specs/:slug/abandon {reason,cascade}` | pass-through |
| `promote <slug>` | `--dir d` | none (mkdir) | `"<dir>/specs/<slug>"` |
| `deps <slug>` / `dependents <slug>` | | `GET /specs/:slug/deps` / `/dependents` | array |
| `map` | | `GET /map` | object |
| `flow [<slug>]` | | `GET /flow` / `GET /flow/:slug` | array / object |
| `outcome_list [--status s]` | | `GET /outcomes?status=` | array |
| `outcome_read <slug>` | | `GET /outcomes/:slug.md` | markdown string |
| `outcome_create <slug>` | markdown on stdin | `POST /outcomes` (text/markdown) | slug string |
| `outcome_write <slug> --set k=v…` | | `PATCH /outcomes/:slug` | pass-through |
| `outcome_rank <slug>…` | | `PUT /outcomes/rank {slugs}` | pass-through |
| `outcome_achieve <slug>` / `outcome_abandon <slug> --reason r` | | `POST /outcomes/:slug/achieve` / `/abandon {reason}` | pass-through |
| `checkpoint_open <slug> <reason> --session s --by who` | ask on stdin | resolves the run, `POST /runs/:id/checkpoints {reason,asked_by,session_id,ask}` | checkpoint id |
| `checkpoint_list <slug>` | | `GET /specs/:slug/checkpoints` | array, oldest first |
| `checkpoint_open_count <slug>` | | same GET, counted client-side | integer |
| `checkpoint_answer <id> --by who` | answer on stdin | `POST /checkpoints/:id/answer {answer,by}` | id |
| `run_event <event> --spec slug --runner id [--detail d]` | | resolves/creates the run, `POST /runs/:id/events {event,detail}` | ISO8601 string |
| `run_list [--spec slug] [--status active\|closed]` | | `GET /runs?spec=&status=` | array of runs `{id,spec,runner_id,session_id,status,started_at,ended_at,last_event_at,detail}` |
| `run_close --spec slug --runner id [--detail d]` | | resolves the run, `POST /runs/:id/close {detail}` | pass-through |
| `brief_sync` | `--dir d` | `GET /brief` (markdown) → writes `<dir>/brief.md` | the path string |
| `whoami` | | `GET /me` | object `{user_id,name,email,projects}` |
| `doctor` | | `GET /doctor` | object |

Run resolution (shared by `checkpoint_open`, `run_event`, `run_close`): `GET /runs?spec=<slug>&status=active`, prefer the run whose `runner_id` equals the identity (`--runner`, else `AGENTILE_RUNNER_ID`, else `CLAUDE_SESSION_ID`), else the newest active run; `run_event` with no active run creates one via `POST /runs {spec, runner_id, session_id}` first. `claim` needs no run id on the command line: the app opens the run when it claims.

- [ ] **Step 1: Write the failing offline tests**

Create `dev/test-ag-store-http.rb`:

```ruby
# frozen_string_literal: true
# Tests for bin/ag-store, the Agentile Projects HTTP client.
#   Offline section: a fake API on 127.0.0.1 checks every subcommand's request
#   shape and stdout contract, with no app running.
#   Online section: runs only when AGENTILE_PROJECTS_URL and
#   AGENTILE_PROJECTS_TOKEN are set (and AGENTILE_PROJECTS_TEST_PROJECT names a
#   project the token can write to), exercising a real app end to end.
require "json"; require "open3"; require "socket"; require "tmpdir"; require "fileutils"

HELP = File.expand_path("../bin/ag-store", __dir__)

# ---------------------------------------------------------------- fake API --
class FakeApi
  attr_reader :requests, :routes
  def initialize
    @requests = []
    @routes = {}
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { loop { handle(@server.accept) } }
  end

  def port = @server.addr[1]
  def url = "http://127.0.0.1:#{port}"

  # route("GET", "/api/v1/projects/p/specs") { |req| [200, {...}] }
  def route(method, path, &blk) = @routes[[method, path]] = blk

  def handle(sock)
    line = sock.gets or return sock.close
    method, target = line.split(" ")
    path, query = target.split("?", 2)
    headers = {}
    while (h = sock.gets) && h != "\r\n"
      k, v = h.chomp.split(": ", 2)
      headers[k.downcase] = v
    end
    body = headers["content-length"] ? sock.read(headers["content-length"].to_i) : ""
    req = { method: method, path: path, query: query.to_s, headers: headers, body: body }
    @requests << req
    handler = @routes[[method, path]]
    status, payload = handler ? handler.call(req) : [404, { "error" => "not_found", "detail" => "no route #{method} #{path}" }]
    text = payload.is_a?(String) ? payload : JSON.generate(payload)
    ctype = payload.is_a?(String) ? "text/markdown" : "application/json"
    sock.write("HTTP/1.1 #{status} X\r\nContent-Type: #{ctype}\r\nContent-Length: #{text.bytesize}\r\nConnection: close\r\n\r\n#{text}")
  rescue StandardError => e
    warn "fake api: #{e.class}: #{e.message}"
  ensure
    sock.close
  end

  def close = @server.close
end

def run_store(*args, env: {}, stdin: nil, chdir: Dir.pwd)
  out, err, st = Open3.capture3(env, "ruby", HELP, *args, stdin_data: stdin.to_s, chdir: chdir)
  [out, err, st]
end

def store!(*args, **kw)
  out, err, st = run_store(*args, **kw)
  raise "ag-store #{args.first} failed (#{st.exitstatus}): #{err}" unless st.success?
  JSON.parse(out)
end

def with_project(url)
  Dir.mktmpdir do |root|
    FileUtils.mkdir_p(File.join(root, ".agentile"))
    File.write(File.join(root, ".agentile", "store.md"), "---\nurl: #{url}\nproject: p\n---\n")
    FileUtils.mkdir_p(File.join(root, "docs", "agentile"))
    yield root
  end
end

api = FakeApi.new
ENV_OK = { "AGENTILE_PROJECTS_TOKEN" => "tok_test", "AGENTILE_RUNNER_ID" => "runner-1", "CLAUDE_SESSION_ID" => "sess-1" }.freeze
P = "/api/v1/projects/p"

# 1. config: missing token exits 2 with a message; missing store.md exits 2
with_project(api.url) do |root|
  _o, err, st = run_store("inbox_list", env: { "AGENTILE_PROJECTS_TOKEN" => "" }, chdir: root)
  raise "missing token should exit 2: #{st.exitstatus} #{err}" unless st.exitstatus == 2 && err.include?("AGENTILE_PROJECTS_TOKEN")
end
Dir.mktmpdir do |root|
  _o, err, st = run_store("inbox_list", env: ENV_OK, chdir: root)
  raise "missing store.md should exit 2: #{st.exitstatus} #{err}" unless st.exitstatus == 2 && err.include?("/ag-init")
end

# 2. connectivity: unreachable url exits 2 and names the url
with_project("http://127.0.0.1:1") do |root|
  _o, err, st = run_store("inbox_list", env: ENV_OK, chdir: root)
  raise "unreachable should exit 2: #{st.exitstatus} #{err}" unless st.exitstatus == 2 && err.include?("127.0.0.1:1")
end

# 3. auth header + pass-through: inbox_list sends the bearer token, prints the API array verbatim
api.route("GET", "#{P}/inbox") { [200, [{ "id" => 7, "title" => "T", "text" => "x", "type" => "feature" }]] }
with_project(api.url) do |root|
  out = store!("inbox_list", env: ENV_OK, chdir: root)
  raise "inbox_list pass-through: #{out.inspect}" unless out == [{ "id" => 7, "title" => "T", "text" => "x", "type" => "feature" }]
  req = api.requests.last
  raise "bearer header: #{req[:headers].inspect}" unless req[:headers]["authorization"] == "Bearer tok_test"
end

# 4. AGENTILE_PROJECTS_URL overrides store.md's url
with_project("http://127.0.0.1:1") do |root|
  out = store!("inbox_list", env: ENV_OK.merge("AGENTILE_PROJECTS_URL" => api.url), chdir: root)
  raise "env url override: #{out.inspect}" unless out.is_a?(Array)
end

# 5. API error: non-2xx prints detail to stderr and exits 1
api.route("POST", "#{P}/inbox/9/drop") { [404, { "error" => "not_found", "detail" => "no inbox item 9" }] }
with_project(api.url) do |root|
  _o, err, st = run_store("inbox_drop", "9", env: ENV_OK, chdir: root)
  raise "api error should exit 1: #{st.exitstatus} #{err}" unless st.exitstatus == 1 && err.include?("no inbox item 9")
end

# 6. inbox_add maps --type to kind and --serves to serves; prints true
api.route("POST", "#{P}/inbox") { |r| b = JSON.parse(r[:body]); [201, { "id" => 1, "title" => b["title"], "kind" => b["kind"] }] }
with_project(api.url) do |root|
  out = store!("inbox_add", "Rate-limit the login endpoint", "--title", "Login rate limit", "--type", "chore", "--serves", "identity", env: ENV_OK, chdir: root)
  raise "inbox_add should print true: #{out.inspect}" unless out == true
  body = JSON.parse(api.requests.last[:body])
  raise "inbox_add body: #{body.inspect}" unless body == { "text" => "Rate-limit the login endpoint", "title" => "Login rate limit", "kind" => "chore", "serves" => "identity" }
end

# 7. inbox_assist passes the text; inbox_shape posts markdown from stdin with text/markdown
api.route("POST", "#{P}/inbox/assist") { |r| [200, { "title" => "T", "text" => JSON.parse(r[:body])["text"], "kind" => "feature" }] }
api.route("POST", "#{P}/inbox/3/shape") { |r| [201, "my-slug"] } # app returns the slug as JSON string; fake returns text — client must accept both
with_project(api.url) do |root|
  out = store!("inbox_assist", "make login faster", env: ENV_OK, chdir: root)
  raise "inbox_assist: #{out.inspect}" unless out["text"] == "make login faster"
  md = "---\ntitle: My slug\nslug: my-slug\nstatus: ready\n---\n\n# My slug\n"
  run_store("inbox_shape", "3", env: ENV_OK, stdin: md, chdir: root)
  req = api.requests.last
  raise "inbox_shape body/type: #{req.inspect}" unless req[:body] == md && req[:headers]["content-type"].start_with?("text/markdown")
end

# 8. spec_read returns the markdown body as a JSON string; spec_create posts markdown
api.route("GET", "#{P}/specs/my-slug.md") { [200, "---\nslug: my-slug\n---\n\n# My slug\n"] }
api.route("POST", "#{P}/specs") { |r| [201, "my-slug"] }
with_project(api.url) do |root|
  out = store!("spec_read", "my-slug", env: ENV_OK, chdir: root)
  raise "spec_read: #{out.inspect}" unless out.start_with?("---\nslug: my-slug")
  out = store!("spec_create", "my-slug", env: ENV_OK, stdin: "---\nslug: my-slug\n---\n# x\n", chdir: root)
  raise "spec_create: #{out.inspect}" unless out == "my-slug"
  raise "spec_create content-type" unless api.requests.last[:headers]["content-type"].start_with?("text/markdown")
end

# 9. spec_list forwards status/pool; spec_write turns bracketed lists into arrays
api.route("GET", "#{P}/specs") { |r| [200, [{ "slug" => "a", "prefix" => 1, "status" => "ready", "q" => r[:query] }]] }
api.route("PATCH", "#{P}/specs/a") { |r| [200, JSON.parse(r[:body])] }
with_project(api.url) do |root|
  out = store!("spec_list", "--status", "ready", "--pool", "active", env: ENV_OK, chdir: root)
  raise "spec_list query: #{out.inspect}" unless out[0]["q"].include?("status=ready") && out[0]["q"].include?("pool=active")
  out = store!("spec_write", "a", "--set", "depends_on=[b, c]", "--set", "route=spike", "--set", "tags=[]", env: ENV_OK, chdir: root)
  raise "spec_write lists: #{out.inspect}" unless out == { "depends_on" => %w[b c], "route" => "spike", "tags" => [] }
end

# 10. rank / outcome_rank send {slugs: [...]} with PUT
api.route("PUT", "#{P}/specs/rank") { |r| [200, JSON.parse(r[:body])["slugs"]] }
api.route("PUT", "#{P}/outcomes/rank") { |r| [200, JSON.parse(r[:body])["slugs"]] }
with_project(api.url) do |root|
  raise "rank" unless store!("rank", "b", "a", env: ENV_OK, chdir: root) == %w[b a]
  raise "outcome_rank" unless store!("outcome_rank", "o2", "o1", env: ENV_OK, chdir: root) == %w[o2 o1]
end

# 11. claim posts identity/label/wip/slug and prints only the result string (slug or code)
api.route("POST", "#{P}/specs/claim") { |r| b = JSON.parse(r[:body]); [200, { "result" => (b["slug"] || "WIP_FULL"), "run_id" => 42 }] }
with_project(api.url) do |root|
  raise "claim slug" unless store!("claim", "runner-1", "my label", "2", "--spec", "a", env: ENV_OK, chdir: root) == "a"
  body = JSON.parse(api.requests.last[:body])
  raise "claim body: #{body.inspect}" unless body == { "identity" => "runner-1", "label" => "my label", "wip" => 2, "slug" => "a" }
  raise "claim code" unless store!("claim", "runner-1", "", "1", env: ENV_OK, chdir: root) == "WIP_FULL"
  raise "claim omits slug when absent" if JSON.parse(api.requests.last[:body]).key?("slug")
end

# 12. release/ship/abandon (with --reason and optional --cascade)
api.route("POST", "#{P}/specs/a/release") { [200, true] }
api.route("POST", "#{P}/specs/a/ship") { [200, "a"] }
api.route("POST", "#{P}/specs/a/abandon") { |r| [200, JSON.parse(r[:body])] }
with_project(api.url) do |root|
  raise "release" unless store!("release", "a", env: ENV_OK, chdir: root) == true
  raise "ship" unless store!("ship", "a", env: ENV_OK, chdir: root) == "a"
  out = store!("abandon", "a", "--reason", "spike said no", "--cascade", "[b, c]", env: ENV_OK, chdir: root)
  raise "abandon: #{out.inspect}" unless out == { "reason" => "spike said no", "cascade" => %w[b c] }
end

# 13. promote makes the spec directory under --dir and prints its path; no HTTP call
with_project(api.url) do |root|
  before = api.requests.size
  out = store!("promote", "a", "--dir", "docs/agentile", env: ENV_OK, chdir: root)
  raise "promote path: #{out.inspect}" unless out == "docs/agentile/specs/a"
  raise "promote should mkdir" unless File.directory?(File.join(root, "docs/agentile/specs/a"))
  raise "promote made a request" unless api.requests.size == before
end

# 14. deps / dependents / map / flow pass through
api.route("GET", "#{P}/specs/a/deps") { [200, ["b"]] }
api.route("GET", "#{P}/specs/a/dependents") { [200, %w[c d]] }
api.route("GET", "#{P}/map") { [200, { "outcomes" => [], "unlinked" => {}, "orphaned" => {}, "tags" => {} }] }
api.route("GET", "#{P}/flow") { [200, [{ "slug" => "a" }]] }
api.route("GET", "#{P}/flow/a") { [200, { "slug" => "a", "cycle_seconds" => 10 }] }
with_project(api.url) do |root|
  raise "deps" unless store!("deps", "a", env: ENV_OK, chdir: root) == ["b"]
  raise "dependents" unless store!("dependents", "a", env: ENV_OK, chdir: root) == %w[c d]
  raise "map" unless store!("map", env: ENV_OK, chdir: root).key?("outcomes")
  raise "flow all" unless store!("flow", env: ENV_OK, chdir: root) == [{ "slug" => "a" }]
  raise "flow one" unless store!("flow", "a", env: ENV_OK, chdir: root)["cycle_seconds"] == 10
end

# 15. outcomes: list/read/create/write/achieve/abandon
api.route("GET", "#{P}/outcomes") { |r| [200, [{ "slug" => "o1", "status" => "open", "q" => r[:query] }]] }
api.route("GET", "#{P}/outcomes/o1.md") { [200, "---\nslug: o1\n---\n\n# O1\n"] }
api.route("POST", "#{P}/outcomes") { [201, "o1"] }
api.route("PATCH", "#{P}/outcomes/o1") { |r| [200, JSON.parse(r[:body])] }
api.route("POST", "#{P}/outcomes/o1/achieve") { [200, "o1"] }
api.route("POST", "#{P}/outcomes/o1/abandon") { |r| [200, JSON.parse(r[:body])] }
with_project(api.url) do |root|
  raise "outcome_list" unless store!("outcome_list", "--status", "open", env: ENV_OK, chdir: root)[0]["q"] == "status=open"
  raise "outcome_read" unless store!("outcome_read", "o1", env: ENV_OK, chdir: root).start_with?("---\nslug: o1")
  raise "outcome_create" unless store!("outcome_create", "o1", env: ENV_OK, stdin: "---\nslug: o1\n---\n", chdir: root) == "o1"
  raise "outcome_write" unless store!("outcome_write", "o1", "--set", "rank=2", env: ENV_OK, chdir: root) == { "rank" => "2" }
  raise "outcome_achieve" unless store!("outcome_achieve", "o1", env: ENV_OK, chdir: root) == "o1"
  raise "outcome_abandon" unless store!("outcome_abandon", "o1", "--reason", "stop rule fired", env: ENV_OK, chdir: root) == { "reason" => "stop rule fired" }
end

# 16. run resolution: run_event with no active run creates one, then posts the event;
#     checkpoint_open resolves the run by (spec, runner) and posts the ask from stdin
runs = []
api.route("GET", "#{P}/runs") { |r| q = r[:query]; [200, runs.select { |x| (!q.include?("spec=") || q.include?("spec=#{x['spec']}")) && (!q.include?("status=active") || x["status"] == "active") }] }
api.route("POST", "#{P}/runs") { |r| b = JSON.parse(r[:body]); run = { "id" => runs.size + 1, "spec" => b["spec"], "runner_id" => b["runner_id"], "session_id" => b["session_id"], "status" => "active", "started_at" => "2026-09-21T00:00:00Z" }; runs << run; [201, run] }
api.route("POST", "#{P}/runs/1/events") { |r| [201, "2026-09-21T00:00:01Z"] }
api.route("POST", "#{P}/runs/1/checkpoints") { |r| b = JSON.parse(r[:body]); [201, { "id" => 500, "seq" => 1, "ref" => "a #001 #{b['reason']}", "echo" => b }] }
api.route("POST", "#{P}/runs/1/close") { |r| [200, true] }
with_project(api.url) do |root|
  out = store!("run_event", "claimed", "--spec", "a", "--runner", "runner-1", "--detail", "hi", env: ENV_OK, chdir: root)
  raise "run_event stamp: #{out.inspect}" unless out == "2026-09-21T00:00:01Z"
  created = api.requests.find { |r| r[:method] == "POST" && r[:path] == "#{P}/runs" }
  raise "run_event should create the run first" unless created && JSON.parse(created[:body]) == { "spec" => "a", "runner_id" => "runner-1", "session_id" => "sess-1" }
  ev = api.requests.last
  raise "event body: #{ev.inspect}" unless JSON.parse(ev[:body]) == { "event" => "claimed", "detail" => "hi" }

  out = store!("checkpoint_open", "a", "ship_approval", "--session", "sess-1", "--by", "ship", env: ENV_OK, stdin: "Approve to ship a?", chdir: root)
  raise "checkpoint_open id: #{out.inspect}" unless out == 500
  echo = JSON.parse(api.requests.last[:body])
  raise "checkpoint body: #{echo.inspect}" unless echo == { "reason" => "ship_approval", "asked_by" => "ship", "session_id" => "sess-1", "ask" => "Approve to ship a?" }

  _o, err, st = run_store("checkpoint_open", "a", "not_a_reason", env: ENV_OK, stdin: "x", chdir: root)
  raise "bad reason should exit 1: #{err}" unless st.exitstatus == 1 && err.include?("unknown checkpoint reason")

  _o, err, st = run_store("run_event", "started", env: ENV_OK, chdir: root)
  raise "run_event without --spec should exit 1: #{err}" unless st.exitstatus == 1 && err.include?("--spec")

  raise "run_close" unless store!("run_close", "--spec", "a", "--runner", "runner-1", "--detail", "done", env: ENV_OK, chdir: root) == true
  raise "run_list" unless store!("run_list", "--spec", "a", "--status", "active", env: ENV_OK, chdir: root).first["id"] == 1
end

# 17. checkpoint_list / checkpoint_open_count / checkpoint_answer
api.route("GET", "#{P}/specs/a/checkpoints") { [200, [{ "id" => 1, "seq" => 1, "status" => "answered" }, { "id" => 2, "seq" => 2, "status" => "open" }]] }
api.route("POST", "#{P}/checkpoints/2/answer") { |r| [200, JSON.parse(r[:body])] }
with_project(api.url) do |root|
  raise "checkpoint_list" unless store!("checkpoint_list", "a", env: ENV_OK, chdir: root).map { |c| c["seq"] } == [1, 2]
  raise "open_count" unless store!("checkpoint_open_count", "a", env: ENV_OK, chdir: root) == 1
  out = store!("checkpoint_answer", "2", "--by", "keith", env: ENV_OK, stdin: "approved", chdir: root)
  raise "checkpoint_answer: #{out.inspect}" unless out == { "answer" => "approved", "by" => "keith" }
end

# 18. brief_sync writes <dir>/brief.md from GET /brief and prints the path
api.route("GET", "#{P}/brief") { [200, "# Brief\n\n## Prioritised outcomes\n\n1. **O1** (`o1`)\n"] }
with_project(api.url) do |root|
  out = store!("brief_sync", "--dir", "docs/agentile", env: ENV_OK, chdir: root)
  raise "brief_sync path: #{out.inspect}" unless out == "docs/agentile/brief.md"
  raise "brief_sync content" unless File.read(File.join(root, "docs/agentile/brief.md")).include?("Prioritised outcomes")
end

# 19. whoami hits /me (unscoped); doctor hits the project doctor
api.route("GET", "/api/v1/me") { [200, { "user_id" => 1, "name" => "Keith", "email" => "k@x", "projects" => [{ "slug" => "p", "role" => "owner" }] }] }
api.route("GET", "#{P}/doctor") { [200, { "project" => "p", "role" => "owner", "reachable" => true }] }
with_project(api.url) do |root|
  raise "whoami" unless store!("whoami", env: ENV_OK, chdir: root)["name"] == "Keith"
  raise "doctor" unless store!("doctor", env: ENV_OK, chdir: root)["reachable"] == true
end

# 20. --store is obsolete: warns on stderr, still works; unknown op exits 1
with_project(api.url) do |root|
  out, err, st = run_store("inbox_list", "--store", "airtable", env: ENV_OK, chdir: root)
  raise "--store should warn but succeed: #{st.exitstatus} #{err}" unless st.success? && err.include?("obsolete") && JSON.parse(out).is_a?(Array)
  _o, err, st = run_store("frobnicate", env: ENV_OK, chdir: root)
  raise "unknown op: #{err}" unless st.exitstatus == 1 && err.include?("unknown op")
end

api.close
puts "OFFLINE PASS"

# ------------------------------------------------------------------ online --
url = ENV["AGENTILE_PROJECTS_URL"].to_s
tok = ENV["AGENTILE_PROJECTS_TOKEN"].to_s
proj = ENV["AGENTILE_PROJECTS_TEST_PROJECT"].to_s
if url.empty? || tok.empty? || proj.empty?
  puts "SKIP online: set AGENTILE_PROJECTS_URL, AGENTILE_PROJECTS_TOKEN and AGENTILE_PROJECTS_TEST_PROJECT to run against a live app"
  puts "ALL PASS"
  exit 0
end

env = { "AGENTILE_PROJECTS_URL" => url, "AGENTILE_PROJECTS_TOKEN" => tok, "AGENTILE_RUNNER_ID" => "test-runner-#{Process.pid}", "CLAUDE_SESSION_ID" => "test-sess-#{Process.pid}" }
Dir.mktmpdir do |root|
  FileUtils.mkdir_p(File.join(root, ".agentile"))
  File.write(File.join(root, ".agentile", "store.md"), "---\nurl: #{url}\nproject: #{proj}\n---\n")
  FileUtils.mkdir_p(File.join(root, "docs", "agentile"))
  tag = "t#{Process.pid}#{Time.now.to_i % 100_000}"

  me = store!("whoami", env: env, chdir: root)
  raise "online whoami: #{me.inspect}" unless me["projects"].any? { |p| p["slug"] == proj }
  raise "online doctor" unless store!("doctor", env: env, chdir: root)["reachable"] == true

  # inbox round trip
  store!("inbox_add", "Online test stub #{tag}", "--title", "Stub #{tag}", "--type", "chore", env: env, chdir: root)
  stub = store!("inbox_list", env: env, chdir: root).find { |s| s["title"] == "Stub #{tag}" }
  raise "online inbox_list should show the stub" unless stub
  assist = store!("inbox_assist", "make the login page faster for #{tag}", env: env, chdir: root)
  raise "online inbox_assist should return a title: #{assist.inspect}" unless assist["title"].to_s != ""

  # shape the stub into a spec; spec_read round-trips the sections
  slug_a = "#{tag}-a"
  md = <<~MD
    ---
    title: Spec A #{tag}
    slug: #{slug_a}
    status: ready
    type: feature
    route: background
    business_value: high
    technical_certainty: high
    depends_on: []
    tags: [online-test]
    ---

    # Spec A #{tag}

    ## Problem / why now

    Testing the client.

    ## Acceptance criteria

    - [ ] round-trips

    ## Scope boundary

    **In scope:** this test

    **Out of scope:** everything else

    ## Edge cases and failure paths

    none

    ## Affected areas

    dev/

    ## Open questions

    none

    ## Verification

    ruby dev/test-ag-store-http.rb
  MD
  raise "online inbox_shape" unless store!("inbox_shape", stub["id"].to_s, env: env, stdin: md, chdir: root) == slug_a
  read = store!("spec_read", slug_a, env: env, chdir: root)
  raise "online spec_read round trip: #{read.inspect}" unless read.include?("slug: #{slug_a}") && read.include?("## Acceptance criteria") && read.include?("round-trips")
  raise "online stub should be shaped (not listed as open)" if store!("inbox_list", env: env, chdir: root).any? { |s| s["id"] == stub["id"] }

  # a second spec depending on the first; rank; claim; checkpoint; run; ship
  slug_b = "#{tag}-b"
  store!("spec_create", slug_b, env: env, stdin: md.sub("Spec A", "Spec B").sub("slug: #{slug_a}", "slug: #{slug_b}").sub("depends_on: []", "depends_on: [#{slug_a}]"), chdir: root)
  raise "online deps" unless store!("deps", slug_b, env: env, chdir: root) == [slug_a]
  raise "online dependents" unless store!("dependents", slug_a, env: env, chdir: root).include?(slug_b)
  store!("rank", slug_b, slug_a, env: env, chdir: root)
  listed = store!("spec_list", "--status", "ready", env: env, chdir: root).select { |s| s["slug"].start_with?(tag) }
  raise "online rank order: #{listed.map { |s| [s['slug'], s['prefix']] }.inspect}" unless listed.map { |s| s["slug"] } == [slug_b, slug_a]

  claimed = store!("claim", env["AGENTILE_RUNNER_ID"], "online", "0", env: env, chdir: root)
  raise "online claim should skip the blocked B and take A: #{claimed.inspect}" unless claimed == slug_a
  raise "online claim again should be BLOCKED (B waits on A): " unless store!("claim", env["AGENTILE_RUNNER_ID"], "", "0", env: env, chdir: root) == "BLOCKED"
  inprog = store!("spec_list", "--status", "in_progress", env: env, chdir: root).find { |s| s["slug"] == slug_a }
  raise "online in_progress listing" unless inprog && inprog["claimed_by"] == env["AGENTILE_RUNNER_ID"]
  raise "online claim should have opened a run" unless store!("run_list", "--spec", slug_a, "--status", "active", env: env, chdir: root).any?

  cp = store!("checkpoint_open", slug_a, "ship_approval", "--session", env["CLAUDE_SESSION_ID"], "--by", "ship", env: env, stdin: "Approve to ship #{slug_a}?", chdir: root)
  raise "online checkpoint_open_count" unless store!("checkpoint_open_count", slug_a, env: env, chdir: root) == 1
  raise "online run should be paused" unless store!("run_list", "--spec", slug_a, env: env, chdir: root).last["status"] == "paused"
  store!("checkpoint_answer", cp.to_s, "--by", "test", env: env, stdin: "approved", chdir: root)
  last = store!("checkpoint_list", slug_a, env: env, chdir: root).last
  raise "online answered: #{last.inspect}" unless last["status"] == "answered" && last["answer"] == "approved"
  store!("run_event", "shipped", "--spec", slug_a, "--runner", env["AGENTILE_RUNNER_ID"], env: env, chdir: root)
  store!("ship", slug_a, env: env, chdir: root)
  raise "online ship" unless store!("spec_list", "--pool", "done", env: env, chdir: root).any? { |s| s["slug"] == slug_a }
  raise "online claim B after A shipped" unless store!("claim", env["AGENTILE_RUNNER_ID"], "", "0", env: env, chdir: root) == slug_b
  store!("release", slug_b, env: env, chdir: root)
  flow = store!("flow", slug_a, env: env, chdir: root)
  raise "online flow: #{flow.inspect}" unless flow["checkpoint_count"] == 1 && flow["lead_seconds"].is_a?(Integer)
  store!("abandon", slug_b, "--reason", "online test cleanup", env: env, chdir: root)
  raise "online abandon" unless store!("spec_list", "--pool", "abandoned", env: env, chdir: root).any? { |s| s["slug"] == slug_b }

  # outcomes + map + brief
  o = "#{tag}-o"
  store!("outcome_create", o, env: env, stdin: "---\ntitle: Outcome #{tag}\nslug: #{o}\nstatus: open\n---\n\n# Outcome #{tag}\n\n## Claim\n\nc\n\n## Measure\n\nm\n\n## Stop rule\n\ns\n\n## Notes\n\n", chdir: root)
  raise "online outcome_read" unless store!("outcome_read", o, env: env, chdir: root).include?("## Measure")
  store!("outcome_rank", o, env: env, chdir: root)
  raise "online map" unless store!("map", env: env, chdir: root)["outcomes"].any? { |x| x["slug"] == o }
  raise "online brief_sync" unless File.read(File.join(root, store!("brief_sync", "--dir", "docs/agentile", env: env, chdir: root))).include?(o)
  store!("outcome_abandon", o, "--reason", "online test cleanup", env: env, chdir: root)
end
puts "ONLINE PASS"
puts "ALL PASS"
```

- [ ] **Step 2: Run it to confirm it fails against the current adapter-based CLI**

```bash
ruby dev/test-ag-store-http.rb
```

Expected: fails at case 1 (`missing token should exit 2`) — the old CLI does not know about `AGENTILE_PROJECTS_TOKEN`.

- [ ] **Step 3: Write the new `bin/ag-store`**

Replace the whole file with:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# ag-store — the backlog store CLI. Since 0.20.0 the only store is Agentile
# Projects (the web app); this file is a thin HTTP client over its JSON API.
# Every skill that touches the Inbox, a spec, an Outcome, a checkpoint or a
# run goes through here instead of talking to the API itself, so a skill's
# instructions name one command and one output shape.
#
# Usage: ag-store <op> [args...] [--dir <agentile-dir>]
#
# Config — .agentile/store.md frontmatter, written by /ag-init:
#   url:     https://agentile-projects.agentaconsulting.com   (AGENTILE_PROJECTS_URL overrides)
#   project: <slug>
# Auth — AGENTILE_PROJECTS_TOKEN in the environment only, never a tracked file.
# --dir (default docs/agentile) is used by promote and brief_sync, which touch
# the repo; every other op ignores it.
#
# Ops (all output one JSON value on stdout; errors to stderr, exit 1 for an API
# or usage error, exit 2 for a configuration/connectivity error):
#   inbox_list [--status open|shaped|dropped]
#   inbox_add <text> [--title "<label>"] [--type feature|bug|chore|spike] [--serves <outcome-slug>]
#   inbox_drop <id>
#   inbox_assist <text>                          tidy + classify; returns suggestions, saves nothing
#   inbox_shape <id>            (markdown on stdin)  create the spec, mark the stub shaped
#   spec_list [--status s] [--pool active|done|abandoned]
#   spec_read <slug>                              canonical markdown
#   spec_create <slug>          (markdown on stdin)
#   spec_write <slug> --set k=v [--set k=v ...]   list fields accept "[a, b]"
#   rank <slug> [<slug>...]                       ready specs only, dense ranks in this order
#   claim <identity> [label] [wip] [--spec <slug>]   slug, or WIP_FULL|BLOCKED|UNPRIORITISED|NONE|NOT_FOUND|TAKEN
#   release <slug> | ship <slug> | abandon <slug> --reason "<text>" [--cascade "[a, b]"]
#   promote <slug> --dir <dir>                    ensures <dir>/specs/<slug>/ exists; prints it
#   deps <slug> | dependents <slug>
#   map | flow [<slug>]
#   outcome_list [--status s] | outcome_read <slug> | outcome_create <slug> (stdin) | outcome_write <slug> --set k=v
#   outcome_rank <slug>... | outcome_achieve <slug> | outcome_abandon <slug> --reason "<text>"
#   checkpoint_open <slug> <reason> --session <id> --by <who>   (ask on stdin) -> checkpoint id
#   checkpoint_list <slug> | checkpoint_open_count <slug>
#   checkpoint_answer <id> --by <who>             (answer on stdin)
#   run_event <event> --spec <slug> --runner <id> [--detail "<text>"]   -> ISO8601 stamp
#   run_list [--spec <slug>] [--status active|closed]
#   run_close --spec <slug> --runner <id> [--detail "<text>"]
#   brief_sync --dir <dir>                        writes <dir>/brief.md from the store; prints the path
#   whoami | doctor
#
# Runs belong to a spec. checkpoint_open, run_event and run_close resolve the
# run themselves: the active run for <spec> whose runner_id is the identity
# (--runner, else AGENTILE_RUNNER_ID, else CLAUDE_SESSION_ID), else the newest
# active run; run_event creates one when none exists. `claim` opens the run
# server-side, so no skill ever handles a run id.

require "json"
require "yaml"
require "net/http"
require "uri"
require "fileutils"

module AgStore
  class Error < StandardError; end        # exit 1
  class ConfigError < StandardError; end  # exit 2

  CHECKPOINT_REASONS = %w[plan_review build_blocked build_checkpoint gate_failure
                          verify_checkpoint ship_approval question].freeze
  RUN_EVENTS = %w[started claimed shipped paused failed idle deployed closed].freeze
  LIST_FIELDS = %w[depends_on tags shaped_by cascade].freeze
  STORE_MD = ".agentile/store.md"

  def self.parse_flags(argv)
    positional = []
    flags = {}
    i = 0
    while i < argv.length
      arg = argv[i]
      if arg.start_with?("--")
        key = arg[2..]
        if i + 1 < argv.length && !argv[i + 1].start_with?("--")
          flags[key] = argv[i + 1]
          i += 2
        else
          flags[key] = true
          i += 1
        end
      else
        positional << arg
        i += 1
      end
    end
    [positional, flags]
  end

  # --set key=value may repeat; pull every occurrence out before the generic parser runs.
  def self.extract_sets(argv)
    sets = {}
    rest = []
    i = 0
    while i < argv.length
      if argv[i] == "--set" && argv[i + 1]
        k, v = argv[i + 1].split("=", 2)
        sets[k] = v
        i += 2
      else
        rest << argv[i]
        i += 1
      end
    end
    [rest, sets]
  end

  # "[a, b]" -> ["a", "b"]; "[]" -> []; anything else unchanged.
  def self.coerce_list(key, val)
    return val unless LIST_FIELDS.include?(key) && val.is_a?(String)

    s = val.strip
    return val unless s.start_with?("[") && s.end_with?("]")

    s[1..-2].split(",").map(&:strip).reject(&:empty?)
  end

  class Config
    attr_reader :url, :project, :token, :dir

    def initialize(flags)
      fm = self.class.read_store_md
      env_url = ENV["AGENTILE_PROJECTS_URL"].to_s
      @url = (env_url.empty? ? fm["url"] : env_url).to_s.sub(%r{/+\z}, "")
      @project = (flags["project"] || fm["project"]).to_s
      @token = ENV["AGENTILE_PROJECTS_TOKEN"].to_s
      @dir = (flags["dir"] || "docs/agentile").to_s.sub(%r{/+\z}, "")
    end

    def self.read_store_md
      return {} unless File.exist?(STORE_MD)

      fm = File.read(STORE_MD)[/\A---\n(.*?)\n---/m, 1]
      fm ? (YAML.safe_load(fm) || {}) : {}
    rescue StandardError
      {}
    end

    def validate!(needs_project: true)
      if url.empty?
        raise ConfigError, "no store url — #{STORE_MD} has no `url:` (run /ag-init to link this project) and AGENTILE_PROJECTS_URL is unset"
      end
      raise ConfigError, "AGENTILE_PROJECTS_TOKEN is not set — create a token in Agentile Projects (Settings → API tokens) and export it" if token.empty?
      raise ConfigError, "no project — #{STORE_MD} has no `project:` (run /ag-init to link this project)" if needs_project && project.empty?
    end
  end

  class Client
    def initialize(config)
      @config = config
    end

    def get(path, params = {})   = request(:get, path, params: params)
    def post(path, body = nil)   = request(:post, path, body: body)
    def patch(path, body)        = request(:patch, path, body: body)
    def put(path, body)          = request(:put, path, body: body)
    def post_markdown(path, md)  = request(:post, path, body: md, content_type: "text/markdown")

    def project_path(rest) = "/projects/#{@config.project}#{rest}"

    private

    def request(method, path, body: nil, params: {}, content_type: "application/json")
      uri = URI.parse("#{@config.url}/api/v1#{path}")
      clean = params.reject { |_, v| v.nil? || v.to_s.empty? }
      uri.query = URI.encode_www_form(clean) unless clean.empty?
      req = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, put: Net::HTTP::Put }.fetch(method).new(uri)
      req["Authorization"] = "Bearer #{@config.token}"
      req["Accept"] = "application/json, text/markdown"
      unless body.nil?
        req["Content-Type"] = content_type
        req.body = content_type == "application/json" ? JSON.generate(body) : body
      end
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 60) do |http|
        http.request(req)
      end
      parse(res)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Net::OpenTimeout => e
      raise ConfigError, "cannot reach #{@config.url} (#{e.class}) — is Agentile Projects running, and is the url in #{STORE_MD} (or AGENTILE_PROJECTS_URL) right?"
    end

    def parse(res)
      text = res.body.to_s
      json = res["content-type"].to_s.include?("json") || text.start_with?("{", "[", "\"") ? (JSON.parse(text) rescue text) : text
      json = json.strip if json.is_a?(String) && !res["content-type"].to_s.include?("markdown")
      return json if res.is_a?(Net::HTTPSuccess)

      detail = json.is_a?(Hash) ? (json["detail"] || json["error"] || text) : text
      raise ConfigError, "#{res.code} #{detail} — check AGENTILE_PROJECTS_TOKEN" if res.code == "401"
      raise Error, "#{res.code} #{detail}"
    end
  end

  class Ops
    def initialize(config, client)
      @c = config
      @api = client
    end

    def identity(flag = nil)
      return flag.to_s unless flag.to_s.empty?
      return ENV["AGENTILE_RUNNER_ID"].to_s unless ENV["AGENTILE_RUNNER_ID"].to_s.empty?

      ENV["CLAUDE_SESSION_ID"].to_s
    end

    def active_run_for(slug, runner)
      runs = Array(@api.get(@api.project_path("/runs"), spec: slug, status: "active"))
      runs.find { |r| r["runner_id"] == runner } || runs.max_by { |r| r["started_at"].to_s }
    end

    def ensure_run(slug, runner, session)
      active_run_for(slug, runner) ||
        @api.post(@api.project_path("/runs"), { spec: slug, runner_id: runner, session_id: session })
    end

    def require_spec!(flags, op)
      raise Error, "#{op} needs --spec <slug> — since 0.20.0 a run belongs to a spec" if flags["spec"].to_s.empty?

      flags["spec"].to_s
    end

    def run(op, positional, flags, sets)
      p = ->(rest) { @api.project_path(rest) }
      case op
      when "inbox_list" then @api.get(p["/inbox"], status: flags["status"])
      when "inbox_add"
        @api.post(p["/inbox"], { text: positional[0].to_s, title: flags["title"], kind: flags["type"], serves: flags["serves"] }.compact)
        true
      when "inbox_drop" then @api.post(p["/inbox/#{positional[0]}/drop"]); true
      when "inbox_assist" then @api.post(p["/inbox/assist"], { text: positional[0].to_s })
      when "inbox_shape" then @api.post_markdown(p["/inbox/#{positional[0]}/shape"], $stdin.read)
      when "spec_list" then @api.get(p["/specs"], status: flags["status"], pool: flags["pool"] || "active")
      when "spec_read" then @api.get(p["/specs/#{positional[0]}.md"])
      when "spec_create" then @api.post_markdown(p["/specs"], $stdin.read)
      when "spec_write" then @api.patch(p["/specs/#{positional[0]}"], sets.to_h { |k, v| [k, AgStore.coerce_list(k, v)] })
      when "rank" then @api.put(p["/specs/rank"], { slugs: positional })
      when "claim"
        body = { identity: positional[0].to_s, label: positional[1].to_s, wip: positional[2].to_i }
        body[:slug] = flags["spec"] if flags["spec"]
        res = @api.post(p["/specs/claim"], body)
        res.is_a?(Hash) ? res["result"] : res
      when "release" then @api.post(p["/specs/#{positional[0]}/release"])
      when "ship" then @api.post(p["/specs/#{positional[0]}/ship"])
      when "abandon"
        body = { reason: flags["reason"].to_s }
        body[:cascade] = AgStore.coerce_list("cascade", flags["cascade"]) if flags["cascade"]
        @api.post(p["/specs/#{positional[0]}/abandon"], body)
      when "promote"
        path = File.join(@c.dir, "specs", positional[0].to_s)
        FileUtils.mkdir_p(path)
        path
      when "deps" then @api.get(p["/specs/#{positional[0]}/deps"])
      when "dependents" then @api.get(p["/specs/#{positional[0]}/dependents"])
      when "map" then @api.get(p["/map"])
      when "flow" then positional[0].to_s.empty? ? @api.get(p["/flow"]) : @api.get(p["/flow/#{positional[0]}"])
      when "outcome_list" then @api.get(p["/outcomes"], status: flags["status"])
      when "outcome_read" then @api.get(p["/outcomes/#{positional[0]}.md"])
      when "outcome_create" then @api.post_markdown(p["/outcomes"], $stdin.read)
      when "outcome_write" then @api.patch(p["/outcomes/#{positional[0]}"], sets.to_h { |k, v| [k, AgStore.coerce_list(k, v)] })
      when "outcome_rank" then @api.put(p["/outcomes/rank"], { slugs: positional })
      when "outcome_achieve" then @api.post(p["/outcomes/#{positional[0]}/achieve"])
      when "outcome_abandon" then @api.post(p["/outcomes/#{positional[0]}/abandon"], { reason: flags["reason"].to_s })
      when "checkpoint_open"
        slug, reason = positional
        raise Error, "unknown checkpoint reason #{reason.inspect} (#{CHECKPOINT_REASONS.join('|')})" unless CHECKPOINT_REASONS.include?(reason.to_s)

        session = flags["session"].to_s.empty? ? ENV["CLAUDE_SESSION_ID"].to_s : flags["session"].to_s
        run = ensure_run(slug, identity, session)
        res = @api.post(p["/runs/#{run['id']}/checkpoints"],
                        { reason: reason, asked_by: flags["by"].to_s, session_id: session, ask: $stdin.read.to_s.strip })
        res.is_a?(Hash) ? res["id"] : res
      when "checkpoint_list" then @api.get(p["/specs/#{positional[0]}/checkpoints"])
      when "checkpoint_open_count"
        Array(@api.get(p["/specs/#{positional[0]}/checkpoints"])).count { |c| c["status"].to_s != "answered" }
      when "checkpoint_answer"
        @api.post(p["/checkpoints/#{positional[0]}/answer"], { answer: $stdin.read.to_s.strip, by: flags["by"].to_s })
      when "run_event"
        event = positional[0].to_s
        raise Error, "unknown run event #{event.inspect} (#{RUN_EVENTS.join('|')})" unless RUN_EVENTS.include?(event)

        slug = require_spec!(flags, "run_event")
        run = ensure_run(slug, identity(flags["runner"]), ENV["CLAUDE_SESSION_ID"].to_s)
        @api.post(p["/runs/#{run['id']}/events"], { event: event, detail: flags["detail"].to_s })
      when "run_list" then @api.get(p["/runs"], spec: flags["spec"], status: flags["status"])
      when "run_close"
        slug = require_spec!(flags, "run_close")
        run = active_run_for(slug, identity(flags["runner"]))
        raise Error, "no active run for #{slug} — nothing to close" unless run

        @api.post(p["/runs/#{run['id']}/close"], { detail: (flags["detail"].to_s.empty? ? "run closed" : flags["detail"].to_s) })
      when "brief_sync"
        md = @api.get(p["/brief"])
        path = File.join(@c.dir, "brief.md")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, md.to_s)
        path
      when "whoami" then @api.get("/me")
      when "doctor" then @api.get(p["/doctor"])
      else raise Error, "unknown op '#{op}'"
      end
    end
  end
end

op = ARGV[0]
abort "usage: ag-store <op> [args...] [--dir <agentile-dir>]" if op.nil?

rest, sets = AgStore.extract_sets(ARGV[1..])
positional, flags = AgStore.parse_flags(rest)
warn "ag-store: --store is obsolete since 0.20.0 (Agentile Projects is the only store) — ignoring it" if flags.key?("store")
warn "ag-store: --airtable-base is obsolete since 0.20.0 — ignoring it" if flags.key?("airtable-base")

begin
  config = AgStore::Config.new(flags)
  config.validate!(needs_project: !%w[whoami promote].include?(op))
  result = AgStore::Ops.new(config, AgStore::Client.new(config)).run(op, positional, flags, sets)
  puts JSON.generate(result)
rescue AgStore::ConfigError => e
  warn "ag-store: #{e.message}"
  exit 2
rescue AgStore::Error => e
  warn "ag-store: #{e.message}"
  exit 1
end
```

- [ ] **Step 4: Run the offline tests**

```bash
ruby dev/test-ag-store-http.rb
```

Expected: `OFFLINE PASS`, then `SKIP online: …` and `ALL PASS`. If a case fails on the fake server's text-vs-JSON handling (case 7/8), the fix belongs in `Client#parse`, not the test.

- [ ] **Step 5: Commit**

```bash
git add bin/ag-store dev/test-ag-store-http.rb
git commit -m "ag-store: thin HTTP client for Agentile Projects, with offline and online tests"
```

---

### Task 3: Delete the adapters, legacy helpers and store templates; fix every reference

**Files:**
- Delete: `bin/ag-store-adapters/` (whole directory), `bin/ag-claim`, `bin/ag-checkpoint`, `bin/ag-dependents`, `dev/test-ag-store-local.rb`, `dev/test-ag-store-airtable.rb`, `dev/test-ag-claim.rb`, `dev/test-ag-checkpoint.rb`, `dev/test-ag-dependents.rb`, `dev/smoke-airtable.rb`, `templates/stores/` (whole directory), `templates/inbox.md`, `templates/agentile/runs.md`
- Rewrite: `templates/agentile/store.md`
- Create: `templates/agentile/deploys.md`
- Modify: `bin/ag-run:5-8,21-22,83-84`, `bin/ag-lock:6-8`, `hooks/test-gate.rb:34-37,102-103`, `templates/agentile/gates.json:2`, `templates/agentile/spec-template.md:1`, `templates/agentile/adr-template.md:1`, `templates/agentile/shape.md:30`, `templates/agentile/outcome-template.md:9-11` (unchanged — names `ag-store` ops that still exist), `templates/agentile/brief-template.md:19`

**Interfaces:**
- Consumes: Task 2's CLI.
- Produces: `templates/agentile/store.md` (new shape, read by `/ag-init` in Task 4); `templates/agentile/deploys.md` (read by `/ag-deploy` in Task 7).

- [ ] **Step 1: Delete**

```bash
git rm -r bin/ag-store-adapters bin/ag-claim bin/ag-checkpoint bin/ag-dependents \
  dev/test-ag-store-local.rb dev/test-ag-store-airtable.rb dev/test-ag-claim.rb \
  dev/test-ag-checkpoint.rb dev/test-ag-dependents.rb dev/smoke-airtable.rb \
  templates/stores templates/inbox.md templates/agentile/runs.md
```

- [ ] **Step 2: Rewrite `templates/agentile/store.md`**

```markdown
---
url: https://agentile-projects.agentaconsulting.com
project: <project-slug>
---

# Store

Where the Inbox, specs, Outcomes, checkpoints and runs live: **Agentile
Projects**, the web app. `url` is the app; `project` is this repo's project
slug there. `/ag-init` writes both; `AGENTILE_PROJECTS_URL` in the environment
overrides `url` (handy for a locally running app).

Credentials are never written here — `AGENTILE_PROJECTS_TOKEN` is an
environment variable only (create one under Settings → API tokens in the app),
set wherever you keep local secrets for tools you run, never in a tracked file.

The split is **events vs artefacts**:

- **Events go to the store** — stubs, specs, Outcomes, the brief, checkpoints
  and run events. A checkpoint is a question addressed to a human who may be at
  another machine or on the app's dashboard; the run log is the team's record
  of what ran where.
- **Artefacts stay in this repo** — `plan.md`, the `SPEC.md` snapshot,
  findings, supporting files (all under `docs/agentile/specs/<slug>/`) and
  ADRs (`docs/adr/`). They are things you review and amend, and they belong
  beside the diff they describe. `docs/agentile/brief.md` is a read-only copy
  of the store's brief, refreshed by every `/ag-*` skill; edit the brief in
  the app.
```

- [ ] **Step 3: Create `templates/agentile/deploys.md`**

```markdown
# Agentile deploy log

Append-only. One line per deploy, oldest first. Written by `/ag-deploy`; read
by `/ag-deploy` to compute the next batch (every spec shipped after the last
line's timestamp). Not hand-edited — only append.

Format: `- <ISO8601> runner=<identity> target=<target> ref=<git sha> specs=<n> detail=<free text>`

A rollback is recorded as a new line too — the log is a history of what was
live, not a list of successes.
```

- [ ] **Step 4: Fix `bin/ag-run` hints**

Replace lines 5–8:

```ruby
# pause a human needs to answer — a detached process can't answer a
# checkpoint; answer it with `ag-checkpoint answer <path>` and re-run with
# the same AGENTILE_RUNNER_ID. For parallel workers, chosen models, and a
# console for what needs you, see docs/agentile-factory.md.
```

with:

```ruby
# pause a human needs to answer — a detached process can't answer a
# checkpoint; answer it in Agentile Projects (or with `printf 'reply' |
# ag-store checkpoint_answer <id> --by <you>`) and re-run with the same
# AGENTILE_RUNNER_ID. For parallel workers, chosen models, and the app's
# dashboards, see docs/agentile-factory.md.
```

Replace lines 21–22:

```ruby
#     ag-run -- --permission-mode acceptEdits --permission-prompts none --allowedTools "Bash(ag-store:*)" "Bash(ag-checkpoint:*)" "Bash(git:*)"
```

with:

```ruby
#     ag-run -- --permission-mode acceptEdits --permission-prompts none --allowedTools "Bash(ag-store:*)" "Bash(git:*)"
```

Replace lines 83–84:

```ruby
    puts "[ag-run] to resume: answer it (ag-checkpoint answer <path>, or reply in a session with"
    puts "[ag-run] AGENTILE_RUNNER_ID=#{runner_id} and /ag-build), then re-run ag-run with the same AGENTILE_RUNNER_ID."
```

with:

```ruby
    puts "[ag-run] to resume: answer it in Agentile Projects (or: printf 'reply' | ag-store checkpoint_answer #{checkpoint} --by you),"
    puts "[ag-run] then re-run ag-run with the same AGENTILE_RUNNER_ID=#{runner_id}."
```

- [ ] **Step 5: Fix `bin/ag-lock` and `hooks/test-gate.rb` comments**

`bin/ag-lock` lines 6–8: replace

```ruby
# first to finish rather than both erroring out. Same primitive ag-claim uses
# for its atomic spec claim (File#flock) — works identically on Linux and
# macOS, no dependency on the platform flock(1) CLI (which macOS lacks).
```

with

```ruby
# first to finish rather than both erroring out. Uses File#flock, which works
# identically on Linux and macOS, with no dependency on the platform flock(1)
# CLI (which macOS lacks). (Claiming a spec no longer needs a lock: since
# 0.20.0 the store claims transactionally, server-side.)
```

`hooks/test-gate.rb` lines 34–37: replace

```ruby
# This is separate from, and stacks with, the opt-in `ag-lock` wrapper
# /ag-init can add around gates.json's own `test` command: that one also
# covers a human or ag-builder invoking the gate command directly, outside
# this hook.
```

with

```ruby
# This is separate from, and stacks with, the opt-in `ag-lock` wrapper a
# project can put around gates.json's own `test` command: that one also
# covers a human or ag-builder invoking the gate command directly, outside
# this hook.
```

and lines 102–103: replace

```ruby
# Serialize concurrent hook-triggered test runs for this project directory (see
# header comment) — same File#flock primitive ag-claim uses, portable and
```

with

```ruby
# Serialize concurrent hook-triggered test runs for this project directory (see
# header comment) — the same File#flock primitive ag-lock uses, portable and
```

and line 107 `# Interactive Bash tool calls get this plugin's bin/ (ag-claim, ag-lock, ...)` → `# Interactive Bash tool calls get this plugin's bin/ (ag-store, ag-lock, ...)`, and line 110 `# convention skills use for ag-claim), so guarantee it resolves here too by` → `# convention skills use for ag-store), so guarantee it resolves here too by`.

- [ ] **Step 6: Fix template wording that names `ag-claim` or the file layout**

`templates/agentile/gates.json` line 2 (`$comment`): replace the sentence `Fill these in with /ag-init or by hand.` with `Fill these in with /ag-init or by hand.` (unchanged) and replace `wrap the command with the plugin's ag-lock, e.g. \"test\": \"ag-lock storage/.test.lock 'bin/rails test'\" — point the lockfile at an already-gitignored runtime path.` with `wrap the command with the plugin's ag-lock, e.g. \"test\": \"ag-lock tmp/.test.lock 'bin/rails test'\" — point the lockfile at an already-gitignored runtime path (/ag-init no longer asks; add it by hand when a suite needs it).`

`templates/agentile/spec-template.md` line 1 and `templates/agentile/adr-template.md` line 1: replace `the claim tooling (bin/ag-claim) fails to parse it` (adr) / `the claim tooling (bin/ag-claim)` (spec) with `the store's markdown parser` — run `grep -n "ag-claim" templates/` afterwards and fix any remaining occurrence the same way.

`templates/agentile/shape.md` line 30: replace `the claim tooling (\`bin/ag-claim\`) parses the frontmatter with a real YAML parser and fails, so the spec can never be claimed` with `the store parses the frontmatter with a real YAML parser and rejects the spec, so it can never be created`.

`templates/agentile/brief-template.md` line 19: replace `<Once Outcomes exist, this list is regenerated from them by \`ag-store brief_sync\`` with `<Once Outcomes exist, the app regenerates this list from them by rank; \`ag-store brief_sync\` pulls the result into this read-only copy`. Also add as the file's first line: `<!-- READ-ONLY COPY — edit the brief in Agentile Projects; every /ag-* skill overwrites this file from the store. -->`.

- [ ] **Step 7: Verify nothing references the deleted files, run tests, commit**

```bash
grep -rn "ag-claim\|ag-checkpoint\|ag-dependents\|ag-store-adapters\|templates/stores\|smoke-airtable" bin hooks templates dev .claude-plugin || echo "clean"
ruby dev/test-ag-store-http.rb
ruby hooks/test-gates.rb
ruby dev/test-ag-run.rb
git add -A bin hooks templates dev
git commit -m "Remove the local and Airtable stores; Agentile Projects is the only store"
```

Expected: `clean`, three `ALL PASS`. (Skills and docs still reference the old names — Tasks 4–9 fix those.)

---

### Task 4: Rewrite `/ag-init`

**Files:**
- Rewrite: `skills/ag-init/SKILL.md`

**Interfaces:**
- Consumes: `ag-store whoami` (`/me` → `{user_id, name, email, projects: [{slug, role}]}`), `ag-store doctor`, `ag-store brief_sync --dir <dir>`, `templates/agentile/store.md`, `templates/CLAUDE.agentile-section.md` (rewritten in Task 8 — the init text below refers to it by path only).
- Produces: a linked project: `.agentile/store.md` with `url`/`project`, `docs/agentile/brief.md`, `docs/agentile/specs/`, `docs/adr/`, `.agentile/*` playbooks.

- [ ] **Step 1: Replace the file's body**

Keep the frontmatter (lines 1–6 of the current file: `name`, `description`, `allowed-tools`) but change the description to:

```yaml
description: Link this project to Agentile Projects (the backlog store) and scaffold the tailorable .agentile/ layer, docs/agentile/ and docs/adr/. Idempotent — never overwrites a file that exists. Trigger phrases include "/ag-init", "initialise agentile", "set up agentile here", "link this repo to agentile projects".
```

Then replace everything after the frontmatter with:

````markdown
# ag-init

Link this repo to its project in **Agentile Projects** and scaffold the **tailorable layer** of Agentile into it. The **fixed implementation** (skills, agents, hooks) is already installed via the plugin; this skill drops the per-project files the skills read at runtime, so the team can tailor *content* without touching the plugin.

This skill is **idempotent**: it must never overwrite a file that already exists. For each target, check first, and report whether it was created or left as-is.

## Step 1 — Locate the plugin templates

The files to copy live in this plugin's `templates/` directory, one level up from this skill: `${CLAUDE_SKILL_DIR}/../../templates/` (fallback `"${CLAUDE_PLUGIN_ROOT}/templates/"`).

## Step 2 — Link the project

1. Check the token: `[ -n "$AGENTILE_PROJECTS_TOKEN" ]`. If it is unset, stop and tell the user: sign in to Agentile Projects, create a token under **Settings → API tokens**, export it as `AGENTILE_PROJECTS_TOKEN` where they keep local secrets (never in a tracked file), and re-run `/ag-init`.
2. Resolve the app url: `AGENTILE_PROJECTS_URL` if set, else an existing `.agentile/store.md` `url:`, else the default `https://agentile-projects.agentaconsulting.com`. Ask (`AskUserQuestion`) only if the user is running the app somewhere else.
3. If `.agentile/store.md` already has `url:` and `project:`, the project is linked — run `ag-store doctor` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`), confirm `reachable: true`, and skip to Step 3. If it has a `store:` key instead (`local`/`airtable`, pre-0.20.0), say it is being replaced and continue.
4. Otherwise run `AGENTILE_PROJECTS_URL="<url>" ag-store whoami`. It returns `{user_id, name, email, projects: [{slug, role}]}`. Ask (`AskUserQuestion`) which project this repo is — offer the listed slugs (owner/member roles only; a `viewer` cannot capture or claim), plus "it isn't there yet". If it isn't there yet, tell the user to create the project in the app (Projects → New) and add themselves as owner, then re-run; project creation is not available from the CLI.
5. Write `.agentile/store.md` from `templates/agentile/store.md`, replacing the `url:` line with the resolved url and `<project-slug>` with the chosen slug. Then run `ag-store doctor` and stop on anything but `reachable: true`.

## Step 2a — Project brief (fresh projects)

The brief lives in the app (Project → Settings → Brief). Detect a fresh project: no `CLAUDE.md` of substance (absent, or only the Agentile section) AND a near-empty repo. If it looks established, skip this step — `/ag-retro` can seed the brief later.

For a fresh project, first recommend `/ag-new-project`: it runs a fuller interview (brief *and* stack), records the stack as an ADR, writes a starter `CLAUDE.md`, and then runs this scaffold. If the user would rather stay here, offer a short interview (decline-able): who is this for; the one outcome that matters first; the next two or three outcomes; hard constraints; explicit non-goals; what "shipped v1" looks like. Compose the brief from `templates/agentile/brief-template.md` (replace every `<…>` placeholder), show it, and tell the user to paste it into the project's Brief in the app — this skill cannot write the brief through the CLI. If a stack decision emerges, offer to capture it as `docs/adr/0001-…` from the ADR template.

The brief is what makes triage real: `/ag-shape` and `/ag-prioritise` score Business Value against its prioritised outcomes, and the app regenerates that list from Outcomes by rank.

## Step 3 — Scaffold files (skip any that exist)

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`). Copy from `templates/` into the project, preserving structure:

- `.agentile/config.md`
- `.agentile/shape.md`
- `.agentile/playbooks.md`
- `.agentile/build.md`
- `.agentile/verify.md`
- `.agentile/prioritise.md`
- `.agentile/next.md`
- `.agentile/plan.md`
- `.agentile/ship.md`
- `.agentile/deploy.md`
- `.agentile/gates.json` — then fill in the commands and protected branches gathered in Step 4.
- `.agentile/spec-template.md`
- `.agentile/outcome-template.md`
- `.agentile/plan-template.md`
- `.agentile/adr-template.md`
- `<dir>/deploys.md` (from `templates/agentile/deploys.md`) — the deploy log `/ag-deploy` appends to.
- `docs/adr/0000-record-architecture-decisions.md` — replace `<YYYY-MM-DD>` with today's date (`date +%Y-%m-%d`).
- Create the bare directory `<dir>/specs/` (no `.gitkeep`, no `done`/`abandoned` subdirectories — terminal states are status values in the store). Once a spec starts planning, its `plan.md`, `SPEC.md` snapshot and supporting files live at `<dir>/specs/<slug>/`, created on demand by `ag-store promote`.
- Pull the brief: `ag-store brief_sync --dir "<dir>"` writes `<dir>/brief.md` (a read-only copy; the app owns it). If the project's brief is still empty, the file holds the app's placeholder — that is fine.

There is no `inbox.md`, `runs.md`, `outcomes/` directory or `.pull.lock` — the Inbox, Outcomes, checkpoints and runs are store records, and claiming is transactional in the app.

Note the source `templates/agentile/` maps to the project's `.agentile/` directory.

## Step 4 — Gate commands and protected branches

Use `AskUserQuestion` to gather (one compact round):

- **Gate commands** — the project's `format`, `lint`, `test`, `build`, and `deploy` commands (any may be left blank). These populate `.agentile/gates.json`: `test`, `lint` and `build` run at verify and ship, `deploy` at `/ag-deploy`, and `format` after each edit via the `format-on-edit` hook. Every gate no-ops while its command is blank.
- **Protected branches** — branches agents must not commit to directly (default `main`, `master`).
- **Concurrency safety** (only if `test` and/or `build` were filled in) — can two invocations of that command run safely at the same time? Treat "not sure" as *unsafe*. If unsafe, wrap the affected command with the plugin's `ag-lock` (on `PATH` while the plugin is enabled): `"test": "ag-lock tmp/.test.lock 'bin/rails test'"`, pointing the lockfile at an ignored runtime path and confirming `.gitignore` covers it.

If the user is mid-flow and does not want questions, accept defaults, leave `gates.json` blank, and skip the concurrency question.

## Step 5 — Standing context

Append the contents of `templates/CLAUDE.agentile-section.md` to the project's root `CLAUDE.md`:

- If `CLAUDE.md` exists and does **not** already contain a "## Agentile" heading, append the section (with a blank line before it).
- If `CLAUDE.md` does not exist, suggest the user run `/init` first to bootstrap it from the codebase, then create `CLAUDE.md` containing just the Agentile section.
- If the section is already present, leave it.

Offer to write the section to `.claude/rules/agentile.md` instead, for users who keep `CLAUDE.md` short. Default remains appending to `CLAUDE.md`.

The section ends with `@docs/agentile/brief.md`; rewrite that path if the Agentile directory differs from `docs/agentile/`.

## Step 6 — Hooks

Nothing to wire per-project. The plugin's hooks (`hooks/hooks.json`) register automatically whenever the plugin is enabled; the only project-level control is `.agentile/gates.json`.

## Step 7 — Readiness report (observations, not blockers)

The methodology's precondition is "first be agile, then agentic" — a working trunk, gates, and tests. Check and report, without blocking:

- **Tests** — does `gates.json` have a `test` command? Does the repo have a test directory/framework?
- **CI** — is there a CI config (`.github/workflows/`, etc.)?
- **Trunk** — is there a default branch the team integrates to? Any long-lived divergent branches?
- **Store** — `ag-store doctor` reachable, and this user's role in the project (from `whoami`).

Phrase each as an observation ("No test command configured — verify and ship will have nothing to run").

## Step 8 — Report

Summarise what was created versus skipped, then:

> Agentile is initialised — this repo is linked to project **<slug>** at <url>. Capture ideas with `/ag-capture`, review them with `/ag-inbox` (or the app's Inbox), and shape one into a spec with `/ag-shape`. Tailor what "Ready" means by editing `.agentile/shape.md`. To configure how any loop stage runs, use `/ag-customise <stage>`; see `.agentile/playbooks.md` for the directive contract. Build the next ready spec with `/ag-build` (or a named one with `/ag-build <slug>`); for an unattended machine, see the Agentile Factory (`docs/agentile-factory.md`) or the `bin/ag-run` fallback. Dashboards, checkpoints waiting on you and run history are in the app.
````

- [ ] **Step 2: Check the file, run the tests, commit**

```bash
grep -n "Solo\|Team\|airtable\|inbox.md\|runs.md\|pull.lock\|specs/done\|specs/abandoned\|--store" skills/ag-init/SKILL.md || echo clean
ruby dev/test-ag-store-http.rb
git add skills/ag-init/SKILL.md
git commit -m "ag-init: link a repo to its Agentile Projects project; drop Solo/Team and the file layout"
```

Expected: `clean`, `ALL PASS`.

---

### Task 5: `/ag-capture`, `/ag-shape`, `/ag-inbox`

**Files:**
- Modify: `skills/ag-capture/SKILL.md:3,31-77`, `skills/ag-shape/SKILL.md:27-103`, `skills/ag-inbox/SKILL.md:11-19`

**Interfaces:**
- Consumes: `ag-store inbox_assist <text>` → `{title, text, kind, serves_outcome_slug, duplicate_of, duplicate_probability}`; `ag-store inbox_add`; `ag-store inbox_shape <id>` (markdown on stdin) → slug; `ag-store inbox_list`; `ag-store brief_sync`.
- Produces: the **brief-refresh preamble** used verbatim by Task 6 and Task 7:

```markdown
## Refresh the brief

Before anything else, resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). It rewrites `<dir>/brief.md` from the store so this session reads the current brief, and prints the path. If it exits 2 because the project is not linked (no `.agentile/store.md`, or no token), tell the user to run `/ag-init` (or export `AGENTILE_PROJECTS_TOKEN`) and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.
```

- [ ] **Step 1: `/ag-capture` — assist, confirm, `--yes`**

Line 3 description → `Add a stub to the Agentile inbox — tidied and classified by the store's assist, confirmed in one glance (or saved instantly with --yes). Safe to run mid-build. Trigger phrases include "/ag-capture", "capture this idea", "drop a stub", "add to the inbox", "note this down for later".`

Line 4 `allowed-tools: Bash, Read` → `allowed-tools: AskUserQuestion, Bash, Read`.

Replace the `## Rules` and `## Steps` sections (lines 25–77) with:

````markdown
## Rules

- **Do not interview.** The only questions allowed are the one-line ask when `$ARGUMENTS` is empty and the single confirmation in step 4.
- **Do not start work, plan, or shape.** That is what `/ag-shape` is for.
- **Do not estimate, triage, or add acceptance criteria.** A stub is one line; the store's assist may classify it, you do not.

## Refresh the brief

Before anything else, resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). It rewrites `<dir>/brief.md` from the store so this session reads the current brief, and prints the path. If it exits 2 because the project is not linked (no `.agentile/store.md`, or no token), tell the user to run `/ag-init` (or export `AGENTILE_PROJECTS_TOKEN`) and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.

## Steps

1. The stub text is `$ARGUMENTS`, minus a trailing `--yes` if present. If it is empty, ask the user for the one line (this is the only question allowed here) and stop until they answer.
2. Ask the store for suggestions (quote the text so the shell cannot eat an apostrophe or a backtick — the text must reach the store **verbatim**):

   ```
   ag-store inbox_assist "<stub text>"
   ```

   It returns `{title, text, kind, serves_outcome_slug, duplicate_of, duplicate_probability}` — a tidied title and text, a `kind` (`feature`/`bug`/`chore`/`spike`, or null when the store was not confident), the open Outcome it seems to serve (or null), and a possible duplicate (an existing stub or ready spec) when `duplicate_probability` is 0.5 or more. Nothing is saved yet.
3. If the user passed `--yes`, or the assist call failed for any reason other than "not linked" (the store's assist is a convenience, never a gate): skip the confirmation and save the **raw** text with `--title` derived as a very short label (3–6 words, no trailing full stop; the user's own `--title "..."` wins) and `--type` from what the text plainly says (default `feature`; a described defect or repro ⇒ `bug`; housekeeping with no user-visible change ⇒ `chore`; an open question to explore ⇒ `spike`). Pass `--serves` only when the user named an Outcome explicitly.
4. Otherwise show the suggestion in one `AskUserQuestion`: the tidied title and text, the kind, the Outcome, and — when present — the duplicate warning with the existing item's title. Options: **Save as suggested**, **Save my original text** (keeps the user's wording, still uses the suggested title/kind), **Don't save** (a duplicate, or second thoughts). One question, then act.
5. Save:

   ```
   ag-store inbox_add "<text>" --title "<title>" --type "<kind>" [--serves "<outcome-slug>"]
   ```

   The store records who captured it from the token — there is no `--by`. A non-zero exit 2 means the project is not linked — tell the user to run `/ag-init` rather than working around it.
6. Reply with one short line confirming the stub was captured, its title and kind, and (if any) the Outcome it serves. Nothing more.
````

- [ ] **Step 2: `/ag-shape` — single store, `inbox_shape`**

Replace Step 1 (lines 27–33) with:

```markdown
## Refresh the brief

Before anything else, resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). It rewrites `<dir>/brief.md` from the store so this session reads the current brief, and prints the path. If it exits 2 because the project is not linked (no `.agentile/store.md`, or no token), tell the user to run `/ag-init` (or export `AGENTILE_PROJECTS_TOKEN`) and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.

## Step 1 — Load the project's definitions

- Read `.agentile/shape.md` — this is **this project's Definition of Ready**: the exact questions a stub must answer, plus any house additions. Drive the interview against *this* list, not a generic one.
- Read `.agentile/config.md` for the two-axis triage table.
- Read `<dir>/brief.md` (just refreshed) — the project's users, constraints and prioritised outcomes. Run `ag-store outcome_list --status open`; if any Outcomes exist, Business Value is scored as **contribution to the Outcome this spec serves** (Step 3); with none, score against the brief's prose outcomes. Let both inform the shaping questions.
- Read the project's `CLAUDE.md` (and `docs/adr/`) for standing context so your questions fit the architecture.
```

Step 2, line 37: replace `- Run \`ag-store inbox_list ...\` and parse the JSON array of \`{id, title, type, text, captured_at, captured_by, captured_by_id}\` (\`airtable\` store only; \`captured_by_id\` is the raw Members record id behind the display name in \`captured_by\` — carry it into Step 5's spec attribution, never the display name).` with `- Run \`ag-store inbox_list\` and parse the JSON array of \`{id, title, type, text, captured_at, captured_by, serves, suggested_kind, duplicate_of}\`. Attribution is carried by the store when the stub is shaped — nothing to copy by hand.`

Lines 38–42: replace `A null \`type\` (the \`local\` store, or a stub captured before the field existed) means re-derive it from the text.` with `A null \`type\` (a stub captured before the field existed) means re-derive it from the text.`

Step 3 dependencies bullet (line 72): replace `Run \`ag-store spec_list ...\` and offer the existing slugs as candidates.` with `Run \`ag-store spec_list\` and offer the existing slugs as candidates.` and delete the sentence `Note that newly shaped specs are written **unprefixed** (they are Ready but not yet prioritised).` replacing it with `Newly shaped specs are Ready but **unranked** until \`/ag-prioritise\` places them.`

Step 5 "Graduate to a spec" bullet (line 92): replace everything from `Write it with \`ag-store spec_create <slug> --dir "<dir>" --store "<store>"\`, piping the markdown on stdin` through the end of that bullet with:

```markdown
Write it in one call that also retires the stub and records provenance and attribution:

  ```
  ag-store inbox_shape <stub-id>
  ```

  piping the markdown on stdin. The store creates the spec (`slug` from the frontmatter), links it to the stub, marks the stub `shaped`, copies `captured_by` from the stub and records you as `shaped_by` from the token. Newly shaped specs are unranked; the plan stage creates the spec's directory (`<dir>/specs/<slug>/`) when `plan.md` is written. If the shaping session itself produced supporting material (a sketch, a data sample), it belongs on disk in that directory — note it in the spec body for `/ag-plan` to pick up.
```

Delete the whole `**Attribution (\`airtable\` store only, …)**` sub-bullet (line 93).

"Spike" bullet (line 94): replace `on ship its findings (\`findings.md\` in the spec's directory, or an ADR) move to \`done/\` — satisfying dependencies like any spec.` with `on ship its findings (\`findings.md\` in the spec's directory, or an ADR) stay in the repo and the spec is \`shipped\` in the store — satisfying dependencies like any spec.`

"Split" bullet (line 95): replace with `- **Split** — capture the extra stubs with \`ag-store inbox_add "<text>" --title "<title>" --type "<kind>"\`, or shape several specs from one stub: use \`inbox_shape <stub-id>\` for the first and \`ag-store spec_create <slug>\` (markdown on stdin, with \`source_inbox: <stub-id>\` in the frontmatter) for the rest — one stub may link to several specs by design.`

Line 99: replace `Always **drop the original stub** (\`ag-store inbox_drop <id> --dir "<dir>" --store "<store>"\`) once its fate is decided — the inbox is the list of what still needs shaping.` with `\`inbox_shape\` retires the stub itself. For **Merge** and **Drop**, retire it with \`ag-store inbox_drop <id>\` — the inbox is the list of what still needs shaping.`

Step 6 (line 103): replace `(usually \`/ag-plan <dir>/specs/<slug>.md\`)` with `(usually \`/ag-plan <slug>\`)`.

- [ ] **Step 3: `/ag-inbox`**

Replace lines 13–17 with:

```markdown
1. Resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — exit 2 means the project is not linked: tell the user to run `/ag-init` and stop.
2. List the stubs: `ag-store inbox_list`. The output is a JSON array of `{id, title, type, text, captured_at, captured_by, serves, suggested_kind, duplicate_of}` — parse it directly.
3. Present each stub numbered by its `id`, exactly as captured — including its capture date and `captured_by`. Lead the line with its `title`, tag it with its `type` when that is anything but `feature`, note `serves` when set and flag `duplicate_of` when present, then the full text; the title is a label for scanning, never a replacement for the stub. Do not reword, triage, or summarise them.
4. End with a one-line count and a gentle nudge: e.g. "5 stubs awaiting shaping. Run `/ag-shape <id>` to shape one — or triage them in the app's Inbox." If a stub has sat unshaped for weeks, you may flag it as a candidate to drop.
```

- [ ] **Step 4: Check, test, commit**

```bash
grep -n "airtable\|local\` store\|--store\|whoami\|--by" skills/ag-capture/SKILL.md skills/ag-shape/SKILL.md skills/ag-inbox/SKILL.md || echo clean
ruby dev/test-ag-store-http.rb
git add skills/ag-capture skills/ag-shape skills/ag-inbox
git commit -m "capture/shape/inbox: single store, assist on capture, shape in one call"
```

Expected: `clean`, `ALL PASS`.

---

### Task 6: `/ag-build`, `/ag-next`, `/ag-wip`, `/ag-loop`

**Files:**
- Modify: `skills/ag-build/SKILL.md:3,34-36,49-57,71,80,85-99,104,144-146,152-164`, `skills/ag-next/SKILL.md:9,27-47`, `skills/ag-wip/SKILL.md:13-56`, `skills/ag-loop/SKILL.md` (no change needed — verify)

**Interfaces:**
- Consumes: Task 2's `claim`, `spec_list`, `checkpoint_open/list/answer`, `run_event`, `run_close`, `run_list`, `flow`, `release`, `ship`; the brief preamble from Task 5.
- Produces: unchanged `AG_BUILD:` exit contract; `<checkpoint-path>` in the status line is now the checkpoint **id**.

- [ ] **Step 1: `/ag-build`**

Line 3 description: replace `Every pause is a checkpoint file in the spec's directory, so a factory worker and a person at a terminal run the same skill.` with `Every pause is a checkpoint record in the store, answerable in a session, from another machine, or on the Agentile Projects dashboard, so a factory worker and a person at a terminal run the same skill.`

Replace the `## Run log` section (lines 34–36) with:

```markdown
## Refresh the brief

Before anything else, resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). It rewrites `<dir>/brief.md` from the store so this session reads the current brief, and prints the path. If it exits 2 because the project is not linked (no `.agentile/store.md`, or no token), tell the user to run `/ag-init` (or export `AGENTILE_PROJECTS_TOKEN`) and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.

## Run log

The run log is the store's: `claim` opens a run for this spec and identity, and every event below is `ag-store run_event <event> --spec "<slug>" --runner "<identity>" --detail "<free text>"` (`claimed`, `shipped`, `paused`, `failed`). A run belongs to a spec, so there is nothing to log before a claim succeeds or when the queue is idle — the `AG_BUILD:` line carries those.
```

Replace the `## Tools` section (lines 49–57) with:

```markdown
## Tools

`ag-store` ships in this plugin's `bin/`, on `PATH` while the plugin is enabled (fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). Checkpoints and run events are store records; `ag-store` resolves the run for a `checkpoint_open`/`run_event`/`run_close` from the spec and your identity, so you never handle a run id. Every `ag-store checkpoint_open` call passes `--session "${CLAUDE_SESSION_ID}"` so the dashboard can tie a pause back to the session that wrote it; it prints the checkpoint **id**, which is the `<checkpoint-id>` in the status line.

A headless run must pre-authorise these tools and the gates: `--permission-prompts none` denies anything not on the allowlist rather than asking, so pass e.g. `--allowedTools "Bash(ag-store:*)" "Bash(git:*)"` plus each command in `.agentile/gates.json`. The allowlist matches the command text as typed, so **call each tool by its bare name as the first word of its own command**: never prefix `export PATH=…;` or `cd …;`, never use the absolute path, and never chain several commands with `;` or `&&` in one call. A pipe whose every command is allowed (`printf … | ag-store checkpoint_open …`) is fine. If a bare tool name is not found, end with `AG_BUILD: failed <slug> tool_missing` rather than working around it; after one denial the session denies every later prompt-requiring command.

The **spec directory** is `<dir>/specs/<slug>/` — created by `/ag-plan` (via `ag-store promote`), holding `plan.md`, the `SPEC.md` snapshot and supporting files. Every pause in this skill happens after that.

Every `ag-store checkpoint_open` call also passes `--by <who>`, naming what asked — `plan`, `build`, `verify` or `ship` for a stage checkpoint, and `builder` or `reviewer` for a `question`. It lands as the `asked_by` field, and Step 0 routes an answered `question` by it.

**Record an answer that arrives in chat.** The checkpoint record is the record of the decision; the transcript is not. So when the human answers in conversation rather than in the app — an interactive session where you relayed the ask with `AskUserQuestion`, or where the user simply replied in their next turn — record it before you act on it:

```
printf '%s' "<reply>" | ag-store checkpoint_answer "<checkpoint-id>" --by "<identity>"
```

then proceed exactly as Step 0's routing for an answered checkpoint of that reason. Never act on an unrecorded answer: the dashboard, `/ag-wip` and any later resume read the record.
```

Step 0 (line 71): replace `Run \`ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"\`. If no entry's \`claimed_by\` equals this identity, nothing of yours is in flight: append \`event=started\` and go to Step 1. Otherwise that entry is your spec and you claim nothing this run — take its \`slug\` (the \`<slug>\` every run-log line and status line uses) and its \`route\` from the listing, and derive \`<spec-dir>\` from its identifier (see **Tools**) — that identifier is the \`<id>\` for every later \`ag-store\` call, exactly as in Step 1. Then:` with `Run \`ag-store spec_list --status in_progress\`. If no entry's \`claimed_by\` equals this identity, nothing of yours is in flight: go to Step 1. Otherwise that entry is your spec and you claim nothing this run — take its \`slug\` (the \`<slug>\` every run-event and status line uses, and the \`<id>\` for every later \`ag-store\` call) and its \`route\` from the listing; \`<spec-dir>\` is \`<dir>/specs/<slug>/\`. Then:`

Line 73: replace `- If the spec is still in flat form, or \`<spec-dir>/plan.md\` is absent, go to Step 2.` with `- If \`<spec-dir>/plan.md\` is absent, go to Step 2.`

Line 80 (`gate_failure` route): replace `run \`ag-store release "<id>" --dir "<dir>" --store "<store>"\` or point at \`/ag-abandon <slug>\`, append \`event=failed detail=gate_failure\`` with `run \`ag-store release "<slug>"\` or point at \`/ag-abandon <slug>\`, record \`run_event failed --detail gate_failure\``.

Line 83: replace `Headless, report that it is waiting and end with \`AG_BUILD: paused <slug> <reason> <path>\`.` with `Headless, report that it is waiting and end with \`AG_BUILD: paused <slug> <reason> <checkpoint-id>\`.`

Replace Step 1 (lines 85–95) with:

```markdown
### Step 1 — Claim

Read `wip_limit` from `.agentile/prioritise.md` (default unlimited — pass `0`). Run:

```
ag-store claim "<identity>" "" "<wip_limit>" [--spec "<slug from $ARGUMENTS>"]
```

- A slug → the claim succeeded, and the store has opened this run. Use the slug as `<slug>` and `<id>` everywhere below (run events, status lines, `/ag-plan <slug>`, every other `ag-store` call). Establish the spec's fields now — run `ag-store spec_list --status in_progress` and take the entry whose `claimed_by` is this identity: its `route` is what Step 2 reads; `<spec-dir>` is `<dir>/specs/<slug>/`. Record `run_event claimed`, continue.
- `NONE`, `WIP_FULL`, `BLOCKED`, `UNPRIORITISED` → explain in one line (`/ag-prioritise` for `UNPRIORITISED` or `BLOCKED`, `/ag-wip` for `WIP_FULL`, `/ag-shape` for `NONE`), and end with `AG_BUILD: idle <code>`. Nothing is logged: there is no spec to log against.
- `NOT_FOUND` or `TAKEN` (targeted claim only) → say which slug, and end with `AG_BUILD: failed <slug> <code>`.
```

Step 2 (line 99): replace `Invoke \`/ag-plan <id>\`. Invoked from \`/ag-build\`, it dispatches the \`ag-planner\` subagent, writes \`<spec-dir>/plan.md\`, and returns a short confirmation. Under the \`local\` store this is where a flat spec becomes a directory, so re-read the entry for this identity from \`ag-store spec_list --status in_progress --dir "<dir>" --store "<store>"\` afterwards: \`<spec-dir>\` and the \`<id>\` used from here on come from that refreshed listing.` with `Invoke \`/ag-plan <slug>\`. Invoked from \`/ag-build\`, it dispatches the \`ag-planner\` subagent, creates \`<spec-dir>\`, writes \`plan.md\` and a \`SPEC.md\` snapshot there, and returns a short confirmation.`

Line 104 (plan_review checkpoint command): replace `printf '%s' "<summary>. Review or amend plan.md in place, then answer this checkpoint." | ag-store checkpoint_open "<slug>" plan_review --session "${CLAUDE_SESSION_ID}" --by plan` — unchanged. Line 107: replace `append \`event=paused detail=plan_review\`` with `record \`run_event paused --detail plan_review\`` and `\`AG_BUILD: paused <slug> plan_review <checkpoint-path>\`` with `\`AG_BUILD: paused <slug> plan_review <checkpoint-id>\``.

Throughout Steps 3–5 apply the same two substitutions everywhere they occur: `event=paused detail=<x>` → `run_event paused --detail <x>`; `event=failed detail=<x>` → `run_event failed --detail <x>`; and `<path>` in every `AG_BUILD: paused …` line → `<checkpoint-id>`. (Lines 114, 115, 117, 127, 129, 137: six `<path>` occurrences; lines 114, 115, 117, 127, 129, 137 for the event wording.)

Replace Step 6 items 2–3 (lines 144–145) with:

```markdown
2. `ag-store ship "<slug>"` — sets `status: shipped`, stamps `shipped_at`, keeps the claim fields; the store closes the run.
3. Record `run_event shipped` and commit the spec directory (`plan.md`, `SPEC.md` snapshot, findings) with the ship if it is not already committed.
```

Replace `## Closing the run` (lines 152–164) with:

```markdown
## Closing the run

When the spec ships, fails unrecoverably, or you release the claim, close the run so it drops out of the active view while its history is kept for the flow metrics:

```
ag-store run_close --spec "<slug>" --runner "<identity>" --detail "<why>"
```

A `shipped` or `failed` event already closes the run on its own; `run_close` is for the cases those do not cover — a released claim, an abandoned spec, or a worker that stopped for good.
```

Exit contract (line 172): `AG_BUILD: paused <slug> <reason> <checkpoint-path>` → `AG_BUILD: paused <slug> <reason> <checkpoint-id>`.

Line 181 (`## Questions instead of guesses`): replace `so the item shows on the factory console` with `so the item shows on the dashboard`.

- [ ] **Step 2: `/ag-next`**

Line 9: replace `Safe for concurrent loops — the lock in \`ag-claim\` prevents double-claiming.` with `Safe for concurrent loops — the store claims in one transaction, so two sessions can never take the same spec.`

Replace steps 2–5 (lines 29–45) with:

```markdown
2. Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Read `wip_limit` from `.agentile/prioritise.md` (default: unlimited — pass `0`).

3. Run:

   ```
   ag-store claim "<claim-identity from step 1>" "<optional label from $ARGUMENTS>" "<wip_limit>"
   ```

4. Parse the JSON string result. On success it is the claimed spec's **slug** — what every other `ag-store` op's `<slug>` argument expects, and what `/ag-plan` expects. The store has also opened a run for it. Report: claimed `<slug>` as `<claim-identity>`. If the identity is `${CLAUDE_SESSION_ID}`, tell the user that to resume this loop later they can run `claude --resume <claim-identity>`; if it is `${AGENTILE_RUNNER_ID}`, say instead that it is a named runner, not a session, and point at `/ag-wip` for how to continue it.

   Otherwise:
   - **`NONE`** — no ready work is available. Suggest running `/ag-shape` to shape inbox items or `/ag-prioritise` to rank the backlog.
   - **`WIP_FULL`** — the WIP limit (`<wip_limit>`) is already reached. Suggest shipping or releasing something first, then checking `/ag-wip` to see what is in flight.
   - **`BLOCKED`** — all prioritised ready specs are waiting on unshipped dependencies; no work can be claimed right now. Suggest running `/ag-prioritise` to see which items are blocked and what each is waiting on.
   - **`UNPRIORITISED`** — there is shaped work in the backlog but none of it has been prioritised yet (no rank set). Suggest running `/ag-prioritise` to rank the ready specs so they can be claimed.

5. **v1 behaviour: claim and report only — do NOT auto-start the build cycle.** Tell the user they can now run `/ag-plan <slug>` to begin planning the claimed spec.
```

(Renumber: the old step 6 becomes step 5 as shown.)

- [ ] **Step 3: `/ag-wip`**

Replace steps 1–5 (lines 13–56) with:

```markdown
1. Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — exit 2 means the project is not linked: tell the user to run `/ag-init` and stop.

2. Run `ag-store spec_list --status in_progress` and parse the JSON array.

   Also run `ag-store run_list --status active` — an array of runs `{id, spec, runner_id, session_id, status, started_at, last_event_at}`. A spec listed `in_progress` with **no** active run is a claim whose worker is gone: say so, and point at `ag-store release <slug>` rather than leaving it looking busy.

3. For each in-progress spec, classify `claimed_by`: a Claude session id (a UUID), a factory worker (starts with `factory/`), or another named runner (anything else, e.g. `ag-run@host/12345`, set via `AGENTILE_RUNNER_ID`). Then run `ag-store checkpoint_list "<slug>"` and note the newest checkpoint's `reason` and `status` — the list is oldest first, so the newest is the **last** element. Every branch below ends with the same trailing `[…]` column reporting that checkpoint; when the list comes back empty, the column reads `[running]`. Print:

   ```
   <slug>  in_progress  <label if present, otherwise claimed_by>  (claimed <relative age>)  [waiting: <reason> since <asked_at> | answered: <reason>]
     → resume: claude --resume <claimed_by>
   ```

   for a session id;

   ```
   <slug>  in_progress  factory worker <claimed_by>  (claimed <relative age>)  [waiting: <reason> | running]
     → managed by the Agentile Factory — answer it in the app, or `printf 'reply' | ag-store checkpoint_answer <checkpoint-id> --by <you>`
   ```

   for a factory worker; and

   ```
   <slug>  in_progress  <label if present, otherwise claimed_by>  (claimed <relative age>)  [waiting: <reason> since <asked_at> | answered: <reason>]
     → not a session — claimed by runner "<claimed_by>". Re-run its driver with the
       same AGENTILE_RUNNER_ID to continue it, or export AGENTILE_RUNNER_ID=<claimed_by>
       and run /ag-build interactively to pick it up.
   ```

   for any other named runner. Compute the relative age from `claimed_at` (e.g. "2 h ago", "3 d ago").

4. For each in-progress spec, run `ag-store flow "<slug>"` and print the split beneath it:

   ```
     elapsed <cycle_seconds>  =  agent <agent_seconds>  +  waiting on a human <human_wait_seconds>
   ```

   Format the durations readably (e.g. "3h 12m"). When `open_checkpoint_count` is above zero, name the open checkpoint's `reason` and `asked_by` — that is what the loop is waiting for, and its wait is still counting.

5. Flag any spec whose `claimed_at` timestamp is older than approximately 24 hours with a warning:

   > Likely stale — **release the claim** (`ag-store release <slug>`) to put it back in the queue, or resume it with the command above. Releasing a claim is not abandoning: the spec stays live.

6. Make no changes to any file. The same view, live, is the project dashboard in Agentile Projects.
```

- [ ] **Step 4: `/ag-loop`** — read it; it delegates to `/ag-build` and names no store. No change.

- [ ] **Step 5: Check, test, commit**

```bash
grep -n "airtable\|local\` store\|--store\|<path>\|checkpoint-path\|event=\|runs.md\|flat form\|ag-claim\|ag-checkpoint" skills/ag-build/SKILL.md skills/ag-next/SKILL.md skills/ag-wip/SKILL.md || echo clean
ruby dev/test-ag-run.rb
git add skills/ag-build skills/ag-next skills/ag-wip
git commit -m "build/next/wip: runs and checkpoints are store records; claim opens the run"
```

Expected: `clean`, `ALL PASS`.

---

### Task 7: The remaining skills and `ag-planner`

**Files:**
- Modify: `skills/ag-outcome/SKILL.md:20-24,41-55`, `skills/ag-decompose/SKILL.md:16-19,31-38`, `skills/ag-map/SKILL.md:13,32`, `skills/ag-prioritise/SKILL.md:3,10,30-36,40-48,100-115,134-135`, `skills/ag-plan/SKILL.md:30,32,35-52,54`, `skills/ag-abandon/SKILL.md:11-26,31,38-44,49-56,74,84-92,101-103`, `skills/ag-deploy/SKILL.md:43-51,91-99,106-111`, `skills/ag-retro/SKILL.md:31,35,49,61`, `skills/ag-spec/SKILL.md:29,31,32`, `skills/ag-customise/SKILL.md:16,20`, `agents/ag-planner.md:13,16`, `skills/ag-new-project/SKILL.md` (verify only)

**Interfaces:**
- Consumes: Task 2's CLI; the brief preamble from Task 5; `templates/agentile/deploys.md` from Task 3.
- Produces: no new interfaces.

Use this exact **preamble** wherever a skill's "resolve the store" step is replaced:

```markdown
Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.
```

- [ ] **Step 1: `/ag-outcome`**

Replace Step 1 (lines 20–24) with:

```markdown
## Step 1 — Resolve the store

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`. Read `<dir>/brief.md` — an Outcome should sit inside the brief's constraints and non-goals, and usually elaborates one of its prioritised outcomes.

Run `ag-store outcome_list` and show the existing Outcomes (slug, title, status, rank) so the user does not create a duplicate.
```

Lines 41–47: replace

```markdown
Run `ag-store whoami ...` for attribution, then:

```
ag-store outcome_create <slug> --by "<whoami>" --dir "<dir>" --store "<store>"
```

piping the markdown on stdin. The Outcome is created **unranked**; `/ag-prioritise` ranks it. Then run `ag-store brief_sync ...` so the brief's "Prioritised outcomes" list shows it.
```

with

```markdown
```
ag-store outcome_create <slug>
```

piping the markdown on stdin; the store records you as its creator from the token. The Outcome is created **unranked**; `/ag-prioritise` ranks it, and the app regenerates the brief's "Prioritised outcomes" list from ranked Outcomes.
```

Line 51 (edit mode): replace `Body sections (claim, measure, stop rule, notes) are edited in place: \`<dir>/outcomes/<slug>.md\` for the \`local\` store (offer to make the edit), or the \`Outcomes\` table for \`airtable\` (tell the user which field).` with `Body sections (claim, measure, stop rule, notes) are edited with \`ag-store outcome_write <slug> --set claim="..."\` (keys \`claim\`, \`measure\`, \`stop_rule\`, \`notes\`), or in the app.`

Line 55 (achieve mode): replace `then \`ag-store outcome_achieve <slug> ...\` and \`ag-store brief_sync ...\`.` with `then \`ag-store outcome_achieve <slug>\`.`

- [ ] **Step 2: `/ag-decompose`**

Line 16: replace `- Resolve the **Agentile directory** and store as every skill does (\`.agentile/config.md\`, \`.agentile/store.md\`; \`ag-store --dir "<dir>" --store "<store>"\`, fallback \`"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"\`).` with `- ` + the preamble.

Lines 33–38: replace

```markdown
```
ag-store whoami ...
ag-store inbox_add "<stub text>" --title "<title>" --type "<type>" --serves "<outcome-slug>" --by "<whoami>" --dir "<dir>" --store "<store>"
```

Quote the text so the shell cannot eat an apostrophe. The `local` store drops `--serves` (its inbox is a flat list); the `airtable` store links the stub to the Outcome so provenance survives to `/ag-shape`, which will offer the link as the default `serves`.
```

with

```markdown
```
ag-store inbox_add "<stub text>" --title "<title>" --type "<type>" --serves "<outcome-slug>"
```

Quote the text so the shell cannot eat an apostrophe. The store links the stub to the Outcome so provenance survives to `/ag-shape`, which offers the link as the default `serves`, and records you as the capturer from the token.
```

- [ ] **Step 3: `/ag-map`**

Line 13: replace `1. Resolve the **Agentile directory** and store (\`.agentile/config.md\`, \`.agentile/store.md\`). Run \`ag-store map --dir "<dir>" --store "<store>"\` (bare command; fallback \`"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"\`) and parse the JSON object:` with `1. ` + preamble + ` Run \`ag-store map\` and parse the JSON object:`.

Line 32: `\`ag-store spec_write <slug> --set serves=<real-slug>\`` — unchanged.

- [ ] **Step 4: `/ag-prioritise`**

Line 3 description: replace `Interactively order the ready Agentile specs by assigning dense NNNN- filename prefixes that encode priority rank.` with `Interactively order the ready Agentile specs — the rank is a field in the store; the claim always takes the lowest-ranked claimable spec.`

Line 10: replace the paragraph with `Prioritisation writes a dense rank onto each ready spec in the store (\`ag-store rank\`). The claim always picks the lowest-ranked ready spec whose dependencies are shipped, so the order *is* the work order. This skill is a short interactive conversation that produces that ordering.`

Line 30: `Run \`ag-store outcome_list --status open --dir "<dir>" --store "<store>"\`.` → `Run \`ag-store outcome_list --status open\`.` Line 33: `ag-store outcome_rank <slug-1> <slug-2> ... --dir "<dir>" --store "<store>"` → `ag-store outcome_rank <slug-1> <slug-2> ...`. Line 36: replace `Run \`ag-store brief_sync ...\` after ranking so the brief's list matches.` with `The app regenerates the brief's "Prioritised outcomes" list from this order.`

Replace lines 40–48 with:

```markdown
Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`. Read `<dir>/brief.md` — rank Business Value against its prioritised outcomes rather than gut feel.

Run `ag-store spec_list` and parse the JSON array. Each entry already
```

(so the sentence continues `carries \`slug\`, \`prefix\` (null if unprioritised) …` as before; `prefix` is the store's rank).

Lines 100–115 (Step 5): replace with

```markdown
### Step 5 — Apply the order

Once the user confirms, apply it in one call:

```
ag-store rank <slug-1> <slug-2> ...
```

passing every **ready** slug (previously prioritised and unprioritised alike) in the final confirmed order. The store assigns dense sequential ranks by position in one transaction. **Never pass an in-progress slug** — `ag-store rank` only reorders `status: ready` specs and rejects anything else (409), but omit them from the list regardless so the intent is explicit in what you asked for.
```

Lines 134–135: replace `how many specs were renamed, how many were left untouched (in-progress)` with `how many specs were ranked, how many were left untouched (in-progress)`.

- [ ] **Step 5: `/ag-plan`**

Line 30: replace `Resolve its content with \`ag-store spec_read "<slug>" --dir "<dir>" --store "<store>"\` rather than reading the file directly — under the \`local\` store this is the file's bytes; a shared store has no file to read at all.` with `First ` + preamble + ` Resolve the spec's content with \`ag-store spec_read "<slug>"\` — there is no spec file in the repo to read; the \`SPEC.md\` written below is a snapshot.`

Line 32: replace `passing the spec identifier plus the resolved Agentile directory and store (\`ag-planner\` doesn't inherit your resolved variables — it needs \`<id> --dir <dir> --store <store>\` verbatim in its prompt so it can call \`ag-store spec_read\` itself)` with `passing the spec slug (\`ag-planner\` calls \`ag-store spec_read <slug>\` itself)`.

Replace step 4 (lines 35–52) with:

```markdown
4. **Persist the plan.** Run `ag-store promote "<slug>" --dir "<dir>"` — it ensures the spec's directory `<dir>/specs/<slug>/` exists (idempotent) and returns its path. Write the plan to `<returned-dir>/plan.md` using `.agentile/plan-template.md` as the structure. Supporting material gathered while planning (sketches, notes) belongs in the same directory.

   **Also write a read-only `SPEC.md` snapshot** beside `plan.md`, from `ag-store spec_read`. Without it the directory holds a plan for a spec that cannot be read without a network call and a token — so the builder, the reviewer, and anyone reading the pull request see the approach but not the acceptance criteria the diff has to satisfy. Head the file exactly:

   ```
   <!-- SNAPSHOT — not the source of truth.
        Spec <slug> read from Agentile Projects at <ISO8601>.
        Rank, claim and status live in the store; re-run /ag-plan to refresh.
        Never edit this file: edits are lost, and the store will not see them. -->
   ```

   Regenerate it on every re-plan. Read acceptance criteria from it freely; never read *state* (status, rank, claim) from it — that is what goes stale.
```

Line 54: replace `passing the spec path and \`plan.md\`` with `passing the spec slug, the \`SPEC.md\` snapshot path and \`plan.md\``.

- [ ] **Step 6: `/ag-abandon`**

Lines 11–15: replace `moves out of the active queue into \`specs/abandoned/\`, with the reason recorded.` with `becomes \`abandoned\` in the store, with the reason recorded.` Lines 17–18: replace `You only move specs and edit their frontmatter.` with `You only change spec status and dependencies in the store.`

Replace Step 1 (lines 20–26) with:

```markdown
## Step 1 — Resolve the store

Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — it refreshes `<dir>/brief.md` from the store; exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.
```

Line 31: `run \`ag-store spec_list --dir "<dir>" --store "<store>"\`` → `run \`ag-store spec_list\``. Lines 38–44: `\`ag-store outcome_list ...\`` → `\`ag-store outcome_list\``; `\`ag-store map ...\`` → `\`ag-store map\``; replace `\`ag-store outcome_abandon <slug> --reason "<reason>" --dir "<dir>" --store "<store>"\` and \`ag-store brief_sync ...\`.` with `\`ag-store outcome_abandon <slug> --reason "<reason>"\`.`

Line 49: `ag-store dependents "<target-slug>" --dir "<dir>" --store "<store>"` → `ag-store dependents "<target-slug>"`. Line 74: `ag-store spec_write <dependent-slug> --set depends_on="[<remaining slugs>]" --dir "<dir>" --store "<store>"` → `ag-store spec_write <dependent-slug> --set depends_on="[<remaining slugs>]"`.

Replace Step 6 (lines 78–92) with:

```markdown
## Step 6 — Apply the abandonment

Run one call for the target, listing every dependent the user chose to cascade:

```
ag-store abandon "<slug>" --reason "<reason>" [--cascade "[<dependent-slug>, ...]"]
```

using the user's Step 4 reason. The store sets `status: abandoned`, stamps `abandoned_at`, records the reason, clears the claim fields and closes any active run; each cascaded dependent gets the automatic reason `Abandoned as a consequence of abandoning <target-slug>: <target-reason>`.
```

Lines 101–103: replace `abandoning removes specs from the active queue, so the remaining numbers may be sparse — suggest \`/ag-prioritise\` if the user wants them dense again.` with `abandoning removes specs from the active queue, so the remaining ranks may be sparse — suggest \`/ag-prioritise\` if the user wants them dense again.`

- [ ] **Step 7: `/ag-deploy`**

Replace step 1 (lines 43–51) with:

```markdown
1. **Establish what would go out.** Resolve the **Agentile directory** from `.agentile/config.md` (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) — exit 2 means the project is not linked: tell the user to run `/ag-init` and stop. Read the deploy log `<dir>/deploys.md` (create it from `templates/agentile/deploys.md` if missing) for its last line; the batch is every spec in `ag-store spec_list --pool done` whose `shipped_at` is after that line's timestamp. If the log has no lines, say so — this is the first recorded deploy, so list the shipped specs and let the user confirm the starting point rather than claiming the whole history is undeployed.
```

Replace step 7 (lines 91–99) with:

```markdown
7. **Record it.** Append one line to `<dir>/deploys.md`:

   ```
   - <ISO8601> runner=<identity> target=<target> ref=<git sha> specs=<n> detail=<slugs, comma-separated>
   ```

   The sha is what makes this auditable: the next deploy's batch is computed from this line, and a rollback needs to know exactly what went out. Commit `deploys.md` as part of the deploy.
```

Lines 106–111: replace `name the sha and the previous deployed sha from \`runs.md\`` with `name the sha and the previous deployed sha from \`deploys.md\``, and `Record whichever happens as a new \`event=deployed\` line` with `Record whichever happens as a new line in \`deploys.md\``.

- [ ] **Step 8: `/ag-retro`**

Line 31: replace `First resolve the **Agentile directory** from \`.agentile/config.md\` (default \`docs/agentile/\`) and which store answers this project (\`store:\` in \`.agentile/store.md\`, default \`local\`).` with `First ` + preamble. Line 35: replace `\`ag-store spec_list --dir "<dir>" --store "<store>"\` (active) and \`ag-store spec_list --pool done --dir "<dir>" --store "<store>"\` (shipped)` with `\`ag-store spec_list\` (active) and \`ag-store spec_list --pool done\` (shipped)`, and `\`ag-store flow --dir "<dir>" --store "<store>"\`` with `\`ag-store flow\``. Line 49: `(\`ag-store outcome_list --status open ...\`)` → `(\`ag-store outcome_list --status open\`)`; `(\`ag-store map ...\`)` → `(\`ag-store map\`)`. Line 60: replace `- A **\`brief.md\`** update when the project's outcomes, constraints, or non-goals have shifted — keep the brief living rather than a launch document.` with `- A **brief** update (in the app — \`docs/agentile/brief.md\` is a read-only copy) when the project's outcomes, constraints, or non-goals have shifted.` Line 61: replace `— \`ag-store outcome_achieve <slug> ...\`, or \`/ag-abandon <slug>\` (which cascades to the specs serving it) — followed by \`ag-store brief_sync ...\` so the brief's "Prioritised outcomes" list matches the store.` with `— \`ag-store outcome_achieve <slug>\`, or \`/ag-abandon <slug>\` (which cascades to the specs serving it).`

- [ ] **Step 9: `/ag-spec`**

Line 29: replace `(If the project still uses the old \`Specs directory:\` key or a root-level \`specs/\` with no \`Agentile directory\` key, honour that and note \`/ag-init\` can migrate.) Resolve which store answers this project: read \`store:\` from \`.agentile/store.md\` if it exists, default \`local\`.` with `Run \`ag-store brief_sync --dir "<dir>"\` (bare command; fallback \`"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"\`) — exit 2 means the project is not linked: tell the user to run \`/ag-init\` and stop.` Line 31: `(check \`ag-store outcome_list ...\`)` → `(check \`ag-store outcome_list\`)`; `Write it with \`ag-store spec_create <slug> --dir "<dir>" --store "<store>"\` (bare command; fallback \`"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"\`), piping the markdown on stdin.` → `Write it with \`ag-store spec_create <slug>\`, piping the markdown on stdin; the store records you as \`shaped_by\` from the token.` Line 32: `(\`/ag-plan <path>\`)` → `(\`/ag-plan <slug>\`)`.

- [ ] **Step 10: `/ag-customise`**

Line 16: replace `- \`store\` — not a loop stage in the \`delegate_to\`/\`human_checkpoint\` sense; see the branch below.` with `- \`store\` — not a loop stage; it re-links this repo to a project in Agentile Projects (see below).` Line 20: replace the paragraph with `**If the stage is \`store\`**, skip Steps 2–4 below entirely. Instead run \`skills/ag-init/SKILL.md\`'s Step 2 (link the project: token check, \`whoami\`, choose the project, write \`.agentile/store.md\`, \`doctor\`) and its brief pull from Step 3 exactly as written there, then go straight to this skill's Step 5 to report.`

- [ ] **Step 11: `agents/ag-planner.md`**

Line 13: replace `- The spec you were given: \`ag-store spec_read <id> --dir <dir> --store <store>\` (bare command; fallback \`"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"\`), using exactly the identifier, directory, and store passed in your prompt — never assume it's a local file under \`specs/\` to \`Read\` directly, a shared store (e.g. \`airtable\`) has no such file.` with `- The spec you were given: \`ag-store spec_read <slug>\` (bare command; fallback \`"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"\`) — never assume it's a local file under \`specs/\` to \`Read\` directly; the store has no such file (a \`SPEC.md\` there, if any, is a snapshot from an earlier plan).` Line 16: `(\`ag-store outcome_read <slug> --dir <dir> --store <store>\`)` → `(\`ag-store outcome_read <slug>\`)`.

- [ ] **Step 12: `/ag-new-project`** — read its Step 5 (line 144 onward): it executes `/ag-init`'s procedure with gates pre-filled. Since `/ag-init` no longer asks Solo/Team, confirm no line of `ag-new-project` mentions `Solo`, `Team`, `airtable` or `inbox.md` (`grep -n "Solo\|Team\|airtable\|inbox.md\|runs.md" skills/ag-new-project/SKILL.md`); fix any hit by deleting the sentence. Its "first inbox stubs" step should call `/ag-capture <line> --yes` for each stub — update the wording there if it names `ag-store inbox_add` with `--by` or `--store`.

- [ ] **Step 13: Check, test, commit**

```bash
grep -rn "airtable\|--store\|whoami\|brief_sync \.\.\.\|specs/done\|specs/abandoned\|runs.md\|ag-claim\|ag-checkpoint\|local\` store" skills agents | grep -v "ag-init/SKILL.md" || echo clean
ruby dev/test-ag-store-http.rb
git add skills agents
git commit -m "Skills: single store, brief refresh preamble, deploys.md for deploy records"
```

Expected: `clean`, `ALL PASS`. (`ag-init` legitimately mentions `whoami`; the grep excludes it.)

---

### Task 8: Templates — standing context, config, factory worker

**Files:**
- Rewrite: `templates/CLAUDE.agentile-section.md`
- Modify: `templates/agentile/config.md:5-19`, `templates/agentile/ship.md:7-10`, `templates/agentile/deploy.md:37-39`, `templates/factory-worker.md:6-8`

**Interfaces:**
- Consumes: nothing new.
- Produces: the `CLAUDE.md` section `/ag-init` (Task 4) appends.

- [ ] **Step 1: Rewrite `templates/CLAUDE.agentile-section.md`**

```markdown
## Agentile

This project runs the **Agentile loop** (via Agentile for Claude): capture → shape → spec → plan → build → verify → ship → deploy → learn. Work builds from a written, shaped spec — never from a prompt typed from memory.

### Where things live

The backlog lives in **Agentile Projects**, the web app this repo is linked to by `.agentile/store.md` (`url` + `project`; the token is `AGENTILE_PROJECTS_TOKEN` in the environment). Every skill reads and writes it through `ag-store`; nothing in the loop reads backlog files.

- **Brief** — the living project context: who it's for, the prioritised outcomes, constraints, non-goals. Edited in the app; `docs/agentile/brief.md` is a read-only copy every `/ag-*` skill refreshes, imported below so it loads every session. Business Value in triage is scored against it.
- **Outcomes** — the falsifiable bets above specs: a claim, a measure, a stop rule, ranked. A spec may `serve` one; none is required. Create with `/ag-outcome`, propose the work for one with `/ag-decompose <slug>`, see the whole picture with `/ag-map`.
- **Inbox** — one-line stubs awaiting shaping. Capture freely with `/ag-capture`; the store tidies and classifies, you confirm.
- **Specs** — shaped, Ready-to-build specs (`ready` / `in_progress`). Rank is a field; `shipped` and `abandoned` are statuses. Once a spec starts planning, its `plan.md`, a read-only `SPEC.md` snapshot and supporting files live in this repo at `docs/agentile/specs/<slug>/`. The Definition of Ready is `.agentile/shape.md`.
- **Runs and checkpoints** — every `/ag-build` is a run in the store; every pause is a checkpoint record you can answer in a session, from another machine, or on the project dashboard.
- **Deploy log** (`docs/agentile/deploys.md`) — append-only record of what `/ag-deploy` released, by git sha.
- **ADRs** (`docs/adr/`) — the *why* behind significant decisions.
- **Config** (`.agentile/`) — this project's tailoring: `store.md` (the link), `config.md` (paths + triage), `shape.md` (what Ready means), `gates.json` (deterministic build/test/lint/deploy commands; `deploy` is run only by `/ag-deploy`), and the spec/ADR templates. Any loop stage can be further customised via `.agentile/<stage>.md` (playbook frontmatter: `delegate_to`, `also_run`, `human_checkpoint`).

### How to work

- An idea arrives → `/ag-capture <one line>` (add `--yes` to skip the confirmation). Never lose an idea for lack of a place to put it.
- Thinking above the spec level → `/ag-outcome` to state a bet, `/ag-decompose <slug>` to turn it into stubs, `/ag-map` to see what serves what. Outcomes are ranked by `/ag-prioritise` before specs are.
- Ready to develop something → `/ag-shape` to interview it into a spec, then `/ag-plan` before any code — it writes `plan.md` beside the `SPEC.md` snapshot; review or amend that file, it is the approved plan. Shaping asks about `depends_on` by default — list any specs (by slug) that must ship before this one can be claimed.
- Order the ready queue with `/ag-prioritise` — an interactive session that proposes a rank (Business Value × Technical Certainty, dependencies respected), you adjust it, and it writes the rank to the store. An unranked spec is not claimable. Pull the top item with `/ag-next` — the claim is one transaction in the store and is session-stamped so it can be resumed with `claude --resume <id>`. If the queue is blocked on dependencies or has no ranked specs, `/ag-next` tells you which. Check what's in flight with `/ag-wip` or the dashboard.
- Drop work that won't ship with `/ag-abandon <slug>` — it records why, walks the dependency chain, and offers to cascade-abandon (or unblock) anything that depended on it.
- Build the next spec with **`/ag-build`** (or a named one, `/ag-build <slug>`) — it takes one spec from claim to shipped and stops. It pauses at plan for `foreground`/`spike` specs (review `plan.md`, reply approved) and for your sign-off before ship; each pause is a checkpoint in the store. For many specs at once, use the Agentile Factory or the **`bin/ag-run`** fallback, each of which runs `/ag-build` in a fresh process per item.
- Build on a short-lived branch/worktree; run the gates in `.agentile/gates.json`; a fresh-context reviewer critiques the diff before merge.
- Integrate to trunk in small, reversible, flagged batches. Close the loop with `/ag-retro`.

### Concurrent sessions

Several sessions can run this loop against the same backlog at once — multiple
`/ag-build` workers, a factory run, and an interactive session all claiming and
shipping specs in parallel. That is a supported, expected mode, not an
anomaly:

- Another spec showing `in_progress` under a `claimed_by` that is not you, a
  worktree under `.claude/worktrees/` you did not create, or — in a shared
  checkout — uncommitted changes elsewhere in the tree that belong to
  someone else's build in flight, are all normal. Do not flag any of this to
  the user as if something is wrong, and do not stop to ask about it; just
  proceed with your own claimed work. `/ag-wip` shows exactly what is in
  flight and by whom, if you genuinely need to check.
- The claim itself is race-safe (one transaction in the store). Shipping is
  not automatically race-safe: two sessions merging to the same trunk
  checkout at once can collide. If a merge is rejected because trunk moved
  since you branched, pull/rebase and retry once before treating it as a
  failure — a losing race is expected under concurrency, not an error.

### Rules

- Determinism over instruction: repeatable steps (build, test, lint, deploy) are commands in `.agentile/gates.json`, not hopeful sentences.
- Trust but verify: no agent output merges until it passes tests, static analysis, a security skim, and a human read of the diff.
- Measure flow, not output: if lead time does not drop, the constraint is upstream — fix that, not the agents.

@docs/agentile/brief.md
```

- [ ] **Step 2: `templates/agentile/config.md` Paths section**

Replace lines 5–19 with:

```markdown
## Paths

Where the loop keeps its repo-side artefacts. The backlog itself (stubs, specs, Outcomes, checkpoints, runs, the brief) lives in Agentile Projects — see `store.md`. Change **Agentile directory** if you want the artefacts somewhere other than `docs/agentile/`; the layout under it is fixed:

- `brief.md` — read-only copy of the store's brief, refreshed by every `/ag-*` skill
- `specs/<slug>/` — one directory per planned spec: `plan.md`, the `SPEC.md` snapshot, findings, supporting files
- `deploys.md` — the append-only deploy log `/ag-deploy` writes

The settings:

- **Agentile directory:** `docs/agentile/`
- **ADR directory:** `docs/adr/`
```

- [ ] **Step 3: `templates/agentile/ship.md`, `deploy.md`, `factory-worker.md`**

`ship.md` lines 7–8: replace `Ship is the merge to trunk plus the store bookkeeping: \`status: shipped\`,\n\`shipped_at\` stamped, the spec moved to \`specs/done/\` (local store). Describe` with `Ship is the merge to trunk plus the store bookkeeping: \`status: shipped\`,\n\`shipped_at\` stamped, the run closed. Describe`.

`deploy.md` line 38: `deployed sha in \`runs.md\` precisely so the previous one is always recoverable —` → `deployed sha in \`deploys.md\` precisely so the previous one is always recoverable —`.

`factory-worker.md` line 6: replace `Call \`ag-store\`, \`ag-checkpoint\`, \`git\` and the gate commands by their bare names` with `Call \`ag-store\`, \`git\` and the gate commands by their bare names`. Line 7: replace `- Every human decision is a checkpoint file written with \`ag-checkpoint\`, followed by ending your turn with the \`AG_BUILD: paused …\` status line.` with `- Every human decision is a checkpoint record written with \`ag-store checkpoint_open\`, followed by ending your turn with the \`AG_BUILD: paused …\` status line.` Line 8: replace `an answered checkpoint ("Checkpoint <path> is answered. Read it and continue.")` with `an answered checkpoint ("Checkpoint <id> is answered. Read it and continue.")`.

- [ ] **Step 4: Check, test, commit**

```bash
grep -rn "airtable\|inbox.md\|runs.md\|specs/done\|specs/abandoned\|ag-checkpoint\|ag-claim\|Solo\|Team" templates || echo clean
ruby hooks/test-gates.rb
git add templates
git commit -m "Templates: standing context and config for the single store"
```

Expected: `clean`, `ALL PASS`.

---

### Task 9: Docs and CHANGELOG

**Files:**
- Modify: `README.md:15,17,21,26-42,53,75,77,90-125,128,156,173-184,209,237`, `methodology.md:184,187-189,193`, `docs/agentile-workspaces-participants-and-stores.md` (prepend a status note), `docs/agentile-factory.md` (prepend a status note at §7 and §9), `CHANGELOG.md:7`

**Interfaces:** none.

- [ ] **Step 1: README**

Line 15: `drops a one-line stub in \`docs/agentile/inbox.md\`. Instant, mid-build safe.` → `drops a one-line stub in the project's Inbox in Agentile Projects, tidied and classified by the store; one confirmation (or \`--yes\`). Mid-build safe.`

Line 17: `shaped specs land in \`docs/agentile/specs/\`. \`/ag-spec\` writes one directly for trivial work.` → `shaped specs are records in the store, ranked by a field. \`/ag-spec\` writes one directly for trivial work.`

Line 18: `promotes the spec to its directory form and writes \`plan.md\` beside \`SPEC.md\`` → `creates the spec's directory in the repo and writes \`plan.md\` beside a read-only \`SPEC.md\` snapshot`.

Line 21: `then moves — directory and all — to \`specs/done/\`.` → `and its run closes.`

Replace lines 26–42 (the "whole backlog lives under…" paragraph, the tree, and the promotion paragraph) with:

````markdown
The backlog lives in **Agentile Projects** (`.agentile/store.md` links a repo to its project; see "Stores" below). What stays in the repo, under one configurable **Agentile directory** (`docs/agentile/` by default, set in `.agentile/config.md`), is the code-adjacent material:

```
docs/agentile/
  brief.md                 # read-only copy of the store's brief, refreshed by every /ag-* skill
  specs/
    <slug>/                # created when planning starts
      SPEC.md              #   read-only snapshot of the spec (frontmatter + body)
      plan.md              #   the reviewable plan
      ...                  #   supporting files: designs, notes, findings
  deploys.md               # append-only deploy log
```
````

Line 53 (table row): `| \`.agentile/store.md\` | Where the Inbox and specs live — \`local\` (default, files+git) or \`team\` (a shared datastore, \`airtable\` by default). See "Stores" below. |` → `| \`.agentile/store.md\` | The link to this repo's project in Agentile Projects (\`url\` + \`project\`). See "Stores" below. |`

Line 75: replace `it atomically claims the top unclaimed ready spec under a file lock (\`bin/ag-claim\`), stamps it` with `it atomically claims the top unclaimed ready spec in one store transaction, stamps it`.

Line 77: replace `walks the dependency chain with \`bin/ag-dependents\`` with `walks the dependency chain (\`ag-store dependents\`)` and `Abandoned specs move to \`specs/abandoned/\` with \`status: abandoned\`.` with `Abandoned specs get \`status: abandoned\` in the store.`

Replace the `### Stores` section (lines 90–125) with:

```markdown
### Stores

Since 0.20.0 there is one store: **Agentile Projects**, a web app (multi-user, multi-project, with dashboards, Pundit roles, and the loop's business logic — transactional claim, rank, dependency walks, flow metrics, capture assist — server-side). Every skill that touches the backlog calls `bin/ag-store <op>`, a thin HTTP client over the app's JSON API, so the skills name one command and one output shape.

- `.agentile/store.md` holds `url` (the app; `AGENTILE_PROJECTS_URL` overrides it) and `project` (this repo's project slug). `/ag-init` writes it after asking which of your projects this repo is.
- `AGENTILE_PROJECTS_TOKEN` (an API token from the app's Settings) is an environment variable only, never a tracked file. It identifies you: captures, shapes, claims and answers are attributed from it, and your project role (owner / member / viewer) is what the API authorises against.
- Claim and rank are atomic — one transaction in the app — so two sessions can never take the same spec, and there is no file lock, `.pull.lock` or "pull before you touch the queue".
- `plan.md`, the `SPEC.md` snapshot, findings and ADRs stay in the repo; the brief is edited in the app and mirrored to `docs/agentile/brief.md` read-only.

The `local` (files + git) and `airtable` stores were removed in 0.20.0; `/ag-version` flags a pre-0.20 `store.md`, and `/ag-init` re-links the project. Existing Airtable bases are imported by the app's `agentile:import` task.
```

Line 128: replace `When a spec ships it moves to \`specs/done/\`, keeping the active numbered list clean while remaining resolvable as a fulfilled dependency.` with `When a spec ships its status is \`shipped\` and it satisfies dependencies.`

Line 156: replace `Every pause is a **checkpoint file** in the spec's directory (\`specs/NNNN-<slug>/checkpoints/001-plan_review.md\` and so on), written with \`bin/ag-checkpoint\`. In a session you answer by replying; anywhere else you answer with \`ag-checkpoint answer <path>\` or on the factory console, and the next` with `Every pause is a **checkpoint record** in the store. In a session you answer by replying; anywhere else you answer on the project dashboard in Agentile Projects (or \`printf 'reply' | ag-store checkpoint_answer <id> --by <you>\`), and the next`.

Glossary (lines 173–184): line 174 `**spec** — a shaped, Ready work item: a flat \`NNNN-<slug>.md\` or a \`NNNN-<slug>/SPEC.md\` directory.` → `**spec** — a shaped, Ready work item in the store; once planned it also has a directory \`docs/agentile/specs/<slug>/\` in the repo.`; line 176 `**prioritised** — carries an \`NNNN-\` rank prefix; an unprefixed spec is Ready but not claimable.` → `**prioritised** — has a rank in the store; an unranked spec is Ready but not claimable.`; line 178 `**run log** — \`docs/agentile/runs.md\`: an append-only history …` → `**run** — one \`/ag-build\` session against one spec, recorded in the store with its events (claimed, paused, shipped, failed) — durable across a compaction or a fresh process.`; line 180 `it moves to \`specs/abandoned/\` with the reason.` → `\`status: abandoned\` in the store, with the reason.`; line 181 `the spec moves to \`specs/done/\` and satisfies dependencies.` → `\`status: shipped\`; it satisfies dependencies.`; line 184 `**checkpoint** — a file a paused \`/ag-build\` leaves in the spec's directory (\`checkpoints/NNN-<reason>.md\`) holding what it needs decided; answered in a session, with \`ag-checkpoint answer\`, or on the factory console.` → `**checkpoint** — a record a paused \`/ag-build\` leaves in the store holding what it needs decided; answered in a session, on the project dashboard, or with \`ag-store checkpoint_answer\`.`

Line 209: replace `run \`/ag-init\` to scaffold \`docs/agentile/\` (inbox + specs tree), \`.agentile/\`, \`docs/adr/\`, and the \`CLAUDE.md\` standing-context section. It also asks Solo (files+git, the default) or Team (a shared store, Airtable by default — see "Stores" below) for the backlog. On a project that used the old root-level layout (\`inbox.md\`, \`specs/\`, \`specs/archive/\`), \`/ag-init\` detects it and offers to migrate everything into \`docs/agentile/\` with \`git mv\`.` with `export \`AGENTILE_PROJECTS_TOKEN\` (an API token from Agentile Projects) and run \`/ag-init\` in your target project: it asks which of your projects this repo is, writes \`.agentile/store.md\`, and scaffolds \`.agentile/\`, \`docs/agentile/\`, \`docs/adr/\`, and the \`CLAUDE.md\` standing-context section.`

Line 237: replace `the same portable \`File#flock\` primitive \`ag-claim\` uses for its spec-claim lock; \`/ag-init\` offers to wire it in.` with `a portable \`File#flock\` wrapper; \`/ag-init\` offers to wire it in.`

- [ ] **Step 2: methodology.md table**

Line 184: `\`/ag-capture\` and \`/ag-inbox\`, writing to \`docs/agentile/inbox.md\`` → `\`/ag-capture\` and \`/ag-inbox\`, writing to the Inbox in Agentile Projects`. Line 187: `\`docs/agentile/specs/NNNN-<slug>.md\`, promoted at planning to \`NNNN-<slug>/SPEC.md\` + \`plan.md\`` → `a record in Agentile Projects; at planning, \`docs/agentile/specs/<slug>/\` gains a \`SPEC.md\` snapshot + \`plan.md\``. Line 188: `\`/ag-prioritise\`; the rank is the filename prefix` → `\`/ag-prioritise\`; the rank is a field in the store`. Line 189: `\`/ag-next\` → \`bin/ag-claim\`: a file lock; the session id is the worker handle` → `\`/ag-next\` → \`ag-store claim\`: one transaction in the store; the session id is the worker handle`. Line 193: `merge, stamp \`shipped_at\`, move to \`specs/done/\`` → `merge, stamp \`shipped_at\`, close the run`.

- [ ] **Step 3: Status notes on the two design docs**

Insert after line 1 of `docs/agentile-workspaces-participants-and-stores.md`:

```markdown
> **Status (0.20.0):** §3 "Stores" is superseded. The adapter model (`local`, `airtable`, Jira, Azure DevOps packs) was replaced by a single store, Agentile Projects — see `docs/superpowers/specs/2026-09-21-agentile-projects-design.md`. §1 Workspaces and §2 Participants remain design notes; roles now live in the app (owner / member / viewer).
```

Insert after the `## 7. The console` heading in `docs/agentile-factory.md`:

```markdown
> **Status (0.20.0):** the console pages described here are absorbed by Agentile Projects' dashboards (home and per-project attention/in-progress/up-next). The daemon keeps spawning workers; its checkpoints and runs are the store's records (`ag-store checkpoint_open`/`run_event`), and a checkpoint answered on the dashboard is what resumes a worker.
```

and after the `## 9. Data model` heading:

```markdown
> **Status (0.20.0):** `checkpoints` and the run state live in Agentile Projects (`runs`, `run_events`, `checkpoints`); the daemon's local tables become a cache of process state (pid, pipes) only.
```

- [ ] **Step 4: CHANGELOG**

Insert after line 6 (before `## 0.19.0`):

```markdown
## 0.20.0 — 2026-09-21

- **Agentile Projects is the only backlog store.** The `local` (files + git)
  and `airtable` adapters, `bin/ag-store-adapters/`, `bin/ag-claim`,
  `bin/ag-checkpoint`, `bin/ag-dependents`, `templates/stores/`,
  `templates/inbox.md` and `templates/agentile/runs.md` are gone.
  `bin/ag-store` is now a single-file HTTP client over the app's
  `/api/v1` with the same subcommands and JSON output; `.agentile/store.md`
  holds `url` + `project`, `AGENTILE_PROJECTS_TOKEN` authenticates (and
  attributes — no more `whoami`-by-git-email or `--by`). `--store` is
  obsolete and ignored with a warning.
- **Claim, rank and checkpoint sequencing are transactional, server-side.**
  No `.pull.lock`, no `ag-lock` around the claim; `claim` opens the run;
  `checkpoint_open`/`run_event`/`run_close` resolve the run from the spec
  and your identity, so no skill handles a run id. Runs belong to a spec:
  the spec-less `started`/`idle` events are gone (the `AG_BUILD:` line
  still reports idle).
- **New ops:** `inbox_assist` (tidy + classify a captured line — used by
  `/ag-capture`, which now confirms once or saves with `--yes`) and
  `inbox_shape` (create the spec, retire the stub and record provenance in
  one call — used by `/ag-shape`). `abandon` takes `--cascade`.
- **The brief lives in the app.** `docs/agentile/brief.md` is a read-only
  copy that every `/ag-*` skill refreshes with `ag-store brief_sync`;
  `/ag-outcome`, `/ag-prioritise` no longer sync it by hand.
- **`/ag-init` links a repo to its project** (token check, project pick,
  `doctor`) instead of asking Solo/Team; no `inbox.md`, `runs.md`,
  `specs/done|abandoned`, `outcomes/` or legacy-layout migration. The
  specs tree is just `docs/agentile/specs/<slug>/` for plans and snapshots.
- **`/ag-deploy` records deploys in `docs/agentile/deploys.md`** (new
  template) instead of `runs.md`; the batch is every shipped spec after the
  last line's timestamp.
- `/ag-version` flags a pre-0.20 `store.md`. README, methodology and the
  standing-context template describe the single store; the workspaces/stores
  and factory design docs carry status notes.

```

- [ ] **Step 5: Final grep, tests, commit**

```bash
grep -rn "ag-claim\|ag-checkpoint\|ag-dependents\|ag-store-adapters\|specs/done\|specs/abandoned\|inbox\.md\|runs\.md\|\.pull\.lock\|Solo\b\|\bTeam mode" README.md methodology.md skills agents templates bin hooks dev .claude-plugin | grep -v "^CHANGELOG" || echo clean
ruby dev/test-ag-store-http.rb
ruby hooks/test-gates.rb
ruby dev/test-ag-run.rb
git add README.md methodology.md docs/agentile-workspaces-participants-and-stores.md docs/agentile-factory.md CHANGELOG.md
git commit -m "Docs for 0.20.0: one store, Agentile Projects"
```

Expected: `clean` (a hit in README's "removed in 0.20.0" sentence is acceptable — it names the old stores as history), three `ALL PASS`.

---

### Task 10: Cut-over verification (spec §11, plugin side)

**Files:** none in this repo beyond what the steps below observe.

**Interfaces:**
- Consumes: a running Agentile Projects (local `http://localhost:3400` or the hosted url) with the practice-manager project imported, a token for a member/owner, and this branch dev-linked (`dev/ag-dev-link`).

- [ ] **Step 1: Run the online store tests against the app**

```bash
export AGENTILE_PROJECTS_URL=http://localhost:3400
export AGENTILE_PROJECTS_TOKEN=<token>
export AGENTILE_PROJECTS_TEST_PROJECT=ag-store-test   # a throwaway project you own in the app
ruby dev/test-ag-store-http.rb
```

Expected: `OFFLINE PASS`, `ONLINE PASS`, `ALL PASS`. Any failure here is a contract mismatch between this client and the app — fix on the app side unless the client misreads spec §5.

- [ ] **Step 2: Dev-link this branch and link a fresh clone of the practice manager**

```bash
dev/ag-dev-link
cd "$(mktemp -d)" && git clone git@github.com:keithrowell/demo-app-practice-manager.git pm && cd pm
claude
```

In the session: `/ag-init` → expect the token check to pass, the project list to include the practice-manager project, `store.md` written with `url`/`project`, `docs/agentile/brief.md` pulled, `docs/agentile/specs/` and `docs/adr/` created, the CLAUDE.md section appended, readiness report shown.

- [ ] **Step 3: Capture → shape → prioritise**

`/ag-capture Add a keyboard shortcut to open the search box` → expect one `AskUserQuestion` showing the tidied title/text/kind, then a confirmation line; the stub appears in the app's Inbox without a page reload.

`/ag-shape` → pick the stub → answer the interview → expect `ag-store inbox_shape` to create a `ready` spec and the stub to leave the Inbox.

`/ag-prioritise` → accept the proposed order → expect the app's Specs (ready) view to show the rank.

- [ ] **Step 4: Build to the ship-approval checkpoint**

`/ag-build` → expect: claim (the spec shows `in_progress` and a run appears as active on the project dashboard and the home card), `/ag-plan` writes `docs/agentile/specs/<slug>/plan.md` and `SPEC.md`, builder and reviewer run, then `AG_BUILD: paused <slug> ship_approval <id>` — both dashboards show the project needing attention.

- [ ] **Step 5: Answer in the app, resume, ship**

Answer the checkpoint on the project dashboard ("approved"). Then `claude --resume <session-id>` and `/ag-build` → expect Step 0 to find the answered `ship_approval`, merge, `ag-store ship`, `AG_BUILD: shipped <slug>`; the app shows the run `shipped` and the spec `shipped`; `ag-store flow <slug>` reports one checkpoint with a non-zero `wait_seconds`.

- [ ] **Step 6: Switch the two real repos and merge**

In `~/projects/agentile` and `~/projects/demo-app-practice-manager`, run `/ag-init` (or write `.agentile/store.md` with the real `url`/`project`), commit, and then:

```bash
cd ~/projects/agentile
git checkout main
git merge --no-ff store/agentile-projects -m "Merge store/agentile-projects: Agentile Projects is the only store (0.20.0)"
dev/ag-sync
```

Expected: `dev/ag-sync` validates and installs 0.20.0; `/ag-version` reports `Agentile 0.20.0 (running)`.

---

## Self-review notes

- **Spec coverage.** §6 items: `store.md` shape (T3/T4), single-file client with identical subcommands (T2), deletions (T3), `/ag-init` (T4), `/ag-capture` assist + `--yes` (T5), `/ag-shape` via `inbox_shape` (T5), `/ag-build`/`/ag-next`/`/ag-wip` run handling with `AG_BUILD:` unchanged (T6), brief refresh in every skill (T5–T7), `/ag-outcome` without `brief_sync` (T7), docs and CHANGELOG (T9), version 0.20.0 (T1). §11 plugin steps (T10). One deliberate deviation from §6's list: `/ag-deploy` gains `deploys.md` because `runs.md` is gone and the API has no deploy endpoint — recorded in Global Constraints and the CHANGELOG.
- **Not mapped:** spec §5's `attach` endpoint does not exist and the client drops `attach` (the plan path is a fixed convention); `create_base`/`provision` are gone with Airtable; `/ag-build` no longer logs `started`/`idle`/pre-claim `failed` events because runs belong to a spec — the app's dashboards get "idle" from the last claim result, which is out of this plan's scope.
- **Type consistency.** Every skill uses `ag-store <op>` with the signatures in Task 2's table; run resolution is inside the client; `<checkpoint-id>` replaces `<path>` everywhere in `/ag-build` and `factory-worker.md`; `prefix` in `spec_list` remains the rank (unchanged key).
