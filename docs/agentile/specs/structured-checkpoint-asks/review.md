# Review: structured-checkpoint-asks (head f32c03d)

VERDICT: pass

## Checks run (in the worktree)

- `ruby -c bin/ag-store`: Syntax OK
- `ruby dev/test-ag-store-http.rb`: OFFLINE PASS (online section skipped, no live env)
- `ruby dev/test-ag-run.rb`: ALL PASS
- Optional Factory parser run (plan step 4): all 7 fixtures parse with the intended headline as `problem` and 2 to 3 options. None returned nil.
- `.agentile/gates.json`: every gate is blank, so there is nothing more to run.

## Acceptance criteria

- Format section in SKILL.md with template, rules and per-reason table: met.
- Each of Steps 2 to 5 and "Questions instead of guesses" names its sections, covering all 7 reasons: met.
- plan_review `printf` rewritten as one pipe (safe for the headless allowlist); ship_approval "three lines" replaced: met.
- ag-builder `blocked` report gives headline + `Options:`; ag-builder and ag-reviewer `## Question` blocks use `Options:` + `(recommended)`, and legacy `Recommendation:` is still accepted: met.
- ag-reviewer `fail` report gives headline + `Options:`, noted as the gate_failure ask: met.
- factory-worker points at the section and does not restate it: met.
- `checkpoint_open` warning goes to stderr only. The ask is posted unchanged with exit 0, the exemptions work, and `rescue` means the check never raises: met. The reason is still validated before stdin is read, so behaviour there is unchanged.
- The test covers both warnings, the two together, the exempt reasons, a clean short ask and the posted body: met.
- `templates/checkpoint-asks/<reason>.md`: exactly one per reason, each with no warning, and the test enforces both: met.
- Prose fallback stated in the format section: met.
- CHANGELOG plus plugin.json and marketplace.json bumped together to 0.21.0: met.

Scope: stays inside this plugin repo. No client or server-side changes.

## Findings

- nice-to-have: `bin/ag-store:136-141`. `ask_warnings` sits between the "Percent-encode one path segment" comment and `def self.enc`, so that comment now sits above the wrong method. Move `ask_warnings` above the comment or below `enc`.
- nice-to-have (ship-time): main has moved since branching (77c251b). `git merge-tree` shows a conflict in `CHANGELOG.md` only, because main added a `## Unreleased` section. When resolving, keep `## Unreleased` above `## 0.21.0`. `templates/factory-worker.md` merges cleanly.
- note: Routing of the new standard replies was checked against Step 0: `approved`, `release`, `retry — …` and `resume — …` all route as before, so no Step 0 change is needed.

## Security skim

The change adds stderr-only advisory output. The reason is validated against the allowlist before it is interpolated into a message. There is no new input path, no secrets and no shell construction. No `/security-review` needed.
