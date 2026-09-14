# Outcomes Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Outcome layer above specs — a flat, ranked list of falsifiable bets that specs optionally `serve` — to both backlog stores, plus the skills that create, decompose, map, rank, retire and abandon them.

**Architecture:** Outcomes are canonical markdown (frontmatter + Claim/Measure/Stop rule/Notes body), stored at `<dir>/outcomes/<slug>.md` by the `local` adapter and in an `Outcomes` table by the `airtable` adapter. Specs gain optional `serves:` (one outcome slug) and `tags:` (labels). Everything derivable — progress, grouping, blocked lists — is computed by one `map` op whose pure builder is shared by both adapters. `brief_sync` rewrites the brief's "Prioritised outcomes" section from the store so prose and table cannot drift.

**Tech Stack:** Ruby stdlib only (yaml, json, fileutils, open3) — no gems, matching every script in `bin/`. Airtable via the existing `Airtable::Client` (Net::HTTP). Tests are plain Ruby scripts under `dev/` that `raise` on failure and print `ALL PASS`.

**Spec:** `docs/agentile-outcomes.md`

## Global Constraints

- `serves` is the spec→outcome link key; `outcome` remains the spec's own metric field. Never conflate.
- Outcomes are flat: no parent field, ever.
- A parent never gates a child: no change to `claim`, `/ag-next`, or `/ag-loop`.
- No derived field is stored on an Outcome (no counts, no progress). Spec `Rank` is the one materialised cache.
- Outcome status transitions are explicit ops (`outcome_achieve`, `outcome_abandon`), never inferred.
- Every value in frontmatter must be valid YAML — no unquoted colons in `title`.
- Version bump to **0.12.0** in `.claude-plugin/plugin.json` AND `.claude-plugin/marketplace.json` in the final commit, with a CHANGELOG entry (minor: new skills, new store fields, changed skill instructions).
- Run `ruby dev/test-ag-store-local.rb` and `ruby dev/test-ag-store-airtable.rb` before every commit; both must print `ALL PASS`.

---

## File structure

| File | Responsibility |
|---|---|
| `templates/agentile/outcome-template.md` | Create — the canonical Outcome artefact shape |
| `bin/ag-store-adapters/local.rb` | Modify — outcome ops, `serves`/`tags` on specs, `build_map` (shared pure builder), `map`, `brief_sync` |
| `bin/ag-store` | Modify — dispatch the new ops for both stores; usage header |
| `bin/ag-store-adapters/airtable/schema.rb` | Modify — `Outcomes` table fields, link fields, `Tags`, outcome markdown render/parse, `serves`/`tags` in spec render/parse |
| `bin/ag-store-adapters/airtable/client.rb` | Modify — `typecast:` option on create/update |
| `bin/ag-store-adapters/airtable.rb` | Modify — outcome ops, `serves`/`tags`, `map`, provision/doctor/create_base for the new table |
| `dev/test-ag-store-local.rb` | Modify — tests 14–19 |
| `dev/test-ag-store-airtable.rb` | Modify — tests 8–12 |
| `skills/ag-outcome/SKILL.md`, `skills/ag-decompose/SKILL.md`, `skills/ag-map/SKILL.md` | Create |
| `skills/{ag-shape,ag-prioritise,ag-retro,ag-abandon,ag-capture,ag-spec,ag-init}/SKILL.md`, `agents/ag-planner.md` | Modify |
| `templates/agentile/config.md`, `templates/agentile/brief-template.md`, `templates/CLAUDE.agentile-section.md`, `templates/stores/airtable/README.md` | Modify |
| `README.md`, `methodology.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Modify |

---

### Task 1: Outcome template + local outcome ops

**Files:**
- Create: `templates/agentile/outcome-template.md`
- Modify: `bin/ag-store-adapters/local.rb` (append a `# ---- outcomes ----` section before `# ---- whoami / doctor ----`)
- Modify: `bin/ag-store` (usage header + both dispatch branches)
- Test: `dev/test-ag-store-local.rb` (append tests 14, 15)

**Interfaces:**
- Produces: `Local.outcome_list(agentile_dir, status:)`, `Local.outcome_read(agentile_dir, slug)`, `Local.outcome_create(agentile_dir, slug, markdown)`, `Local.outcome_write(agentile_dir, slug, fields)`, `Local.outcome_rank(agentile_dir, slugs)`, `Local.outcome_achieve(agentile_dir, slug)`, `Local.outcome_abandon(agentile_dir, slug, reason:)`. Summary hash shape: `{slug, title, status, rank, created, achieved_at, abandoned_at}`.

- [ ] **Step 1: Write the template**

`templates/agentile/outcome-template.md`:

```markdown
<!-- Frontmatter hygiene: every value must be valid YAML. No unquoted colons in `title` — reword with a dash or comma, or quote the value. -->
---
title: <what becomes true, not what gets built>
slug: <kebab-case-slug>
status: open                  # open | achieved | abandoned
rank:                         # integer set by /ag-prioritise; blank = unranked
created: <YYYY-MM-DD>
# Transition fields — set by the store, never by hand:
# achieved_at:                # ISO8601, via `ag-store outcome_achieve`
# abandoned_at:               # ISO8601, via `ag-store outcome_abandon`
# abandoned_reason:           # free text, via `ag-store outcome_abandon`
---

# <Title>

## Claim

<What will be true when this is achieved. A claim describes an outcome, not a
deliverable: "a buyer cannot reject us on identity grounds" passes; "provide
SSO" fails. Test — can you state the measure below without listing the specs?>

## Measure

<The observable evidence a human will judge this against. Not a spec count.>

## Stop rule

<The evidence that would make us abandon this line of work entirely.>

## Notes

<Optional. Evidence gathered, links, what changed the assessment over time.>
```

- [ ] **Step 2: Write the failing tests**

Append to `dev/test-ag-store-local.rb` before `puts "ALL PASS"`:

```ruby
OUTCOME_MD = <<~MD
  ---
  title: Buyers cannot reject on identity grounds
  slug: identity
  status: open
  rank:
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

MD

# 14. outcome_create / outcome_read / outcome_list round-trip; list sorts ranked before unranked
Dir.mktmpdir do |root|
  dir = scaffold(root)
  path = store("outcome_create", "identity", dir: dir, stdin: OUTCOME_MD)
  raise "outcome_create path: #{path}" unless path.end_with?("outcomes/identity.md")
  raise "outcome_read round-trip" unless store("outcome_read", "identity", dir: dir) == OUTCOME_MD

  store("outcome_create", "speed", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: speed").sub("rank:\n", "rank: 1\n"))
  listed = store("outcome_list", dir: dir)
  raise "outcome_list order: #{listed.map { |o| o['slug'] }}" unless listed.map { |o| o["slug"] } == %w[speed identity]
  raise "outcome_list shape: #{listed[0].inspect}" unless listed[0]["rank"] == 1 && listed[0]["status"] == "open" && listed[0]["title"] == "Buyers cannot reject on identity grounds"

  begin
    store("outcome_create", "identity", dir: dir, stdin: OUTCOME_MD)
    raise "duplicate outcome_create should fail"
  rescue RuntimeError => e
    raise e unless e.message.include?("already exists")
  end
end

# 15. outcome_rank stamps dense ranks on open outcomes only; achieve/abandon stamp status + timestamps
Dir.mktmpdir do |root|
  dir = scaffold(root)
  %w[a b c].each { |s| store("outcome_create", s, dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: #{s}")) }
  store("outcome_achieve", "c", dir: dir)
  ranked = store("outcome_rank", "b", "c", "a", dir: dir)
  raise "outcome_rank skips non-open: #{ranked.inspect}" unless ranked == %w[b a]
  listed = store("outcome_list", "--status", "open", dir: dir)
  raise "outcome_rank order: #{listed.map { |o| [o['slug'], o['rank']] }}" unless listed.map { |o| [o["slug"], o["rank"]] } == [["b", 1], ["a", 2]]

  fm = frontmatter(File.join(dir, "outcomes", "c.md"))
  raise "achieve status: #{fm.inspect}" unless fm["status"] == "achieved" && fm["achieved_at"].to_s.match?(/\d{4}-\d{2}-\d{2}T/)

  store("outcome_abandon", "a", "--reason", "spike showed no buyer cares", dir: dir)
  fm = frontmatter(File.join(dir, "outcomes", "a.md"))
  raise "abandon: #{fm.inspect}" unless fm["status"] == "abandoned" && fm["abandoned_reason"] == "spike showed no buyer cares" && fm["abandoned_at"].to_s.match?(/T/)

  store("outcome_write", "b", "--set", "title=Renamed", dir: dir)
  raise "outcome_write" unless frontmatter(File.join(dir, "outcomes", "b.md"))["title"] == "Renamed"
end
```

