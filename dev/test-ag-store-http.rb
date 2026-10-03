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
    @thread = Thread.new do
      loop do
        sock = begin
          @server.accept
        rescue IOError, Errno::EBADF
          break # #close ran: the accept loop's own socket op, not a request — nothing to warn about
        end
        handle(sock)
      end
    end
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

  def close
    @server.close
    @thread.join
  end
end

# Every subcommand call gets a clean slate for the online-vs-offline env vars:
# nil deletes a key from the child's environment even when it's set (e.g.
# exported) in the process running this test file, so a developer running the
# online suite with AGENTILE_PROJECTS_URL/TOKEN exported doesn't leak them into
# the offline section's calls against the fake API — each call's own `env:`
# hash still layers on top and can re-set any of these deliberately.
ISOLATE = { "AGENTILE_PROJECTS_URL" => nil, "AGENTILE_PROJECTS_TOKEN" => nil,
            "AGENTILE_RUNNER_ID" => nil, "CLAUDE_SESSION_ID" => nil }.freeze

def run_store(*args, env: {}, stdin: nil, chdir: Dir.pwd)
  out, err, st = Open3.capture3(ISOLATE.merge(env), "ruby", HELP, *args, stdin_data: stdin.to_s, chdir: chdir)
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

# 6. inbox_add maps --type to kind and --serves to serves, and the optional
#    assist-passthrough flags (--suggested-kind, --duplicate-of, --duplicate-probability)
#    to their API names, omitted when absent; prints the created item's id (the app's
#    {ok, id}), not `true`
api.route("POST", "#{P}/inbox") { |r| b = JSON.parse(r[:body]); [201, { "ok" => true, "id" => 42, "title" => b["title"], "kind" => b["kind"] }] }
with_project(api.url) do |root|
  out = store!("inbox_add", "Rate-limit the login endpoint", "--title", "Login rate limit", "--type", "chore", "--serves", "identity", env: ENV_OK, chdir: root)
  raise "inbox_add should print the new item's id: #{out.inspect}" unless out == 42
  body = JSON.parse(api.requests.last[:body])
  raise "inbox_add body: #{body.inspect}" unless body == { "text" => "Rate-limit the login endpoint", "title" => "Login rate limit", "kind" => "chore", "serves" => "identity" }

  out = store!("inbox_add", "Maybe a dup", "--suggested-kind", "bug", "--duplicate-of", "7", "--duplicate-probability", "0.8", env: ENV_OK, chdir: root)
  raise "inbox_add with assist flags should print the id: #{out.inspect}" unless out == 42
  body = JSON.parse(api.requests.last[:body])
  raise "inbox_add assist-flag body: #{body.inspect}" \
    unless body == { "text" => "Maybe a dup", "suggested_kind" => "bug", "duplicate_of" => "7", "duplicate_probability" => "0.8" }
end

# 7. inbox_assist passes the text; inbox_shape posts markdown from stdin with text/markdown
#    and unwraps the app's full created-spec object down to its slug
api.route("POST", "#{P}/inbox/assist") { |r| [200, { "title" => "T", "text" => JSON.parse(r[:body])["text"], "kind" => "feature" }] }
api.route("POST", "#{P}/inbox/3/shape") { |r| [201, { "slug" => "my-slug", "title" => "My slug", "status" => "ready" }] }
with_project(api.url) do |root|
  out = store!("inbox_assist", "make login faster", env: ENV_OK, chdir: root)
  raise "inbox_assist: #{out.inspect}" unless out["text"] == "make login faster"
  md = "---\ntitle: My slug\nslug: my-slug\nstatus: ready\n---\n\n# My slug\n"
  out = store!("inbox_shape", "3", env: ENV_OK, stdin: md, chdir: root)
  raise "inbox_shape should unwrap the app's object to a slug string: #{out.inspect}" unless out == "my-slug"
  req = api.requests.last
  raise "inbox_shape body/type: #{req.inspect}" unless req[:body] == md && req[:headers]["content-type"].start_with?("text/markdown")
end

