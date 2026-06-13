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

puts "ALL PASS"
