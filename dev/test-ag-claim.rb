require "yaml"; require "date"; require "tmpdir"; require "open3"; require "fileutils"
HELP = File.expand_path("../bin/ag-claim", __dir__)

def spec(dir, fname, status:, depends_on: [])
  dep = depends_on.empty? ? "[]" : "[#{depends_on.join(", ")}]"
  # `created` is a bare YYYY-MM-DD, which YAML loads as a Date — every test spec
  # carries one so the helper's safe_load must permit Date (regression guard).
  File.write(File.join(dir, fname),
    "---\nstatus: #{status}\ncreated: 2026-06-10\nclaimed_by:\nlabel:\nclaimed_at:\ndepends_on: #{dep}\n---\n# #{fname}\n")
end

def claim(dir, session: "s", wip: 0)
  out, _e, _st = Open3.capture3("ruby", HELP, dir, session, "", wip.to_s)
  out.strip
end

def dirspec(dir, dname, status:, depends_on: [])
  d = File.join(dir, dname)
  FileUtils.mkdir_p(d)
  spec(d, "SPEC.md", status: status, depends_on: depends_on)
end

# 1. picks the lowest prefix among eligible, and stamps it
Dir.mktmpdir do |d|
  spec(d, "0002-low.md",  status: "ready")
  spec(d, "0001-high.md", status: "ready")
  path = claim(d)
  raise "prefix order: #{path}" unless path.end_with?("0001-high.md")
  fm = YAML.safe_load(File.read(path)[/^---\n(.*?)\n---/m, 1], permitted_classes: [Time, Date])
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

# 4c. dep shipped in done/ -> a becomes claimable, and the done/ spec is never claimed
#     itself (top-level-only pool excludes subdirectories regardless of name)
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready", depends_on: ["b"])
  FileUtils.mkdir_p(File.join(d, "done"))
  spec(File.join(d, "done"), "0005-b.md", status: "shipped")
  raise "done dep: #{claim(d)}" unless claim(d).end_with?("0001-a.md")
end

# 4d. dep abandoned in abandoned/ -> dependent stays BLOCKED (abandoned != shipped),
#     and the abandoned spec is not in the claim pool
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready", depends_on: ["b"])
  FileUtils.mkdir_p(File.join(d, "abandoned"))
  spec(File.join(d, "abandoned"), "0002-b.md", status: "abandoned")
  raise "abandoned dep: #{claim(d)}" unless claim(d) == "BLOCKED"
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

# 12. a SPEC.md placed directly inside done/ is never a spec (RESERVED guard)
Dir.mktmpdir do |d|
  FileUtils.mkdir_p(File.join(d, "done"))
  spec(File.join(d, "done"), "SPEC.md", status: "ready")
  raise "done/SPEC.md: #{claim(d)}" unless claim(d) == "NONE"
end

# 13. same slug in flat and directory form aborts loudly
Dir.mktmpdir do |d|
  spec(d, "0001-x.md", status: "ready")
  dirspec(d, "0002-x", status: "ready")
  out, err, st = Open3.capture3("ruby", HELP, d, "s", "", "0")
  raise "dupe slug: #{out.inspect} #{err.inspect}" if st.success? || !err.include?("duplicate slug")
end

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

puts "ALL PASS"