- [ ] **Step 3: Run to verify they fail**

Run: `cd ~/projects/agentile && ruby dev/test-ag-store-local.rb`
Expected: raises `ag-store outcome_create failed (1): ag-store: unknown op 'outcome_create'`

- [ ] **Step 4: Implement in `local.rb`**

Insert before `# ---- whoami / doctor ----`:

```ruby
  # ---- outcomes (docs/agentile-outcomes.md §4.2) ----
  # Flat files at <dir>/outcomes/<slug>.md. Status and rank live in
  # frontmatter — no NNNN- prefix, no done/abandoned moves: there are few
  # outcomes, nothing claims them, and a stable filename beats a visible sort.

  def outcomes_dir(agentile_dir)
    File.join(agentile_dir, "outcomes")
  end

  def load_outcome(path)
    raw = File.read(path)
    fm = (YAML.safe_load(raw[/\A---\n(.*?)\n---/m, 1] || "", permitted_classes: [Time, Date]) || {})
    { path: path, raw: raw, fm: fm, slug: File.basename(path, ".md") }
  end

  def outcomes_in(agentile_dir)
    dir = outcomes_dir(agentile_dir)
    return [] unless File.directory?(dir)

    Dir.glob(File.join(dir, "*.md")).map { |p| load_outcome(p) }
  end

  def find_outcome(agentile_dir, slug)
    outcomes_in(agentile_dir).find { |o| o[:slug] == slug.to_s }
  end

  def outcome_summary(o)
    {
      slug: o[:slug], title: o[:fm]["title"], status: o[:fm]["status"], rank: o[:fm]["rank"],
      created: o[:fm]["created"], achieved_at: o[:fm]["achieved_at"], abandoned_at: o[:fm]["abandoned_at"],
    }
  end

  def outcome_sort_key(summary)
    rank = summary[:rank]
    [rank.is_a?(Integer) ? rank : 1_000_000, summary[:slug].to_s]
  end

  def outcome_list(agentile_dir, status: nil)
    outcomes_in(agentile_dir)
      .map { |o| outcome_summary(o) }
      .select { |o| status.nil? || o[:status] == status }
      .sort_by { |o| outcome_sort_key(o) }
  end

  def outcome_read(agentile_dir, slug)
    o = find_outcome(agentile_dir, slug)
    abort "ag-store: no such outcome: #{slug}" unless o

    o[:raw]
  end

  def outcome_create(agentile_dir, slug, markdown)
    dir = outcomes_dir(agentile_dir)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "#{slug}.md")
    abort "ag-store: an outcome already exists at #{path}" if File.exist?(path)

    File.write(path, markdown)
    path
  end

  def outcome_write(agentile_dir, slug, fields)
    o = find_outcome(agentile_dir, slug)
    abort "ag-store: no such outcome: #{slug}" unless o

    stamp!(o, fields)
    o[:path]
  end

  # Dense integer ranks by position, open outcomes only; anything else in
  # the list is skipped (and reported by omission from the returned slugs).
  def outcome_rank(agentile_dir, ordered_slugs)
    ordered_slugs.each_with_index.filter_map do |slug, _i|
      o = find_outcome(agentile_dir, slug)
      o && o[:fm]["status"] == "open" ? slug : nil
    end.each_with_index.map do |slug, i|
      outcome_write(agentile_dir, slug, { "rank" => i + 1 })
      slug
    end
  end

  def outcome_achieve(agentile_dir, slug, achieved_at: nil)
    outcome_write(agentile_dir, slug, {
      "status" => "achieved",
      "achieved_at" => (achieved_at || Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")),
    })
    true
  end

  def outcome_abandon(agentile_dir, slug, reason:, abandoned_at: nil)
    outcome_write(agentile_dir, slug, {
      "status" => "abandoned",
      "abandoned_at" => (abandoned_at || Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")),
      "abandoned_reason" => reason,
    })
    true
  end
```

`stamp!` already works on any `{raw:, path:}` hash — outcomes reuse it unchanged. Note `rank` stamps over the template's `rank:  # comment` line, which is intended.

- [ ] **Step 5: Wire the dispatcher**

In `bin/ag-store`, add to the usage header after the `attach` line:

```
#   outcome_list [--status open|achieved|abandoned]   --dir <dir>
#   outcome_read <slug>                               --dir <dir>
#   outcome_create <slug>          (markdown on stdin) --dir <dir>
#   outcome_write <slug> --set k=v [--set k=v ...]     --dir <dir>
#   outcome_rank <slug> [<slug>...]                    --dir <dir>
#   outcome_achieve <slug>                             --dir <dir>
#   outcome_abandon <slug> --reason "<text>"           --dir <dir>
#   map                                                --dir <dir>
#   brief_sync                                         --dir <dir>
```

In the **local** branch, before `else abort ...`:

```ruby
  when "outcome_list"
    Local.outcome_list(agentile_dir, status: flags["status"])
  when "outcome_read"
    Local.outcome_read(agentile_dir, positional[0])
  when "outcome_create"
    Local.outcome_create(agentile_dir, positional[0], $stdin.read)
  when "outcome_write"
    Local.outcome_write(agentile_dir, positional[0], sets)
  when "outcome_rank"
    Local.outcome_rank(agentile_dir, positional)
  when "outcome_achieve"
    Local.outcome_achieve(agentile_dir, positional[0])
  when "outcome_abandon"
    Local.outcome_abandon(agentile_dir, positional[0], reason: flags["reason"].to_s)
```

(`map` and `brief_sync` are wired in Tasks 2 and 3.)

- [ ] **Step 6: Run tests, expect ALL PASS**

Run: `ruby dev/test-ag-store-local.rb`
Expected: `ALL PASS`

- [ ] **Step 7: Commit**

```bash
git add templates/agentile/outcome-template.md bin/ag-store bin/ag-store-adapters/local.rb dev/test-ag-store-local.rb
git commit -m "Outcomes: local store ops and the artefact template"
```

---

### Task 2: `serves`/`tags` on specs and stubs, and the `map` op (local)

**Files:**
- Modify: `bin/ag-store-adapters/local.rb` (`spec_list`, `inbox_add`, `inbox_list`, new `build_map`/`map`)
- Modify: `bin/ag-store` (local `map`; `inbox_add` passes `--serves`)
- Test: `dev/test-ag-store-local.rb` (tests 16, 17)

**Interfaces:**
- Produces: `Local.build_map(outcomes, specs)` — pure. `outcomes`: array of outcome summaries (Task 1 shape). `specs`: array of `{slug:, status:, serves:, tags:, blocked:}`. Returns `{outcomes: [...merged with specs:{ready,in_progress,shipped,abandoned}, blocked:[]], unlinked: {ready,…,blocked}, orphaned: {serves_slug => [spec slugs]}, tags: {tag => [spec slugs]}}`. The airtable adapter (Task 5) calls this.
- `spec_list` entries gain `serves` (string or nil) and `tags` (array).
- `inbox_add(agentile_dir, text, captured_by, title, type, serves)` — 6th arg accepted and dropped by local.

- [ ] **Step 1: Write the failing tests**

