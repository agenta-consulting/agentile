# frozen_string_literal: true
# Conformance suite for the Agentile Store Protocol (docs/store-protocol.md).
#
# Drives bin/ag-store, the client every skill uses, against one store and checks
# that it behaves as protocol 1 says. With no arguments it tests the bundled local
# store in a temp dir, so it doubles as that store's test suite.
#
#   ruby dev/test-store-conformance.rb
#   ruby dev/test-store-conformance.rb --url exec:./my-store --project scratch
#   AGENTILE_STORE_TOKEN=… ruby dev/test-store-conformance.rb --url https://store.example --project scratch [--allow-gaps]
#
# Against a real store, point it at an empty scratch project: it creates specs,
# outcomes and stubs with a random suffix and never deletes anything, and the queue
# checks assume no other ready specs. --allow-gaps reports the checks tagged with a
# known gap (§12 of the protocol, G1…) as warnings instead of failures.
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require "securerandom"

AG_STORE = File.expand_path("../bin/ag-store", __dir__)

opts = { url: nil, project: "conformance", allow_gaps: false }
args = ARGV.dup
while (a = args.shift)
  case a
  when "--url" then opts[:url] = args.shift
  when "--project" then opts[:project] = args.shift
  when "--allow-gaps" then opts[:allow_gaps] = true
  else abort "usage: test-store-conformance.rb [--url <store url>] [--project <slug>] [--allow-gaps]"
  end
end

ROOT = Dir.mktmpdir("ag-conformance")
at_exit { FileUtils.rm_rf(ROOT) }
FileUtils.mkdir_p(File.join(ROOT, ".agentile"))
url = opts[:url] || "local:#{File.join(ROOT, 'store-data')}"
File.write(File.join(ROOT, ".agentile/store.md"), "---\nurl: #{url}\nproject: #{opts[:project]}\n---\n")
X = SecureRandom.hex(3)
ENV_BASE = { "AGENTILE_RUNNER_ID" => nil, "CLAUDE_SESSION_ID" => nil, "AGENTILE_MODEL" => nil,
             "AGENTILE_STORE_URL" => nil, "AGENTILE_PROJECTS_URL" => nil }.freeze

Result = Struct.new(:out, :err, :code) do
  def ok? = code.zero?
  def json = JSON.parse(out)
end

def ag(*argv, stdin: nil, env: {})
  out, err, st = Open3.capture3(ENV_BASE.merge(env), "ruby", AG_STORE, *argv.map(&:to_s), stdin_data: stdin.to_s, chdir: ROOT)
  Result.new(out, err, st.exitstatus)
end

def ag!(*argv, **kw)
  r = ag(*argv, **kw)
  raise "ag-store #{argv.join(' ')} exited #{r.code}: #{r.err.strip}" unless r.ok?

  r.json
end

$results = []
def check(name, gap: nil)
  yield
  $results << [ :pass, name, gap ]
rescue StandardError => e
  $results << [ :fail, name, gap, e.message ]
end

def expect(cond, msg) = (raise msg unless cond)
def expect_status(r, status, msg)
  expect(!r.ok? && r.err.include?(status.to_s), "#{msg}: expected #{status}, got exit #{r.code} #{r.err.strip[0, 160]} #{r.out.strip[0, 120]}")
end

