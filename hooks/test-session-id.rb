require "json"; require "open3"
HOOK = File.expand_path("session-id.rb", __dir__)
out, _e, st = Open3.capture3("ruby", HOOK, stdin_data: { "session_id" => "abc-123" }.to_json)
raise "exit #{st.exitstatus}" unless st.exitstatus.zero?
data = JSON.parse(out)
ctx = data.dig("hookSpecificOutput", "additionalContext").to_s
raise "id not surfaced: #{out}" unless ctx.include?("abc-123")
out2, _e2, st2 = Open3.capture3("ruby", HOOK, stdin_data: "{}")
raise "exit2 #{st2.exitstatus}" unless st2.exitstatus.zero?
puts "ALL PASS"
