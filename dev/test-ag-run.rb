require "tmpdir"; require "open3"
RUNNER = File.expand_path("../bin/ag-run", __dir__)

# A stub `claude` binary: each invocation pops the next line from a "plan"
# file (one line per expected /ag-build invocation) and prints it,
# tracking invocation count via a counter file (state can't live in the stub
# process itself — ag-run spawns a fresh one per call, same as the real
# claude -p would). A plan line starting "CRASH:" simulates claude exiting
# non-zero instead of printing an AG_BUILD line. Every invocation also logs the
# AGENTILE_RUNNER_ID it saw, so tests can check identity stays stable across
# calls within one ag-run run, and is respected when the caller sets it.
STUB = <<~'RUBY'
  #!/usr/bin/env ruby
  # frozen_string_literal: true
  plan = File.readlines(ENV.fetch("STUB_PLAN")).map(&:chomp)
  counter_file = ENV.fetch("STUB_COUNTER")
  n = File.exist?(counter_file) ? File.read(counter_file).to_i : 0
  File.write(counter_file, (n + 1).to_s)
  File.open(ENV.fetch("STUB_ENV_LOG"), "a") { |f| f.puts(ENV["AGENTILE_RUNNER_ID"].to_s) }
  line = plan[n] || "AG_BUILD: idle NONE"
  if line.start_with?("CRASH:")
    warn line.sub("CRASH:", "")
    exit 1
  end
  puts "some noise /ag-loop printed along the way"
  puts line
  exit 0
RUBY

def with_stub_claude
  Dir.mktmpdir do |bindir|
    stub_path = File.join(bindir, "claude")
    File.write(stub_path, STUB)
    File.chmod(0o755, stub_path)
    yield bindir
  end
end

# Runs ag-run against a scripted sequence of /ag-loop --once outcomes.
# Returns [stdout, stderr, status, env_log_lines] — env_log_lines is the
# AGENTILE_RUNNER_ID seen on each stub invocation, oldest first.
def run_ag_run(bindir, plan_lines, extra_env: {}, args: [])
  Dir.mktmpdir do |d|
    plan_file = File.join(d, "plan")
    File.write(plan_file, plan_lines.join("\n") + "\n")
    env = {
      "PATH" => "#{bindir}:#{ENV["PATH"]}",
      "STUB_PLAN" => plan_file,
      "STUB_COUNTER" => File.join(d, "counter"),
      "STUB_ENV_LOG" => File.join(d, "env_log"),
      "AGENTILE_RUNNER_ID" => nil, # clear ambient env; extra_env can set it back
    }.merge(extra_env)
    out, err, status = Open3.capture3(env, "ruby", RUNNER, *args)
    log = File.exist?(env["STUB_ENV_LOG"]) ? File.readlines(env["STUB_ENV_LOG"]).map(&:strip) : []
    [out, err, status, log]
  end
end

# 1. drains shipped items until idle, one claude invocation per item, same
#    runner id reused across the whole run
with_stub_claude do |bindir|
  out, _err, status, log = run_ag_run(bindir, ["AG_BUILD: shipped 0001-a", "AG_BUILD: shipped 0002-b", "AG_BUILD: idle NONE"])
  raise "expected success: #{status.exitstatus}" unless status.success?
  raise "expected 3 invocations, got #{log.size}" unless log.size == 3
  raise "runner id not stable across items: #{log.inspect}" unless log.uniq.size == 1
  raise "expected idle report" unless out.include?("backlog idle (NONE)")
end

# 2. a default runner id is generated, printed, and looks like ag-run@host/pid
with_stub_claude do |bindir|
  out, _err, status, log = run_ag_run(bindir, ["AG_LOOP: idle NONE"])
  raise "expected success" unless status.success?
  raise "no id logged" if log.empty? || log.first.to_s.empty?
  raise "id not ag-run@-prefixed: #{log.first}" unless log.first.start_with?("ag-run@")
  raise "printed id mismatch" unless out.include?("runner id: #{log.first}")
end