# 8. spec_read returns the markdown body as a JSON string; spec_create posts markdown and
#    unwraps the app's full created-spec object down to its slug
api.route("GET", "#{P}/specs/my-slug.md") { [200, "---\nslug: my-slug\n---\n\n# My slug\n"] }
api.route("POST", "#{P}/specs") { |r| [201, { "slug" => "my-slug", "title" => "X", "status" => "ready" }] }
with_project(api.url) do |root|
  out = store!("spec_read", "my-slug", env: ENV_OK, chdir: root)
  raise "spec_read: #{out.inspect}" unless out.start_with?("---\nslug: my-slug")
  out = store!("spec_create", "my-slug", env: ENV_OK, stdin: "---\nslug: my-slug\n---\n# x\n", chdir: root)
  raise "spec_create should unwrap the app's object to a slug string: #{out.inspect}" unless out == "my-slug"
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

# 11. claim posts identity/label[/wip]/slug and prints only the result string (slug or code);
#     wip is included only when the third positional was actually given — omitted means "let
#     the project's own wip_limit apply", an explicit 0 is sent through as "unlimited"
api.route("POST", "#{P}/specs/claim") { |r| b = JSON.parse(r[:body]); [200, { "result" => (b["slug"] || "WIP_FULL"), "run_id" => 42 }] }
with_project(api.url) do |root|
  raise "claim slug" unless store!("claim", "runner-1", "my label", "2", "--spec", "a", env: ENV_OK, chdir: root) == "a"
  body = JSON.parse(api.requests.last[:body])
  raise "claim body wip=2: #{body.inspect}" unless body == { "identity" => "runner-1", "label" => "my label", "wip" => 2, "slug" => "a" }

  store!("claim", "runner-1", "", "0", env: ENV_OK, chdir: root)
  body = JSON.parse(api.requests.last[:body])
  raise "claim body explicit wip=0 (unlimited): #{body.inspect}" unless body == { "identity" => "runner-1", "label" => "", "wip" => 0 }

  raise "claim code" unless store!("claim", "runner-1", "", env: ENV_OK, chdir: root) == "WIP_FULL"
  body = JSON.parse(api.requests.last[:body])
  raise "claim omits wip and slug when neither given: #{body.inspect}" unless body == { "identity" => "runner-1", "label" => "" }
end

# 12. release/ship/abandon (with --reason and optional --cascade); release/ship pass through
#     whatever the app returns — the real app returns a full SpecSummary object, not a bare
#     bool/string, so the fake mirrors that shape instead of asserting against a simplification
api.route("POST", "#{P}/specs/a/release") { [200, { "slug" => "a", "status" => "ready" }] }
api.route("POST", "#{P}/specs/a/ship") { [200, { "slug" => "a", "status" => "shipped", "shipped_at" => "2026-09-22T00:00:00Z" }] }
api.route("POST", "#{P}/specs/a/abandon") { |r| [200, JSON.parse(r[:body])] }
with_project(api.url) do |root|
  raise "release" unless store!("release", "a", env: ENV_OK, chdir: root) == { "slug" => "a", "status" => "ready" }
  raise "ship" unless store!("ship", "a", env: ENV_OK, chdir: root) == { "slug" => "a", "status" => "shipped", "shipped_at" => "2026-09-22T00:00:00Z" }
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

# 13b. promote needs neither url nor token (M2) — it makes no HTTP call, so it must not be
#      gated behind store.md/AGENTILE_PROJECTS_TOKEN the way every networked op is
Dir.mktmpdir do |root|
  FileUtils.mkdir_p(File.join(root, ".agentile")) # no store.md at all
  out, err, st = run_store("promote", "a", "--dir", "docs/agentile", env: { "AGENTILE_PROJECTS_TOKEN" => "" }, chdir: root)
  raise "promote without url/token should still work: #{st.exitstatus} #{err}" \
    unless st.success? && JSON.parse(out) == "docs/agentile/specs/a"
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

