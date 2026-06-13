require "yaml"; require "date"; require "tmpdir"; require "open3"; require "fileutils"
HELP = File.expand_path("../bin/ag-dependents", __dir__)

def spec(dir, fname, status:, depends_on: [])
  dep = depends_on.empty? ? "[]" : "[#{depends_on.join(", ")}]"
  File.write(File.join(dir, fname),
    "---\nstatus: #{status}\ncreated: 2026-06-10\ndepends_on: #{dep}\n---\n# #{fname}\n")
end

def dirspec(dir, dname, status:, depends_on: [])
  d = File.join(dir, dname)
  FileUtils.mkdir_p(d)
  spec(d, "SPEC.md", status: status, depends_on: depends_on)
end

def dependents(dir, slug)
  out, _e, _st = Open3.capture3("ruby", HELP, dir, slug)
  out.strip.split("\n").reject(&:empty?)
end

# 1. direct dependent: b depends_on a -> dependents(a) == [b]
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready")
  spec(d, "0002-b.md", status: "ready", depends_on: ["a"])
  got = dependents(d, "a")
  raise "direct: #{got.inspect}" unless got == ["b"]
end

# 2. transitive chain a <- b <- c, nearest first
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready")
  spec(d, "0002-b.md", status: "ready", depends_on: ["a"])
  spec(d, "0003-c.md", status: "in_progress", depends_on: ["b"])
  got = dependents(d, "a")
  raise "transitive: #{got.inspect}" unless got == ["b", "c"]
end

# 3. no dependents -> empty output
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready")
  spec(d, "0002-b.md", status: "ready")
  got = dependents(d, "a")
  raise "none: #{got.inspect}" unless got.empty?
end

# 4. cycle a<->b terminates (b reaches a, a reaches b) -> dependents(a) == [b]
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready", depends_on: ["b"])
  spec(d, "0002-b.md", status: "ready", depends_on: ["a"])
  got = dependents(d, "a")
  raise "cycle: #{got.inspect}" unless got == ["b"]
end

# 5. shipped/abandoned specs are not cascade candidates even if they depend on the target
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready")
  spec(d, "0002-live.md", status: "ready", depends_on: ["a"])
  FileUtils.mkdir_p(File.join(d, "done"))
  spec(File.join(d, "done"), "0003-shipped.md", status: "shipped", depends_on: ["a"])
  FileUtils.mkdir_p(File.join(d, "abandoned"))
  spec(File.join(d, "abandoned"), "0004-gone.md", status: "abandoned", depends_on: ["a"])
  got = dependents(d, "a")
  raise "candidates: #{got.inspect}" unless got == ["live"]
end

# 6. directory-spec dependent is found, identified by its directory slug
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready")
  dirspec(d, "0002-b", status: "ready", depends_on: ["a"])
  got = dependents(d, "a")
  raise "dir dependent: #{got.inspect}" unless got == ["b"]
end

# 7. plan.md beside SPEC.md is not read as a spec
Dir.mktmpdir do |d|
  spec(d, "0001-a.md", status: "ready")
  dirspec(d, "0002-b", status: "ready", depends_on: ["a"])
  File.write(File.join(d, "0002-b", "plan.md"), "---\nstatus: ready\ndepends_on: [a]\n---\n")
  got = dependents(d, "a")
  raise "plan ignored: #{got.inspect}" unless got == ["b"]
end

puts "ALL PASS"