```ruby
# 16. spec_list exposes serves + tags; inbox_add accepts --serves (dropped by local)
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  write_spec(specs_dir, "0001-sso.md", extra: { "serves" => "identity", "tags" => %w[auth testing] })
  write_spec(specs_dir, "0002-free.md")
  listed = store("spec_list", dir: dir)
  sso = listed.find { |s| s["slug"] == "sso" }
  raise "serves: #{sso.inspect}" unless sso["serves"] == "identity"
  raise "tags: #{sso.inspect}" unless sso["tags"] == %w[auth testing]
  free = listed.find { |s| s["slug"] == "free" }
  raise "no serves: #{free.inspect}" unless free["serves"].nil? && free["tags"] == []

  store("inbox_add", "Add SCIM", "--serves", "identity", dir: dir)
  raise "inbox_add --serves accepted" unless store("inbox_list", dir: dir).size == 1
end

# 17. map groups specs by the outcome they serve, buckets by status, flags blocked + orphaned, indexes tags
Dir.mktmpdir do |root|
  dir = scaffold(root)
  specs_dir = File.join(dir, "specs")
  store("outcome_create", "identity", dir: dir, stdin: OUTCOME_MD)
  write_spec(specs_dir, "0001-oidc.md", extra: { "serves" => "identity", "tags" => %w[auth] })
  write_spec(specs_dir, "0002-scim.md", extra: { "serves" => "identity", "depends_on" => %w[oidc], "tags" => %w[auth lifecycle] })
  write_spec(specs_dir, "0003-free.md")
  write_spec(specs_dir, "0004-lost.md", extra: { "serves" => "nonexistent" })
  write_spec(File.join(specs_dir, "done"), "0000-old.md", status: "shipped", extra: { "serves" => "identity" })

  m = store("map", dir: dir)
  o = m["outcomes"].find { |x| x["slug"] == "identity" }
  raise "map outcome specs: #{o.inspect}" unless o["specs"]["ready"] == %w[oidc scim] && o["specs"]["shipped"] == %w[old]
  raise "map blocked: #{o.inspect}" unless o["blocked"] == %w[scim]
  raise "map unlinked: #{m['unlinked'].inspect}" unless m["unlinked"]["ready"] == %w[free]
  raise "map orphaned: #{m['orphaned'].inspect}" unless m["orphaned"] == { "nonexistent" => %w[lost] }
  raise "map tags: #{m['tags'].inspect}" unless m["tags"] == { "auth" => %w[oidc scim], "lifecycle" => %w[scim] }
end
```

- [ ] **Step 2: Run to verify failure**

Run: `ruby dev/test-ag-store-local.rb`
Expected: `serves: …` raise (spec_list has no `serves` key yet).

- [ ] **Step 3: Implement**

In `spec_list`'s projection hash, after `shipped_at:` add:

```ruby
          serves: (s[:fm]["serves"].to_s.empty? ? nil : s[:fm]["serves"].to_s),
          tags: Array(s[:fm]["tags"]).map(&:to_s),
```

Change `inbox_add`'s signature to `def inbox_add(agentile_dir, text, _captured_by = nil, _title = nil, _type = nil, _serves = nil)` and extend its comment: `serves is dropped too — a one-line inbox has nowhere to keep it; /ag-shape asks.` In `inbox_list`, add `serves: nil` to each stub hash.

Add after the outcomes section:

```ruby
  # ---- map (docs/agentile-outcomes.md §4.1) ----
  # The one computed view. build_map is pure and shared with the airtable
  # adapter; each adapter only has to produce the flat spec entries.

  MAP_STATES = %w[ready in_progress shipped abandoned].freeze

  def empty_buckets
    MAP_STATES.to_h { |st| [st, []] }
  end

  def build_map(outcomes, specs)
    known = outcomes.map { |o| o[:slug].to_s }
    by_outcome = Hash.new { |h, k| h[k] = empty_buckets }
    unlinked = empty_buckets
    blocked = Hash.new { |h, k| h[k] = [] }
    orphaned = Hash.new { |h, k| h[k] = [] }
    tags = Hash.new { |h, k| h[k] = [] }

    specs.sort_by { |s| s[:slug].to_s }.each do |s|
      st = s[:status].to_s
      next unless MAP_STATES.include?(st)

      serves = s[:serves].to_s
      if serves.empty?
        unlinked[st] << s[:slug]
      elsif known.include?(serves)
        by_outcome[serves][st] << s[:slug]
      else
        orphaned[serves] << s[:slug]
      end
      blocked[serves] << s[:slug] if s[:blocked]
      Array(s[:tags]).each { |t| tags[t.to_s] << s[:slug] }
    end

    {
      outcomes: outcomes.map { |o| o.merge(specs: by_outcome[o[:slug].to_s], blocked: blocked[o[:slug].to_s]) },
      unlinked: unlinked.merge(blocked: blocked[""]),
      orphaned: orphaned.sort.to_h,
      tags: tags.sort.to_h,
    }
  end

  def map(agentile_dir)
    specs_dir = File.join(agentile_dir, "specs")
    shipped = shipped_map(specs_dir)
    all = specs_in(specs_dir) + specs_in(File.join(specs_dir, "done")) + specs_in(File.join(specs_dir, "abandoned"))
    entries = all.map do |s|
      {
        slug: s[:slug], status: s[:fm]["status"], serves: s[:fm]["serves"], tags: Array(s[:fm]["tags"]),
        blocked: s[:fm]["status"] == "ready" && !Array(s[:fm]["depends_on"]).all? { |d| shipped[d.to_s] },
      }
    end
    build_map(outcome_list(agentile_dir), entries)
  end
```

Dispatcher, local branch: `when "map" then Local.map(agentile_dir)` and change the local `inbox_add` line to pass `flags["serves"]` as the sixth argument.

- [ ] **Step 4: Run tests, expect ALL PASS**

- [ ] **Step 5: Commit**

```bash
git add bin/ag-store bin/ag-store-adapters/local.rb dev/test-ag-store-local.rb
git commit -m "Outcomes: serves/tags on specs, --serves on stubs, and the map view (local)"
```

---

### Task 3: `brief_sync` (shared; brief is always a local file)

**Files:**
- Modify: `bin/ag-store-adapters/local.rb` (new `brief_sync`)
- Modify: `bin/ag-store` (both branches)
- Test: `dev/test-ag-store-local.rb` (test 18)

**Interfaces:**
- Produces: `Local.brief_sync(agentile_dir, outcomes)` — `outcomes` is an `outcome_list` result (already rank-sorted). Returns `true` when written, `false` (with a stderr warning) when the brief has no `## Prioritised outcomes` heading. The airtable branch calls it with `adapter.outcome_list`.

- [ ] **Step 1: Failing test**

```ruby
# 18. brief_sync rewrites only the "Prioritised outcomes" section, open outcomes by rank, ranked before unranked
Dir.mktmpdir do |root|
  dir = scaffold(root)
  File.write(File.join(dir, "brief.md"), <<~MD)
    # Brief

    ## Who it's for

    Banks.

    ## Prioritised outcomes

    1. stale text

    ## Constraints

    Python.
  MD
  store("outcome_create", "second", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: second").sub("title: Buyers cannot reject on identity grounds", "title: Second").sub("rank:\n", "rank: 2\n"))
  store("outcome_create", "first", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: first").sub("title: Buyers cannot reject on identity grounds", "title: First").sub("rank:\n", "rank: 1\n"))
  store("outcome_create", "unranked", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: unranked").sub("title: Buyers cannot reject on identity grounds", "title: Later"))
  store("outcome_create", "gone", dir: dir, stdin: OUTCOME_MD.sub("slug: identity", "slug: gone"))
  store("outcome_abandon", "gone", "--reason", "x", dir: dir)

  raise "brief_sync returns true" unless store("brief_sync", dir: dir) == true
  brief = File.read(File.join(dir, "brief.md"))
  expected = "## Prioritised outcomes\n\n1. **First** (`first`)\n2. **Second** (`second`)\n3. **Later** (`unranked`)\n\n## Constraints"
  raise "brief_sync section:\n#{brief}" unless brief.include?(expected)
  raise "brief_sync touched other sections" unless brief.include?("## Who it's for\n\nBanks.") && brief.include?("## Constraints\n\nPython.")
  raise "brief_sync leaked abandoned" if brief.include?("gone")

  File.write(File.join(dir, "brief.md"), "# Brief\n\nno section here\n")
  raise "brief_sync without heading returns false" unless store("brief_sync", dir: dir) == false
end
```

