# Inbox <-> Spec Provenance Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bidirectional link between an Inbox stub and the Spec(s) `/ag-shape` turns it into, in the Airtable Team-mode store — visible from either record in the Airtable UI, written automatically going forward, and backfilled into the one live base's history where it can be determined with confidence.

**Architecture:** Mirror the existing `Serves Outcome` link pattern exactly: a `multipleRecordLinks` field on Specs (`Source Inbox Item` -> Inbox), whose reciprocal (`Specs` on Inbox) Airtable creates and maintains automatically. `/ag-store spec_create`/`spec_write` gain a `source_inbox` canonical key (a raw Inbox record id, passed straight through with no lookup — the same convention as `captured_by`/`shaped_by`), and `/ag-shape` is the only skill that ever sets it. The existing idempotent `ag-store provision` mechanism adds the field to the live base with no new plumbing.

**Tech Stack:** Ruby (stdlib only, no gems) — `bin/ag-store-adapters/airtable/schema.rb` and `bin/ag-store-adapters/airtable.rb`; tests in `dev/test-ag-store-airtable.rb` (a plain script with a `FakeTransport` HTTP stub, no test framework, asserts via `raise`); the `/ag-shape` skill is a markdown instructions file.

**Spec:** `docs/superpowers/specs/2026-09-18-inbox-spec-provenance-design.md`

## Global Constraints

- Airtable Team-mode (`bin/ag-store-adapters/airtable*`) only — the `local` file-based store is untouched (see spec's Scope section).
- `/ag-decompose` and `/ag-capture` are untouched — they only ever create Inbox items.
- `/ag-spec` is untouched — it never consumes an Inbox item.
- No cardinality enforcement is added for `Source Inbox Item` — consistent with every other link field in this schema today (the `LINK_FIELDS` tuple's third element is documented but decorative).
- Every change to the plugin bumps `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`'s `version` **in the same commit** as the change, plus a `CHANGELOG.md` entry (see `README.md`'s Versioning section). This change is a new store field + a change to what `/ag-shape` instructs, so it's a **minor** bump: `0.16.1` -> `0.17.0`.
- Retrofit writes to the live OmaGames base (`appFVlbVAWb4T4E8j`) only ever set a currently-blank `Source Inbox Item` field on a Spec that already exists — never touch any other field, never guess an ambiguous match.

---

### Task 1: Schema — add the link field and frontmatter key

**Files:**
- Modify: `bin/ag-store-adapters/airtable/schema.rb:148-159` (the `LINK_FIELDS` hash) and `:183-187` (`FRONTMATTER_KEYS`)
- Test: `dev/test-ag-store-airtable.rb` (append near the existing serves/tags round-trip test, currently around line 225-230)

**Interfaces:**
- Consumes: nothing new — pure data additions to two existing constants.
- Produces: `Airtable::Schema::LINK_FIELDS[:specs]` includes `["Source Inbox Item", :inbox, false]`; `Airtable::Schema::FRONTMATTER_KEYS` includes `:source_inbox`. Task 2 relies on both.

- [ ] **Step 1: Write the failing test**

In `dev/test-ag-store-airtable.rb`, right after the existing block that ends with:

```ruby
sre = Airtable::Schema.parse_spec_markdown(Airtable::Schema.render_spec_markdown(sv))
raise "spec serves/tags round-trip" unless sre[:serves] == "identity" && sre[:tags] == %w[auth testing]
```

add:

```ruby
# 8b. spec markdown carries source_inbox as a raw record id (no lookup — same convention as captured_by/shaped_by)
smd_with_inbox = smd.sub("outcome: no more", "source_inbox: recI1\noutcome: no more")
siv = Airtable::Schema.parse_spec_markdown(smd_with_inbox)
raise "spec source_inbox: #{siv.inspect}" unless siv[:source_inbox] == "recI1"
sire = Airtable::Schema.parse_spec_markdown(Airtable::Schema.render_spec_markdown(siv))
raise "spec source_inbox round-trip" unless sire[:source_inbox] == "recI1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby dev/test-ag-store-airtable.rb`
Expected: `spec source_inbox: {...}` raised — `siv[:source_inbox]` is `nil` because `FRONTMATTER_KEYS`/parsing doesn't special-case it yet (parsing is generic, so it actually already captures any `key: value` line — the real failure here is the round-trip: `render_spec_markdown` silently drops it because `FRONTMATTER_KEYS` doesn't list `:source_inbox`, so `sire[:source_inbox]` comes back `nil`). Confirm the raised message is the round-trip one, not the first `siv[:source_inbox]` line — if the first line also fails, re-check the heredoc edit didn't break the `smd` substitution.

