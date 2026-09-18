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

# 8. outcome markdown round-trips; spec markdown carries serves + tags
omd = <<~MD
  ---
  title: Buyers cannot reject on identity grounds
  slug: identity
  status: open
  rank: 1
  created: 2026-09-14
  ---

  # Buyers cannot reject on identity grounds

  ## Claim

  Reviewers sign in through their own IdP.

  ## Measure

  A pilot against a real tenant.

  ## Stop rule

  Two buyers accept local accounts.

  ## Notes

  none yet
MD
ov = Airtable::Schema.parse_outcome_markdown(omd)
raise "outcome parse claim: #{ov.inspect}" unless ov[:claim] == "Reviewers sign in through their own IdP."
raise "outcome parse stop_rule: #{ov.inspect}" unless ov[:stop_rule] == "Two buyers accept local accounts."
raise "outcome parse rank: #{ov.inspect}" unless ov[:rank] == "1"
ore = Airtable::Schema.parse_outcome_markdown(Airtable::Schema.render_outcome_markdown(ov))
raise "outcome round-trip" unless ore[:claim] == ov[:claim] && ore[:measure] == ov[:measure] && ore[:notes] == "none yet" && ore[:title] == ov[:title]

smd = md.sub("outcome: no more", "serves: identity\ntags: [auth, testing]\noutcome: no more")
sv = Airtable::Schema.parse_spec_markdown(smd)
raise "spec serves: #{sv.inspect}" unless sv[:serves] == "identity"
raise "spec tags: #{sv.inspect}" unless sv[:tags] == %w[auth testing]
sre = Airtable::Schema.parse_spec_markdown(Airtable::Schema.render_spec_markdown(sv))
raise "spec serves/tags round-trip" unless sre[:serves] == "identity" && sre[:tags] == %w[auth testing]

# 8b. spec markdown carries source_inbox as a raw record id (no lookup — same convention as captured_by/shaped_by)
smd_with_inbox = smd.sub("outcome: no more", "source_inbox: recI1\noutcome: no more")
siv = Airtable::Schema.parse_spec_markdown(smd_with_inbox)
raise "spec source_inbox: #{siv.inspect}" unless siv[:source_inbox] == "recI1"
sire = Airtable::Schema.parse_spec_markdown(Airtable::Schema.render_spec_markdown(siv))
raise "spec source_inbox round-trip" unless sire[:source_inbox] == "recI1"

# 9. Client sends typecast only when asked
transport = FakeTransport.new
transport.push(200, { "records" => [] })
transport.push(200, {})
client = Airtable::Client.new(token: "t", transport: transport)
client.create_records("appTEST", "Specs", [{ "Tags" => ["auth"] }], typecast: true)
client.update_record("appTEST", "Specs", "recA", { "Title" => "x" })
raise "typecast on create: #{transport.calls[0][:body].inspect}" unless transport.calls[0][:body]["typecast"] == true
raise "no typecast by default: #{transport.calls[1][:body].inspect}" if transport.calls[1][:body].key?("typecast")