# 15. outcomes: list/read/create/write/achieve/abandon; outcome_create unwraps the app's
#     full created-outcome object down to its slug
api.route("GET", "#{P}/outcomes") { |r| [200, [{ "slug" => "o1", "status" => "open", "q" => r[:query] }]] }
api.route("GET", "#{P}/outcomes/o1.md") { [200, "---\nslug: o1\n---\n\n# O1\n"] }
api.route("POST", "#{P}/outcomes") { [201, { "slug" => "o1", "title" => "O1", "status" => "open" }] }
api.route("PATCH", "#{P}/outcomes/o1") { |r| [200, JSON.parse(r[:body])] }
api.route("POST", "#{P}/outcomes/o1/achieve") { [200, "o1"] }
api.route("POST", "#{P}/outcomes/o1/abandon") { |r| [200, JSON.parse(r[:body])] }
with_project(api.url) do |root|
  raise "outcome_list" unless store!("outcome_list", "--status", "open", env: ENV_OK, chdir: root)[0]["q"] == "status=open"
  raise "outcome_read" unless store!("outcome_read", "o1", env: ENV_OK, chdir: root).start_with?("---\nslug: o1")
  raise "outcome_create should unwrap the app's object to a slug string" unless store!("outcome_create", "o1", env: ENV_OK, stdin: "---\nslug: o1\n---\n", chdir: root) == "o1"
  raise "outcome_write" unless store!("outcome_write", "o1", "--set", "rank=2", env: ENV_OK, chdir: root) == { "rank" => "2" }
  raise "outcome_achieve" unless store!("outcome_achieve", "o1", env: ENV_OK, chdir: root) == "o1"
  raise "outcome_abandon" unless store!("outcome_abandon", "o1", "--reason", "stop rule fired", env: ENV_OK, chdir: root) == { "reason" => "stop rule fired" }
end

# 16. run resolution: run_event with no active run creates one, then posts the event and
#     unwraps the app's full run object down to last_event_at; checkpoint_open resolves the
#     run by (spec, runner) and posts the ask from stdin
runs = []
api.route("GET", "#{P}/runs") { |r| q = r[:query]; [200, runs.select { |x| (!q.include?("spec=") || q.include?("spec=#{x['spec']}")) && (!q.include?("status=active") || x["status"] == "active") }] }
api.route("POST", "#{P}/runs") { |r| b = JSON.parse(r[:body]); run = { "id" => runs.size + 1, "spec" => b["spec"], "runner_id" => b["runner_id"], "session_id" => b["session_id"], "status" => "active", "started_at" => "2026-09-21T00:00:00Z" }; runs << run; [201, run] }
api.route("POST", "#{P}/runs/1/events") { |r| [201, { "id" => 1, "spec" => "a", "status" => "active", "last_event_at" => "2026-09-21T00:00:01Z" }] }
api.route("POST", "#{P}/runs/1/checkpoints") { |r| b = JSON.parse(r[:body]); [201, { "id" => 500, "seq" => 1, "ref" => "a #001 #{b['reason']}", "echo" => b }] }
api.route("POST", "#{P}/runs/1/close") { |r| [200, true] }
with_project(api.url) do |root|
  out = store!("run_event", "claimed", "--spec", "a", "--runner", "runner-1", "--detail", "hi", env: ENV_OK, chdir: root)
  raise "run_event should unwrap the app's run object to last_event_at: #{out.inspect}" unless out == "2026-09-21T00:00:01Z"
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

  # run_close against a spec with no live run at all: exit 1 with a message, not a crash
  _o, err, st = run_store("run_close", "--spec", "no-such-run-here", "--runner", "runner-1", env: ENV_OK, chdir: root)
  raise "run_close with no live run should exit 1 and say so: #{st.exitstatus} #{err}" \
    unless st.exitstatus == 1 && err.include?("no active run")
end

# 16b. C1 regression: run_event on a spec whose only run has already ended creates a
#      brand-new (phantom) run, because ensure_run finds nothing under --status active and
#      posts one. This is exactly the bug /ag-build's Unrecoverable-errors path must avoid —
#      by checking `run_list --status active` itself before ever calling run_event — so this
#      asserts the client-side behaviour the skill has to route around, not a client bug to fix.
runs << { "id" => 900, "spec" => "ended-spec", "runner_id" => "runner-1", "session_id" => "sess-1", "status" => "closed", "started_at" => "2026-09-21T00:00:00Z" }
with_project(api.url) do |root|
  before = api.requests.count { |r| r[:method] == "POST" && r[:path] == "#{P}/runs" }
  run_store("run_event", "failed", "--spec", "ended-spec", "--runner", "runner-1", "--detail", "run_ended", env: ENV_OK, chdir: root)
  after = api.requests.count { |r| r[:method] == "POST" && r[:path] == "#{P}/runs" }
  raise "run_event on a spec whose only run has ended should still create a new run (the C1 bug)" unless after == before + 1
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
# (the app renders each prioritised outcome by title, in bold, with no slug — match that shape)
api.route("GET", "#{P}/brief") { [200, "# Brief\n\n## Prioritised outcomes\n\n1. **Ship faster checkout** — Customers abandon checkout when it feels slow.\n"] }
with_project(api.url) do |root|
  out = store!("brief_sync", "--dir", "docs/agentile", env: ENV_OK, chdir: root)
  raise "brief_sync path: #{out.inspect}" unless out == "docs/agentile/brief.md"
  raise "brief_sync content" unless File.read(File.join(root, "docs/agentile/brief.md")).include?("Prioritised outcomes")
