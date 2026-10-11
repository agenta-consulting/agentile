# frozen_string_literal: true
# Tests specific to the bundled local store (bin/ag-store-local). The protocol
# behaviour is covered by dev/test-store-conformance.rb, which runs against this
# store by default; this file covers what that suite cannot see from outside:
# that every request really holds the project lock, that a write is atomic on
# disk, and the process-binding edge cases.
require "json"
require "open3"
require "tmpdir"
require "fileutils"

AG_STORE = File.expand_path("../bin/ag-store", __dir__)
LOCAL = File.expand_path("../bin/ag-store-local", __dir__)
CLEAN = { "AGENTILE_STORE_URL" => nil, "AGENTILE_PROJECTS_URL" => nil, "AGENTILE_RUNNER_ID" => nil,
          "CLAUDE_SESSION_ID" => nil }.freeze

def with_repo(url_for)
  Dir.mktmpdir("ag-local") do |root|
    data = File.join(root, "data")
    FileUtils.mkdir_p(File.join(root, ".agentile"))
    File.write(File.join(root, ".agentile/store.md"), "---\nurl: #{url_for.call(data)}\nproject: demo\nwip_limit: 2\n---\n")
    yield root, data
  end
end

def ag(root, *argv, stdin: nil)
  out, err, st = Open3.capture3(CLEAN, "ruby", AG_STORE, *argv.map(&:to_s), stdin_data: stdin.to_s, chdir: root)
  [ out, err, st.exitstatus ]
end

def ag!(root, *argv, **kw)
  out, err, code = ag(root, *argv, **kw)
  raise "ag-store #{argv.join(' ')} exited #{code}: #{err}" unless code.zero?

  JSON.parse(out)
end

SPEC = "---\nslug: one\ntitle: One\n---\n"
failures = []
test = lambda do |name, &blk|
  blk.call
  puts "  ok    #{name}"
rescue StandardError => e
  failures << name
  puts "  FAIL  #{name}\n        #{e.message}"
end

with_repo(->(d) { "local:#{d}" }) do |root, data|
  ag!(root, "spec_create", stdin: SPEC)

  test.call("a claim waits while another process holds the project lock") do
    File.open(File.join(data, "demo.lock"), File::RDWR | File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)
      t = Thread.new { ag(root, "claim", "racer", "", "0", "--spec", "one") }
      sleep 2.5
      raise "the claim finished while the lock was held: #{t.value.inspect}" unless t.alive?

      lock.flock(File::LOCK_UN)
      out, _err, code = t.value
      raise "after the lock was released the claim should win: #{code} #{out}" unless code.zero? && JSON.parse(out) == "one"
    end
  end

  test.call("wip_limit in store.md reaches the store as config") do
    raise "doctor wip_limit" unless ag!(root, "doctor")["wip_limit"] == 2
  end

  test.call("the data file is valid JSON with no temp files left behind") do
    JSON.parse(File.read(File.join(data, "demo.json")))
    leftovers = Dir.glob(File.join(data, "*.tmp-*"))
    raise "temp files: #{leftovers}" unless leftovers.empty?
  end

  test.call("a read leaves the data file untouched") do
    path = File.join(data, "demo.json")
    before = File.mtime(path)
    sleep 1.1
    ag!(root, "spec_list")
    raise "spec_list rewrote the file" unless File.mtime(path) == before
  end

  test.call("projects live in separate files") do
    File.write(File.join(root, ".agentile/store.md"), "---\nurl: local:#{data}\nproject: other\n---\n")
    raise "other project should be empty" unless ag!(root, "spec_list").empty?
    raise "whoami should list both" unless (ag!(root, "whoami")["projects"].map { |p| p["slug"] } & %w[demo other]).size == 2
  end

  test.call("a malformed project slug is 404 without creating a file") do
    File.write(File.join(root, ".agentile/store.md"), "---\nurl: local:#{data}\nproject: Not/A Slug\n---\n")
    _out, err, code = ag(root, "spec_list")
    raise "expected exit 1 and 404: #{code} #{err}" unless code == 1 && err.include?("404")
    raise "no file for a bad slug" unless Dir.glob(File.join(data, "Not*")).empty?
  end
end

with_repo(->(_d) { "exec:#{LOCAL} --root /dev/null/nowhere" }) do |root, _data|
  test.call("a process store that crashes is a configuration error (exit 2)") do
    _out, err, code = ag(root, "spec_list")
    raise "expected exit 2 naming the command: #{code} #{err}" unless code == 2 && err.include?("store command")
  end
end

with_repo(->(_d) { "exec:/bin/echo not-json" }) do |root, _data|
  test.call("a process store that prints garbage is a configuration error (exit 2)") do
    _out, err, code = ag(root, "spec_list")
    raise "expected exit 2: #{code} #{err}" unless code == 2 && err.include?("not a protocol response")
  end
end

with_repo(->(_d) { "exec:/no/such/store-binary" }) do |root, _data|
  test.call("a missing process store command is a configuration error (exit 2)") do
    _out, err, code = ag(root, "doctor")
    raise "expected exit 2: #{code} #{err}" unless code == 2 && err.include?("cannot start")
  end
end

test.call("the local store answers a raw request on stdin") do
  Dir.mktmpdir do |d|
    req = { "protocol" => 1, "method" => "GET", "path" => "/projects/raw/doctor", "query" => {}, "body" => nil,
            "user" => { "email" => "a@b.c", "name" => "A" }, "config" => {} }
    out, _err, st = Open3.capture3("ruby", LOCAL, "--root", d, stdin_data: JSON.generate(req))
    res = JSON.parse(out)
    raise "raw doctor: #{out}" unless st.success? && res["status"] == 200 && res["body"]["store"] == "local"
  end
end

puts(failures.empty? ? "ALL PASS" : "#{failures.size} FAILED")
exit(failures.empty? ? 0 : 1)