# 10. outcome_create sends per-field values to the Outcomes table; spec_create with tags sends typecast + Serves Outcome link
transport = FakeTransport.new
transport.push(200, records_page([])) # outcomes lookup (dup check)
transport.push(200, { "records" => [{ "id" => "recO1" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.outcome_create("identity", omd, nil)
oc = transport.calls.last
raise "outcome path: #{oc[:path]}" unless oc[:path] == "/v0/appTEST/Outcomes"
of = oc[:body]["records"][0]["fields"]
raise "outcome fields: #{of.inspect}" unless of["Slug"] == "identity" && of["Claim"] == "Reviewers sign in through their own IdP." && of["Stop Rule"] == "Two buyers accept local accounts." && of["Rank"] == 1 && of["Status"] == "open"

transport = FakeTransport.new
transport.push(200, records_page([])) # specs (depends_on resolution)
transport.push(200, records_page([rec("recO1", { "Slug" => "identity", "Status" => "open" })])) # outcomes (serves resolution)
transport.push(200, { "records" => [{ "id" => "recS1" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.spec_create("sso", smd)
sc = transport.calls.last
raise "spec typecast: #{sc[:body].inspect}" unless sc[:body]["typecast"] == true
sf = sc[:body]["records"][0]["fields"]
raise "spec serves link: #{sf.inspect}" unless sf["Serves Outcome"] == ["recO1"]
raise "spec tags: #{sf.inspect}" unless sf["Tags"] == %w[auth testing]

# 10b. spec_create sends source_inbox straight through to Source Inbox Item — no lookup call, unlike serves
transport = FakeTransport.new
transport.push(200, records_page([])) # specs (depends_on resolution)
transport.push(200, records_page([rec("recO1", { "Slug" => "identity", "Status" => "open" })])) # outcomes (serves resolution)
transport.push(200, { "records" => [{ "id" => "recS1" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.spec_create("sso", smd_with_inbox)
sic = transport.calls.last
sif = sic[:body]["records"][0]["fields"]
raise "spec source_inbox link: #{sif.inspect}" unless sif["Source Inbox Item"] == ["recI1"]

# 10c. spec_read resolves Source Inbox Item to the linked Inbox record's Title, for display only
transport = FakeTransport.new
transport.push(200, records_page([rec("recS9", { "Slug" => "sso", "Title" => "SSO", "Created" => "2026-06-10", "Source Inbox Item" => ["recI1"] })])) # specs_records, via spec_by_slug
transport.push(200, rec("recI1", { "Title" => "Buyers want SSO" })) # get_record on Inbox
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
srv = Airtable::Schema.parse_spec_markdown(adapter.spec_read("sso"))
raise "spec_read source_inbox: #{srv.inspect}" unless srv[:source_inbox] == "Buyers want SSO"

# 11. map: groups specs by Serves Outcome, computes blocked from Depends On, indexes tags
transport = FakeTransport.new
transport.push(200, records_page([
                     rec("recA", { "Slug" => "oidc", "Status" => "ready", "Serves Outcome" => ["recO1"], "Tags" => ["auth"] }),
                     rec("recB", { "Slug" => "scim", "Status" => "ready", "Serves Outcome" => ["recO1"], "Depends On" => ["recA"], "Tags" => %w[auth lifecycle] }),
                     rec("recC", { "Slug" => "free", "Status" => "shipped" }),
                   ]))
transport.push(200, records_page([rec("recO1", { "Slug" => "identity", "Title" => "Identity", "Status" => "open", "Rank" => 1 })]))
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
m = adapter.map
o = m[:outcomes][0]
raise "map outcome: #{o.inspect}" unless o[:slug] == "identity" && o[:specs]["ready"] == %w[oidc scim] && o[:blocked] == %w[scim]
raise "map unlinked: #{m[:unlinked].inspect}" unless m[:unlinked]["shipped"] == %w[free]
raise "map tags: #{m[:tags].inspect}" unless m[:tags] == { "auth" => %w[oidc scim], "lifecycle" => %w[scim] }

# 12. doctor reports a missing Outcomes table and the new Specs fields as drift
transport = FakeTransport.new
transport.push(200, { "tables" => [{ "name" => "Specs", "fields" => [{ "name" => "Slug" }] }, { "name" => "Inbox", "fields" => [] }, { "name" => "Members", "fields" => [] }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
checks = adapter.doctor
raise "doctor outcomes table: #{checks.inspect}" unless checks["Outcomes table exists"] == false
raise "doctor drift: #{checks.inspect}" unless checks["missing fields"].include?("Specs.Serves Outcome") && checks["missing fields"].include?("Specs.Tags") && checks["missing fields"].include?("Specs.Source Inbox Item")

# 13. spec_write accepts bracketed list strings from --set for tags and depends_on (the CLI hands strings, not arrays)
transport = FakeTransport.new
transport.push(200, records_page([rec("recS1", { "Slug" => "sso", "Status" => "ready" }), rec("recD", { "Slug" => "dep", "Status" => "ready" })]))
transport.push(200, {})
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.spec_write("sso", { tags: "[testing, ui]", depends_on: "[dep]" })
wc = transport.calls.last
raise "spec_write tags from string: #{wc[:body].inspect}" unless wc[:body]["fields"]["Tags"] == %w[testing ui] && wc[:body]["typecast"] == true
raise "spec_write depends_on from string: #{wc[:body].inspect}" unless wc[:body]["fields"]["Depends On"] == ["recD"]

# 14. blank frontmatter values: date/number fields are dropped on create and sent as null on write (Airtable rejects "")
bmd = md.sub("created: 2026-06-10\n", "created: 2026-06-10\nrank:\nclaimed_by:\nlabel:\nclaimed_at:\n")
transport = FakeTransport.new
transport.push(200, records_page([]))
transport.push(200, { "records" => [{ "id" => "recB" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.spec_create("blank", bmd)
bf = transport.calls.last[:body]["records"][0]["fields"]
raise "blank date/number sent on create: #{bf.inspect}" if bf.key?("Claimed At") || bf.key?("Rank")
raise "blank text dropped on create: #{bf.inspect}" unless bf["Label"] == "" && bf["Claimed By (Session)"] == ""
transport = FakeTransport.new
transport.push(200, records_page([rec("recB", { "Slug" => "blank", "Status" => "ready" })]))
transport.push(200, {})
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.spec_write("blank", { claimed_at: "", shipped_at: "" })
wf = transport.calls.last[:body]["fields"]
raise "blank date on write should be null: #{wf.inspect}" unless wf.key?("Claimed At") && wf["Claimed At"].nil? && wf["Shipped At"].nil?

# 15. Created At (datetime) replaces Created (date); spec markdown round-trips created_at
raise "Created At in schema" unless Airtable::Schema::SPECS_BASE_FIELDS.any? { |f| f[:name] == "Created At" && f[:type] == "dateTime" }
cmd = md.sub("created: 2026-06-10", 'created_at: "2026-06-10T09:00:00Z"')
cv = Airtable::Schema.parse_spec_markdown(cmd)
raise "parse created_at: #{cv.inspect}" unless cv[:created_at] == '"2026-06-10T09:00:00Z"' || cv[:created_at] == "2026-06-10T09:00:00Z"
rt = Airtable::Schema.parse_spec_markdown(Airtable::Schema.render_spec_markdown(cv))
raise "created_at round-trip: #{rt[:created_at].inspect}" unless rt[:created_at].to_s.include?("2026-06-10T09:00:00")

transport = FakeTransport.new
transport.push(200, records_page([]))
transport.push(200, records_page([]))
transport.push(200, { "records" => [{ "id" => "recC" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.spec_create("dated", cmd)
cf = transport.calls.last[:body]["records"][0]["fields"]
raise "sends Created At: #{cf.inspect}" unless cf["Created At"].to_s.include?("2026-06-10T09:00:00")

# 16. flow: computed from the record's timestamps, falling back to the legacy Created date
transport = FakeTransport.new
transport.push(200, records_page([rec("recF", {
  "Slug" => "shipped-thing", "Status" => "shipped",
  "Created" => "2026-09-01", "Claimed At" => "2026-09-01T10:00:00.000Z",
  "Shipped At" => "2026-09-01T13:00:00.000Z" })]))
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
f = adapter.flow("/nonexistent-dir", "shipped-thing")
raise "cycle: #{f.inspect}" unless f[:cycle_seconds] == 10800
raise "no checkpoints -> zero human wait: #{f.inspect}" unless f[:human_wait_seconds] == 0 && f[:agent_seconds] == 10800
raise "legacy Created fallback: #{f.inspect}" unless f[:queue_wait_seconds] == 36000   # 00:00 -> 10:00
raise "in_progress: #{f.inspect}" unless f[:in_progress] == false

# 17. spec_read surfaces the legacy Created date when Created At is empty (no data loss on read)
transport = FakeTransport.new
transport.push(200, records_page([rec("recL", { "Slug" => "legacy", "Status" => "ready", "Title" => "Legacy",
                                                "Created" => "2026-09-13" })]))
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
out = adapter.spec_read("legacy")
raise "legacy created lost on read: #{out[0, 200].inspect}" unless out.include?("2026-09-13")

# 18. checkpoints and run events are store records; flow reads checkpoints from the store, not files
raise "Checkpoints schema" unless defined?(Airtable::Schema::CHECKPOINTS_BASE_FIELDS)
raise "Runs schema" unless defined?(Airtable::Schema::RUNS_BASE_FIELDS)
raise "Checkpoints link to Specs" unless Airtable::Schema::LINK_FIELDS[:checkpoints].any? { |f| f[0] == "Spec" }
raise "Runs link to Specs" unless Airtable::Schema::LINK_FIELDS[:runs].any? { |f| f[0] == "Spec" }

# open a checkpoint -> creates a record linked to the spec
transport = FakeTransport.new
transport.push(200, records_page([rec("recS", { "Slug" => "cp", "Status" => "in_progress" })]))  # spec lookup
transport.push(200, records_page([]))                                                            # existing checkpoints
transport.push(200, { "records" => [{ "id" => "recCP1" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
id = adapter.checkpoint_open("cp", "ship_approval", "Approve to ship cp?", session: "s1", by: "ship")
raise "returns record id: #{id.inspect}" unless id == "recCP1"
call = transport.calls.last
raise "checkpoint path: #{call[:path]}" unless call[:path] == "/v0/appTEST/Checkpoints"
cf = call[:body]["records"][0]["fields"]
raise "checkpoint fields: #{cf.inspect}" unless cf["Reason"] == "ship_approval" && cf["Asked By"] == "ship" &&
  cf["Status"] == "open" && cf["Ask"] == "Approve to ship cp?" && cf["Spec"] == ["recS"] && cf["Seq"] == 1 &&
  !cf["Asked At"].to_s.empty?

# list projects the same canonical shape the local store returns
transport = FakeTransport.new
transport.push(200, records_page([rec("recS", { "Slug" => "cp" })]))
transport.push(200, records_page([rec("recCP1", { "Spec" => ["recS"], "Seq" => 1, "Reason" => "ship_approval",
  "Asked By" => "ship", "Asked At" => "2026-09-01T12:30:00.000Z", "Status" => "answered",
  "Ask" => "ship?", "Answer" => "approved", "Answered At" => "2026-09-01T13:00:00.000Z" })]))
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
l = adapter.checkpoint_list("cp")
raise "list: #{l.inspect}" unless l.length == 1 && l[0][:id] == "recCP1" && l[0][:reason] == "ship_approval" &&
  l[0][:ask] == "ship?" && l[0][:answer] == "approved" && l[0][:status] == "answered"

# run_event creates a Runs record
transport = FakeTransport.new
transport.push(200, records_page([rec("recS", { "Slug" => "cp" })]))
transport.push(200, { "records" => [{ "id" => "recR1" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.run_event("claimed", spec: "cp", runner: "r1", detail: "rank 1")
rc = transport.calls.last
raise "runs path: #{rc[:path]}" unless rc[:path] == "/v0/appTEST/Runs"
rf = rc[:body]["records"][0]["fields"]
raise "run fields: #{rf.inspect}" unless rf["Event"] == "claimed" && rf["Runner"] == "r1" &&
  rf["Detail"] == "rank 1" && rf["Spec"] == ["recS"] && !rf["At"].to_s.empty?

# flow takes its human-wait from the store's checkpoints
transport = FakeTransport.new
transport.push(200, records_page([rec("recS", { "Slug" => "cp", "Status" => "shipped",
  "Created At" => "2026-09-01T09:00:00.000Z", "Claimed At" => "2026-09-01T10:00:00.000Z",
  "Shipped At" => "2026-09-01T13:00:00.000Z" })]))
transport.push(200, records_page([rec("recCP1", { "Spec" => ["recS"], "Seq" => 1, "Reason" => "ship_approval",
  "Asked By" => "ship", "Asked At" => "2026-09-01T12:30:00.000Z", "Status" => "answered",
  "Answered At" => "2026-09-01T13:00:00.000Z" })]))
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
f = adapter.flow(nil, "cp")
raise "flow human wait from store: #{f.inspect}" unless f[:human_wait_seconds] == 1800
raise "flow agent: #{f.inspect}" unless f[:agent_seconds] == 9000 && f[:cycle_seconds] == 10800

# 19. Runs carry a Status so the Airtable view can hide finished runs; closing appends
raise "Runs Status field" unless Airtable::Schema::RUNS_BASE_FIELDS.any? { |f| f[:name] == "Status" }
raise "closed is a valid event" unless Airtable::Schema::RUNS_BASE_FIELDS
  .find { |f| f[:name] == "Event" }[:options][:choices].map { |c| c[:name] }.include?("closed")

transport = FakeTransport.new
transport.push(200, records_page([rec("recS", { "Slug" => "alpha" })]))
transport.push(200, { "records" => [{ "id" => "recR1" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.run_event("claimed", spec: "alpha", runner: "r1")
raise "claimed active: #{transport.calls.last[:body].inspect}" unless transport.calls.last[:body]["records"][0]["fields"]["Status"] == "active"

transport = FakeTransport.new
transport.push(200, records_page([rec("recS", { "Slug" => "alpha" })]))
transport.push(200, { "records" => [{ "id" => "recR2" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.run_event("shipped", spec: "alpha", runner: "r1")
raise "shipped closed: #{transport.calls.last[:body].inspect}" unless transport.calls.last[:body]["records"][0]["fields"]["Status"] == "closed"

# run_list --status active drops pairs whose last event was terminal
transport = FakeTransport.new
transport.push(200, records_page([
  rec("r1", { "At" => "2026-09-01T10:00:00.000Z", "Event" => "claimed", "Runner" => "a", "Spec" => ["recA"], "Status" => "active" }),
  rec("r2", { "At" => "2026-09-01T11:00:00.000Z", "Event" => "shipped", "Runner" => "a", "Spec" => ["recA"], "Status" => "closed" }),
  rec("r3", { "At" => "2026-09-01T12:00:00.000Z", "Event" => "claimed", "Runner" => "b", "Spec" => ["recB"], "Status" => "active" }),
]))
transport.push(200, records_page([rec("recA", { "Slug" => "alpha" }), rec("recB", { "Slug" => "beta" })]))
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
live = adapter.run_list(status: "active").map { |e| e[:spec] }.uniq
raise "active only beta: #{live.inspect}" unless live == ["beta"]

# 20. Airtable cannot add a choice to an existing select via the API (both PATCH forms 422),
#     so a value added to the schema later reaches a live base by `typecast` on first write.
#     doctor still reports the drift so it is visible rather than silently self-healing.
transport = FakeTransport.new
existing_event_field = { "id" => "fldEV", "name" => "Event",
                         "options" => { "choices" => [{ "id" => "sel1", "name" => "claimed" }] } }
tables = [{ "id" => "tblR", "name" => "Runs", "fields" => [existing_event_field] }]
client = Airtable::Client.new(token: "t", transport: FakeTransport.new)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
missing = adapter.missing_select_choices(tables)
raise "detects missing choices: #{missing.inspect}" unless missing.any? { |m| m.include?("Runs.Event") && m.include?("closed") }

# run_event writes with typecast, which is what lets the unknown option be created
transport = FakeTransport.new
transport.push(200, records_page([rec("recS", { "Slug" => "alpha" })]))
transport.push(200, { "records" => [{ "id" => "recR9" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.run_event("closed", spec: "alpha", runner: "r1")
raise "run_event uses typecast: #{transport.calls.last[:body].inspect}" unless transport.calls.last[:body]["typecast"] == true

# so does opening a checkpoint (Reason and Status are both selects)
transport = FakeTransport.new
transport.push(200, records_page([rec("recS", { "Slug" => "alpha" })]))
transport.push(200, records_page([]))
transport.push(200, { "records" => [{ "id" => "recCP9" }] })
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
adapter.checkpoint_open("alpha", "question", "?", by: "builder")
raise "checkpoint_open uses typecast: #{transport.calls.last[:body].inspect}" unless transport.calls.last[:body]["typecast"] == true

puts "ALL PASS"