end

# 19. whoami hits /me (unscoped); doctor hits the project doctor and the client adds the
#     resolved host itself (I11) so a misdirected url is visible without decoding store.md
api.route("GET", "/api/v1/me") { [200, { "user_id" => 1, "name" => "Keith", "email" => "k@x", "projects" => [{ "slug" => "p", "role" => "owner" }] }] }
api.route("GET", "#{P}/doctor") { [200, { "project" => "p", "role" => "owner", "reachable" => true }] }
with_project(api.url) do |root|
  raise "whoami" unless store!("whoami", env: ENV_OK, chdir: root)["name"] == "Keith"
  doc = store!("doctor", env: ENV_OK, chdir: root)
  raise "doctor" unless doc["reachable"] == true
  raise "doctor should print the resolved host client-side: #{doc.inspect}" unless doc["host"] == "127.0.0.1"
end

# 20. --store is obsolete: warns on stderr, still works; unknown op exits 1
with_project(api.url) do |root|
  out, err, st = run_store("inbox_list", "--store", "airtable", env: ENV_OK, chdir: root)
  raise "--store should warn but succeed: #{st.exitstatus} #{err}" unless st.success? && err.include?("obsolete") && JSON.parse(out).is_a?(Array)
  _o, err, st = run_store("frobnicate", env: ENV_OK, chdir: root)
  raise "unknown op: #{err}" unless st.exitstatus == 1 && err.include?("unknown op")
end

# 21. error paths: 401 exits 2, names AGENTILE_PROJECTS_TOKEN, never the token value;
#     403/409 exit 1 with the app's detail on stderr; a non-JSON 5xx body (an HTML error
#     page, say) exits 1 with stderr truncated to a sane length instead of dumped whole
api.route("POST", "#{P}/inbox/401/drop") { [401, { "error" => "unauthorized", "detail" => "missing or invalid bearer token" }] }
api.route("POST", "#{P}/inbox/403/drop") { [403, { "error" => "forbidden", "detail" => "not a member of this project" }] }
api.route("POST", "#{P}/inbox/409/drop") { [409, { "error" => "conflict", "detail" => "already dropped" }] }
api.route("POST", "#{P}/inbox/555/drop") { [500, "<html><body>#{'Internal Server Error. ' * 30}</body></html>"] }
with_project(api.url) do |root|
  _o, err, st = run_store("inbox_drop", "401", env: ENV_OK, chdir: root)
  raise "401 should exit 2, name the token env var, never the token value: #{st.exitstatus} #{err}" \
    unless st.exitstatus == 2 && err.include?("AGENTILE_PROJECTS_TOKEN") && !err.include?("tok_test")

  _o, err, st = run_store("inbox_drop", "403", env: ENV_OK, chdir: root)
  raise "403 should exit 1 with the detail on stderr: #{st.exitstatus} #{err}" unless st.exitstatus == 1 && err.include?("not a member of this project")

  _o, err, st = run_store("inbox_drop", "409", env: ENV_OK, chdir: root)
  raise "409 should exit 1 with the detail on stderr: #{st.exitstatus} #{err}" unless st.exitstatus == 1 && err.include?("already dropped")

  _o, err, st = run_store("inbox_drop", "555", env: ENV_OK, chdir: root)
  raise "non-JSON 5xx should exit 1 with a truncated stderr message: #{st.exitstatus} #{err.length}" unless st.exitstatus == 1 && err.length < 400
end

