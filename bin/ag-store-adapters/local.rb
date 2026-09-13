# frozen_string_literal: true
# The `local` store adapter — files + git, exactly today's Agentile behaviour.
# Every method takes the resolved Agentile directory's `specs/` path (or the
# Agentile directory itself for inbox ops) as its first argument; callers
# (bin/ag-store, and the thin bin/ag-claim / bin/ag-dependents wrappers) do
# the config-resolution and printing. Kept dependency-free (stdlib only),
# matching every other script in bin/.
require "yaml"
require "date" # spec frontmatter has `created: YYYY-MM-DD`, which YAML loads as a Date
require "fileutils"
require "time"

module Local
  RESERVED = %w[done abandoned].freeze

  module_function

  # ---- shared spec loading (unchanged from the pre-refactor ag-claim/ag-dependents) ----

  # A spec is a flat file <root>/NNNN-<slug>.md (identity from the filename) or a
  # directory <root>/NNNN-<slug>/SPEC.md (identity from the directory name; plan.md
  # and supporting files beside SPEC.md are never specs).
  def load_spec(path, ident)
    raw = File.read(path)
    fm  = (YAML.safe_load(raw[/\A---\n(.*?)\n---/m, 1] || "", permitted_classes: [Time, Date]) || {})
    m   = ident.match(/\A(\d+)-(.+)\z/)
    { path: path, raw: raw, fm: fm, prefix: (m ? m[1].to_i : nil), slug: (m ? m[2] : ident) }
  end

  # Enumerate the specs directly under one root: flat *.md files plus */SPEC.md dirs.
  def specs_in(root)
    return [] unless File.directory?(root)

    flat = Dir.glob(File.join(root, "*.md")).map { |p| load_spec(p, File.basename(p, ".md")) }
    # The single-level glob means done/ and abandoned/ contents never match here;
    # the RESERVED reject covers the degenerate case of a SPEC.md placed directly
    # inside <root>/done/ or <root>/abandoned/.
    dirs = Dir.glob(File.join(root, "*", "SPEC.md"))
              .reject { |p| RESERVED.include?(File.basename(File.dirname(p))) }
              .map { |p| load_spec(p, File.basename(File.dirname(p))) }
    flat + dirs
  end

  def shipped_map(specs_dir)
    resolved = specs_in(specs_dir) + specs_in(File.join(specs_dir, "done")) + specs_in(File.join(specs_dir, "abandoned"))
    shipped = {}
    resolved.each { |s| shipped[s[:slug]] = true if s[:fm]["status"] == "shipped" }
    shipped
  end

  def find_by_ident(specs_dir, ident)
    bare = ident.sub(/\A\d+-/, "")
    (specs_in(specs_dir) + specs_in(File.join(specs_dir, "done")) + specs_in(File.join(specs_dir, "abandoned")))
      .find { |s| s[:slug] == bare || s[:slug] == ident || File.basename(s[:path], ".md") == ident }
  end

  # Patch one or more frontmatter keys in place, preserving comments/key order
  # (block-form sub throughout — label/reason are arbitrary user text, and the
  # string form of sub would interpret \&, \1, \\ etc. in the replacement).
  def stamp!(spec, fields)
    fm_text = spec[:raw][/\A---\n(.*?)\n---/m, 1]
    if fm_text.nil?
      warn "ag-store: #{spec[:path]} has no YAML frontmatter — cannot stamp"
      exit 1
    end
    new_fm = fm_text.dup
    fields.each do |key, val|
      if new_fm =~ /^#{Regexp.escape(key)}:.*$/
        new_fm = new_fm.sub(/^#{Regexp.escape(key)}:.*$/) { "#{key}: #{val}" }
      else
        new_fm = "#{new_fm}\n#{key}: #{val}"
      end
    end
    body = spec[:raw].sub(/\A---\n.*?\n---/m) { "---\n#{new_fm}\n---" }
    if body == spec[:raw] && !fields.empty?
      warn "ag-store: could not rewrite frontmatter for #{spec[:path]}"
      exit 1
    end
    File.write(spec[:path], body)
    body
  end

  def git_mv(old_path, new_path)
    system("git", "mv", old_path, new_path, out: File::NULL, err: File::NULL) ||
      FileUtils.mv(old_path, new_path) # outside a git repo (or an untracked path): plain rename
  end

  # ---- claim (bin/ag-claim's exact behaviour) ----

  # Prints/returns the claimed spec path, or one of: WIP_FULL | BLOCKED | UNPRIORITISED | NONE.
  def claim(specs_dir, session, label, wip)
    abort "ag-store: no such specs dir: #{specs_dir}" unless File.directory?(specs_dir)
    wip = (wip.to_s.empty? ? 0 : wip.to_i)

    result = nil
    lock_path = File.join(specs_dir, ".pull.lock")
    File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
      lock.flock(File::LOCK_EX)

      pool = specs_in(specs_dir)
      dupes = pool.group_by { |s| s[:slug] }.select { |_, v| v.size > 1 }.keys
      abort "ag-store: duplicate slug(s) in claim pool: #{dupes.join(', ')}" if dupes.any?

      shipped = shipped_map(specs_dir)

      in_progress = pool.count { |s| s[:fm]["status"] == "in_progress" }
      if wip.positive? && in_progress >= wip
        result = "WIP_FULL"
        next
      end

      ready = pool.select { |s| s[:fm]["status"] == "ready" && s[:fm]["claimed_by"].to_s.empty? }
      if ready.empty?
        result = "NONE"
        next
      end

      prioritised = ready.select { |s| s[:prefix] }
      if prioritised.empty?
        result = "UNPRIORITISED"
        next
      end

      eligible = prioritised.select { |s| Array(s[:fm]["depends_on"]).all? { |dep| shipped[dep.to_s] } }
      if eligible.empty?
        result = "BLOCKED"
        next
      end

      chosen = eligible.min_by { |s| [s[:prefix], s[:slug]] }
      stamp!(chosen, {
        "status" => "in_progress",
        "claimed_by" => session,
        "label" => label.to_s,
        "claimed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      })
      result = chosen[:path]
    end
    result
  end

  # ---- dependents (bin/ag-dependents' exact behaviour) ----

  def each_active_spec(specs_dir)
    Dir.glob(File.join(specs_dir, "*.md")).each { |path| yield path, File.basename(path, ".md") }
    Dir.glob(File.join(specs_dir, "*", "SPEC.md")).each do |path|
      dname = File.basename(File.dirname(path))
      next if RESERVED.include?(dname)

      yield path, dname
    end
  end

  # Transitive set of ACTIVE (ready/in_progress) specs whose depends_on reaches
  # <target>, nearest first, cycle-safe. Ignores done/ and abandoned/.
  def dependents(specs_dir, target)
    abort "ag-store: no such specs dir: #{specs_dir}" unless File.directory?(specs_dir)

    reverse = Hash.new { |h, k| h[k] = [] } # dep slug -> [dependent slugs]
    each_active_spec(specs_dir) do |path, ident|
      fm = (YAML.safe_load(File.read(path)[/\A---\n(.*?)\n---/m, 1] || "", permitted_classes: [Time, Date]) || {})
      next unless %w[ready in_progress].include?(fm["status"])

      m = ident.match(/\A(\d+)-(.+)\z/)
      s = m ? m[2] : ident
      Array(fm["depends_on"]).each { |dep| reverse[dep.to_s] << s }
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

  def deps(specs_dir, ident)
    spec = find_by_ident(specs_dir, ident)
    abort "ag-store: no such spec: #{ident}" unless spec

    Array(spec[:fm]["depends_on"])
  end

  # ---- inbox ----

  def inbox_path(agentile_dir)
    File.join(agentile_dir, "inbox.md")
  end

  STUB_RE = /\A- \[ \] (.*?)(?: — \(captured (\d{4}-\d{2}-\d{2})\))?\z/

  def inbox_list(agentile_dir)
    path = inbox_path(agentile_dir)
    abort "ag-store: no such inbox: #{path}" unless File.exist?(path)

    lines = File.readlines(path, chomp: true)
    stubs = []
    lines.each_with_index do |line, idx|
      m = STUB_RE.match(line)
      next unless m

      stubs << { id: (stubs.size + 1).to_s, line_index: idx, text: m[1], captured_at: m[2], captured_by: nil }
    end
    stubs
  end

  # captured_by is accepted for a uniform contract across adapters but not
  # written into the plain-text line — git blame already gives attribution
  # for free in solo mode (see the design note in the team-mode plan).
  def inbox_add(agentile_dir, text, _captured_by = nil)
    path = inbox_path(agentile_dir)
    abort "ag-store: no such inbox: #{path} — run /ag-init first" unless File.exist?(path)

    date = Time.now.strftime("%Y-%m-%d")
    File.open(path, "a") { |f| f.puts("- [ ] #{text} — (captured #{date})") }
    true
  end

  def inbox_drop(agentile_dir, id)
    path = inbox_path(agentile_dir)
    abort "ag-store: no such inbox: #{path}" unless File.exist?(path)

    stubs = inbox_list(agentile_dir)
    target = stubs.find { |s| s[:id] == id.to_s }
    abort "ag-store: no such inbox stub: #{id}" unless target

    lines = File.readlines(path, chomp: true)
    lines.delete_at(target[:line_index])
    File.write(path, lines.join("\n") + "\n")
    true
  end

  # ---- spec list / read / create ----

  def spec_pool(specs_dir, pool: "active")
    case pool
    when "active" then specs_in(specs_dir)
    when "done" then specs_in(File.join(specs_dir, "done"))
    when "abandoned" then specs_in(File.join(specs_dir, "abandoned"))
    else abort "ag-store: unknown pool: #{pool}"
    end
  end

  def spec_list(specs_dir, status: nil, pool: "active")
    spec_pool(specs_dir, pool: pool)
      .select { |s| status.nil? || s[:fm]["status"] == status }
      .sort_by { |s| [s[:prefix] || 1_000_000, s[:slug]] }
      .map do |s|
        {
          slug: s[:slug],
          prefix: s[:prefix],
          path: s[:path],
          status: s[:fm]["status"],
          title: s[:fm]["title"],
          created: s[:fm]["created"],
          business_value: s[:fm]["business_value"],
          technical_certainty: s[:fm]["technical_certainty"],
          route: s[:fm]["route"],
          depends_on: Array(s[:fm]["depends_on"]),
          claimed_by: s[:fm]["claimed_by"],
          claimed_at: s[:fm]["claimed_at"],
          label: s[:fm]["label"],
          shipped_at: s[:fm]["shipped_at"],
        }
      end
  end

  def spec_read(specs_dir, ident)
    spec = find_by_ident(specs_dir, ident)
    abort "ag-store: no such spec: #{ident}" unless spec

    spec[:raw]
  end

  # New specs are always written unprefixed (Ready but not yet prioritised) —
  # unchanged from today's ag-shape/ag-spec behaviour.
  def spec_create(specs_dir, slug, markdown)
    FileUtils.mkdir_p(specs_dir)
    path = File.join(specs_dir, "#{slug}.md")
    abort "ag-store: a spec already exists at #{path}" if File.exist?(path)

    File.write(path, markdown)
    path
  end

  # ---- rank (ag-prioritise's Step 5, absorbed from prose into a tool) ----

  # ordered_slugs: the FULL desired queue order (ready specs only; in_progress
  # specs must never appear here — they are never renamed). Dense NNNN-
  # prefixes are assigned by position. Two-step (temp name, then final name)
  # avoids collisions when renumbering swaps prefixes around.
  def rank(specs_dir, ordered_slugs)
    pool = specs_in(specs_dir)
    by_slug = {}
    pool.each { |s| by_slug[s[:slug]] = s }

    valid = ordered_slugs.map { |slug| by_slug[slug] }.compact.select { |s| s[:fm]["status"] == "ready" }

    temps = valid.map do |s|
      is_dir = File.basename(s[:path]) == "SPEC.md"
      old = is_dir ? File.dirname(s[:path]) : s[:path]
      tmp = is_dir ? File.join(specs_dir, "tmp-#{s[:slug]}") : File.join(specs_dir, "tmp-#{s[:slug]}.md")
      git_mv(old, tmp)
      [s[:slug], tmp, is_dir]
    end

    temps.each_with_index.map do |(slug, tmp, is_dir), idx|
      prefix = (idx + 1).to_s.rjust(4, "0")
      final = is_dir ? File.join(specs_dir, "#{prefix}-#{slug}") : File.join(specs_dir, "#{prefix}-#{slug}.md")
      git_mv(tmp, final)
      final
    end
  end

  # Patch arbitrary frontmatter fields on an existing spec in place (comments
  # and key order preserved, same as claim/release/ship/abandon). Used for
  # edits none of the named ops cover — e.g. /ag-abandon stripping a dead
  # slug out of a dependent's depends_on.
  def spec_write(specs_dir, ident, fields)
    spec = find_by_ident(specs_dir, ident)
    abort "ag-store: no such spec: #{ident}" unless spec

    stamp!(spec, fields)
    spec[:path]
  end

  # ---- release / ship / abandon ----

  def release(specs_dir, ident)
    spec = find_by_ident(specs_dir, ident)
    abort "ag-store: no such spec: #{ident}" unless spec

    stamp!(spec, { "status" => "ready", "claimed_by" => "", "label" => "", "claimed_at" => "" })
    true
  end

  def ship(specs_dir, ident, shipped_at: nil)
    spec = find_by_ident(specs_dir, ident)
    abort "ag-store: no such spec: #{ident}" unless spec

    stamp!(spec, { "status" => "shipped", "shipped_at" => (shipped_at || Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")) })
    dest_dir = File.join(specs_dir, "done")
    FileUtils.mkdir_p(dest_dir)
    move_to(spec, dest_dir)
  end

  def abandon(specs_dir, ident, reason:, abandoned_at: nil)
    spec = find_by_ident(specs_dir, ident)
    abort "ag-store: no such spec: #{ident}" unless spec

    stamp!(spec, {
      "status" => "abandoned",
      "abandoned_at" => (abandoned_at || Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")),
      "abandoned_reason" => reason,
      "claimed_by" => "",
      "label" => "",
      "claimed_at" => "",
    })
    dest_dir = File.join(specs_dir, "abandoned")
    FileUtils.mkdir_p(dest_dir)
    move_to(spec, dest_dir)
  end

  # Moves a spec (flat file or NNNN-slug/ directory) into dest_dir, preserving
  # its current basename as a record — collision-safe two-step via a temp name
  # in dest_dir, matching /ag-prioritise's and /ag-abandon's documented pattern.
  def move_to(spec, dest_dir)
    is_dir = File.basename(spec[:path]) == "SPEC.md"
    old = is_dir ? File.dirname(spec[:path]) : spec[:path]
    base = File.basename(old)
    tmp = File.join(dest_dir, "tmp-#{Process.pid}-#{base}")
    final = File.join(dest_dir, base)
    git_mv(old, tmp)
    git_mv(tmp, final)
    final
  end

  # ---- promote / attach ----

  # Promotes a flat spec to its directory form (<specs>/NNNN-slug/SPEC.md) so
  # plan.md and supporting material can live beside it. A no-op, returning
  # the existing directory, if it's already in directory form. Returns the
  # spec's directory (repo-relative to the caller's cwd, same as the path
  # style every other op already returns).
  def promote(specs_dir, ident)
    spec = find_by_ident(specs_dir, ident)
    abort "ag-store: no such spec: #{ident}" unless spec

    return File.dirname(spec[:path]) if File.basename(spec[:path]) == "SPEC.md"

    base = File.basename(spec[:path], ".md")
    dir = File.join(specs_dir, base)
    FileUtils.mkdir_p(dir)
    git_mv(spec[:path], File.join(dir, "SPEC.md"))
    dir
  end

  # No-op for local: plan.md's location is implied by the spec's own
  # directory form, <specs>/NNNN-slug/plan.md beside SPEC.md.
  def attach(_specs_dir, _ident, plan_path)
    plan_path
  end

  # ---- whoami / doctor ----

  def whoami
    email = `git config user.email 2>/dev/null`.strip
    name = `git config user.name 2>/dev/null`.strip
    return email unless email.empty?
    return name unless name.empty?

    "unknown"
  end

  def doctor(agentile_dir)
    specs_dir = File.join(agentile_dir, "specs")
    checks = {
      "inbox exists" => File.exist?(inbox_path(agentile_dir)),
      "specs/ exists" => File.directory?(specs_dir),
      "specs/done/ exists" => File.directory?(File.join(specs_dir, "done")),
      "specs/abandoned/ exists" => File.directory?(File.join(specs_dir, "abandoned")),
      "specs/ writable (claim lock)" => File.directory?(specs_dir) && File.writable?(specs_dir),
    }
    checks
  end
end
