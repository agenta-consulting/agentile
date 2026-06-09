require "yaml"; require "tmpdir"; require "open3"
HELP = File.expand_path("ag-claim", __dir__)

def spec(dir, name, status:, priority:)
  File.write(File.join(dir, "#{name}.md"),
    "---\nstatus: #{status}\npriority: #{priority}\nclaimed_by:\nlabel:\nclaimed_at:\n---\n# #{name}\n")
end

def claim(dir, session:, wip:)
  out, _err, st = Open3.capture3("ruby", HELP, dir, session, "", wip.to_s)
  [out.strip, st.exitstatus]
end

Dir.mktmpdir do |dir|
  spec(dir, "low",  status: "ready", priority: 5)
  spec(dir, "high", status: "ready", priority: 1)   # lower number = higher priority
  path, code = claim(dir, session: "sess-A", wip: 2)
  raise "exit #{code}" unless code == 0
  raise "picked #{path}" unless path.end_with?("high.md")
  fm = YAML.load(File.read(path)[/^---\n(.*?)\n---/m, 1])
  raise "status"     unless fm["status"] == "in_progress"
  raise "claimed_by" unless fm["claimed_by"] == "sess-A"
  raise "claimed_at" if fm["claimed_at"].to_s.empty?
  path2, = claim(dir, session: "sess-B", wip: 2)
  raise "second #{path2}" unless path2.end_with?("low.md")
  path3, = claim(dir, session: "sess-C", wip: 2)
  raise "wip not enforced: #{path3}" unless path3 == "WIP_FULL"
  puts "ALL PASS"
end