def spec_md(slug, title, extra = {})
  fm = { "slug" => slug, "title" => title }.merge(extra).map { |k, v| "#{k}: #{v.is_a?(Array) ? "[#{v.join(', ')}]" : v}" }
  <<~MD
    ---
    #{fm.join("\n")}
    ---

    # #{title}

    ## Problem / why now

    Because the suite says so.

    ## Acceptance criteria

    - It conforms.

    ## Scope boundary

    **In scope:** the protocol

    **Out of scope:** everything else

    ## Edge cases and failure paths

    None.

    ## Affected areas

    app/models

    ## Open questions

    None.

    ## Verification

    Run the suite.
  MD
end

def outcome_md(slug, title)
  "---\nslug: #{slug}\ntitle: #{title}\n---\n\n# #{title}\n\n## Claim\n\nIt works.\n\n## Measure\n\nThe suite passes.\n\n## Stop rule\n\nIt fails twice.\n\n## Notes\n\n"
end

a = "conf-a-#{X}"
b = "conf-b-#{X}"
c = "conf-c-#{X}"
d = "conf-d-#{X}"
o = "conf-o-#{X}"
o2 = "conf-p-#{X}"
sha = "3f9c2a1"

# ------------------------------------------------------------- identity --
check("doctor reports protocol 1, a store name and capabilities", gap: "G10") do
  r = ag!("doctor")
  expect(r["protocol"] == 1, "protocol: #{r['protocol'].inspect}")
  expect(r["store"].is_a?(String) && !r["store"].empty?, "store: #{r['store'].inspect}")
  expect(r["capabilities"].is_a?(Array), "capabilities: #{r['capabilities'].inspect}")
  expect(r["reachable"] == true && r["project"] == opts[:project], "project/reachable: #{r.inspect}")
end

check("whoami lists the project") do
  r = ag!("whoami")
  expect(r["projects"].any? { |p| p["slug"] == opts[:project] }, "projects: #{r['projects'].inspect}")
end

# ------------------------------------------------------------- outcomes --
check("outcome create, read and list") do
  expect(ag!("outcome_create", stdin: outcome_md(o, "Conformance outcome")) == o, "create should print the slug")
  md = ag!("outcome_read", o)
  expect(md.include?("## Claim") && md.include?("It works.") && md.include?("status: open"), "markdown: #{md[0, 200]}")
  expect(ag!("outcome_list").any? { |x| x["slug"] == o && x.key?("created") }, "list should include it with `created`")
end

check("outcome create refuses a malformed slug", gap: "G7") do
  expect_status(ag("outcome_create", stdin: outcome_md("Bad Slug #{X}", "Bad")), 422, "malformed outcome slug")
end

check("outcome create refuses a non-open status", gap: "G14") do
  expect_status(ag("outcome_create", stdin: "---\nslug: conf-q-#{X}\ntitle: Q\nstatus: achieved\n---\n"), 422, "achieved at create")
end

# ---------------------------------------------------------------- inbox --
stub = nil
check("inbox add, list and assist") do
  stub = ag!("inbox_add", "Conformance stub #{X}. With a second sentence.", "--serves", o)
  expect(stub.is_a?(Integer), "inbox_add should print an integer id, got #{stub.inspect}")
  item = ag!("inbox_list").find { |i| i["id"] == stub }
  expect(item && item["title"] == "Conformance stub #{X}" && item["serves"] == o && item["status"] == "open", "item: #{item.inspect}")
  as = ag!("inbox_assist", "fix the broken login page #{X}")
  %w[title text kind serves_outcome_slug duplicate_of duplicate_of_type duplicate_probability judgment_id].each do |k|
    expect(as.key?(k), "assist is missing #{k}: #{as.inspect}")
  end
end

check("shape turns a stub into a spec in one step") do
  slug = ag!("inbox_shape", stub, stdin: spec_md(a, "Conformance A", "shaped_against" => sha, "serves" => o, "tags" => [ "conf-#{X}" ], "route" => "background"))
  expect(slug == a, "shape should print the slug, got #{slug.inspect}")
  expect(ag!("inbox_list", "--status", "shaped").any? { |i| i["id"] == stub }, "the stub should be shaped")
end

check("shaping a stub twice is refused", gap: "G12") do
  expect_status(ag("inbox_shape", stub, stdin: spec_md("conf-z-#{X}", "Z")), 409, "second shape")
end

check("drop is idempotent for a dropped stub") do
  s2 = ag!("inbox_add", "Conformance drop #{X}")
  expect(ag!("inbox_drop", s2) == true, "drop should print true")
  expect(ag("inbox_drop", s2).ok?, "dropping a dropped stub should succeed")
end

check("dropping a shaped stub is refused", gap: "G12") do
  expect_status(ag("inbox_drop", stub), 409, "dropping a shaped stub")
end

# ---------------------------------------------------------------- specs --
check("canonical markdown round-trips, shaped_against included", gap: "G11") do
  md = ag!("spec_read", a)
  %w[## Problem\ /\ why\ now ## Acceptance\ criteria **In\ scope:**\ the\ protocol ## Verification].each do |frag|
    expect(md.include?(frag), "spec markdown lacks #{frag.inspect}")
  end
  expect(md.include?("serves: #{o}") && md.include?("status: ready"), "frontmatter: #{md[0, 300]}")
  expect(md.include?("shaped_against: #{sha}"), "shaped_against was dropped")
end

check("SpecSummary carries rank, prefix and type") do
  s = ag!("spec_list").find { |x| x["slug"] == a }
  expect(s, "spec_list should include #{a}")
  %w[rank prefix type path depends_on claimed_by tags serves].each { |k| expect(s.key?(k), "summary lacks #{k}: #{s.keys}") }
  expect(s["path"] == "docs/agentile/specs/#{a}", "path: #{s['path']}")
end

check("spec create with dependencies; deps and dependents") do
  expect(ag!("spec_create", stdin: spec_md(b, "Conformance B", "depends_on" => [ a ])) == b, "create b")
  expect(ag!("spec_create", stdin: spec_md(c, "Conformance C", "depends_on" => [ b ])) == c, "create c")
  expect(ag!("deps", c) == [ b ], "deps c")
  expect(ag!("dependents", a) == [ b, c ].sort, "dependents a: transitive, sorted")
end

check("spec create refuses duplicates, bad slugs and blank titles") do
  expect_status(ag("spec_create", stdin: spec_md(a, "Again")), 422, "duplicate slug")
  expect_status(ag("spec_create", stdin: spec_md("Not A Slug", "x")), 422, "bad slug")
  expect_status(ag("spec_create", stdin: "---\nslug: conf-t-#{X}\n---\n\nno heading\n"), 422, "blank title")
end

check("spec create refuses an unknown dependency or outcome") do
  expect_status(ag("spec_create", stdin: spec_md("conf-u-#{X}", "U", "depends_on" => [ "nope-#{X}" ])), 404, "unknown depends_on")
  expect_status(ag("spec_create", stdin: spec_md("conf-v-#{X}", "V", "serves" => "nope-#{X}")), 404, "unknown serves")
end

check("spec create accepts only status ready", gap: "G2") do
  expect_status(ag("spec_create", stdin: spec_md("conf-w-#{X}", "W", "status" => "shipped")), 422, "shipped at create")
end

check("spec_write updates fields and refuses status and rank") do
  r = ag!("spec_write", b, "--set", "tags=[x-#{X}, y-#{X}]", "--set", "route=spike")
  expect(r["tags"].sort == [ "x-#{X}", "y-#{X}" ] && r["route"] == "spike", "patched: #{r.inspect}")
  expect_status(ag("spec_write", b, "--set", "status=shipped"), 422, "status via PATCH")
  expect_status(ag("spec_write", b, "--set", "rank=1"), 422, "rank via PATCH")
end

check("spec_write keeps shaping context", gap: "G11") do
  r = ag!("spec_write", b, "--set", "shaped_against=#{sha}", "--set", "shaped_at=2026-10-12T00:00:00Z")
  expect(r["shaped_against"] == sha, "shaped_against: #{r['shaped_against'].inspect}")
end

check("dependencies refuse self-reference and cycles", gap: "G8") do
  # Throwaway specs, so a store that wrongly accepts the cycle does not block
  # the specs the queue checks below depend on.
  s1 = "conf-s-#{X}"
  s2 = "conf-t-#{X}"
  ag!("spec_create", stdin: spec_md(s1, "Cycle S"))
  ag!("spec_create", stdin: spec_md(s2, "Cycle T", "depends_on" => [ s1 ]))
  expect_status(ag("spec_write", s1, "--set", "depends_on=[#{s1}]"), 422, "self dependency")
  expect_status(ag("spec_write", s1, "--set", "depends_on=[#{s2}]"), 422, "cycle s -> t -> s")
end

# ---------------------------------------------------------------- claim --
check("an unranked queue is UNPRIORITISED") do
  expect(ag!("claim", "conf-1", "", "0") == "UNPRIORITISED", "queue of unranked specs")
end

check("rank writes dense ranks in the given order") do
  r = ag!("rank", b, a)
  expect(r["ranked"].first(2) == [ b, a ], "ranked: #{r.inspect}")
  expect(ag!("spec_list").select { |x| [ a, b ].include?(x["slug"]) }.sort_by { |x| x["rank"] }.map { |x| x["slug"] } == [ b, a ], "ranks")
end

check("the queue skips a blocked spec and takes the next eligible one") do
  expect(ag!("claim", "conf-1", "label-1", "0") == a, "b is blocked by a, so a is next")
end

check("claim opens a run with started and claimed events") do
  runs = ag!("run_list", "--spec", a, "--status", "active")
  expect(runs.size == 1, "one live run: #{runs.size}")
  expect(runs[0]["runner_id"] == "conf-1" && runs[0]["events"].map { |e| e["event"] } == %w[started claimed], "run: #{runs[0].inspect}")
  s = ag!("spec_list").find { |x| x["slug"] == a }
  expect(s["status"] == "in_progress" && s["claimed_by"] == "conf-1" && s["label"] == "label-1", "claim fields: #{s.inspect}")
end

check("claim results: WIP_FULL, BLOCKED, TAKEN, NOT_FOUND") do
  expect(ag!("claim", "conf-2", "", "1") == "WIP_FULL", "wip 1 with one in progress")
  expect(ag!("claim", "conf-2", "", "0", "--spec", c) == "BLOCKED", "c waits on b")
  expect(ag!("claim", "conf-2", "", "0", "--spec", a) == "TAKEN", "a is held by conf-1")
  expect(ag!("claim", "conf-2", "", "0", "--spec", "nope-#{X}") == "NOT_FOUND", "unknown slug")
end

check("a repeated claim by the holder returns the spec", gap: "G3") do
  expect(ag!("claim", "conf-1", "", "0", "--spec", a) == a, "re-claim by the holder")
end

# ---------------------------------------------------------- checkpoints --
cp = nil
check("a checkpoint pauses the run; answering resumes it") do
  cp = ag!("checkpoint_open", a, "question", "--by", "builder", "--runner", "conf-1",
           stdin: "Which way?\n\nOptions:\n- A\n- B", env: { "AGENTILE_RUNNER_ID" => "conf-1" })
  expect(cp.is_a?(Integer), "checkpoint_open should print an id: #{cp.inspect}")
  expect(ag!("checkpoint_open_count", a) == 1, "one open checkpoint")
  run = ag!("run_list", "--spec", a, "--status", "active").first
  expect(run && run["status"] == "paused", "run should be paused: #{run.inspect}")
  list = ag!("checkpoint_list", a)
  expect(list.first["ref"] == format("%s #%03d %s", a, 1, "question") && list.first["status"] == "open", "ref: #{list.first.inspect}")
  ans = ag!("checkpoint_answer", cp, "--by", "nobody@example.com", stdin: "A")
  expect(ans["status"] == "answered" && ans["answer"] == "A", "answer: #{ans.inspect}")
  run = ag!("run_list", "--spec", a, "--status", "active").first
  expect(run && run["status"] == "active", "run should be active again: #{run.inspect}")
end

check("a second answer is refused") do
  expect_status(ag("checkpoint_answer", cp, stdin: "B"), 409, "second answer")
end

# ----------------------------------------------------------------- ship --
check("ship stamps the spec and closes its run") do
  r = ag!("ship", a)
  expect(r["status"] == "shipped" && r["shipped_at"], "ship: #{r.inspect}")
  expect(ag!("spec_list", "--pool", "done").any? { |x| x["slug"] == a }, "a in the done pool")
  run = ag!("run_list", "--spec", a).first
  expect(run["status"] == "shipped" && run["ended_at"], "run: #{run.inspect}")
end

check("a shipped spec cannot be shipped again or released", gap: "G1") do
  expect_status(ag("ship", a), 409, "second ship")
  expect_status(ag("release", a), 409, "release of a shipped spec")
end

check("flow reports the cycle and the human wait") do
  f = ag!("flow", a)
  expect(f["checkpoint_count"] == 1 && f["open_checkpoint_count"].zero?, "checkpoints: #{f.inspect}")
  expect(f["lead_seconds"].is_a?(Integer) && f["cycle_seconds"].is_a?(Integer) && f["human_wait_seconds"].is_a?(Integer), "durations: #{f.inspect}")
end

check("shipping a dependency unblocks its dependent; release is idempotent") do
  expect(ag!("claim", "conf-3", "", "0", "--spec", b) == b, "b is claimable once a shipped")
  expect(ag!("release", b)["status"] == "ready", "release b")
  expect(ag("release", b).ok?, "releasing a ready spec again should succeed")
  expect(ag!("run_list", "--spec", b, "--status", "active").empty?, "release closes the run")
end

check("events need a live run", gap: "G6") do
  expect_status(ag("run_event", "claimed", "--spec", b, "--runner", "conf-9"), 409, "a run for a ready spec")
end

# -------------------------------------------------------------- abandon --
check("abandon cascades the same reason, without recursion") do
  r = ag!("abandon", b, "--reason", "conformance #{X}", "--cascade", "[#{c}, nope-#{X}]")
  expect(r["slug"] == b && r["status"] == "abandoned", "target: #{r.inspect}")
  gone = ag!("spec_list", "--pool", "abandoned").select { |x| [ b, c ].include?(x["slug"]) }
  expect(gone.size == 2, "both abandoned: #{gone.map { |x| x['slug'] }}")
  expect(ag!("spec_read", c).include?("abandoned_reason: conformance #{X}"), "c carries the same reason")
end

check("an abandoned spec cannot be abandoned again", gap: "G1") do
  expect_status(ag("abandon", b, "--reason", "again"), 409, "second abandon")
end

check("abandon needs a reason") do
  ag!("spec_create", stdin: spec_md(d, "Conformance D"))
  expect_status(ag("abandon", d, "--reason", ""), 422, "blank reason")
end

# ----------------------------------------------------------- concurrency --
check("concurrent claims of one spec: exactly one wins") do
  # Several rounds of many racers: process start-up jitter is large next to a
  # store's critical section, so one round of a few racers rarely collides even
  # against a store with no locking at all.
  racers = []
  5.times do |round|
    slug = "conf-r#{round}-#{X}"
    ag!("spec_create", stdin: spec_md(slug, "Race #{round}"))
    results = Array.new(12) { |i| Thread.new { ag("claim", "racer-#{round}-#{i}", "", "0", "--spec", slug).out.strip } }.map(&:value)
    winners = results.count { |x| x == "\"#{slug}\"" }
    expect(winners == 1, "round #{round}: #{winners} winners: #{results.tally.inspect}")
    expect(results.all? { |x| [ "\"#{slug}\"", "\"TAKEN\"" ].include?(x) }, "losers should see TAKEN: #{results.tally.inspect}")
    holders = ag!("run_list", "--spec", slug, "--status", "active")
    expect(holders.size == 1, "round #{round}: #{holders.size} live runs")
    racers << slug
  end
end

# ------------------------------------------------------------- outcomes --
check("map groups specs under outcomes and tags") do
  m = ag!("map")
  expect(m.keys.first(4) == %w[outcomes unlinked orphaned tags], "key order: #{m.keys}")
  entry = m["outcomes"].find { |x| x["slug"] == o }
  expect(entry && entry["specs"]["shipped"].include?(a), "outcome entry: #{entry.inspect}")
  expect(m["tags"]["conf-#{X}"] == [ a ], "tags: #{m['tags'].inspect}")
end

check("brief lists open outcomes in rank order") do
  ag!("outcome_create", stdin: outcome_md(o2, "Second conformance outcome"))
  ag!("outcome_rank", o2, o)
  path = ag!("brief_sync", "--dir", "docs/agentile")
  text = File.read(File.join(ROOT, path))
  expect(text.include?("## Prioritised outcomes") && text.index("Second conformance outcome") < text.index("Conformance outcome"), "brief: #{text[0, 300]}")
end

check("outcome achieve is a one-way door", gap: "G4") do
  expect(ag!("outcome_achieve", o)["status"] == "achieved", "achieve")
  expect_status(ag("outcome_achieve", o), 409, "second achieve")
  expect_status(ag("outcome_abandon", o, "--reason", "late"), 409, "abandon after achieve")
end

check("brief_write replaces the brief", gap: "G13") do
  expect(ag("brief_write", stdin: "# Conformance brief #{X}\n\nFor the suite.\n").ok?, "brief_write")
  text = File.read(File.join(ROOT, ag!("brief_sync", "--dir", "docs/agentile")))
  expect(text.start_with?("# Conformance brief #{X}") && text.include?("## Prioritised outcomes"), "brief: #{text[0, 200]}")
end

check("unknown resources are 404") do
  expect_status(ag("spec_read", "nope-#{X}"), 404, "unknown spec")
  expect_status(ag("outcome_read", "nope-#{X}"), 404, "unknown outcome")
end

# --------------------------------------------------------------- report --
gaps_seen = []
failures = 0
$results.each do |status, name, gap, msg|
  tag = gap ? " [#{gap}]" : ""
  if status == :pass
    puts "  ok    #{name}#{tag}"
  elsif gap && opts[:allow_gaps]
    gaps_seen << gap
    puts "  GAP   #{name}#{tag}\n        #{msg}"
  else
    failures += 1
    puts "  FAIL  #{name}#{tag}\n        #{msg}"
  end
end
passed = $results.count { |r| r[0] == :pass }
puts "\n#{passed}/#{$results.size} checks pass against #{url} (project #{opts[:project]})" \
     "#{gaps_seen.empty? ? '' : "; known gaps: #{gaps_seen.uniq.join(', ')}"}"
puts(failures.zero? ? "CONFORMS" : "DOES NOT CONFORM (#{failures} failure#{'s' unless failures == 1})")
exit(failures.zero? ? 0 : 1)
