# Manual end-to-end check against a REAL Airtable base — makes real network
# calls and real writes (which it cleans up afterwards). NOT part of
# automated CI (dev/test-ag-store-airtable.rb is the hermetic unit suite);
# run this by hand once after setting up a sandbox base, or whenever the
# adapter's HTTP request shaping changes, to prove it actually works against
# the real API and not just a plausible-looking stub.
#
# Usage:
#   AGENTILE_AIRTABLE_TOKEN=... ruby dev/smoke-airtable.rb <base-id>
require_relative "../bin/ag-store-adapters/airtable"

base_id = ARGV[0]
if base_id.to_s.empty? || ENV["AGENTILE_AIRTABLE_TOKEN"].to_s.empty?
  abort "usage: AGENTILE_AIRTABLE_TOKEN=... ruby dev/smoke-airtable.rb <base-id>\n" \
        "(point it at a sandbox base you're fine writing test records into and having provisioned)"
end

def step(name)
  print "#{name}... "
  yield
  puts "ok"
rescue => e
  puts "FAILED: #{e.class}: #{e.message}"
  raise
end

adapter = Airtable::Adapter.new(base_id: base_id)

step("provision (idempotent)") { adapter.provision }
step("clean up any stray smoke-test-* records from a prior failed run") do
  client = adapter.instance_variable_get(:@client)
  stray = client.list_records(base_id, "Specs").select { |r| r["fields"]["Slug"].to_s.start_with?("smoke-test-") }
  stray.each { |r| client.delete_record(base_id, "Specs", r["id"]) }
  adapter.invalidate_specs_cache!
end
step("doctor reports the schema present") do
  checks = adapter.doctor
  raise "doctor: #{checks.inspect}" unless checks.values_at("Specs table exists", "Inbox table exists", "Members table exists").all?
end

slug = "smoke-test-#{Time.now.to_i}"
md = <<~MD
  ---
  title: Smoke test spec
  slug: #{slug}
  status: ready
  depends_on: []
  type: feature
  route: background
  business_value: low
  technical_certainty: high
  created: #{Time.now.strftime('%Y-%m-%d')}
  outcome: this script exits zero
  ---

  # Smoke test spec

  ## Problem / why now

  Proving the airtable adapter against a real base.

  ## Acceptance criteria

  - [ ] round-trips through spec_read

  ## Scope boundary

  **In scope:** this script.

  **Out of scope:** everything else.

  ## Edge cases and failure paths

  None — this is a throwaway record, deleted at the end of this run.

  ## Affected areas

  None.

  ## Open questions

  None.

  ## Verification

  This script printing "ALL PASS".
MD

step("inbox_add + inbox_list + inbox_drop round-trip") do
  adapter.inbox_add("smoke test stub #{slug}")
  stub = adapter.inbox_list.find { |s| s[:text].include?(slug) }
  raise "stub not found after inbox_add" unless stub

  adapter.inbox_drop(stub[:id])
  raise "stub still listed after inbox_drop" if adapter.inbox_list.any? { |s| s[:id] == stub[:id] }
end

step("spec_create + spec_read round-trip") do
  adapter.spec_create(slug, md)
  back = adapter.spec_read(slug)
  raise "title missing from spec_read" unless back.include?("Smoke test spec")
  raise "acceptance criteria missing from spec_read" unless back.include?("round-trips through spec_read")
end

step("rank") do
  adapter.rank([slug])
  listed = adapter.spec_list.find { |s| s[:slug] == slug }
  raise "rank not applied: #{listed.inspect}" unless listed[:prefix] == 1
end

step("claim -> release") do
  claimed = adapter.claim("smoke-session", "smoke", "0")
  raise "claim failed: #{claimed}" unless claimed == slug

  adapter.release(slug)
  listed = adapter.spec_list.find { |s| s[:slug] == slug }
  raise "release didn't clear status: #{listed.inspect}" unless listed[:status] == "ready"
end

step("ship") do
  adapter.ship(slug)
  shipped = adapter.spec_list(pool: "done").find { |s| s[:slug] == slug }
  raise "ship didn't land in the done pool: #{shipped.inspect}" unless shipped
end

step("cleanup: delete the smoke-test spec record") do
  r = adapter.spec_by_slug(slug)
  adapter.instance_variable_get(:@client).delete_record(base_id, "Specs", r["id"]) if r
end

puts "ALL PASS"