- [ ] **Step 3: Add the field to the schema**

In `bin/ag-store-adapters/airtable/schema.rb`, change:

```ruby
    LINK_FIELDS = {
      specs: [
        ["Depends On", :specs, true],
        ["Claimed By (Member)", :members, false],
        ["Captured By", :members, false],
        ["Shaped By", :members, true],
        ["Serves Outcome", :outcomes, false],
      ],
```

to:

```ruby
    LINK_FIELDS = {
      specs: [
        ["Depends On", :specs, true],
        ["Claimed By (Member)", :members, false],
        ["Captured By", :members, false],
        ["Shaped By", :members, true],
        ["Serves Outcome", :outcomes, false],
        ["Source Inbox Item", :inbox, false],
      ],
```

and change:

```ruby
    FRONTMATTER_KEYS = %i[
      title slug status depends_on type route business_value technical_certainty
      rank created_at serves tags outcome claimed_by label claimed_at claimed_by_member
      abandoned_reason abandoned_at shipped_at captured_by shaped_by
    ].freeze
```

to:

```ruby
    FRONTMATTER_KEYS = %i[
      title slug status depends_on type route business_value technical_certainty
      rank created_at serves tags outcome claimed_by label claimed_at claimed_by_member
      abandoned_reason abandoned_at shipped_at captured_by shaped_by source_inbox
    ].freeze
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby dev/test-ag-store-airtable.rb`
Expected: reaches `puts "ALL PASS"` with no `raise`.

- [ ] **Step 5: Extend the doctor/drift test for the new field**

In the same file, find:

```ruby
raise "doctor drift: #{checks.inspect}" unless checks["missing fields"].include?("Specs.Serves Outcome") && checks["missing fields"].include?("Specs.Tags")
```

change to:

```ruby
raise "doctor drift: #{checks.inspect}" unless checks["missing fields"].include?("Specs.Serves Outcome") && checks["missing fields"].include?("Specs.Tags") && checks["missing fields"].include?("Specs.Source Inbox Item")
```

- [ ] **Step 6: Run the full suite once more**

Run: `ruby dev/test-ag-store-airtable.rb`
Expected: `ALL PASS`.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/agentile
git add bin/ag-store-adapters/airtable/schema.rb dev/test-ag-store-airtable.rb
git commit -m "Add Source Inbox Item to the Specs schema"
```

---

### Task 2: Adapter — wire `source_inbox` through create/read

**Files:**
- Modify: `bin/ag-store-adapters/airtable.rb` — `build_fields` (~line 263-279), `resolved_values_for_read` (~line 236-250), and the "lookups" section (~line 91-144, add a new method near `member_name_of`/`outcome_slug_of`)
- Test: `dev/test-ag-store-airtable.rb` (append after the existing spec_create/Serves Outcome test, currently ending around line 265)

**Interfaces:**
- Consumes: `Airtable::Schema::LINK_FIELDS[:specs]` and `FRONTMATTER_KEYS` from Task 1 (already include the new field/key).
- Produces: `Adapter#build_fields(v)` sets `fields["Source Inbox Item"]` when `v.key?(:source_inbox)`; `Adapter#resolved_values_for_read(r)` sets `v[:source_inbox]` to a display string; new `Adapter#inbox_title_of(record_id)` — Task 3's retrofit script (Task 5) does not depend on this method, only on `spec_write`'s existing `--set` mechanism.

- [ ] **Step 1: Write the failing test — spec_create passes the raw id through**

In `dev/test-ag-store-airtable.rb`, right after the existing block that ends with:

```ruby
raise "spec tags: #{sf.inspect}" unless sf["Tags"] == %w[auth testing]
```

(this is the end of test 10, the `spec_create` / Serves Outcome test) add:

```ruby
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby dev/test-ag-store-airtable.rb`
Expected: FAIL with `spec source_inbox link: {...}` — `sif["Source Inbox Item"]` is `nil` because `build_fields` doesn't handle `:source_inbox` yet.

