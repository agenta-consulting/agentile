require "tmpdir"; require "open3"; require "json"; require "fileutils"; require "yaml"; require "date"
TOOL = File.expand_path("../bin/ag-checkpoint", __dir__)

def cp(*args, stdin: nil)
  out, err, st = Open3.capture3("ruby", TOOL, *args, stdin_data: stdin.to_s)
  [out.strip, err, st]
end

def spec_dir(root)
  d = File.join(root, "docs", "agentile", "specs", "0007-thing")
  FileUtils.mkdir_p(d)
  File.write(File.join(d, "SPEC.md"), "---\nslug: thing\nstatus: in_progress\n---\n# Thing\n")
  d
end

# 1. open writes 001-<reason>.md with frontmatter and the ask; prints the path
Dir.mktmpdir do |root|
  d = spec_dir(root)
  path, err, st = cp("open", d, "plan_review", "--session", "abc-123", stdin: "Plan written. Review or amend plan.md.")
  raise "open failed: #{err}" unless st.success?
  raise "path: #{path}" unless path == File.join(d, "checkpoints", "001-plan_review.md")
  body = File.read(path)
  fm = YAML.safe_load(body[/\A---\n(.*?)\n---/m, 1], permitted_classes: [Time, Date])
  raise "reason" unless fm["reason"] == "plan_review"
  raise "status" unless fm["status"] == "open"
  raise "session" unless fm["session_id"] == "abc-123"
  raise "asked_at" unless fm["asked_at"].to_s.match?(/\A\d{4}-\d{2}-\d{2}T/)
  raise "ask body" unless body.include?("## Ask\n\nPlan written. Review or amend plan.md.")
  raise "answer section" unless body.include?("## Answer\n")
end

# 2. a second open numbers 002; list returns both oldest first with parsed fields
Dir.mktmpdir do |root|
  d = spec_dir(root)
  cp("open", d, "plan_review", stdin: "first")
  path2, _e, _s = cp("open", d, "question", stdin: "Which auth scheme?\n\n1. cookie\n2. token\n\nRecommend 2.")
  raise "second number: #{path2}" unless path2.end_with?("002-question.md")
  out, err, st = cp("list", d)
  raise "list failed: #{err}" unless st.success?
  rows = JSON.parse(out)
  raise "count: #{rows.size}" unless rows.size == 2
  raise "order" unless rows[0]["reason"] == "plan_review" && rows[1]["reason"] == "question"
  raise "ask parsed" unless rows[1]["ask"].start_with?("Which auth scheme?")
  raise "answer empty" unless rows[1]["answer"].to_s.empty?
  raise "open_count" unless cp("open_count", d)[0] == "2"
end

# 3. answer fills ## Answer, flips status, stamps answered_at/answered_by
Dir.mktmpdir do |root|
  d = spec_dir(root)
  path, _e, _s = cp("open", d, "question", stdin: "Which?")
  _o, err, st = cp("answer", path, "--by", "keith", stdin: "Option 2, and keep the old route for a release.")
  raise "answer failed: #{err}" unless st.success?
  body = File.read(path)
  fm = YAML.safe_load(body[/\A---\n(.*?)\n---/m, 1], permitted_classes: [Time, Date])
  raise "answered status" unless fm["status"] == "answered"
  raise "answered_by" unless fm["answered_by"] == "keith"
  raise "answered_at" unless fm["answered_at"].to_s.match?(/\A\d{4}-\d{2}-\d{2}T/)
  raise "answer body" unless body.include?("## Answer\n\nOption 2, and keep the old route for a release.")
  rows = JSON.parse(cp("list", d)[0])
  raise "list answer" unless rows[0]["answer"] == "Option 2, and keep the old route for a release."
  raise "open_count after answer" unless cp("open_count", d)[0] == "0"
end

# 4. answer with empty stdin still marks answered (plan_review approval carries no prose)
Dir.mktmpdir do |root|
  d = spec_dir(root)
  path, _e, _s = cp("open", d, "plan_review", stdin: "Review plan.md")
  _o, err, st = cp("answer", path, stdin: "")
  raise "empty answer failed: #{err}" unless st.success?
  raise "empty answer status" unless File.read(path).include?("status: answered")
end

# 5. an unknown reason aborts cleanly; a missing spec dir aborts cleanly; list on no checkpoints is []
Dir.mktmpdir do |root|
  d = spec_dir(root)
  _o, err, st = cp("open", d, "coffee", stdin: "x")
  raise "bad reason should fail" if st.success?
  raise "bad reason message: #{err}" unless err.include?("unknown reason")
  _o, err, st = cp("open", File.join(root, "nope"), "question", stdin: "x")
  raise "missing dir should fail" if st.success?
  raise "missing dir message: #{err}" unless err.include?("no such spec dir")
  raise "empty list" unless cp("list", d)[0] == "[]"
end

puts "ALL PASS"