- [ ] **Step 2: Run, expect `unknown op 'brief_sync'`**

- [ ] **Step 3: Implement**

```ruby
  # ---- brief_sync (docs/agentile-outcomes.md §4.2) ----
  # Rewrites the brief's "## Prioritised outcomes" section from the open
  # outcomes, by rank, so the prose list and the store cannot drift. The
  # brief is a repo file in both store modes; the caller passes whichever
  # adapter's outcome_list applies.

  BRIEF_HEADING = "## Prioritised outcomes"

  def brief_sync(agentile_dir, outcomes)
    path = File.join(agentile_dir, "brief.md")
    abort "ag-store: no brief at #{path}" unless File.exist?(path)

    raw = File.read(path)
    unless raw.include?(BRIEF_HEADING)
      warn "ag-store: #{path} has no '#{BRIEF_HEADING}' heading — nothing to sync"
      return false
    end

    open = outcomes.select { |o| o[:status].to_s == "open" }
    lines = open.each_with_index.map { |o, i| "#{i + 1}. **#{o[:title]}** (`#{o[:slug]}`)" }
    body = lines.empty? ? "_No open outcomes yet — create one with `/ag-outcome`._" : lines.join("\n")
    section = "#{BRIEF_HEADING}\n\n#{body}\n\n"
    new_raw = raw.sub(/^#{Regexp.escape(BRIEF_HEADING)}\n.*?(?=^## |\z)/m) { section }
    File.write(path, new_raw)
    true
  end
```

Dispatcher: local `when "brief_sync" then Local.brief_sync(agentile_dir, Local.outcome_list(agentile_dir))`; airtable `when "brief_sync" then Local.brief_sync(agentile_dir, adapter.outcome_list)` (the airtable `outcome_list` lands in Task 5 — add the line now, it is exercised then).

- [ ] **Step 4: Run tests, expect ALL PASS**

- [ ] **Step 5: Commit**

```bash
git add bin/ag-store bin/ag-store-adapters/local.rb dev/test-ag-store-local.rb
git commit -m "Outcomes: brief_sync keeps the brief's prioritised outcomes in step with the store"
```

---

### Task 4: Airtable schema, client typecast, outcome markdown translation

**Files:**
- Modify: `bin/ag-store-adapters/airtable/schema.rb`
- Modify: `bin/ag-store-adapters/airtable/client.rb:82-91`
- Test: `dev/test-ag-store-airtable.rb` (tests 8, 9)

**Interfaces:**
- Produces: `Schema::OUTCOMES_BASE_FIELDS`, `Schema::LINK_FIELDS[:outcomes]`, `Schema.multi_select`, `Schema.render_outcome_markdown(v)`, `Schema.parse_outcome_markdown(md)` with canonical keys `title slug status rank created achieved_at abandoned_at abandoned_reason created_by` + sections `claim measure stop_rule notes`. Spec render/parse gains `serves` (string) and `tags` (array). `Client#create_records(base, table, records, typecast: false)`, `Client#update_record(base, table, id, fields, typecast: false)`.

- [ ] **Step 1: Failing tests**

Append before `puts "ALL PASS"` in `dev/test-ag-store-airtable.rb`:

```ruby
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

# 9. Client sends typecast only when asked
transport = FakeTransport.new
transport.push(200, { "records" => [] })
transport.push(200, {})
client = Airtable::Client.new(token: "t", transport: transport)
client.create_records("appTEST", "Specs", [{ "Tags" => ["auth"] }], typecast: true)
client.update_record("appTEST", "Specs", "recA", { "Title" => "x" })
raise "typecast on create: #{transport.calls[0][:body].inspect}" unless transport.calls[0][:body]["typecast"] == true
raise "no typecast by default: #{transport.calls[1][:body].inspect}" if transport.calls[1][:body].key?("typecast")
```

- [ ] **Step 2: Run, expect `undefined method 'parse_outcome_markdown'`**

- [ ] **Step 3: Implement schema.rb**

Add helper after `self.number`:

```ruby
    # Options are created on write with `typecast: true` (see client.rb), so
    # the field starts empty and a new tag never needs a schema call.
    def self.multi_select
      { type: "multipleSelects", options: { choices: [] } }
    end
```

In `SPECS_BASE_FIELDS`, after `{ name: "Rank" }.merge(number),` add `{ name: "Tags" }.merge(multi_select),`.

After `MEMBERS_BASE_FIELDS` add:

```ruby
    # Title first so it is the primary field (a slug is a poor record name).
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
```

In `LINK_FIELDS`: specs gets `["Serves Outcome", :outcomes, false],`; inbox gets `["Serves Outcome", :outcomes, false],`; add `outcomes: [["Created By", :members, false]],`.

`FRONTMATTER_KEYS`: insert `serves tags` after `created`.

`render_spec_markdown`: no change needed — `yaml_scalar` already renders arrays; `parse_spec_markdown` already turns `[a, b]` into an array. Verify the test passes without edits; if `tags` renders as `tags: [auth, testing]` and parses back, done.

Add the outcome translation after `parse_spec_markdown`:

```ruby
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
      v[:title] ||= body[/\A#\s+(.+)$/, 1].to_s.strip
      v[:title] = body[/\A#\s+(.+)$/, 1].to_s.strip if v[:title].empty?
      sections = body.split(/^## /).drop(1).to_h do |chunk|
        heading, rest = chunk.split("\n", 2)
        [heading.strip, rest.to_s.strip]
      end
      OUTCOME_SECTIONS.each { |key, heading| v[key] = sections[heading].to_s }
      v
    end
```

- [ ] **Step 4: Implement client.rb typecast**

Replace `create_records` and `update_record`:

```ruby
    # Airtable accepts at most 10 records per create/update call — chunk transparently.
    # typecast: true lets Airtable create a missing select option (used for Tags).
    def create_records(base_id, table, records_fields, typecast: false)
      records_fields.each_slice(10).flat_map do |chunk|
        body = { records: chunk.map { |f| { fields: f } } }
        body[:typecast] = true if typecast
        request(:post, "/v0/#{base_id}/#{URI.encode_www_form_component(table)}", body: body)["records"]
      end
    end

    def update_record(base_id, table, record_id, fields, typecast: false)
      body = { fields: fields }
      body[:typecast] = true if typecast
      request(:patch, "/v0/#{base_id}/#{URI.encode_www_form_component(table)}/#{record_id}", body: body)
    end
```

- [ ] **Step 5: Run both suites, expect ALL PASS**

- [ ] **Step 6: Commit**

```bash
git add bin/ag-store-adapters/airtable/schema.rb bin/ag-store-adapters/airtable/client.rb dev/test-ag-store-airtable.rb
git commit -m "Outcomes: Airtable schema (Outcomes table, Serves Outcome, Tags) and markdown translation"
```

---

### Task 5: Airtable adapter — outcome ops, serves/tags, map, provisioning

**Files:**
- Modify: `bin/ag-store-adapters/airtable.rb`
- Modify: `bin/ag-store` (airtable branch + `--airtable-outcomes-table` flag)
- Test: `dev/test-ag-store-airtable.rb` (tests 10, 11, 12)

**Interfaces:**
- Consumes: `Local.build_map` (Task 2), `Schema.*outcome*` (Task 4).
- Produces: `Adapter#outcome_list(status:)`, `#outcome_read`, `#outcome_create(slug, md, created_by)`, `#outcome_write(slug, fields)`, `#outcome_rank(slugs)`, `#outcome_achieve`, `#outcome_abandon(slug, reason:)`, `#map`; `inbox_add(text, by, title, type, serves)`; `Adapter.new(..., outcomes_table: "Outcomes")`.

- [ ] **Step 1: Failing tests**

```ruby
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
raise "doctor drift: #{checks.inspect}" unless checks["missing fields"].include?("Specs.Serves Outcome") && checks["missing fields"].include?("Specs.Tags")
```

- [ ] **Step 2: Run, expect `undefined method 'outcome_create'`**

- [ ] **Step 3: Implement airtable.rb**

Constructor: add `outcomes_table: "Outcomes"` keyword, store `@outcomes_table`. Add constant after `INBOX_FIELDS`:

```ruby
    OUTCOMES_FIELDS = {
      title: "Title", slug: "Slug", status: "Status", rank: "Rank", claim: "Claim", measure: "Measure",
      stop_rule: "Stop Rule", notes: "Notes", created: "Created", achieved_at: "Achieved At",
      abandoned_at: "Abandoned At", abandoned_reason: "Abandoned Reason",
    }.freeze
```

Lookups (after `find_member_by_email`):

```ruby
    def outcomes_records
      @outcomes_records ||= @client.list_records(@base_id, @outcomes_table)
    end

    def invalidate_outcomes_cache!
      @outcomes_records = nil
    end

    def outcome_by_slug(slug)
      outcomes_records.find { |r| r["fields"]["Slug"] == slug.to_s || r["id"] == slug }
    end

    def outcome_slug_of(record_id)
      (outcomes_records.find { |r| r["id"] == record_id } || {}).dig("fields", "Slug")
    end
```

`inbox_list`: add `serves: outcome_slug_of(Array(r["fields"]["Serves Outcome"]).first),` to the hash. `inbox_add(text, captured_by = nil, title = nil, type = nil, serves = nil)`: after the Type line add

```ruby
      if !serves.to_s.strip.empty? && (o = outcome_by_slug(serves))
        fields["Serves Outcome"] = [o["id"]]
      end
```

`project_spec_summary` and `resolved_values_for_read`: add

```ruby
        serves: outcome_slug_of(Array(f["Serves Outcome"]).first),
        tags: Array(f["Tags"]),
```

(in `resolved_values_for_read` as `v[:serves] = …` / `v[:tags] = …`).

`build_fields`: after the depends_on block add

```ruby
      if v.key?(:serves)
        o = v[:serves].to_s.empty? ? nil : outcome_by_slug(v[:serves])
        fields["Serves Outcome"] = o ? [o["id"]] : []
      end
      fields["Tags"] = Array(v[:tags]).map(&:to_s) if v.key?(:tags)
```

`spec_create` / `spec_write`: compute `fields = build_fields(v)` and pass `typecast: fields.key?("Tags")` to the client call.

Outcome ops (new section before `# ---- doctor / provision ----`):

```ruby
    # ---- outcomes (docs/agentile-outcomes.md §4.3) ----

    def project_outcome_summary(r)
      f = r["fields"]
      { slug: f["Slug"], title: f["Title"], status: f["Status"], rank: f["Rank"], created: f["Created"],
        achieved_at: f["Achieved At"], abandoned_at: f["Abandoned At"] }
    end

    def outcome_list(status: nil)
      recs = outcomes_records
      recs = recs.select { |r| r["fields"]["Status"] == status } if status
      recs.map { |r| project_outcome_summary(r) }.sort_by { |o| Local.outcome_sort_key(o) }
    end

    def outcome_read(ident)
      r = outcome_by_slug(ident)
      abort "ag-store: no such outcome: #{ident}" unless r

      v = {}
      OUTCOMES_FIELDS.each { |canon, name| v[canon] = r["fields"][name] }
      v[:created_by] = member_name_of(Array(r["fields"]["Created By"]).first)
      Schema.render_outcome_markdown(v)
    end

    def build_outcome_fields(v)
      fields = {}
      OUTCOMES_FIELDS.each { |canon, name| fields[name] = v[canon] if v.key?(canon) }
      fields["Rank"] = fields["Rank"].to_s.empty? ? nil : fields["Rank"].to_i if fields.key?("Rank")
      fields.delete("Rank") if fields["Rank"].nil?
      fields
    end

    def outcome_create(slug, markdown, created_by = nil)
      abort "ag-store: an outcome already exists with slug #{slug}" if outcome_by_slug(slug)

      v = Schema.parse_outcome_markdown(markdown)
      v[:slug] = slug
      v[:status] = "open" if v[:status].to_s.empty?
      fields = build_outcome_fields(v)
      fields["Created By"] = [created_by] if created_by.to_s.start_with?("rec")
      @client.create_records(@base_id, @outcomes_table, [fields])
      invalidate_outcomes_cache!
      slug
    end

    def outcome_write(ident, canonical_fields)
      r = outcome_by_slug(ident)
      abort "ag-store: no such outcome: #{ident}" unless r

      @client.update_record(@base_id, @outcomes_table, r["id"], build_outcome_fields(canonical_fields))
      invalidate_outcomes_cache!
      r["id"]
    end

    def outcome_rank(ordered_slugs)
      open = ordered_slugs.filter_map { |s| (r = outcome_by_slug(s)) && r["fields"]["Status"] == "open" ? s : nil }
      open.each_with_index { |s, i| outcome_write(s, { rank: i + 1 }) }
      open
    end

    def outcome_achieve(ident)
      outcome_write(ident, { status: "achieved", achieved_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ") })
      true
    end

    def outcome_abandon(ident, reason:)
      outcome_write(ident, { status: "abandoned", abandoned_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
                             abandoned_reason: reason })
      true
    end

    def map
      shipped = specs_records.select { |r| r["fields"]["Status"] == "shipped" }.map { |r| r["fields"]["Slug"] }.to_set
      entries = specs_records.map do |r|
        f = r["fields"]
        deps = (f["Depends On"] || []).map { |id| slug_of(id) }.compact
        {
          slug: f["Slug"], status: f["Status"], serves: outcome_slug_of(Array(f["Serves Outcome"]).first),
          tags: Array(f["Tags"]), blocked: f["Status"] == "ready" && !deps.all? { |d| shipped.include?(d) },
        }
      end
      Local.build_map(outcome_list, entries)
    end
```

`airtable.rb` must `require_relative "local"` at the top for `Local.build_map` / `Local.outcome_sort_key`.

`doctor`: add `"Outcomes table exists" => names.include?(@outcomes_table),`. `schema_drift`: add `@outcomes_table => Schema::OUTCOMES_BASE_FIELDS.map { |f| f[:name] } + Schema::LINK_FIELDS.fetch(:outcomes, []).map(&:first),`. `provision`: `outcomes_id = ensure_table(existing, @outcomes_table, Schema::OUTCOMES_BASE_FIELDS)`, `ensure_base_fields(outcomes_id, …)`, add `outcomes: outcomes_id` to `table_ids`, and `ensure_link_fields(outcomes_id, :outcomes, table_ids)`. `Airtable.create_base`: add the Outcomes table to `tables_def`, capture its id, and call `ensure_link_fields` for it; accept `outcomes_table: "Outcomes"`.

Dispatcher, airtable branch: pass `outcomes_table: flags["airtable-outcomes-table"] || "Outcomes"` to `Adapter.new` and to `create_base`; `inbox_add` passes `flags["serves"]`; add

```ruby
    when "outcome_list" then adapter.outcome_list(status: flags["status"])
    when "outcome_read" then adapter.outcome_read(positional[0])
    when "outcome_create" then adapter.outcome_create(positional[0], $stdin.read, flags["by"])
    when "outcome_write" then adapter.outcome_write(positional[0], sets.transform_keys(&:to_sym))
    when "outcome_rank" then adapter.outcome_rank(positional)
    when "outcome_achieve" then adapter.outcome_achieve(positional[0])
    when "outcome_abandon" then adapter.outcome_abandon(positional[0], reason: flags["reason"].to_s)
    when "map" then adapter.map
```

- [ ] **Step 4: Run both suites, expect ALL PASS**

- [ ] **Step 5: Commit**

```bash
git add bin/ag-store bin/ag-store-adapters/airtable.rb dev/test-ag-store-airtable.rb
git commit -m "Outcomes: Airtable adapter ops, provisioning, and the map view"
```

---

### Task 6: New skills — `/ag-outcome`, `/ag-decompose`, `/ag-map`

**Files:**
- Create: `skills/ag-outcome/SKILL.md`, `skills/ag-decompose/SKILL.md`, `skills/ag-map/SKILL.md`

No automated tests exist for skills; the acceptance check is Task 9 (dogfood).

- [ ] **Step 1: Write `skills/ag-outcome/SKILL.md`**

```markdown
---
name: ag-outcome
description: Create or edit an Agentile Outcome — the falsifiable bet above specs — through a short interview for its claim, measure and stop rule; or record one as achieved. Non-coding. Trigger phrases include "/ag-outcome", "new outcome", "add an outcome", "edit the outcome", "mark the outcome achieved", "what are we betting on".
allowed-tools: AskUserQuestion, Bash, Read
arguments: [slug-or-achieve]
---

# ag-outcome

An **Outcome** is a bet: a claim about what becomes true, a measure a human can judge it by, and a stop rule that says when to give up. It is the layer above specs (`docs/agentile-outcomes.md`) and the input `/ag-decompose` works from. This skill is the shaping interview one level up — short, and biased toward rejecting a claim that is really a deliverable.

**You do not write code or specs here.** You produce or edit one Outcome.

## Modes

- `/ag-outcome` — interview and create a new Outcome.
- `/ag-outcome <slug>` — re-open an existing one; ask what changed and patch it.
- `/ag-outcome achieve <slug>` — record the measure as met.

## Step 1 — Resolve the store

Read `.agentile/config.md` for the **Agentile directory** (default `docs/agentile/`) and `store:` from `.agentile/store.md` (default `local`). Every operation goes through `ag-store --dir "<dir>" --store "<store>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). Read `<dir>/brief.md` — an Outcome should sit inside the brief's constraints and non-goals, and usually elaborates one of its prioritised outcomes.

Run `ag-store outcome_list ...` and show the existing Outcomes (slug, title, status, rank) so the user does not create a duplicate.

## Step 2 — Interview (create mode)

One or two questions at a time, `AskUserQuestion` for discrete choices.

1. **The claim.** "When this is achieved, what is true that isn't true today?" Push back on any answer that names a deliverable — "provide SSO", "build the export" — with: *what would that let someone do, or stop someone doing?* The claim passes when the measure can be stated without listing the work.
2. **The measure.** "What evidence would you accept that the claim now holds?" It must be observable by a human when evidence arrives — a pilot passing, a questionnaire answered, a number crossing a line. A spec count is not a measure.
3. **The stop rule.** "What would make you abandon this whole line of work?" An Outcome without a stop rule is not Ready; if the user cannot name one, say so and ask what evidence would embarrass the bet.
4. **Title and slug.** Derive a short title from the claim (no colons — dashes or commas), and a kebab-case slug. Confirm both in one question.

Optional, only if it comes up: notes (evidence already in hand, links).

## Step 3 — Write it

Build the markdown from `.agentile/outcome-template.md` (fallback `"${CLAUDE_PLUGIN_ROOT}/templates/agentile/outcome-template.md"`): frontmatter `title`, `slug`, `status: open`, `rank:` blank, `created:` today; body sections **Claim**, **Measure**, **Stop rule**, **Notes**. Keep every frontmatter value valid YAML.

Run `ag-store whoami ...` for attribution, then:

```
ag-store outcome_create <slug> --by "<whoami>" --dir "<dir>" --store "<store>"
```

piping the markdown on stdin. The Outcome is created **unranked**; `/ag-prioritise` ranks it. Then run `ag-store brief_sync ...` so the brief's "Prioritised outcomes" list shows it.

## Step 2b — Edit mode (`/ag-outcome <slug>`)

`ag-store outcome_read <slug> ...`, show it, ask what changed (one question). Patch frontmatter with `ag-store outcome_write <slug> --set key=value ...`; for body sections re-create is not available — tell the user body edits are made directly in `<dir>/outcomes/<slug>.md` (local) or the `Outcomes` table (airtable), and offer to make the edit for the local store.

## Step 2c — Achieve mode (`/ag-outcome achieve <slug>`)

Read the Outcome and `ag-store map ...` for the specs serving it. Ask one question: *what evidence shows the measure is met?* Record the answer as a Notes addition where the store allows it, then `ag-store outcome_achieve <slug> ...` and `ag-store brief_sync ...`. If serving specs are still `ready`/`in_progress`, say so — achieving does not abandon them, and the user may want `/ag-abandon` on leftovers.

## Step 4 — Report

One short block: slug, title, status, and the next move — `/ag-prioritise` to rank it, `/ag-decompose <slug>` to propose the work that would make it true.
```

- [ ] **Step 2: Write `skills/ag-decompose/SKILL.md`**

```markdown
---
name: ag-decompose
description: Propose the inbox stubs that would make an Agentile Outcome true — four to eight one-liners the user accepts, edits or rejects, each landing in the Inbox linked to the Outcome. Never writes specs. Trigger phrases include "/ag-decompose", "decompose this outcome", "what work would achieve", "break down the outcome", "propose specs for".
allowed-tools: AskUserQuestion, Bash, Read
arguments: [outcome-slug]
---

# ag-decompose

The reason Outcomes exist. An Outcome with a sharp claim, a measure and constraints is a *prompt*: this skill turns it into candidate work. It proposes **stubs**, not specs — decomposition is a proposal, shaping (`/ag-shape`) remains the gate where each idea is interviewed into something buildable.

**You do not write code, specs, or plans here.** You add stubs to the Inbox, each linked to the Outcome.

## Step 1 — Load context

- Resolve the **Agentile directory** and store as every skill does (`.agentile/config.md`, `.agentile/store.md`; `ag-store --dir "<dir>" --store "<store>"`, fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`).
- The target is `$outcome-slug` (or `$ARGUMENTS`). If absent or ambiguous, run `ag-store outcome_list --status open ...` and ask which.
- Read the Outcome (`ag-store outcome_read <slug> ...`), the brief (`<dir>/brief.md`), the project's `CLAUDE.md`, and skim `docs/adr/` — the constraints and non-goals bound what you may propose.
- Run `ag-store map ...` and note the specs **already serving this Outcome** (any status) and the current Inbox (`ag-store inbox_list ...`). You are adding to existing work, not restarting it.

## Step 2 — Propose

Produce **four to eight** candidate stubs. Each is one line in the voice `/ag-capture` uses — what to change and why, concrete enough to shape — with a derived **title** (3–6 words) and a **type** (`feature`/`bug`/`chore`/`spike`). Together they should be sufficient for the claim; individually each should be shippable on its own.

Before the list, name the **landmines** in two or three lines: existing specs the proposals overlap or collide with, constraints from the brief or ADRs that shape the approach (an air-gapped install, a determinism guarantee, a non-goal), and anything that should be a spike because the approach is unknown.

Present the proposals as a numbered list. Then, with `AskUserQuestion` (multi-select), ask which to accept as-is. For any the user wants changed, take the edit in plain language and show the revised line. Never add acceptance criteria or estimates — those are shaping's job.

## Step 3 — Capture

For each accepted stub:

```
ag-store whoami ...
ag-store inbox_add "<stub text>" --title "<title>" --type "<type>" --serves "<outcome-slug>" --by "<whoami>" --dir "<dir>" --store "<store>"
```

Quote the text so the shell cannot eat an apostrophe. The `local` store drops `--serves` (its inbox is a flat list); the `airtable` store links the stub to the Outcome so provenance survives to `/ag-shape`, which will offer the link as the default `serves`.

## Step 4 — Report

How many stubs landed, their titles, and the next move: `/ag-shape` on each. Mention any proposal the user rejected in one line, so the reasoning is not lost.
```

- [ ] **Step 3: Write `skills/ag-map/SKILL.md`**

```markdown
---
name: ag-map
description: Show the Agentile world at Outcome level — each Outcome by rank with its specs by state, what is blocked, the free-standing specs, and the tag index. Read-only. Trigger phrases include "/ag-map", "show the map", "outcome view", "where are we", "what serves what", "the big picture".
allowed-tools: Bash, Read
---

# ag-map

The higher-level view. Everything shown is **computed** from Outcomes and specs by `ag-store map` — nothing here is a stored field, so it can never be stale. Makes no changes.

## Steps

1. Resolve the **Agentile directory** and store (`.agentile/config.md`, `.agentile/store.md`). Run `ag-store map --dir "<dir>" --store "<store>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) and parse the JSON object: `outcomes` (rank-ordered, each with `specs` bucketed by `ready`/`in_progress`/`shipped`/`abandoned` and a `blocked` list), `unlinked` (specs serving no Outcome, same buckets), `orphaned` (specs whose `serves` names no known Outcome), and `tags`.

2. Render, in this order:

   ```
   1. <title>  (<slug>)  open · rank 1
      ready 3 (1 blocked: <slug>) · in progress 1 · shipped 4 · abandoned 0
      <spec slugs, grouped by state>
   …
   Unlinked  ready 2 · in progress 0 · shipped 6
   Tags      auth (3) · testing (2)
   ```

   Achieved and abandoned Outcomes go in a short trailer, one line each, after the open ones.

3. Flag, one line each, only when true:
   - an open Outcome with **no specs at all** → "no work serves this yet — `/ag-decompose <slug>`?"
   - an open Outcome whose serving specs are **all shipped or abandoned** → "all serving work is done — is the measure met? `/ag-outcome achieve <slug>`"
   - an open Outcome that is **unranked** → "unranked — `/ag-prioritise`"
   - any **orphaned** specs → name them; the fix is `ag-store spec_write <slug> --set serves=<real-slug>` or clearing it.

4. End with one line: the count of open Outcomes, ready specs, and blocked specs. Do not summarise, triage, or recommend beyond the flags above.
```

- [ ] **Step 4: Commit**

```bash
git add skills/ag-outcome skills/ag-decompose skills/ag-map
git commit -m "Outcomes: /ag-outcome, /ag-decompose and /ag-map skills"
```

---

### Task 7: Existing skills, agent, and templates learn about Outcomes

**Files:**
- Modify: `skills/ag-shape/SKILL.md:72` (dependencies bullet), `:91` (graduate bullet), `:32` (brief bullet)
- Modify: `skills/ag-prioritise/SKILL.md` (new Step 0, Step 3 ordering)
- Modify: `skills/ag-retro/SKILL.md` (Step 2 bullet, Step 3 bullet)
- Modify: `skills/ag-abandon/SKILL.md` (Step 2 + new Step 6a)
- Modify: `skills/ag-capture/SKILL.md:66` (command line)
- Modify: `skills/ag-spec/SKILL.md:31`
- Modify: `skills/ag-init/SKILL.md:53-55` (brief note), `:142` (scaffold), file list
- Modify: `agents/ag-planner.md:17`
- Modify: `templates/agentile/config.md:9-12`, `templates/agentile/brief-template.md:17-21`, `templates/CLAUDE.agentile-section.md`, `templates/stores/airtable/README.md`

- [ ] **Step 1: ag-shape**

Replace the brief bullet (line 32) with:

> - Read `<dir>/brief.md` if present — the project's users and constraints. Run `ag-store outcome_list --status open ...`; if any Outcomes exist, Business Value is scored as **contribution to the Outcome this spec serves** (Step 3); with none, score against the brief's prose outcomes as before.

Append to the Dependencies bullet (line 72):

> - **Serves**: ask which Outcome this spec serves, offering the open slugs from `outcome_list` plus "none — free-standing". A stub that arrived from `/ag-decompose` already carries `serves` (shown by `inbox_list`); offer it as the default. Write the slug to `serves:`; blank means free-standing and is always allowed. If the conversation surfaced natural themes (an area, a layer), write two or three as `tags: [...]`; never invent tags to fill the field.

In the Graduate bullet (line 91), after `technical_certainty` add `, serves, tags`.

- [ ] **Step 2: ag-prioritise**

Insert before "### Step 1 — Read the active set":

```markdown
### Step 0 — Rank the Outcomes first

Run `ag-store outcome_list --status open --dir "<dir>" --store "<store>"`. If there are none, skip to Step 1. If any open Outcome has a null `rank`, show the open Outcomes (slug, title, rank) and ask for their order (`AskUserQuestion`, or plain language), then apply it:

```
ag-store outcome_rank <slug-1> <slug-2> ... --dir "<dir>" --store "<store>"
```

Outcome rank is **authored**; spec rank below is **derived** from it and materialised — that is the one prioritisation authority, made practical. Run `ag-store brief_sync ...` after ranking.
```

In Step 1's `spec_list` sentence, add `serves` to the listed fields. Replace Step 3's second sentence onward with:

> Rank the rest by the **rank of the Outcome each serves** first (specs serving rank-1 before rank-2, …), then within an Outcome by **Business Value × Technical Certainty** (descending), ties alphabetically by slug. Specs serving no Outcome form a final bucket in BV × TC order — promote one above the buckets only if its BV is high and you say why. Then enforce dependency ordering: if spec A declares `depends_on: [B]`, move A after B, even across Outcome buckets.

- [ ] **Step 3: ag-retro**

Step 2, add a bullet after "Did shipped work actually work?":

> - **Are the bets still good?** For each open Outcome (`ag-store outcome_list --status open ...`) read its measure and stop rule against what shipped (`ag-store map ...`). Propose `achieved` where the evidence meets the measure, `abandoned` where the stop rule has fired, and say plainly where neither is yet decidable. A person confirms; you do not transition an Outcome on your own.

Step 3, add a bullet:

> - An **Outcome transition** on approval — `ag-store outcome_achieve <slug> ...` or `/ag-abandon <slug>` (which cascades to serving specs) — followed by `ag-store brief_sync ...` so the brief's list matches the store.

- [ ] **Step 4: ag-abandon**

Step 2: add a paragraph:

> If the target is an **Outcome** (its slug appears in `ag-store outcome_list ...` and not in `spec_list`), the cascade candidates are the specs serving it — every `ready`/`in_progress` slug under that Outcome in `ag-store map ...` — plus *their* dependents from Step 3. Run Steps 4–6 for each of those specs as usual, then apply the Outcome itself with `ag-store outcome_abandon <slug> --reason "<reason>" --dir "<dir>" --store "<store>"` and `ag-store brief_sync ...`. Shipped specs are untouched — the work happened; the bet is what is being closed.

- [ ] **Step 5: ag-capture, ag-spec, ag-init, ag-planner**

ag-capture line 66: add `[--serves "<outcome-slug>"]` after `--type "<type>"`, and a sentence: `Pass --serves only when the user named an Outcome explicitly ("for the identity outcome") — never ask.`

ag-spec step 4: after `today's date` add `, and serves: when the idea plainly names an existing Outcome (check ag-store outcome_list); otherwise leave it blank`.

ag-init: in Step 2a's closing paragraph add: `The brief's "Prioritised outcomes" section is the sync target for ag-store brief_sync — once Outcomes exist (/ag-outcome), that list is regenerated from them; the rest of the brief stays hand-written.` In Step 4's file list add `.agentile/outcome-template.md` after `.agentile/spec-template.md`, and to the specs-tree bullet add: `Also create <dir>/outcomes/ with a .gitkeep (Solo); in Team mode Outcomes live in the store's Outcomes table, which provision created.`

ag-planner line 17: append ` If the spec's frontmatter has serves:, also read that Outcome (ag-store outcome_read <slug> ...) — the plan should serve the claim, not only the acceptance criteria.`

- [ ] **Step 6: Templates**

config.md Paths list: add `- outcomes/ — the Outcomes (falsifiable bets) specs may serve; flat, status in frontmatter` after the `inbox.md` line.

brief-template.md: replace the "Prioritised outcomes" section body with:

```markdown
<Once Outcomes exist, this list is regenerated from them by `ag-store brief_sync`
(rank order, open only) — edit them with `/ag-outcome`, not here. Until then:>

1. <outcome>
2. <outcome>
3. <outcome>
```

CLAUDE.agentile-section.md "Where things live": add after the Brief bullet:

`- **Outcomes** (`docs/agentile/outcomes/`) — the falsifiable bets above specs: a claim, a measure, a stop rule, ranked and flat. A spec may `serve` one; none is required. Create with `/ag-outcome`, propose the work for one with `/ag-decompose <slug>`, see the whole picture with `/ag-map`.`

And in "How to work" add a line: `- Thinking above the spec level → `/ag-outcome` to state a bet, `/ag-decompose <slug>` to turn it into stubs, `/ag-map` to see what serves what. Outcomes are ranked by `/ag-prioritise` before specs are.`

templates/stores/airtable/README.md: add an `Outcomes` table row to its schema description (fields as in Task 4) and note `Serves Outcome` on Specs/Inbox and `Tags` (multiple select, typecast on write); note that `ag-store provision` backfills all of it on an existing base.

- [ ] **Step 7: Commit**

```bash
git add skills agents templates
git commit -m "Outcomes: shape, prioritise, retro, abandon, capture, spec, init and planner learn the layer"
```

---

### Task 8: Docs, changelog, version 0.12.0

**Files:**
- Modify: `README.md` (Skills line; new "### Outcomes" subsection after "### Spec dependencies"), `methodology.md` (new subsection after "### The spec artefact"), `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: README**

Skills line: add `/ag-outcome`, `/ag-decompose`, `/ag-map` after `/ag-shape`.

Insert after the "### Spec dependencies" paragraph:

```markdown
### Outcomes

The layer above specs. An **Outcome** is a bet — a claim about what becomes
true, a measure a human judges it by, and a stop rule — kept flat and ranked.
A spec may `serve` one Outcome (frontmatter `serves: <slug>`) and carry
free-form `tags`; neither is ever required, and a spec with no Outcome is
claimable exactly as before. Everything you would want to *report* — progress,
what's blocked, what's grouped where — is computed by `ag-store map`, never
stored, so it cannot go stale. The layer earns its place as an *input*:
`/ag-decompose <slug>` turns an Outcome into candidate stubs. Design and the
Jira-epic argument it rejects: `docs/agentile-outcomes.md`.
```

- [ ] **Step 2: methodology.md**

Insert after "### The spec artefact":

```markdown
### Outcomes: the bet above the spec

Specs are units of change; they do not say what the change is *for* beyond
their own metric. An **Outcome** does: a claim that spans specs and is
falsifiable independently of them, a measure, and a stop rule. It is not a
container — it has no progress field, no rollup, and nothing derived is stored
on it; the grouped view is computed on demand. It is flat: a grouping with its
own claim is a sibling Outcome, one without is a tag. And it never gates:
work can be captured, shaped and claimed with no Outcome at all.

The point of the layer is decomposition, not reporting. An Outcome is the
prompt the loop generates work from, and the unit at which a human decides to
stop. (Whether Outcomes are files or rows is the implementation's business.)
```

- [ ] **Step 3: CHANGELOG + version**

Prepend to CHANGELOG under the header:

```markdown
## 0.12.0 — 2026-09-14

- **Outcomes: the layer above specs.** A flat, ranked list of falsifiable bets
  — claim, measure, stop rule — that specs may optionally `serve`. Nothing
  derivable is stored on one; `ag-store map` computes the grouped view. New
  skills `/ag-outcome` (shape a bet), `/ag-decompose` (propose the stubs that
  would make it true), `/ag-map` (the world at Outcome level). Design, and the
  Jira-epic model it deliberately rejects: `docs/agentile-outcomes.md`.
- Specs gain optional `serves:` and `tags:`; stubs gain an optional `serves`
  hint; `/ag-shape` asks, `/ag-prioritise` ranks Outcomes before specs,
  `/ag-retro` reviews bets against their measures, `/ag-abandon` closes a bet
  and cascades to the work serving it.
- `ag-store brief_sync` regenerates the brief's "Prioritised outcomes" list
  from the store so prose and table cannot drift.
- Airtable: new `Outcomes` table, `Serves Outcome` links on Specs and Inbox,
  `Tags` multiple-select written with `typecast`; `provision` backfills an
  existing base and `doctor` reports the drift.
```

`plugin.json` and `marketplace.json`: `"0.11.0"` → `"0.12.0"` (one occurrence each; verify they agree).

- [ ] **Step 4: Run every suite**

```bash
ruby dev/test-ag-store-local.rb && ruby dev/test-ag-store-airtable.rb && ruby hooks/test-gates.rb && ruby dev/test-ag-claim.rb && ruby dev/test-ag-dependents.rb
```

Expected: `ALL PASS` from each.

- [ ] **Step 5: Commit**

```bash
git add README.md methodology.md CHANGELOG.md .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "Outcomes: docs, changelog, 0.12.0"
```

---

### Task 9: Dogfood on Tekmor (Team store)

**Files:** none in this repo. Uses `~/agenta/products/docassure` (`.agentile/store.md`: airtable, base `apptZkYqMga5DAtpZ`).

- [ ] **Step 1: Provision the live base**

```bash
cd ~/agenta/products/docassure && set -a && . ~/projects/agentile/.env.local && set +a
ruby ~/projects/agentile/bin/ag-store provision --dir docs/agentile/ --store airtable --airtable-base apptZkYqMga5DAtpZ
ruby ~/projects/agentile/bin/ag-store doctor    --dir docs/agentile/ --store airtable --airtable-base apptZkYqMga5DAtpZ
```

Expected: doctor reports every check `true` and `schema up to date: true`. If `Tags` creation is rejected for an empty `choices` list, seed the field with one placeholder choice in `Schema.multi_select` and re-run.

- [ ] **Step 2: Promote the brief's four outcomes**

For each of the four prioritised outcomes in `docs/agentile/brief.md`, write an Outcome markdown with a claim/measure/stop rule (interviewing the user as `/ag-outcome` would), and `outcome_create` it. Rank them 1–4 with `outcome_rank`. Run `brief_sync` and confirm the brief's list now reads from the store.

- [ ] **Step 3: Link a spec and read the map**

```
ruby ~/projects/agentile/bin/ag-store spec_write playwright-vite-dev-server --set serves=<outcome-2-slug> --dir docs/agentile/ --store airtable --airtable-base apptZkYqMga5DAtpZ
ruby ~/projects/agentile/bin/ag-store map --dir docs/agentile/ --store airtable --airtable-base apptZkYqMga5DAtpZ
```

Expected: the map shows the spec under outcome 2, four open ranked Outcomes, and the six stubs untouched.

- [ ] **Step 4: Restart Claude Code and run `/ag-map`, then `/ag-decompose` against the procurement outcome** — the identity worked example. Report what was proposed and what was accepted.

---

## Self-review

**Spec coverage.** §1 stack → Tasks 1, 4. §2 artefact → Task 1 template, Task 4 render/parse. §3 links → Tasks 2, 4, 5, 7. §4 ops table → Tasks 1, 2, 3, 5 (all nine ops + changed ops). §4.1 map → Tasks 2, 5. §4.2 local → Tasks 1–3. §4.3 airtable → Tasks 4, 5. §5.1–5.3 new skills → Task 6. §5.4 skill changes → Task 7 (all eight named, plus planner). §7 migration → provision/doctor in Task 5. §8 dogfood → Task 9. §6 exclusions: no task adds a parent field, a derived field, or outcome-level `depends_on` — confirmed by the field lists in Tasks 1 and 4.

**Placeholder scan.** None of the banned phrases appear; every code step shows code, every skill file is complete.

**Type consistency.** `outcome_summary`/`project_outcome_summary` both produce `{slug,title,status,rank,created,achieved_at,abandoned_at}` (Task 1, Task 5) and `Local.outcome_sort_key` is used by both (Task 1 defines it, Task 5 calls it — Task 5 adds `require_relative "local"`). `build_map` spec entry shape `{slug,status,serves,tags,blocked}` matches in Task 2 (local `map`) and Task 5 (airtable `map`). `inbox_add` sixth positional `serves` matches across dispatcher, local, airtable. Airtable test 10 expects `Rank == 1` because `build_outcome_fields` casts `"1"` → `1`.