- [ ] **Step 3: Implement in `build_fields`**

In `bin/ag-store-adapters/airtable.rb`, find:

```ruby
      fields["Captured By"] = Array(v[:captured_by]) if v.key?(:captured_by)
      fields["Shaped By"] = Array(v[:shaped_by]) if v.key?(:shaped_by)
      fields["Claimed By (Member)"] = Array(v[:claimed_by_member]) if v.key?(:claimed_by_member)
      fields
    end
```

change to:

```ruby
      fields["Captured By"] = Array(v[:captured_by]) if v.key?(:captured_by)
      fields["Shaped By"] = Array(v[:shaped_by]) if v.key?(:shaped_by)
      fields["Claimed By (Member)"] = Array(v[:claimed_by_member]) if v.key?(:claimed_by_member)
      fields["Source Inbox Item"] = Array(v[:source_inbox]) if v.key?(:source_inbox)
      fields
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby dev/test-ag-store-airtable.rb`
Expected: `ALL PASS`.

- [ ] **Step 5: Write the failing test — spec_read resolves it to a display title**

Append:

```ruby
# 10c. spec_read resolves Source Inbox Item to the linked Inbox record's Title, for display only
transport = FakeTransport.new
transport.push(200, records_page([rec("recS9", { "Slug" => "sso", "Title" => "SSO", "Created" => "2026-06-10", "Source Inbox Item" => ["recI1"] })])) # specs_records, via spec_by_slug
transport.push(200, rec("recI1", { "Title" => "Buyers want SSO" })) # get_record on Inbox
client = Airtable::Client.new(token: "t", transport: transport)
adapter = Airtable::Adapter.new(base_id: "appTEST", client: client)
srv = Airtable::Schema.parse_spec_markdown(adapter.spec_read("sso"))
raise "spec_read source_inbox: #{srv.inspect}" unless srv[:source_inbox] == "Buyers want SSO"
```

- [ ] **Step 6: Run test to verify it fails**

Run: `ruby dev/test-ag-store-airtable.rb`
Expected: FAIL — either a `NoMethodError` (no `inbox_title_of`) or `srv[:source_inbox]` is `nil`, depending on how far you've read; either way it's not `"Buyers want SSO"` yet.

- [ ] **Step 7: Implement `inbox_title_of` and wire it into `resolved_values_for_read`**

In `bin/ag-store-adapters/airtable.rb`, find the `outcome_slug_of` method (in the lookups section):

```ruby
    def outcome_slug_of(record_id)
      return nil if record_id.nil?

      (outcomes_records.find { |r| r["id"] == record_id } || {}).dig("fields", "Slug")
    end
```

Add immediately after it:

```ruby
    # A single get_record, not a full inbox_records list — spec_read is a
    # one-off read, and inbox_list already filters to Open items only (this
    # needs Dropped ones too), so there's no cache to reuse here.
    def inbox_title_of(record_id)
      return nil if record_id.nil?

      @client.get_record(@base_id, @inbox_table, record_id)["fields"]["Title"]
    rescue Airtable::ApiError
      nil
    end
```

Then find, in `resolved_values_for_read`:

```ruby
      v[:shaped_by] = (f["Shaped By"] || []).map { |id| member_name_of(id) }.compact
```

and add immediately after it:

```ruby
      v[:source_inbox] = inbox_title_of(Array(f["Source Inbox Item"]).first)
```

- [ ] **Step 8: Run test to verify it passes**

Run: `ruby dev/test-ag-store-airtable.rb`
Expected: `ALL PASS`.

- [ ] **Step 9: Commit**

```bash
cd ~/projects/agentile
git add bin/ag-store-adapters/airtable.rb dev/test-ag-store-airtable.rb
git commit -m "Wire source_inbox through spec_create/spec_read"
```

---

### Task 3: `/ag-shape` writes `source_inbox` on every spec it creates; version bump

**Files:**
- Modify: `skills/ag-shape/SKILL.md` (Step 5, the "Graduate to a spec" and "Split" bullets, ~lines 92-94, and the final `inbox_drop` line ~line 98)
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (`version`)
- Modify: `CHANGELOG.md` (new entry)

**Interfaces:**
- Consumes: `source_inbox` as a spec_create frontmatter key (Tasks 1-2).
- Produces: nothing new for later tasks — this is the last code/content task; Task 4 and 5 are operational.

