# Unit-level tests for the airtable store adapter — the HTTP transport is
# stubbed (FakeTransport), so this suite makes NO real network calls and
# needs no credentials. It verifies request shaping (what bin/ag-store-adapters
# would actually send Airtable) and the fields <-> canonical-markdown
# round-trip, not live Airtable behaviour — see dev/smoke-airtable.rb for
# that (manual, needs a real token + base).
require "json"
require_relative "../bin/ag-store-adapters/airtable/client"
require_relative "../bin/ag-store-adapters/airtable/schema"
require_relative "../bin/ag-store-adapters/airtable"

# Records every call; serves canned [status, body] pairs from a queue (or,
# for list_records-style GETs, a single reusable page so tests don't have to
# enumerate pagination). Queue entries are consumed in order — a test that
# needs a specific sequence (claim's read -> update -> re-read) pushes
# exactly that many responses.
class FakeTransport
  attr_reader :calls

  def initialize(queue = [])
    @queue = queue
    @calls = []
  end

  def push(status, body)
    @queue << [status, JSON.generate(body)]
  end

  def call(method, uri, headers, body_json)
    @calls << { method: method, path: uri.path, query: uri.query, body: body_json && JSON.parse(body_json) }
    @queue.shift || [200, "{}"]
  end
end

def records_page(records, offset: nil)
  { "records" => records, "offset" => offset }.compact
end

def rec(id, fields)
  { "id" => id, "fields" => fields }
end

# 1. schema round-trip: every frontmatter key and every body section survives
#    parse -> render, so the boundary contract (canonical markdown in/out) holds
#    regardless of the airtable adapter's fully-decomposed internal storage.
md = <<~MD
  ---
  title: Rate-limit the login endpoint
  slug: rate-limit-login
  status: ready
  depends_on: [auth-tokens]
  type: feature
  route: foreground
  business_value: high
  technical_certainty: high
  created: 2026-06-10
  outcome: no more than 5 failed attempts per IP per minute
  ---

  # Rate-limit the login endpoint

  ## Problem / why now

  Saw a brute-force attempt in the logs last week.

  ## Acceptance criteria

  - [ ] 6th attempt within 60s from one IP is rejected with 429

  ## Scope boundary

  **In scope:** the /login endpoint only.

  **Out of scope:** other auth endpoints, CAPTCHA.

  ## Edge cases and failure paths

  Shared NAT IPs must not lock out unrelated users.

  ## Affected areas

  apps/api/auth.py

  ## Open questions

  None.

  ## Verification

  Load test confirms the 429 after the 6th attempt.
MD

parsed = Airtable::Schema.parse_spec_markdown(md)
raise "parse title: #{parsed[:title]}" unless parsed[:title] == "Rate-limit the login endpoint"
raise "parse depends_on: #{parsed[:depends_on].inspect}" unless parsed[:depends_on] == ["auth-tokens"]
raise "parse problem: #{parsed[:problem].inspect}" unless parsed[:problem] == "Saw a brute-force attempt in the logs last week."
raise "parse scope_in: #{parsed[:scope_in].inspect}" unless parsed[:scope_in] == "the /login endpoint only."
raise "parse scope_out: #{parsed[:scope_out].inspect}" unless parsed[:scope_out] == "other auth endpoints, CAPTCHA."
raise "parse verification: #{parsed[:verification].inspect}" unless parsed[:verification].include?("Load test")

rendered = Airtable::Schema.render_spec_markdown(parsed)
reparsed = Airtable::Schema.parse_spec_markdown(rendered)
raise "round-trip title" unless reparsed[:title] == parsed[:title]
raise "round-trip scope_in" unless reparsed[:scope_in] == parsed[:scope_in]
raise "round-trip scope_out" unless reparsed[:scope_out] == parsed[:scope_out]
raise "round-trip depends_on" unless reparsed[:depends_on] == parsed[:depends_on]

