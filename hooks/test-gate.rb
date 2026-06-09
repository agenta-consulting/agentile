#!/usr/bin/env ruby
# frozen_string_literal: true

# Agentile Stop/SubagentStop hook: hold "done" until the project's tests pass.
#
# Reads the configured `test` command from the project's .agentile/gates.json and
# runs it. If tests fail, it emits a block decision so Claude keeps working
# until they pass. No-op (allow stop) whenever:
#   - .agentile/gates.json is missing or unparseable,
#   - the `test` command is blank,
#   - this stop was itself triggered by a prior block (stop_hook_active),
#     which prevents an infinite loop.
# So installing the plugin never blocks an unconfigured repo.

require 'json'
require 'open3'

def allow
  exit 0
end

def block(reason)
  puts JSON.generate({ 'decision' => 'block', 'reason' => reason })
  exit 0
end

raw = $stdin.read
allow if raw.nil? || raw.strip.empty?

data = begin
  JSON.parse(raw)
rescue JSON::ParserError
  allow
end

# Avoid re-triggering on the stop we ourselves caused.
allow if data['stop_hook_active']

cwd = data['cwd'] || Dir.pwd
gates_path = File.join(cwd, '.lal', 'gates.json')
allow unless File.exist?(gates_path)

gates = begin
  JSON.parse(File.read(gates_path))
rescue JSON::ParserError
  allow
end

cmd = gates['test'].to_s.strip
allow if cmd.empty?

stdout, stderr, status = Open3.capture3(cmd, chdir: cwd)
allow if status.success?

tail = (stdout.to_s + stderr.to_s).split("\n").last(20).join("\n")
block(
  "Agentile gate: tests are failing, so the work is not done. Run the project test " \
  "command (`#{cmd}`), fix the failures, and try again.\n\nLast output:\n#{tail}"
)
