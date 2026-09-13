# frozen_string_literal: true
# The `airtable` store adapter. Same op contract as local.rb, backed by an
# Airtable base instead of files+git. See docs/agentile-workspaces-participants-and-stores.md
# for the design rationale and templates/stores/airtable/README.md for setup.
#
# Known limitation (see the team-mode plan's "Known limitations" section):
# claim/rank are NOT atomic here — Airtable has no server-side conditional
# write. claim does read -> check empty -> update -> re-read to confirm;
# rank is a batch field update. Both leave a small race window, stated
# honestly rather than papered over.
require "set"
require_relative "airtable/client"
require_relative "airtable/schema"

module Airtable
  # Creates a brand-new base with the three tables (base fields first, then
  # the link fields once every table's id is known) and returns its id. No
  # Adapter exists yet at this point — there's no base_id to construct one
  # with — so this is a module-level entry point, used once by /ag-init's
  # "create a new base" team-mode flow. Attaching to an EXISTING base instead
  # goes through Adapter#provision.
  def self.create_base(token:, workspace_id:, name:, inbox_table: "Inbox", specs_table: "Specs", members_table: "Members")
    client = Client.new(token: token)
    tables_def = [
      { name: specs_table, fields: Schema::SPECS_BASE_FIELDS },
      { name: inbox_table, fields: Schema::INBOX_BASE_FIELDS },
      { name: members_table, fields: Schema::MEMBERS_BASE_FIELDS },
    ]
    created = client.create_base(workspace_id, name, tables_def)
    base_id = created["id"]
    table_ids = {}
    created["tables"].each do |t|
      table_ids[:specs] = t["id"] if t["name"] == specs_table
      table_ids[:inbox] = t["id"] if t["name"] == inbox_table
      table_ids[:members] = t["id"] if t["name"] == members_table
    end

    adapter = Adapter.new(base_id: base_id, inbox_table: inbox_table, specs_table: specs_table,
                           members_table: members_table, token: token, client: client)
    adapter.ensure_link_fields(table_ids[:specs], :specs, table_ids)
    adapter.ensure_link_fields(table_ids[:inbox], :inbox, table_ids)
    base_id
  end

  class Adapter
    SPECS_FIELDS = {
      title: "Title", slug: "Slug", status: "Status", type: "Type", route: "Route",
      business_value: "Business Value", technical_certainty: "Technical Certainty",
      rank: "Rank", outcome: "Outcome", problem: "Problem / Why Now",
      acceptance_criteria: "Acceptance Criteria", scope_in: "Scope In", scope_out: "Scope Out",
      edge_cases: "Edge Cases", affected_areas: "Affected Areas", open_questions: "Open Questions",
      verification: "Verification", created: "Created", plan_path: "Plan Path",
      claimed_by: "Claimed By (Session)", label: "Label", claimed_at: "Claimed At",
      shipped_at: "Shipped At", abandoned_reason: "Abandoned Reason", abandoned_at: "Abandoned At",
    }.freeze
    SPECS_LINK_FIELDS = { depends_on: "Depends On", claimed_by_member: "Claimed By (Member)",
                          captured_by: "Captured By", shaped_by: "Shaped By" }.freeze
    INBOX_FIELDS = { text: "Text", captured_at: "Captured At", status: "Status" }.freeze

    def initialize(base_id:, inbox_table: "Inbox", specs_table: "Specs", members_table: "Members",
                   token: ENV.fetch("AGENTILE_AIRTABLE_TOKEN", nil), client: nil)
      abort "ag-store: --airtable-base is required for the airtable store" if base_id.to_s.empty?
      abort "ag-store: AGENTILE_AIRTABLE_TOKEN is not set" if client.nil? && token.to_s.empty?

      @base_id = base_id
      @inbox_table = inbox_table
      @specs_table = specs_table
      @members_table = members_table
      @client = client || Client.new(token: token)
    end

    # ---- lookups (id <-> slug/name), fetched lazily and cached per invocation ----

    def specs_records
      @specs_records ||= @client.list_records(@base_id, @specs_table)
    end

    # Every op that writes to the Specs table calls this afterward. Within
    # one `ag-store` CLI invocation this never matters (one op, fresh
    # process, cache never outlives it) — it matters for anything that
    # reuses one Adapter across several ops (dev/smoke-airtable.rb, or any
    # future in-process embedding), where a write must be visible to the
    # next read on the same instance.
    def invalidate_specs_cache!
      @specs_records = nil
    end

    def spec_by_slug(slug)
      bare = slug.to_s.sub(/\A\d+-/, "")
      specs_records.find { |r| r["fields"]["Slug"] == bare || r["id"] == slug }
    end

    def slug_of(record_id)
      (specs_records.find { |r| r["id"] == record_id } || {}).dig("fields", "Slug")
    end

    def members_records
      @members_records ||= @client.list_records(@base_id, @members_table)
    end

    def member_name_of(record_id)
      (members_records.find { |r| r["id"] == record_id } || {}).dig("fields", "Name")
    end

    def find_member_by_email(email)
      members_records.find { |r| r["fields"]["Git Email"] == email || r["fields"]["Email"] == email }
    end

    # ---- whoami ----

    def whoami
      email = `git config user.email 2>/dev/null`.strip
      return "unknown" if email.empty?

      member = find_member_by_email(email)
      member ? member["id"] : "unknown: no Members match for #{email} — add yourself to the Members table"
    end

    # ---- inbox ----

    def inbox_list
      @client.list_records(@base_id, @inbox_table)
             .select { |r| r["fields"]["Status"].to_s.empty? || r["fields"]["Status"] == "Open" }
             .map do |r|
        member_ids = r["fields"]["Captured By"] || []
        {
          id: r["id"],
          text: r["fields"]["Text"],
          captured_at: r["fields"]["Captured At"],
          captured_by: member_ids.map { |m| member_name_of(m) }.compact.first,
        }
      end
    end

    def inbox_add(text, captured_by = nil)
      fields = { "Text" => text, "Captured At" => Time.now.strftime("%Y-%m-%d"), "Status" => "Open" }
      fields["Captured By"] = [captured_by] if captured_by.to_s.start_with?("rec")
      @client.create_records(@base_id, @inbox_table, [fields])
      true
    end

    def inbox_drop(id)
      @client.update_record(@base_id, @inbox_table, id, { "Status" => "Dropped" })
      true
    end

    # ---- spec projection (matches local's spec_list shape) ----

    def project_spec_summary(r)
      f = r["fields"]
      {
        slug: f["Slug"],
        prefix: f["Rank"],
        path: r["id"],
        status: f["Status"],
        title: f["Title"],
        created: f["Created"],
        business_value: f["Business Value"],
        technical_certainty: f["Technical Certainty"],
        route: f["Route"],
        depends_on: (f["Depends On"] || []).map { |id| slug_of(id) }.compact,
        claimed_by: f["Claimed By (Session)"],
        claimed_at: f["Claimed At"],
        label: f["Label"],
        shipped_at: f["Shipped At"],
      }
    end

    def spec_list(status: nil, pool: "active")
      pool_statuses = case pool
                       when "active" then %w[ready in_progress]
                       when "done" then %w[shipped]
                       when "abandoned" then %w[abandoned]
                       else abort "ag-store: unknown pool: #{pool}"
                       end
      recs = specs_records.select { |r| pool_statuses.include?(r["fields"]["Status"]) }
      recs = recs.select { |r| r["fields"]["Status"] == status } if status
      recs.sort_by { |r| [r["fields"]["Rank"] || 1_000_000, r["fields"]["Slug"].to_s] }
          .map { |r| project_spec_summary(r) }
    end

    # ---- spec read / create / write (canonical markdown at the boundary) ----

    def resolved_values_for_read(r)
      f = r["fields"]
      v = {}
      SPECS_FIELDS.each { |canon, name| v[canon] = f[name] }
      v[:depends_on] = (f["Depends On"] || []).map { |id| slug_of(id) }.compact
      v[:captured_by] = (f["Captured By"] || []).map { |id| member_name_of(id) }.compact
      v[:shaped_by] = (f["Shaped By"] || []).map { |id| member_name_of(id) }.compact
      v[:claimed_by_member] = member_name_of(Array(f["Claimed By (Member)"]).first)
      v
    end

    def spec_read(ident)
      r = spec_by_slug(ident)
      abort "ag-store: no such spec: #{ident}" unless r

      Schema.render_spec_markdown(resolved_values_for_read(r))
    end

    # Builds the Airtable API `fields` hash from canonical values, resolving
    # depends_on slugs -> Specs record ids. Member-link canonical keys
    # (captured_by/shaped_by/claimed_by_member) are expected already-resolved
    # to record ids by the caller (they come from `whoami`, not free text).
    def build_fields(v)
      fields = {}
      SPECS_FIELDS.each { |canon, name| fields[name] = v[canon] if v.key?(canon) }
      if v.key?(:depends_on)
        fields["Depends On"] = Array(v[:depends_on]).filter_map { |slug| spec_by_slug(slug)&.dig("id") }
      end
      fields["Captured By"] = Array(v[:captured_by]) if v.key?(:captured_by)
      fields["Shaped By"] = Array(v[:shaped_by]) if v.key?(:shaped_by)
      fields["Claimed By (Member)"] = Array(v[:claimed_by_member]) if v.key?(:claimed_by_member)
      fields
    end

    def spec_create(slug, markdown)
      v = Schema.parse_spec_markdown(markdown)
      v[:slug] = slug
      v[:status] ||= "ready"
      @client.create_records(@base_id, @specs_table, [build_fields(v)])
      invalidate_specs_cache!
      slug
    end

    def spec_write(ident, canonical_fields)
      r = spec_by_slug(ident)
      abort "ag-store: no such spec: #{ident}" unless r

      @client.update_record(@base_id, @specs_table, r["id"], build_fields(canonical_fields))
      invalidate_specs_cache!
      r["id"]
    end

    # ---- rank (batch field update — see the file header's concurrency note) ----

    def rank(ordered_slugs)
      updates = ordered_slugs.each_with_index.filter_map do |slug, i|
        r = spec_by_slug(slug)
        next unless r && r["fields"]["Status"] == "ready"

        [r["id"], i + 1]
      end
      updates.each { |record_id, n| @client.update_record(@base_id, @specs_table, record_id, { "Rank" => n }) }
      invalidate_specs_cache!
      updates.map(&:first)
    end

    # ---- claim (read -> check -> update -> re-read; see the concurrency note) ----

    def claim(identity, label, wip)
      wip = wip.to_s.empty? ? 0 : wip.to_i
      @specs_records = nil # force a fresh read — claim must not work from a stale cache
      pool = specs_records

      in_progress = pool.count { |r| r["fields"]["Status"] == "in_progress" }
      return "WIP_FULL" if wip.positive? && in_progress >= wip

      ready = pool.select { |r| r["fields"]["Status"] == "ready" && r["fields"]["Claimed By (Session)"].to_s.empty? }
      return "NONE" if ready.empty?

      prioritised = ready.select { |r| r["fields"]["Rank"] }
      return "UNPRIORITISED" if prioritised.empty?

      shipped_slugs = pool.select { |r| r["fields"]["Status"] == "shipped" }.map { |r| r["fields"]["Slug"] }.to_set
      eligible = prioritised.select do |r|
        (r["fields"]["Depends On"] || []).all? { |dep_id| shipped_slugs.include?(slug_of(dep_id)) }
      end
      return "BLOCKED" if eligible.empty?

      chosen = eligible.min_by { |r| [r["fields"]["Rank"], r["fields"]["Slug"]] }
      @client.update_record(@base_id, @specs_table, chosen["id"], {
                               "Status" => "in_progress", "Claimed By (Session)" => identity.to_s,
                               "Label" => label.to_s, "Claimed At" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
                             })
      # Re-read to confirm this write actually stuck (see concurrency note) —
      # not a hard guarantee, but catches the common case of a lost race.
      confirmed = @client.get_record(@base_id, @specs_table, chosen["id"])
      invalidate_specs_cache!
      if confirmed["fields"]["Claimed By (Session)"] != identity.to_s
        return "NONE" # lost the race — caller should retry
      end

      chosen["fields"]["Slug"]
    end

    def release(ident)
      r = spec_by_slug(ident)
      abort "ag-store: no such spec: #{ident}" unless r

      @client.update_record(@base_id, @specs_table, r["id"],
                             { "Status" => "ready", "Claimed By (Session)" => "", "Label" => "", "Claimed At" => nil })
      invalidate_specs_cache!
      true
    end

    def ship(ident)
      r = spec_by_slug(ident)
      abort "ag-store: no such spec: #{ident}" unless r

      @client.update_record(@base_id, @specs_table, r["id"],
                             { "Status" => "shipped", "Shipped At" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ") })
      invalidate_specs_cache!
      r["id"]
    end

    def abandon(ident, reason:)
      r = spec_by_slug(ident)
      abort "ag-store: no such spec: #{ident}" unless r

      @client.update_record(@base_id, @specs_table, r["id"], {
                               "Status" => "abandoned",
                               "Abandoned At" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
                               "Abandoned Reason" => reason,
                               "Claimed By (Session)" => "", "Label" => "", "Claimed At" => nil,
                             })
      invalidate_specs_cache!
      r["id"]
    end

    def deps(ident)
      r = spec_by_slug(ident)
      abort "ag-store: no such spec: #{ident}" unless r

      (r["fields"]["Depends On"] || []).map { |id| slug_of(id) }.compact
    end

    # Transitive ACTIVE (ready/in_progress) dependents of target, nearest first.
    def dependents(target)
      reverse = Hash.new { |h, k| h[k] = [] }
      specs_records.each do |r|
        next unless %w[ready in_progress].include?(r["fields"]["Status"])

        deps = (r["fields"]["Depends On"] || []).map { |id| slug_of(id) }.compact
        deps.each { |dep_slug| reverse[dep_slug] << r["fields"]["Slug"] }
      end
      out = []
      seen = { target.to_s => true }
      queue = reverse[target.to_s].dup
      until queue.empty?
        s = queue.shift
        next if seen[s]

        seen[s] = true
        out << s
        queue.concat(reverse[s])
      end
      out
    end

    # ---- promote / attach ----
    # Airtable specs have no filesystem directory of their own; "promotion"
    # is a no-op here — the repo-relative plan directory convention
    # (<Agentile dir>/specs/<slug>/plan.md) is just declared, not created by
    # renaming anything. attach records it on the record for anyone reading
    # the base directly (Airtable's own view) to find the plan.

    def promote(ident, agentile_dir)
      r = spec_by_slug(ident)
      abort "ag-store: no such spec: #{ident}" unless r

      File.join(agentile_dir, "specs", r["fields"]["Slug"])
    end

    def attach(ident, plan_path)
      r = spec_by_slug(ident)
      abort "ag-store: no such spec: #{ident}" unless r

      @client.update_record(@base_id, @specs_table, r["id"], { "Plan Path" => plan_path })
      invalidate_specs_cache!
      plan_path
    end

    # ---- doctor / provision ----

    def doctor
      tables = @client.list_tables(@base_id)
      names = tables.map { |t| t["name"] }
      {
        "base reachable" => true,
        "Inbox table exists" => names.include?(@inbox_table),
        "Specs table exists" => names.include?(@specs_table),
        "Members table exists" => names.include?(@members_table),
      }
    rescue Airtable::ApiError => e
      { "base reachable" => false, "error" => e.message }
    end

    # Idempotently creates the three tables (base fields first, then the
    # link fields once every table's id is known) — safe to re-run.
    def provision
      existing = @client.list_tables(@base_id).to_h { |t| [t["name"], t] }

      specs_id = ensure_table(existing, @specs_table, Schema::SPECS_BASE_FIELDS)
      inbox_id = ensure_table(existing, @inbox_table, Schema::INBOX_BASE_FIELDS)
      members_id = ensure_table(existing, @members_table, Schema::MEMBERS_BASE_FIELDS)

      table_ids = { specs: specs_id, inbox: inbox_id, members: members_id }
      ensure_link_fields(specs_id, :specs, table_ids)
      ensure_link_fields(inbox_id, :inbox, table_ids)
      doctor
    end

    def ensure_table(existing, name, base_fields)
      return existing[name]["id"] if existing[name]

      @client.create_table(@base_id, name, base_fields)["id"]
    end

    def ensure_link_fields(table_id, table_key, table_ids)
      current = @client.list_tables(@base_id).find { |t| t["id"] == table_id }
      current_names = (current["fields"] || []).map { |f| f["name"] }
      Schema::LINK_FIELDS.fetch(table_key, []).each do |(name, target_key, _multi)|
        next if current_names.include?(name)

        @client.create_field(@base_id, table_id, Schema.link_field(name, table_ids[target_key]))
      end
    end
  end
end
