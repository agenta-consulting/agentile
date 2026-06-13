#!/usr/bin/env ruby
# frozen_string_literal: true

# Agentile Stop/SubagentStop hook: hold "done" until the project's tests pass.
#
# Reads the configured `test` command from the project's .agentile/gates.json and
# runs it. If tests fail, it emits a block decision so Claude keeps working
# until they pass. No-op (allow stop) whenever:
#   - .agentile/gates.json is missing or unparseable,
#   - the `test` command is blank,
#   - this stop was itself triggered by a prior block (stop_hook_active,
#     kept as a first-line allow but no longer relied upon),
#   - the git working tree is clean (idle loop tick / already-green commit),
#   - the per-session consecutive-block cap (MAX_CONSECUTIVE_BLOCKS) is reached,
#     which is the real re-block guard ensuring a permanently-failing suite
#     can never cause an infinite loop.
# So installing the plugin never blocks an unconfigured repo.

require 'json'
require 'open3'
require 'tmpdir'
require 'digest'

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
gates_path = File.join(cwd, '.agentile', 'gates.json')
allow unless File.exist?(gates_path)

gates = begin
  JSON.parse(File.read(gates_path))
rescue JSON::ParserError
  allow
end

cmd = gates['test'].to_s.strip
allow if cmd.empty?

# Skip when the working tree is clean: an idle loop tick or an already-green
# commit has nothing new to test. Only applies inside a git repo.
porcelain, _pe, pst = Open3.capture3('git', '-C', cwd, 'status', '--porcelain')
allow if pst.success? && porcelain.strip.empty?

# Independent re-block guard (stop_hook_active is unreliable): cap consecutive
# blocks per session so a suite that can never pass can't loop forever.
# The counter file persists until tests pass (clearing it) or the session ends.
# Once the cap is reached we write "capped" so all subsequent stops also allow.
MAX_CONSECUTIVE_BLOCKS = 5
sid = (data['session_id'] || 'nosession').to_s
counter = File.join(Dir.tmpdir, "agentile-stopgate-#{Digest::SHA1.hexdigest(sid + cwd)}")

# Already given up for this session+dir: allow immediately.
allow if File.exist?(counter) && File.read(counter).strip == 'capped'

stdout, stderr, status = Open3.capture3(cmd, chdir: cwd)
if status.success?
  File.delete(counter) if File.exist?(counter)
  allow
end

count = (File.read(counter).to_i rescue 0) + 1
if count >= MAX_CONSECUTIVE_BLOCKS
  File.write(counter, 'capped')
  allow
end
File.write(counter, count.to_s)

tail = (stdout.to_s + stderr.to_s).split("\n").last(20).join("\n")
block(
  "Agentile gate: tests are failing, so the work is not done. Run the project test " \
  "command (`#{cmd}`), fix the failures, and try again.\n\nLast output:\n#{tail}"
)
