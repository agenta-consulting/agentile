# Agentile — Backlog Layout, Abandonment & Migration

Design note. Status: implemented. Date: 2026-06-11. Historical snapshot; the README and `methodology.md` are normative.

## Why

The backlog used to live in two disjointed places — `inbox.md` at the repo root and
`specs/` (with `specs/archive/` for shipped work) also at the root — with no home for work
that was **abandoned**, and no way to walk the dependency chain when dropping a spec. This
change unifies the layout under one configurable directory, renames `archive/` → `done/`,
adds `abandoned/`, and introduces `/ag-abandon`.

## Layout

One configurable base directory; everything under it is fixed.

```
.agentile/                      # config layer (stays at repo root)
docs/agentile/                  # <Agentile directory> — configurable, default docs/agentile/
  inbox.md                      # captured stubs awaiting shaping
  specs/                        # active specs (status: ready | in_progress)
    0001-<slug>.md
    done/                       # status: shipped
    abandoned/                  # status: abandoned
```

- `.agentile/config.md` carries a single **Agentile directory** key (default
  `docs/agentile/`) under "## Paths", replacing the old `Inbox:` and `Specs directory:`
  keys. `ADR directory:` is unchanged.
- Skills derive every path from it: inbox = `<dir>/inbox.md`, specs = `<dir>/specs/`,
  done = `<dir>/specs/done/`, abandoned = `<dir>/specs/abandoned/`.
- Spec `status` is `ready | in_progress | shipped | abandoned`.

## `ag-claim` is top-level only

`bin/ag-claim` builds its shipped-status map by globbing `specs/**/*.md` recursively (so
shipped specs in `done/` still resolve `depends_on`), but its **claim pool** is now
specs at the *top level* of the specs dir only:

```ruby
specs_root = File.expand_path(specs_dir)
pool = all.select { |s| File.dirname(File.expand_path(s[:path])) == specs_root }
```

This excludes both `done/` and `abandoned/` by position rather than by name, so the rule
holds for any future subdirectory. Because abandoned specs keep `status: abandoned` (never
`shipped`), a spec that depends on an abandoned one stays `BLOCKED` until the dependency is
removed — which is exactly what `/ag-abandon` helps with.

## `/ag-abandon` — dropping a spec, cascade-aware

`bin/ag-dependents <specs-dir> <slug>` prints the transitive set of **active** specs
(top-level, `ready`/`in_progress`) whose `depends_on` reaches `<slug>`, nearest first.
Reverse dependencies are not stored anywhere; this helper computes them on demand. It is
cycle-safe and ignores `done/` and `abandoned/` specs (a shipped or already-dropped spec is
not a cascade candidate).

The `/ag-abandon` skill:

1. Resolves the target (from `$ARGUMENTS` or interactively).
2. Runs `ag-dependents` to find what depends on it.
3. Asks the user for the **reason** (top level only).
4. Offers, per dependent, to **cascade-abandon** it — down-the-chain abandonments get an
   automatic reason: `Abandoned as a consequence of abandoning <target-slug>: <reason>`.
5. For each dependent the user keeps active: warns it will be `BLOCKED`, and offers to
   **strip** the dead slug from its `depends_on`.
6. For each abandoned spec: sets `status: abandoned`, adds `abandoned_reason` +
   `abandoned_at`, clears the claim fields, and `git mv`s it into `specs/abandoned/`
   (collision-safe two-step rename, as in `/ag-prioritise`).

## Migration (folded into `/ag-init`)

`/ag-init` detects a legacy layout — root-level `inbox.md`, root-level `specs/`,
`specs/archive/`, or old `Inbox:` / `Specs directory:` config keys — and, on the user's
confirmation, `git mv`s everything into `docs/agentile/` (`specs/archive/*` →
`specs/done/`), rewrites the config Paths section to the single `Agentile directory:` key,
and creates the `done/` + `abandoned/` directories. It is idempotent: a project already on
the new layout is a no-op. Other path-reading skills honour the old keys for the current
run and point the user at `/ag-init` to migrate.

## Tests

- `bin/test-ag-claim.rb` — adds: shipped dep in `done/` resolves; abandoned dep in
  `abandoned/` leaves the dependent `BLOCKED`; subdirectory specs are never in the pool.
- `bin/test-ag-dependents.rb` — direct dependent, transitive chain, none, cycle terminates,
  and shipped/abandoned specs excluded as candidates.
