#!/usr/bin/env ruby
# frozen_string_literal: true

# Agentile subagent status line.
#
# Wired via the plugin's root settings.json `subagentStatusLine` key. Claude Code
# runs this once per refresh tick, passing a single JSON object on stdin with a
# `tasks` array (each task: id, name, type, status, description, label,
# startTime, tokenCount, tokenSamples, cwd) plus `columns`.
#
# We emit one JSON line per row, `{"id": <task id>, "content": <row body>}`,
# prefixing the subagent's own name with a small `agentile` badge so loop work
# is recognisable in the agent panel. Token count is appended when present.
#
# Safety: this is a cosmetic nicety. Any parse error or missing field degrades to
# a no-op (no stdout), which leaves each row's default rendering untouched. It
# never raises and never blocks.

require "json"

begin
  raw = $stdin.read
  data = JSON.parse(raw)
  tasks = data["tasks"]
  exit 0 unless tasks.is_a?(Array)

  tasks.each do |task|
    next unless task.is_a?(Hash)

    id = task["id"]
    next if id.nil? || id.to_s.empty?

    name = task["name"].to_s
    name = "subagent" if name.empty?

    parts = ["agentile · #{name}"]
    desc = task["description"].to_s
    parts << desc unless desc.empty?
    tokens = task["tokenCount"]
    parts << "#{tokens} tok" if tokens.is_a?(Numeric) && tokens.positive?

    puts JSON.generate({ "id" => id, "content" => parts.join(" · ") })
  end
rescue StandardError
  # Cosmetic only — never disrupt the session. Fall back to default rendering.
  exit 0
end