# 2. spec_create sends real per-field values to the Specs table — no blob field
transport = FakeTransport.new
transport.push(200, records_page([])) # spec_by_slug's dependency lookup (Depends On resolution) during build_fields
transport.push(200, { "records" => [{ "id" => "recNEW" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.spec_create("rate-limit-login", md)
create_call = transport.calls.last
raise "create path: #{create_call[:path]}" unless create_call[:path] == "/v0/appTEST/Specs"
fields = create_call[:body]["records"][0]["fields"]
raise "no blob field" if fields.key?("Spec Markdown") || fields.key?("Markdown") || fields.key?("Body")
raise "create Title: #{fields.inspect}" unless fields["Title"] == "Rate-limit the login endpoint"
raise "create Problem field: #{fields.inspect}" unless fields["Problem / Why Now"] == "Saw a brute-force attempt in the logs last week."
raise "create Scope In field: #{fields.inspect}" unless fields["Scope In"] == "the /login endpoint only."

# 3. claim: picks the lowest-Rank eligible ready spec, stamps it, and confirms via a re-read
transport = FakeTransport.new
transport.push(200, records_page([
                     rec("recB", { "Slug" => "b", "Status" => "ready", "Rank" => 2, "Claimed By (Session)" => "" }),
                     rec("recA", { "Slug" => "a", "Status" => "ready", "Rank" => 1, "Claimed By (Session)" => "" }),
                   ]))
transport.push(200, {}) # the update
transport.push(200, rec("recA", { "Slug" => "a", "Claimed By (Session)" => "sess-1" })) # the confirming re-read
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
claimed = adapter.claim("sess-1", "", "0")
raise "claim picked wrong spec: #{claimed}" unless claimed == "a"
update_call = transport.calls[1]
raise "claim update path: #{update_call[:path]}" unless update_call[:path] == "/v0/appTEST/Specs/recA"
raise "claim stamps identity: #{update_call[:body].inspect}" unless update_call[:body]["fields"]["Claimed By (Session)"] == "sess-1"

# 3b. claim reports a lost race honestly (re-read shows a different claimant)
transport = FakeTransport.new
transport.push(200, records_page([rec("recA", { "Slug" => "a", "Status" => "ready", "Rank" => 1, "Claimed By (Session)" => "" })]))
transport.push(200, {})
transport.push(200, rec("recA", { "Slug" => "a", "Claimed By (Session)" => "someone-else" }))
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
raise "lost race should report NONE: #{adapter.claim('sess-1', '', '0')}" unless adapter.claim("sess-1", "", "0") == "NONE"

# 4. rank issues one batch of PATCHes with dense Rank values in the given order
transport = FakeTransport.new
transport.push(200, records_page([
                     rec("recA", { "Slug" => "a", "Status" => "ready" }),
                     rec("recB", { "Slug" => "b", "Status" => "ready" }),
                   ]))
transport.push(200, {})
transport.push(200, {})
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.rank(%w[b a])
patches = transport.calls.drop(1)
raise "rank order: #{patches.map { |c| c[:path] }}" unless patches[0][:path] == "/v0/appTEST/Specs/recB" && patches[0][:body]["fields"]["Rank"] == 1
raise "rank order 2: #{patches.map { |c| c[:path] }}" unless patches[1][:path] == "/v0/appTEST/Specs/recA" && patches[1][:body]["fields"]["Rank"] == 2

# 5. Client#list_records follows pagination via offset
transport = FakeTransport.new
transport.push(200, records_page([rec("rec1", {})], offset: "off1"))
transport.push(200, records_page([rec("rec2", {})]))
client = Airtable::Client.new(token: "t", transport: transport)
got = client.list_records("appTEST", "Specs")
raise "pagination: #{got.map { |r| r['id'] }}" unless got.map { |r| r["id"] } == %w[rec1 rec2]

# 6. Client#request raises ApiError with the server's message on a non-2xx
transport = FakeTransport.new
transport.push(422, { "error" => { "type" => "INVALID_REQUEST", "message" => "Unknown field name" } })
client = Airtable::Client.new(token: "t", transport: transport)
begin
  client.request(:post, "/v0/appTEST/Specs", body: { records: [] })
  raise "expected ApiError"
rescue Airtable::ApiError => e
  raise "error message: #{e.message}" unless e.message.include?("Unknown field name")
end

# 7. doctor reports missing tables without raising, when the base has none yet
transport = FakeTransport.new
transport.push(200, { "tables" => [{ "name" => "Specs" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
checks = adapter.doctor
raise "doctor: #{checks.inspect}" unless checks["Specs table exists"] == true && checks["Inbox table exists"] == false

puts "ALL PASS"
