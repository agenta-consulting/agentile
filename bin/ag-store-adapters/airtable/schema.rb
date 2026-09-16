# frozen_string_literal: true
# The Airtable table/field schema, and the markdown <-> fields translation.
# Every frontmatter key and every body section in templates/agentile/spec-template.md
# maps to one real Airtable field — no blob field anywhere. This file is pure
# (no HTTP, no record-id resolution): it deals in plain scalars/arrays keyed
# by our canonical field names; ../airtable.rb resolves linked-record ids
# (slugs <-> record ids for Depends On, member names <-> record ids for the
# attribution fields) before/after calling the client.
module Airtable
  module Schema
    # ---- provisioning: table + field definitions for the Metadata API ----
    # Field type strings and `options` shapes are Airtable Metadata API field
    # types (https://airtable.com/developers/web/api/field-model). The first
    # field in each table's list becomes that table's primary field.

    def self.select(*choices)
      { type: "singleSelect", options: { choices: choices.map { |c| { name: c } } } }
    end

    def self.text
      { type: "singleLineText" }
    end

    def self.long_text
      { type: "multilineText" }
    end

    def self.date
      { type: "date", options: { dateFormat: { name: "iso" } } }
    end

    def self.datetime
      { type: "dateTime", options: { dateFormat: { name: "iso" }, timeFormat: { name: "24hour" }, timeZone: "utc" } }
    end

    def self.number
      { type: "number", options: { precision: 0 } }
    end

    # Options are created on write with `typecast: true` (see client.rb), so
    # the field starts empty and a new tag never needs a schema call.
    def self.multi_select
      { type: "multipleSelects", options: { choices: [] } }
    end

    # Non-link fields only — link fields (Depends On, the *By member fields)
    # are added in a second pass once every table's id is known; see airtable.rb#provision.
    SPECS_BASE_FIELDS = [
      { name: "Slug" }.merge(text),
      { name: "Title" }.merge(text),
      { name: "Status" }.merge(select("ready", "in_progress", "shipped", "abandoned")),
      { name: "Type" }.merge(select("feature", "spike", "bug", "chore")),
      { name: "Route" }.merge(select("foreground", "background", "spike")),
      { name: "Business Value" }.merge(select("high", "medium", "low")),
      { name: "Technical Certainty" }.merge(select("high", "medium", "low")),
      { name: "Rank" }.merge(number),
      { name: "Tags" }.merge(multi_select),
      { name: "Outcome" }.merge(long_text),
      { name: "Problem / Why Now" }.merge(long_text),
      { name: "Acceptance Criteria" }.merge(long_text),
      { name: "Scope In" }.merge(long_text),
      { name: "Scope Out" }.merge(long_text),
      { name: "Edge Cases" }.merge(long_text),
      { name: "Affected Areas" }.merge(long_text),
      { name: "Open Questions" }.merge(long_text),
      { name: "Verification" }.merge(long_text),
      { name: "Created" }.merge(date),        # legacy; read-only fallback for specs created before 0.14.0
      { name: "Created At" }.merge(datetime),
      { name: "Plan Path" }.merge(text),
      { name: "Claimed By (Session)" }.merge(text),
      { name: "Label" }.merge(text),
      { name: "Claimed At" }.merge(datetime),
      { name: "Shipped At" }.merge(datetime),
      { name: "Abandoned Reason" }.merge(long_text),
      { name: "Abandoned At" }.merge(datetime),
    ].freeze

    # Title is first so it becomes the primary field: a stub's Text is a
    # paragraph, which makes a useless record name in the Airtable UI and in
    # every linked-record chip. /ag-capture generates the title from the text
    # when the human doesn't supply one; it is a label, never the stub itself.
    INBOX_BASE_FIELDS = [
      { name: "Title" }.merge(text),
      { name: "Text" }.merge(long_text),
      # Same vocabulary as SPECS_BASE_FIELDS' Type so shaping carries it over
      # as a copy, not a mapping. Derived at capture and defaulted to
      # "feature": describing a change is not triaging it, so it costs the
      # capture nothing. Its job is to route — /ag-shape gives a bug the short
      # repro interview instead of the feature Definition of Ready.
      { name: "Type" }.merge(select("feature", "bug", "chore", "spike")),
      { name: "Captured At" }.merge(date),
      { name: "Status" }.merge(select("Open", "Shaped", "Dropped")),
    ].freeze

    MEMBERS_BASE_FIELDS = [
      { name: "Name" }.merge(text),
      { name: "Email" }.merge(text),
      { name: "Git Email" }.merge(text),
    ].freeze

    # Outcomes (docs/agentile-outcomes.md §4.3). Title first so it is the
    # primary field — a slug makes a poor record name in linked-record chips.
    OUTCOMES_BASE_FIELDS = [
      { name: "Title" }.merge(text),
      { name: "Slug" }.merge(text),
      { name: "Status" }.merge(select("open", "achieved", "abandoned")),
      { name: "Rank" }.merge(number),
      { name: "Claim" }.merge(long_text),
      { name: "Measure" }.merge(long_text),
      { name: "Stop Rule" }.merge(long_text),
      { name: "Notes" }.merge(long_text),
      { name: "Created" }.merge(date),
      { name: "Achieved At" }.merge(datetime),
      { name: "Abandoned At" }.merge(datetime),
      { name: "Abandoned Reason" }.merge(long_text),
    ].freeze

    # Link fields added once every table's id is known (table: field name -> [target table key, multiple?]).
    LINK_FIELDS = {
      specs: [
        ["Depends On", :specs, true],
        ["Claimed By (Member)", :members, false],
        ["Captured By", :members, false],
        ["Shaped By", :members, true],
        ["Serves Outcome", :outcomes, false],
      ],
      inbox: [
        ["Captured By", :members, false],
        ["Serves Outcome", :outcomes, false],
      ],
      outcomes: [
        ["Created By", :members, false],
      ],
    }.freeze

    def self.link_field(name, linked_table_id)
      { name: name, type: "multipleRecordLinks", options: { linkedTableId: linked_table_id } }
    end

    # ---- markdown <-> fields ----
    # `values` / the returned hash use these canonical (snake_case) keys.
    # Anything airtable-only (rank, captured_by, shaped_by, claimed_by_member)
    # is emitted as an additive frontmatter key — harmless extra YAML that
    # every other skill's frontmatter reader already ignores if it doesn't
    # need it.

    FRONTMATTER_KEYS = %i[
      title slug status depends_on type route business_value technical_certainty
      rank created_at serves tags outcome claimed_by label claimed_at claimed_by_member
      abandoned_reason abandoned_at shipped_at captured_by shaped_by
    ].freeze

    SECTION_HEADINGS = {
      problem: "Problem / why now",
      acceptance_criteria: "Acceptance criteria",
      edge_cases: "Edge cases and failure paths",
      affected_areas: "Affected areas",
      open_questions: "Open questions",
      verification: "Verification",
    }.freeze

    # A list value may arrive as an Array (parsed markdown) or as the string
    # "[a, b]" (an ag-store --set flag hands the adapter raw text). The local
    # store never sees the difference — YAML parses the string on read — so
    # this is where the airtable adapter has to.
    def self.list_value(val)
      return [] if val.nil?
      return val.map(&:to_s) if val.is_a?(Array)

      s = val.to_s.strip
      s = s[1..-2] if s.start_with?("[") && s.end_with?("]")
      s.split(",").map(&:strip).reject(&:empty?)
    end

    def self.yaml_scalar(val)
      return "[#{Array(val).join(', ')}]" if val.is_a?(Array)

      val.to_s
    end

    def self.render_spec_markdown(v)
      fm = FRONTMATTER_KEYS.filter_map do |k|
        next if v[k].nil? || v[k] == ""

        "#{k}: #{yaml_scalar(v[k])}"
      end.join("\n")

      body = +"# #{v[:title]}\n\n"
      body << "## #{SECTION_HEADINGS[:problem]}\n\n#{v[:problem]}\n\n"
      body << "## #{SECTION_HEADINGS[:acceptance_criteria]}\n\n#{v[:acceptance_criteria]}\n\n"
      body << "## Scope boundary\n\n**In scope:** #{v[:scope_in]}\n\n**Out of scope:** #{v[:scope_out]}\n\n"
      body << "## #{SECTION_HEADINGS[:edge_cases]}\n\n#{v[:edge_cases]}\n\n"
      body << "## #{SECTION_HEADINGS[:affected_areas]}\n\n#{v[:affected_areas]}\n\n"
      body << "## #{SECTION_HEADINGS[:open_questions]}\n\n#{v[:open_questions]}\n\n"
      body << "## #{SECTION_HEADINGS[:verification]}\n\n#{v[:verification]}\n"

      "---\n#{fm}\n---\n\n#{body}"
    end

    def self.parse_spec_markdown(markdown)
      fm_text = markdown[/\A---\n(.*?)\n---/m, 1] || ""
      body = markdown.sub(/\A---\n.*?\n---/m, "").strip

      v = {}
      fm_text.each_line do |line|
        line = line.chomp
        next unless (m = line.match(/\A([A-Za-z_]+):\s*(.*)\z/))

        key = m[1].to_sym
        val = m[2].strip
        val = val[1..-2].split(",").map(&:strip).reject(&:empty?) if val.start_with?("[") && val.end_with?("]")
        v[key] = val
      end

      title = body[/\A#\s+(.+)$/, 1]
      v[:title] ||= title.to_s.strip

      sections = body.split(/^## /).drop(1).to_h do |chunk|
        heading, rest = chunk.split("\n", 2)
        [heading.strip, rest.to_s.strip]
      end

      v[:problem] = sections[SECTION_HEADINGS[:problem]].to_s
      v[:acceptance_criteria] = sections[SECTION_HEADINGS[:acceptance_criteria]].to_s
      v[:edge_cases] = sections[SECTION_HEADINGS[:edge_cases]].to_s
      v[:affected_areas] = sections[SECTION_HEADINGS[:affected_areas]].to_s
      v[:open_questions] = sections[SECTION_HEADINGS[:open_questions]].to_s
      v[:verification] = sections["Verification"].to_s

      scope = sections["Scope boundary"].to_s
      v[:scope_in] = scope[/\*\*In scope:\*\*\s*(.*?)(?=\n\n\*\*Out of scope|\z)/m, 1].to_s.strip
      v[:scope_out] = scope[/\*\*Out of scope:\*\*\s*(.*)\z/m, 1].to_s.strip

      v
    end

    # ---- outcome markdown <-> fields (docs/agentile-outcomes.md §2) ----

    OUTCOME_FRONTMATTER_KEYS = %i[title slug status rank created achieved_at abandoned_at abandoned_reason created_by].freeze
    OUTCOME_SECTIONS = { claim: "Claim", measure: "Measure", stop_rule: "Stop rule", notes: "Notes" }.freeze

    def self.render_outcome_markdown(v)
      fm = OUTCOME_FRONTMATTER_KEYS.filter_map do |k|
        next if v[k].nil? || v[k] == ""

        "#{k}: #{yaml_scalar(v[k])}"
      end.join("\n")
      body = +"# #{v[:title]}\n\n"
      OUTCOME_SECTIONS.each { |key, heading| body << "## #{heading}\n\n#{v[key]}\n\n" }
      "---\n#{fm}\n---\n\n#{body.rstrip}\n"
    end

    def self.parse_outcome_markdown(markdown)
      fm_text = markdown[/\A---\n(.*?)\n---/m, 1] || ""
      body = markdown.sub(/\A---\n.*?\n---/m, "").strip
      v = {}
      fm_text.each_line do |line|
        next unless (m = line.chomp.match(/\A([A-Za-z_]+):\s*(.*)\z/))

        v[m[1].to_sym] = m[2].strip
      end
      v[:title] = body[/\A#\s+(.+)$/, 1].to_s.strip if v[:title].to_s.empty?
      sections = body.split(/^## /).drop(1).to_h do |chunk|
        heading, rest = chunk.split("\n", 2)
        [heading.strip, rest.to_s.strip]
      end
      OUTCOME_SECTIONS.each { |key, heading| v[key] = sections[heading].to_s }
      v
    end
  end
end