This task is prose, not code — there's no automated test for a skill instructions file. Verify by reading the edited section back against Task 1/2's exact field name (`source_inbox`) and the exact `inbox_list` shape (`{id, title, type, text, captured_at, captured_by}`) so the instruction is internally consistent with what the tool actually returns.

- [ ] **Step 1: Read the current Step 5 text**

Read `skills/ag-shape/SKILL.md` lines 88-99 in full before editing, so the edit lands in the right place relative to the existing "Graduate to a spec" / "Spike" / "Split" / "Merge" / "Drop" bullets and the closing `inbox_drop` instruction.

- [ ] **Step 2: Add the instruction**

In the "Graduate to a spec" bullet, find:

```
Write it with `ag-store spec_create <slug> --dir "<dir>" --store "<store>"`, piping the markdown on stdin.
```

Change to:

```
Write it with `ag-store spec_create <slug> --dir "<dir>" --store "<store>"`, piping the markdown on stdin — include `source_inbox: <id>` in the frontmatter, `<id>` being the stub's own `id` from `inbox_list`, so the spec keeps a record of which stub it came from.
```

In the "Split" bullet, find:

```
- **Split** — capture multiple new stubs (`ag-store inbox_add`) or write multiple specs.
```

Change to:

```
- **Split** — capture multiple new stubs (`ag-store inbox_add`) or write multiple specs. If writing multiple specs from one stub, every one of them gets the same `source_inbox: <id>` — the store's `Source Inbox Item`/`Specs` link is many-specs-per-stub by design.
```

- [ ] **Step 3: Verify the edit reads correctly**

Read `skills/ag-shape/SKILL.md` lines 88-99 back. Confirm: the "Graduate to a spec" bullet and the "Split" bullet both mention `source_inbox`, the field name matches Task 1's `FRONTMATTER_KEYS` entry exactly (`source_inbox`, not `source-inbox` or `inbox_source`), and nothing else in Step 5 was disturbed.

- [ ] **Step 4: Bump the version**

In `.claude-plugin/plugin.json`, change `"version": "0.16.1",` to `"version": "0.17.0",`.

In `.claude-plugin/marketplace.json`, change the matching `"version": "0.16.1",` to `"version": "0.17.0",`.

- [ ] **Step 5: Add the changelog entry**

In `CHANGELOG.md`, add a new section immediately after the `# Changelog` header block (before the existing `## 0.16.1` entry):

```markdown
## 0.17.0 — 2026-09-18

- **Specs now remember which Inbox stub they came from.** A new `Source Inbox
  Item` link on Specs (reciprocal `Specs` on Inbox, auto-maintained by
  Airtable) records provenance — one stub can link to several specs, since
  `/ag-shape`'s "Split" case can turn one stub into more than one. Written by
  `/ag-shape` on every spec it creates via a new `source_inbox` frontmatter
  key; `ag-store spec_create`/`spec_write` resolve it the same way as
  `captured_by`/`shaped_by` (a raw record id, no lookup). `spec_read` shows
  it back as the stub's Title, for readability.
```

- [ ] **Step 6: Commit**

```bash
cd ~/projects/agentile
git add skills/ag-shape/SKILL.md .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "ag-shape: write source_inbox on every spec it creates (0.17.0)"
```

---

### Task 4: Provision the live OmaGames base

**Files:** none (operational step against live Airtable data — no repo changes here)

