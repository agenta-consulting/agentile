#!/usr/bin/env ruby
# frozen_string_literal: true

# Agentile PostToolUse hook: run the project's formatter after an edit.
#
# Reads the configured `format` command from the project's .agentile/gates.json and
# runs it. No-op (exit 0, no output) whenever:
#   - .agentile/gates.json is missing or unparseable,
#   - the `format` command is blank,
#   - the edited file is outside the project.
# So installing the plugin never disrupts an unconfigured repo.
#
# If the format command contains the literal `{file}`, it is replaced with the
# edited file's shell-escaped path; otherwise the command runs as-is.
# Formatting failures are swallowed — formatting must never block the loop.

require 'json'
require 'shellwords'

def bail
  exit 0
end

raw = $stdin.read
bail if raw.nil? || raw.strip.empty?

data = begin
  JSON.parse(raw)
rescue JSON::ParserError
  bail
end

cwd = data['cwd'] || Dir.pwd
file = data.dig('tool_input', 'file_path')

gates_path = File.join(cwd, '.lal', 'gates.json')
bail unless File.exist?(gates_path)

gates = begin
  JSON.parse(File.read(gates_path))
rescue JSON::ParserError
  bail
end

cmd = gates['format'].to_s.strip
bail if cmd.empty?

# Only act on files inside the project.
if file
  abs = File.expand_path(file, cwd)
  bail unless abs.start_with?(File.expand_path(cwd))
  cmd = cmd.gsub('{file}', Shellwords.escape(abs)) if cmd.include?('{file}')
end

# Run quietly; never fail the hook on a formatter error.
system(cmd, chdir: cwd, out: File::NULL, err: File::NULL)
exit 0
