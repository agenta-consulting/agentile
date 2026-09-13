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

puts "ALL PASS"