**Interfaces:**
- Consumes: Task 1's updated `schema.rb` (must run this task only after Task 1-3 are committed, since `ag-store` resolves directly to this working copy of the plugin).
- Produces: the live base now has the `Source Inbox Item` field on Specs (and Airtable's auto-created `Specs` reciprocal on Inbox), and the pre-existing `Created At` drift on Specs is fixed. Task 5's writes depend on the field existing.

- [ ] **Step 1: Confirm the drift exists before provisioning**

```bash
export AGENTILE_AIRTABLE_TOKEN="$(tr -d '[:space:]' < ~/.config/agentile/token)"
ag-store doctor --dir docs/agentile/ --store airtable --airtable-base appFVlbVAWb4T4E8j
```

(run from `~/projects/oma_brain_games`, or any directory — `--dir`/`--store`/`--airtable-base` are explicit, no cwd dependency). Expected: `"missing fields"` includes `"Specs.Created At"` and does **not yet** include `"Specs.Source Inbox Item"` (that field doesn't exist as a concept until this doctor run reflects Task 1's schema change — if `ag-store` resolves to the edited working copy, it *will* report `"Specs.Source Inbox Item"` as missing too, which is expected and fine).

- [ ] **Step 2: Provision**

```bash
ag-store provision --dir docs/agentile/ --store airtable --airtable-base appFVlbVAWb4T4E8j
```

This is idempotent and additive-only (see `Adapter#provision`/`ensure_base_fields`/`ensure_link_fields`) — it will not touch any existing field or record.

- [ ] **Step 3: Confirm the drift is gone**

```bash
ag-store doctor --dir docs/agentile/ --store airtable --airtable-base appFVlbVAWb4T4E8j
```

Expected: `"schema up to date"` is `true` (or, if some *other*, unrelated field is still stale — e.g. a `select` choice list per the 0.16.1 changelog entry — `"missing fields"` is empty and does not mention `Specs.Created At` or `Specs.Source Inbox Item`).

- [ ] **Step 4: Confirm the field shape in the Airtable UI**

Open the OmaGames base in Airtable. Confirm: Specs has a `Source Inbox Item` link field pointing at Inbox; Inbox has a new `Specs` link field pointing at Specs (Airtable's auto-created reciprocal). No commit for this task — it's a live-data change, not a repo change.

---

### Task 5: Retrofit historical data

**Files:** none (a one-off data-migration operation against the live base; no repo changes)

**Interfaces:**
- Consumes: Task 4's provisioned `Source Inbox Item` field.
- Produces: a written match report (in this task's own output, not a file) — which Specs got linked, and which Inbox/Spec records need Keith's manual call because the match was ambiguous or absent.

- [ ] **Step 1: Pull every Inbox and Spec record, all statuses**

Use the Airtable MCP's `list_records_for_table` (or an equivalent read) against base `appFVlbVAWb4T4E8j`, table `Inbox` and table `Specs`, with no status filter — `ag-store inbox_list` only returns `Open` items, which excludes the `Dropped` stubs this retrofit needs. Expect roughly 28 Inbox records and 20 Specs records (counts as of the design's research pass; re-confirm live).

- [ ] **Step 2: Build the candidate mapping**

For each `Dropped` Inbox record, look for Spec(s) whose title is near-identical or clearly derived from the stub's `Title`/`Text`, cross-checked against matching `Serves Outcome` (when both have one) and `Dropped`-at/`Created`-at date proximity. Known case to confirm: the stub "Drop the Oma prefix everywhere" maps to **both** `web-drop-oma-prefix-and-reddoor` and `native-drop-oma-prefix-and-reddoor` (a real one-to-many case — write both).

- [ ] **Step 3: Write the high-confidence matches**

For each confident match, from `~/projects/oma_brain_games`:

```bash
export AGENTILE_AIRTABLE_TOKEN="$(tr -d '[:space:]' < ~/.config/agentile/token)"
ag-store spec_write "<spec-slug>" --set source_inbox=<inbox-record-id> --dir docs/agentile/ --store airtable --airtable-base appFVlbVAWb4T4E8j
```

This exercises the exact same `build_fields` code path Task 2 tested — `Array(v[:source_inbox])` — no separate migration code needed. Do this only for records where `Source Inbox Item` is currently blank (avoid clobbering anything, though nothing should be set yet since this is the first run after Task 4's provisioning).

- [ ] **Step 4: Leave ambiguous or unmatched cases blank and report them**

Do not write anything for: a stub with multiple similarly-plausible spec candidates and no way to prefer one; a stub with no plausible candidate at all; a Spec with no plausible originating stub (this is a legitimate, expected "no source" per the design, not a gap). List every one of these explicitly in the final report to Keith, with enough detail (stub title, candidate spec slugs considered, why it's ambiguous) that he can resolve it by hand via `ag-store spec_write <slug> --set source_inbox=<id> ...` himself if he wants to.

- [ ] **Step 5: Report**

Summarize: how many Specs got `source_inbox` written, the one-to-many case confirmed, and the full list of flagged-but-unwritten ambiguous/unmatched cases. No commit — this task produces no repo changes, only live-base data changes and a report.
