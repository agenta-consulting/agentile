#!/usr/bin/env ruby
# frozen_string_literal: true
# SessionStart hook: surface the Claude Code session id into the session context
# so Agentile skills (ag-next) can stamp claims with a resumable handle.
require "json"
raw = $stdin.read
sid = (JSON.parse(raw)["session_id"] rescue nil)
exit 0 if sid.nil? || sid.to_s.empty?
puts JSON.generate(
  "hookSpecificOutput" => {
    "hookEventName"     => "SessionStart",
    "additionalContext" => "Agentile: this session's id is #{sid}. " \
      "When you claim work with /ag-next, stamp it claimed_by: #{sid} so the " \
      "loop can be resumed later with `claude --resume #{sid}`."
  }
)