# 22. path segments (project, slugs, ids) are URL-encoded — a project slug with a space
#     must reach the fake API already percent-encoded in the request path
api.route("GET", "/api/v1/projects/p%202/inbox") { [200, []] }
Dir.mktmpdir do |root|
  FileUtils.mkdir_p(File.join(root, ".agentile"))
  File.write(File.join(root, ".agentile", "store.md"), "---\nurl: #{api.url}\nproject: p 2\n---\n")
  FileUtils.mkdir_p(File.join(root, "docs", "agentile"))
  out = store!("inbox_list", env: ENV_OK, chdir: root)
  raise "project slug should be url-encoded in the request path" unless out == []
end

# 23. security (I11): a non-https url is refused unless the host is localhost/127.0.0.1 —
#     before any request is sent, exit 2, and the message names the offending host, never
#     the token. Every other offline test above already proves the localhost allowance,
#     since the fake API itself is plain http on 127.0.0.1. AGENTILE_PROJECTS_ALLOW_HTTP=1
#     overrides the check for a non-local host, letting the bad url reach the connection
#     attempt — pointed at a closed local port (bound then immediately released) so that
#     attempt fails fast with ECONNREFUSED instead of the ~5s open_timeout a real
#     unreachable hostname would incur.
with_project("http://evil.example.com") do |root|
  before = api.requests.size
  _o, err, st = run_store("inbox_list", env: ENV_OK, chdir: root)
  raise "non-https, non-local url should exit 2 and name the host, never the token: #{st.exitstatus} #{err}" \
    unless st.exitstatus == 2 && err.include?("evil.example.com") && !err.include?("tok_test")
  raise "should never have sent a request to the refused host" unless api.requests.size == before

  closed = TCPServer.new("127.0.0.1", 0)
  closed_url = "http://127.0.0.1:#{closed.addr[1]}"
  closed.close
  _o, err, st = run_store("inbox_list", env: ENV_OK.merge("AGENTILE_PROJECTS_ALLOW_HTTP" => "1", "AGENTILE_PROJECTS_URL" => closed_url), chdir: root)
  raise "AGENTILE_PROJECTS_ALLOW_HTTP=1 should bypass the scheme/host refusal: #{st.exitstatus} #{err}" \
    unless st.exitstatus == 2 && !err.include?("refusing") && err.include?(closed_url) && !err.include?("tok_test")
end

# 23b. *.localhost is a loopback host too (RFC 6761) — Keith's dev apps are served through
# a local Caddy proxy on stable *.localhost hostnames, so a plain-http url on one of those
# must be accepted without AGENTILE_PROJECTS_ALLOW_HTTP=1, same as localhost/127.0.0.1.
# The fake API is bound to 127.0.0.1, and agentile-projects.localhost resolves to loopback
# on this machine, so pointing the url's host at the *.localhost name while keeping the
# fake API's port reaches the same server.
with_project("http://agentile-projects.localhost:#{api.port}") do |root|
  out = store!("inbox_list", env: ENV_OK, chdir: root)
  raise "*.localhost should be accepted as a loopback host: #{out.inspect}" unless out.is_a?(Array)
end

