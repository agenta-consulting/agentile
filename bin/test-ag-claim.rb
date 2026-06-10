require "yaml"; require "date"; require "tmpdir"; require "open3"; require "fileutils"
HELP = File.expand_path("ag-claim", __dir__)

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