# 3. an explicit AGENTILE_RUNNER_ID is honoured and passed through unchanged
with_stub_claude do |bindir|
  _out, _err, status, log = run_ag_run(
    bindir, ["AG_BUILD: shipped a", "AG_BUILD: idle NONE"],
    extra_env: { "AGENTILE_RUNNER_ID" => "my-fixed-id" }
  )
  raise "expected success" unless status.success?
  raise "custom id not used: #{log.inspect}" unless log.all? { |id| id == "my-fixed-id" }
end

# 4. a pause stops the drain after exactly the paused item, exit 0 (expected stop, not an error)
with_stub_claude do |bindir|
  out, _err, status, log = run_ag_run(bindir, ["AG_BUILD: paused 0003-c gate_failure", "AG_BUILD: shipped should-not-run"])
  raise "pause should exit 0: #{status.exitstatus}" unless status.success?
  raise "should stop at 1 invocation, got #{log.size}" unless log.size == 1
  raise "missing pause report" unless out.include?("paused on 0003-c (gate_failure)")
  raise "missing resume hint" unless out.include?("AGENTILE_RUNNER_ID=")
end

# 5. a failure stops the drain, exit 1
with_stub_claude do |bindir|
  _out, err, status, log = run_ag_run(bindir, ["AG_BUILD: failed 0004-d gate_failure"])
  raise "failure should exit non-zero" if status.success?
  raise "should stop at 1 invocation" unless log.size == 1
  raise "missing failure report: #{err.inspect}" unless err.include?("failed on 0004-d")
end

# 6. claude itself crashing (no AG_BUILD line, non-zero exit) is reported and exits 1
with_stub_claude do |bindir|
  _out, err, status, _log = run_ag_run(bindir, ["CRASH: boom"])
  raise "crash should exit non-zero" if status.success?
  raise "missing crash report: #{err.inspect}" unless err.include?("claude exited")
end

# 7. claude exiting 0 with no AG_BUILD line anywhere is reported and exits 1
with_stub_claude do |bindir|
  _out, err, status, _log = run_ag_run(bindir, ["nothing useful printed here"])
  raise "missing status line should exit non-zero" if status.success?
  raise "missing report: #{err.inspect}" unless err.include?("no AG_BUILD status line found")
end

# 8. --limit stops the drain early even though more items would be ready
with_stub_claude do |bindir|
  out, _err, status, log = run_ag_run(
    bindir, ["AG_BUILD: shipped a", "AG_BUILD: shipped b", "AG_BUILD: shipped c"],
    args: ["--limit", "2"]
  )
  raise "expected success" unless status.success?
  raise "expected exactly 2 invocations, got #{log.size}" unless log.size == 2
  raise "missing limit report" unless out.include?("reached --limit 2")
end

# 9. an unrecognised flag aborts cleanly before spawning claude
with_stub_claude do |bindir|
  _out, err, status, log = run_ag_run(bindir, ["AG_BUILD: idle NONE"], args: ["--bogus"])
  raise "bad flag should exit non-zero" if status.success?
  raise "should never spawn claude" unless log.empty?
  raise "missing usage error: #{err.inspect}" unless err.include?("unknown argument")
end

# 10. the retired AG_LOOP prefix is still accepted for one release
with_stub_claude do |bindir|
  out, _err, status, log = run_ag_run(bindir, ["AG_LOOP: shipped 0001-old", "AG_BUILD: idle NONE"])
  raise "expected success: #{status.exitstatus}" unless status.success?
  raise "expected 2 invocations, got #{log.size}" unless log.size == 2
  raise "old prefix not reported" unless out.include?("AG_LOOP: shipped 0001-old")
end

# 11. a pause line carries the checkpoint path through to the report
with_stub_claude do |bindir|
  out, _err, status, _log = run_ag_run(bindir, ["AG_BUILD: paused 0003-c plan_review docs/agentile/specs/0003-c/checkpoints/001-plan_review.md"])
  raise "pause should exit 0" unless status.success?
  raise "checkpoint path missing from report" unless out.include?("001-plan_review.md")
end

puts "ALL PASS"