# 24. checkpoint_open format warnings: advisory only — stderr, exit 0, ask posted unchanged.
#     Reuses section 16's run and checkpoint route (which echoes the posted body).
with_project(api.url) do |root|
  open_ask = lambda do |reason, ask|
    _o, err, st = run_store("checkpoint_open", "a", reason, "--session", "sess-1", "--by", "build", env: ENV_OK, stdin: ask, chdir: root)
    posted = JSON.parse(api.requests.reverse.find { |r| r[:method] == "POST" && r[:path] == "#{P}/runs/1/checkpoints" }[:body])["ask"]
    raise "checkpoint_open must exit 0 and post the ask unchanged (#{reason}): #{st.exitstatus} #{err}" unless st.exitstatus == 0 && posted == ask.strip
    err
  end

  long_one_para = "Blocked because the spec is unclear. " * 8 + "\nOptions:\n1. resume"
  raise "setup: ask should be over 200 chars" unless long_one_para.length > 200 && !long_one_para.match?(/\n[ \t]*\n/)
  err = open_ask.call("build_blocked", long_one_para)
  raise "over-length no-blank-line ask should warn: #{err}" unless err.include?("no blank line") && !err.include?("no Options:")

  err = open_ask.call("build_blocked", "Blocked on the schema.")
  raise "build_blocked without Options should warn: #{err}" unless err.include?("no Options: line") && !err.include?("no blank line")

  err = open_ask.call("gate_failure", "Review still fails. " * 12)
  raise "long ask with no blank line and no Options should give both warnings: #{err}" unless err.include?("no blank line") && err.include?("no Options: line")

  %w[plan_review ship_approval].each do |reason|
    err = open_ask.call(reason, "Short ask with no options.")
    raise "#{reason} is exempt from the Options warning: #{err}" unless err.empty?
  end

  err = open_ask.call("question", "Which one?\n\nOptions:\n1. a (recommended)\n2. b")
  raise "a formatted short ask should not warn: #{err}" unless err.empty?

  fixtures = Dir[File.join(__dir__, "..", "templates", "checkpoint-asks", "*.md")].map { |f| File.basename(f, ".md") }.sort
  expected = %w[build_blocked build_checkpoint gate_failure plan_review question ship_approval verify_checkpoint]
  raise "templates/checkpoint-asks should hold exactly one fixture per reason: #{fixtures.inspect}" unless fixtures == expected
  expected.each do |reason|
    text = File.read(File.join(__dir__, "..", "templates", "checkpoint-asks", "#{reason}.md"))
    err = open_ask.call(reason, text)
    raise "fixture #{reason} should pass the check with no warning: #{err}" unless err.empty?
    raise "fixture #{reason} should have exactly one Options: line" unless text.scan(/\bOptions?\s*:/i).size == 1
    raise "fixture #{reason} should have a --- line" unless text.match?(/^---$/)
  end
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

  # Every claim below is named (--spec) and targets only slugs this run created, so the
  # result is deterministic regardless of whatever else is in tekmore's shared queue
  # (other agents in this session use the same demo project concurrently).
  claimed = store!("claim", env["AGENTILE_RUNNER_ID"], "online", "0", "--spec", slug_a, env: env, chdir: root)
  raise "online claim should take our own A: #{claimed.inspect}" unless claimed == slug_a
  raise "online named claim on our own blocked dependent (B waits on unshipped A) should be BLOCKED" \
    unless store!("claim", env["AGENTILE_RUNNER_ID"], "", "0", "--spec", slug_b, env: env, chdir: root) == "BLOCKED"
  raise "online named claim by another identity on our already-claimed A should be TAKEN" \
    unless store!("claim", "#{env['AGENTILE_RUNNER_ID']}-rival", "", "0", "--spec", slug_a, env: env, chdir: root) == "TAKEN"
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
  raise "online named claim on B after A shipped" \
    unless store!("claim", env["AGENTILE_RUNNER_ID"], "", "0", "--spec", slug_b, env: env, chdir: root) == slug_b
  store!("release", slug_b, env: env, chdir: root)
  flow = store!("flow", slug_a, env: env, chdir: root)
  raise "online flow: #{flow.inspect}" unless flow["checkpoint_count"] == 1 && flow["lead_seconds"].is_a?(Integer)
  store!("abandon", slug_b, "--reason", "online test cleanup", env: env, chdir: root)
  raise "online abandon" unless store!("spec_list", "--pool", "abandoned", env: env, chdir: root).any? { |s| s["slug"] == slug_b }

  # outcomes + map + brief
  o = "#{tag}-o"
  outcome_title = "Outcome #{tag}"
  store!("outcome_create", o, env: env, stdin: "---\ntitle: #{outcome_title}\nslug: #{o}\nstatus: open\n---\n\n# #{outcome_title}\n\n## Claim\n\nc\n\n## Measure\n\nm\n\n## Stop rule\n\ns\n\n## Notes\n\n", chdir: root)
  raise "online outcome_read" unless store!("outcome_read", o, env: env, chdir: root).include?("## Measure")
  store!("outcome_rank", o, env: env, chdir: root)
  raise "online map" unless store!("map", env: env, chdir: root)["outcomes"].any? { |x| x["slug"] == o }
  # the app's brief renders outcomes by title, not slug — assert on the title we gave it
  raise "online brief_sync" unless File.read(File.join(root, store!("brief_sync", "--dir", "docs/agentile", env: env, chdir: root))).include?(outcome_title)
  store!("outcome_abandon", o, "--reason", "online test cleanup", env: env, chdir: root)
end
puts "ONLINE PASS"
puts "ALL PASS"
