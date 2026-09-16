require "yaml"; require "date"; require "tmpdir"; require "open3"; require "fileutils"; require "json"
HELP = File.expand_path("../bin/ag-store", __dir__)

def store(*args, dir:, stdin: nil)
  cmd = ["ruby", HELP, *args, "--dir", dir]
  out, err, st = Open3.capture3(*cmd, stdin_data: stdin.to_s)
  raise "ag-store #{args.first} failed (#{st.exitstatus}): #{err}" unless st.success?

  JSON.parse(out)
end

def frontmatter(path)
  YAML.safe_load(File.read(path)[/\A---\n(.*?)\n---/m, 1], permitted_classes: [Time, Date])
end

def scaffold(root)
  agentile_dir = File.join(root, "docs", "agentile")
  FileUtils.mkdir_p(File.join(agentile_dir, "specs", "done"))
  FileUtils.mkdir_p(File.join(agentile_dir, "specs", "abandoned"))
  File.write(File.join(agentile_dir, "inbox.md"), "# Inbox (stubs awaiting shaping)\n\n")
  agentile_dir
end

def write_spec(specs_dir, fname, status: "ready", extra: {})
  fields = { "title" => "Test spec", "slug" => fname.sub(/\A\d+-/, "").sub(/\.md\z/, ""),
             "status" => status, "created" => "2026-06-10", "depends_on" => [],
             "claimed_by" => nil, "label" => nil, "claimed_at" => nil }.merge(extra)
  fm = fields.map { |k, v| "#{k}: #{v.is_a?(Array) ? "[#{v.join(', ')}]" : v}" }.join("\n")
  File.write(File.join(specs_dir, fname), "---\n#{fm}\n---\n# Test\n\n## Acceptance criteria\n\n- [ ] works\n")
end

# 1. inbox_add / inbox_list / inbox_drop round-trip
Dir.mktmpdir do |root|
  dir = scaffold(root)
  store("inbox_add", "Rate-limit the login endpoint", dir: dir)
  store("inbox_add", "Export to CSV", dir: dir)
  stubs = store("inbox_list", dir: dir)
  raise "inbox_list count: #{stubs.inspect}" unless stubs.size == 2
  raise "inbox text: #{stubs.inspect}" unless stubs[0]["text"] == "Rate-limit the login endpoint"
  raise "inbox captured_at: #{stubs.inspect}" if stubs[0]["captured_at"].nil?

  store("inbox_drop", stubs[0]["id"], dir: dir)
  remaining = store("inbox_list", dir: dir)
  raise "inbox_drop: #{remaining.inspect}" unless remaining.size == 1 && remaining[0]["text"] == "Export to CSV"
end

# 2. spec_create writes an unprefixed flat spec; spec_read round-trips the markdown
Dir.mktmpdir do |root|
  dir = scaffold(root)
  md = "---\ntitle: Foo\nslug: foo\nstatus: ready\ncreated: 2026-06-10\ndepends_on: []\n---\n# Foo\n"
  path = store("spec_create", "foo", dir: dir, stdin: md)
  raise "spec_create path: #{path}" unless path.end_with?("specs/foo.md")

  back = store("spec_read", "foo", dir: dir)
  raise "spec_read round-trip" unless back == md
end

# 3. spec_list reflects status and sorts by rank prefix
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0002-low.md")
  write_spec(specs_dir, "0001-high.md")
  write_spec(specs_dir, "unranked.md")
  listed = store("spec_list", dir: dir)
  raise "spec_list order: #{listed.map { |s| s['slug'] }}" unless listed.map { |s| s["slug"] } == ["high", "low", "unranked"]
end

# 4. rank assigns dense NNNN- prefixes by the given order, leaves in_progress untouched
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  system("git", "-C", root, "init", "-q")
  write_spec(specs_dir, "a.md")
  write_spec(specs_dir, "b.md")
  write_spec(specs_dir, "wip.md", status: "in_progress")
  store("rank", "b", "a", dir: dir)
  raise "rank a: #{Dir.children(specs_dir)}" unless File.exist?(File.join(specs_dir, "0002-a.md"))
  raise "rank b: #{Dir.children(specs_dir)}" unless File.exist?(File.join(specs_dir, "0001-b.md"))
  raise "wip untouched" unless File.exist?(File.join(specs_dir, "wip.md"))
end

# 5. claim via ag-store matches bin/ag-claim's vocabulary (JSON-encoded)
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0001-a.md")
  claimed = store("claim", "sess-1", "", "0", dir: dir)
  raise "claim: #{claimed}" unless claimed.end_with?("0001-a.md")
  raise "claim again: #{store('claim', 'sess-2', '', '0', dir: dir)}" unless store("claim", "sess-2", "", "0", dir: dir) == "NONE"
end

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

# 6. release clears the claim and returns the spec to ready
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0001-a.md", status: "in_progress", extra: { "claimed_by" => "sess-1" })
  store("release", "a", dir: dir)
  fm = frontmatter(File.join(specs_dir, "0001-a.md"))
  raise "release: #{fm.inspect}" unless fm["status"] == "ready" && fm["claimed_by"].to_s.empty?
end

# 7. ship stamps shipped_at and moves the spec into done/
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  system("git", "-C", root, "init", "-q")
  write_spec(specs_dir, "0001-a.md", status: "in_progress")
  store("ship", "a", dir: dir)
  done_path = File.join(specs_dir, "done", "0001-a.md")
  raise "ship move: #{Dir.children(File.join(specs_dir, 'done'))}" unless File.exist?(done_path)
  fm = frontmatter(done_path)
  raise "ship stamp: #{fm.inspect}" unless fm["status"] == "shipped" && !fm["shipped_at"].to_s.empty?
end

# 8. abandon stamps the reason, clears claim fields, and moves into abandoned/
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  system("git", "-C", root, "init", "-q")
  write_spec(specs_dir, "0001-a.md", status: "in_progress", extra: { "claimed_by" => "sess-1" })
  store("abandon", "a", "--reason", "not worth it", dir: dir)
  path = File.join(specs_dir, "abandoned", "0001-a.md")
  raise "abandon move: #{Dir.children(File.join(specs_dir, 'abandoned'))}" unless File.exist?(path)
  fm = frontmatter(path)
  raise "abandon stamp: #{fm.inspect}" unless fm["status"] == "abandoned" && fm["abandoned_reason"] == "not worth it" && fm["claimed_by"].to_s.empty?
end

# 9. deps / dependents agree with the frontmatter graph
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0001-a.md")
  write_spec(specs_dir, "0002-b.md", extra: { "depends_on" => ["a"] })
  raise "deps: #{store('deps', 'b', dir: dir)}" unless store("deps", "b", dir: dir) == ["a"]
  raise "dependents: #{store('dependents', 'a', dir: dir)}" unless store("dependents", "a", dir: dir) == ["b"]
end

# 10. whoami resolves from git config in the process's own working directory
Dir.mktmpdir do |root|
  system("git", "-C", root, "init", "-q")
  system("git", "-C", root, "config", "user.email", "dev@example.com")
  out, err, st = Open3.capture3("ruby", HELP, "whoami", chdir: root)
  raise "whoami failed: #{err}" unless st.success?
  raise "whoami: #{out}" unless JSON.parse(out) == "dev@example.com"
end

# 11. promote turns a flat spec into directory form, is a no-op the second time
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  system("git", "-C", root, "init", "-q")
  write_spec(specs_dir, "0001-a.md")
  spec_dir = store("promote", "a", dir: dir)
  raise "promote: #{spec_dir}" unless spec_dir.end_with?("specs/0001-a") && File.exist?(File.join(spec_dir, "SPEC.md"))
  raise "promote idempotent: #{store('promote', 'a', dir: dir)}" unless store("promote", "a", dir: dir) == spec_dir
end

# 12. spec_write patches an arbitrary frontmatter field (e.g. stripping a dead dependency)
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0001-b.md", extra: { "depends_on" => ["a"] })
  store("spec_write", "b", "--set", "depends_on=[]", dir: dir)
  fm = frontmatter(File.join(specs_dir, "0001-b.md"))
  raise "spec_write: #{fm.inspect}" unless Array(fm["depends_on"]).empty?
end

# 13. doctor reports the scaffolded layout as healthy
Dir.mktmpdir do |root|
  dir = scaffold(root)
  checks = store("doctor", dir: dir)
  raise "doctor: #{checks.inspect}" unless checks.values.all?
end

OUTCOME_MD = <<~MD
  ---
  title: Buyers cannot reject on identity grounds
  slug: identity
  status: open
  rank:
  created: 2026-09-14
  ---

  # Buyers cannot reject on identity grounds

  ## Claim

  Reviewers sign in through their own IdP.

  ## Measure

  A pilot against a real tenant.

  ## Stop rule

  Two buyers accept local accounts.

  ## Notes

MD

# 14. outcome_create / outcome_read / outcome_list round-trip; list sorts ranked before unranked
Dir.mktmpdir do |root|
  dir = scaffold(root)
  path = store("outcome_create", "identity", dir: dir, stdin: OUTCOME_MD)
  raise "outcome_create path: #{path}" unless path.end_with?("outcomes/identity.md")
  raise "outcome_read round-trip" unless store("outcome_read", "identity", dir: dir) == OUTCOME_MD

  store("outcome_create", "speed", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: speed").sub("rank:\n", "rank: 1\n"))
  listed = store("outcome_list", dir: dir)
  raise "outcome_list order: #{listed.map { |o| o['slug'] }}" unless listed.map { |o| o["slug"] } == %w[speed identity]
  raise "outcome_list shape: #{listed[0].inspect}" unless listed[0]["rank"] == 1 && listed[0]["status"] == "open" && listed[0]["title"] == "Buyers cannot reject on identity grounds"

  begin
    store("outcome_create", "identity", dir: dir, stdin: OUTCOME_MD)
    raise "duplicate outcome_create should fail"
  rescue RuntimeError => e
    raise e unless e.message.include?("already exists")
  end
end

# 15. outcome_rank stamps dense ranks on open outcomes only; achieve/abandon stamp status + timestamps
Dir.mktmpdir do |root|
  dir = scaffold(root)
  %w[a b c].each { |s| store("outcome_create", s, dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: #{s}")) }
  store("outcome_achieve", "c", dir: dir)
  ranked = store("outcome_rank", "b", "c", "a", dir: dir)
  raise "outcome_rank skips non-open: #{ranked.inspect}" unless ranked == %w[b a]
  listed = store("outcome_list", "--status", "open", dir: dir)
  raise "outcome_rank order: #{listed.map { |o| [o['slug'], o['rank']] }}" unless listed.map { |o| [o["slug"], o["rank"]] } == [["b", 1], ["a", 2]]

  fm = frontmatter(File.join(dir, "outcomes", "c.md"))
  raise "achieve status: #{fm.inspect}" unless fm["status"] == "achieved" && fm["achieved_at"].is_a?(Time) # ISO8601 stamp, parsed by YAML

  store("outcome_abandon", "a", "--reason", "spike showed no buyer cares", dir: dir)
  fm = frontmatter(File.join(dir, "outcomes", "a.md"))
  raise "abandon: #{fm.inspect}" unless fm["status"] == "abandoned" && fm["abandoned_reason"] == "spike showed no buyer cares" && fm["abandoned_at"].is_a?(Time)

  store("outcome_write", "b", "--set", "title=Renamed", dir: dir)
  raise "outcome_write" unless frontmatter(File.join(dir, "outcomes", "b.md"))["title"] == "Renamed"
end

# 16. spec_list exposes serves + tags; inbox_add accepts --serves (dropped by local)
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0001-sso.md", extra: { "serves" => "identity", "tags" => %w[auth testing] })
  write_spec(specs_dir, "0002-free.md")
  listed = store("spec_list", dir: dir)
  sso = listed.find { |s| s["slug"] == "sso" }
  raise "serves: #{sso.inspect}" unless sso["serves"] == "identity"
  raise "tags: #{sso.inspect}" unless sso["tags"] == %w[auth testing]
  free = listed.find { |s| s["slug"] == "free" }
  raise "no serves: #{free.inspect}" unless free["serves"].nil? && free["tags"] == []

  store("inbox_add", "Add SCIM", "--serves", "identity", dir: dir)
  raise "inbox_add --serves accepted" unless store("inbox_list", dir: dir).size == 1
end

# 17. map groups specs by the outcome they serve, buckets by status, flags blocked + orphaned, indexes tags
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  store("outcome_create", "identity", dir: dir, stdin: OUTCOME_MD)
  write_spec(specs_dir, "0001-oidc.md", extra: { "serves" => "identity", "tags" => %w[auth] })
  write_spec(specs_dir, "0002-scim.md", extra: { "serves" => "identity", "depends_on" => %w[oidc], "tags" => %w[auth lifecycle] })
  write_spec(specs_dir, "0003-free.md")
  write_spec(specs_dir, "0004-lost.md", extra: { "serves" => "nonexistent" })
  write_spec(File.join(specs_dir, "done"), "0000-old.md", status: "shipped", extra: { "serves" => "identity" })

  m = store("map", dir: dir)
  o = m["outcomes"].find { |x| x["slug"] == "identity" }
  raise "map outcome specs: #{o.inspect}" unless o["specs"]["ready"] == %w[oidc scim] && o["specs"]["shipped"] == %w[old]
  raise "map blocked: #{o.inspect}" unless o["blocked"] == %w[scim]
  raise "map unlinked: #{m['unlinked'].inspect}" unless m["unlinked"]["ready"] == %w[free]
  raise "map orphaned: #{m['orphaned'].inspect}" unless m["orphaned"] == { "nonexistent" => %w[lost] }
  raise "map tags: #{m['tags'].inspect}" unless m["tags"] == { "auth" => %w[oidc scim], "lifecycle" => %w[scim] }
end

# 18. brief_sync rewrites only the "Prioritised outcomes" section, open outcomes by rank, ranked before unranked
Dir.mktmpdir do |root|
  dir = scaffold(root)
  File.write(File.join(dir, "brief.md"), <<~MD)
    # Brief

    ## Who it's for

    Banks.

    ## Prioritised outcomes

    1. stale text

    ## Constraints

    Python.
  MD
  t = "title: Buyers cannot reject on identity grounds"
  store("outcome_create", "second", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: second").sub(t, "title: Second").sub("rank:\n", "rank: 2\n"))
  store("outcome_create", "first", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: first").sub(t, "title: First").sub("rank:\n", "rank: 1\n"))
  store("outcome_create", "unranked", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: unranked").sub(t, "title: Later"))
  store("outcome_create", "gone", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: gone"))
  store("outcome_abandon", "gone", "--reason", "x", dir: dir)

  raise "brief_sync returns true" unless store("brief_sync", dir: dir) == true
  brief = File.read(File.join(dir, "brief.md"))
  expected = "## Prioritised outcomes\n\n1. **First** (`first`)\n2. **Second** (`second`)\n3. **Later** (`unranked`)\n\n## Constraints"
  raise "brief_sync section:\n#{brief}" unless brief.include?(expected)
  raise "brief_sync touched other sections" unless brief.include?("## Who it's for\n\nBanks.") && brief.include?("## Constraints\n\nPython.")
  raise "brief_sync leaked abandoned" if brief.include?("gone")

  File.write(File.join(dir, "brief.md"), "# Brief\n\nno section here\n")
  raise "brief_sync without heading returns false" unless store("brief_sync", dir: dir) == false
end

# 19. flow: queue wait, cycle time, and the agent/human split from checkpoints
Dir.mktmpdir do |root|
  dir = scaffold(root); specs_dir = File.join(dir, "specs")
  FileUtils.mkdir_p(File.join(specs_dir, "0001-timed", "checkpoints"))
  File.write(File.join(specs_dir, "0001-timed", "SPEC.md"), <<~MD)
    ---
    title: Timed
    slug: timed
    status: shipped
    created_at: "2026-09-01T09:00:00Z"
    claimed_at: "2026-09-01T10:00:00Z"
    shipped_at: "2026-09-01T13:00:00Z"
    ---
    # Timed
  MD
  cp = lambda do |n, reason, asked, answered|
    File.write(File.join(specs_dir, "0001-timed", "checkpoints", format("%03d-%s.md", n, reason)), <<~MD)
      ---
      reason: #{reason}
      asked_at: "#{asked}"
      session_id: s1
      asked_by: #{reason == 'ship_approval' ? 'ship' : 'plan'}
      status: #{answered ? 'answered' : 'open'}
      answered_at: #{answered ? "\"#{answered}\"" : ''}
      answered_by: #{answered ? 'keith' : ''}
      ---
      ## Ask

      q

      ## Answer

      #{answered ? 'approved' : ''}
    MD
  end
  cp.call(1, "plan_review",  "2026-09-01T10:30:00Z", "2026-09-01T11:00:00Z")   # 30 min human wait
  cp.call(2, "ship_approval","2026-09-01T12:30:00Z", "2026-09-01T13:00:00Z")   # 30 min human wait

  f = store("flow", "timed", dir: dir)
  raise "queue wait: #{f.inspect}"  unless f["queue_wait_seconds"] == 3600      # 09:00 -> 10:00
  raise "cycle: #{f.inspect}"       unless f["cycle_seconds"] == 10800          # 10:00 -> 13:00
  raise "human wait: #{f.inspect}"  unless f["human_wait_seconds"] == 3600      # 2 x 30 min
  raise "agent: #{f.inspect}"       unless f["agent_seconds"] == 7200           # cycle - human
  raise "lead: #{f.inspect}"        unless f["lead_seconds"] == 14400           # 09:00 -> 13:00
  raise "in_progress: #{f.inspect}" unless f["in_progress"] == false
  raise "checkpoints: #{f.inspect}" unless f["checkpoints"].length == 2
  raise "cp detail: #{f['checkpoints'][0].inspect}" unless f["checkpoints"][0]["reason"] == "plan_review" &&
    f["checkpoints"][0]["wait_seconds"] == 1800 && f["checkpoints"][0]["asked_by"] == "plan"
end

# 20. flow on an in-progress spec with an OPEN checkpoint counts the wait so far, and legacy `created` still reads
Dir.mktmpdir do |root|
  dir = scaffold(root); specs_dir = File.join(dir, "specs")
  FileUtils.mkdir_p(File.join(specs_dir, "0001-live", "checkpoints"))
  File.write(File.join(specs_dir, "0001-live", "SPEC.md"), <<~MD)
    ---
    title: Live
    slug: live
    status: in_progress
    created: 2026-09-01
    claimed_at: "#{(Time.now.utc - 3600).strftime('%Y-%m-%dT%H:%M:%SZ')}"
    ---
    # Live
  MD
  File.write(File.join(specs_dir, "0001-live", "checkpoints", "001-ship_approval.md"), <<~MD)
    ---
    reason: ship_approval
    asked_at: "#{(Time.now.utc - 600).strftime('%Y-%m-%dT%H:%M:%SZ')}"
    session_id: s1
    asked_by: ship
    status: open
    answered_at:
    answered_by:
    ---
    ## Ask

    ship it?

    ## Answer

  MD
  f = store("flow", "live", dir: dir)
  raise "in_progress: #{f.inspect}" unless f["in_progress"] == true
  raise "cycle ~1h: #{f.inspect}" unless (3500..3700).cover?(f["cycle_seconds"])
  raise "open wait ~10m: #{f.inspect}" unless (540..660).cover?(f["human_wait_seconds"])
  raise "agent ~50m: #{f.inspect}" unless (2900..3100).cover?(f["agent_seconds"])
  raise "legacy created: #{f.inspect}" unless f["created_at"].to_s.start_with?("2026-09-01")
  raise "open cp flagged: #{f.inspect}" unless f["checkpoints"][0]["status"] == "open"
  raise "shipped nil: #{f.inspect}" unless f["shipped_at"].nil? && f["lead_seconds"].nil?
end

# 21. flow with no slug returns every spec, and spec_list exposes created_at
Dir.mktmpdir do |root|
  dir = scaffold(root); specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0001-a.md", extra: { "created_at" => '"2026-09-01T09:00:00Z"' })
  write_spec(specs_dir, "0002-b.md")
  all = store("flow", dir: dir)
  raise "flow all: #{all.inspect}" unless all.length == 2 && all.map { |f| f["slug"] }.sort == %w[a b]
  listed = store("spec_list", dir: dir)
  raise "created_at in spec_list: #{listed[0].inspect}" unless listed[0].key?("created_at")
end

# 22. checkpoint ops through ag-store: open -> list -> answer, local store keeps files
Dir.mktmpdir do |root|
  dir = scaffold(root); specs_dir = File.join(dir, "specs")
  FileUtils.mkdir_p(File.join(specs_dir, "0001-cp"))
  File.write(File.join(specs_dir, "0001-cp", "SPEC.md"), "---\ntitle: Cp\nslug: cp\nstatus: in_progress\nclaimed_at: \"2026-09-01T10:00:00Z\"\n---\n# Cp\n")

  id = store("checkpoint_open", "cp", "ship_approval", "--by", "ship", "--session", "s1", dir: dir, stdin: "Approve to ship cp?")
  raise "open returns an id: #{id.inspect}" unless id.is_a?(String) && !id.empty?
  raise "local id is a path: #{id}" unless id.include?("checkpoints/001-ship_approval.md") && File.file?(id)

  open_list = store("checkpoint_list", "cp", dir: dir)
  raise "list: #{open_list.inspect}" unless open_list.length == 1
  c = open_list[0]
  raise "list shape: #{c.inspect}" unless c["reason"] == "ship_approval" && c["asked_by"] == "ship" &&
    c["status"] == "open" && c["ask"] == "Approve to ship cp?" && c["id"] == id
  raise "open_count: #{store('checkpoint_open_count', 'cp', dir: dir)}" unless store("checkpoint_open_count", "cp", dir: dir) == 1

  store("checkpoint_answer", id, "--by", "keith", dir: dir, stdin: "approved")
  done = store("checkpoint_list", "cp", dir: dir)[0]
  raise "answered: #{done.inspect}" unless done["status"] == "answered" && done["answer"] == "approved" &&
    done["answered_by"] == "keith" && !done["answered_at"].to_s.empty?
  raise "open_count after: #{store('checkpoint_open_count', 'cp', dir: dir)}" unless store("checkpoint_open_count", "cp", dir: dir) == 0

  # and flow now sees that wait
  f = store("flow", "cp", dir: dir)
  raise "flow sees checkpoint: #{f.inspect}" unless f["checkpoint_count"] == 1 && f["checkpoints"][0]["reason"] == "ship_approval"
end

# 23. run events through ag-store: append and read back, newest last
Dir.mktmpdir do |root|
  dir = scaffold(root)
  File.write(File.join(dir, "runs.md"), "# Agentile run log\n\nAppend-only.\n\n")
  store("run_event", "claimed", "--spec", "cp", "--runner", "r1", "--detail", "rank 1", dir: dir)
  store("run_event", "shipped", "--spec", "cp", "--runner", "r1", dir: dir)
  evs = store("run_list", dir: dir)
  raise "run_list: #{evs.inspect}" unless evs.length == 2
  raise "order/shape: #{evs.inspect}" unless evs[0]["event"] == "claimed" && evs[1]["event"] == "shipped" &&
    evs[0]["spec"] == "cp" && evs[0]["runner"] == "r1" && evs[0]["detail"] == "rank 1" && !evs[0]["at"].to_s.empty?
  raise "filter by spec: #{store('run_list', '--spec', 'nope', dir: dir).inspect}" unless store("run_list", "--spec", "nope", dir: dir).empty?
end

puts "ALL PASS"
