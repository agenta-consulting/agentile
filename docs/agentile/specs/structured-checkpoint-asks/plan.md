# Plan — /ag-build writes every checkpoint ask in one structured format

Spec: `structured-checkpoint-asks` (snapshot in `SPEC.md` beside this file).
Route: background, so no plan-review pause. One PR; it is wording plus one
small, non-blocking CLI check, and the pieces only make sense together.

## The format (the contract this spec defines)

The spec's AC says "the format above", but the store copy of the spec does not
include the format block. **Assumption (low stakes, recorded instead of asked):**
the format is the one in the spec's `outcome:` field and the sibling spec
`agentile_projects/checkpoint-ask-layout`, shaped so that the Factory's existing
parser (`lib/factory/ask_layout.rb`, deployed copy at
`~/.local/share/agentile-factory/current/lib/factory/ask_layout.rb`) already
produces a layout from it with no parser change. Write this into the new
section of `skills/ag-build/SKILL.md`:

```
<Headline: one sentence on one line. What the human must decide or know.>

<Context: optional, one to three short lines. Why now, what was tried.>

Before approving:                       (ship_approval; optional elsewhere)
- <thing to check, e.g. open http://localhost:3000/x and confirm Y>
- <...>

Options:
1. <the exact reply this option sends> (recommended)
2. <the exact reply this option sends>
3. Fix it yourself with: <command>, then answer 'done'

---

<Details: findings, gate output, file:line bullets, evidence paths or links.>
```

Rules to state in the section (each one is something a parser relies on):

- Line 1 is the headline: a single sentence, no markdown heading, no list
  marker, no visual-evidence link. The Factory parser takes the first sentence
  of the text before `Options:` as `problem`.
- Blank lines separate the blocks. An ask of 200 characters or fewer may be the
  headline alone.
- `Options:` sits alone on its line, followed directly by a numbered list
  (`1.`, `2.` ...), two to four items, one item per line, no blank lines inside
  the list. This is the `list_options` path in the parser.
- Each option is written **exactly as the reply it sends** (the worker matches
  the answer text against it). A one-line consequence may follow after ` — `.
  At most one option carries `(recommended)`.
- An option that needs the human to act elsewhere says so in words the parser
  and a reader both recognise (`yourself`, `with: <command>`, `answer with a
  different instruction`); clients give it no button. An option that sends a
  fixed reply after acting elsewhere uses `then answer '<reply>'`.
- `Options:` (or `Option:`) appears once only. The parser uses the last match,
  so Details must not contain that word followed by a colon.
- `---` on its own line separates the decision from the Details. Everything
  after it is reference material, folded by clients.
- `Recommendation: <n>` on its own line after the list is still accepted (legacy).
- plan_review and ship_approval replies are fixed (approve, or send back with a
  note), so their Options are written but `checkpoint_open` does not warn when
  they are missing. Standard wording for both:
  `1. approved` / `2. Send it back: answer with a different instruction saying what to change`.
- Clients keep their existing prose heuristics as the fallback: old asks are
  still accepted (`checkpoint_open` only warns), and a client must render an
  ask that does not follow this format.
- `templates/checkpoint-asks/<reason>.md` holds one worked example per reason;
  they are the shared fixtures client repos test their parsers against.

Per reason, the sections that apply (put this as a short table in the section,
then reference it from each Step):

| reason | headline | context | Before approving | Options | `---` Details |
|---|---|---|---|---|---|
| plan_review | "Plan ready for `<slug>`: <one-line summary>." | optional | optional | approved / send back (exempt from the warning) | plan summary; path to plan.md |
| build_blocked | why the builder stopped | what it tried | no | required | builder's report bullets |
| question | the question | optional | no | required, one `(recommended)` | consequences, background |
| build_checkpoint | what was built | optional | optional | required (approved / send back) | builder's summary |
| gate_failure | what still fails after retries | retry count | no | required (retry with fixes / `release` / abandon yourself with: `/ag-abandon <slug>`) | reviewer's must-fix findings |
| verify_checkpoint | the verify outcome | optional | optional | required (approved / send back) | reviewer's findings |
| ship_approval | "Ship `<slug>` — <title>?" | what was built (one sentence), verify outcome (one sentence) | yes | approved / send back (exempt) | evidence links/paths, report extracts |

## Files to touch

- `skills/ag-build/SKILL.md`
  - New `## Checkpoint ask format` section, placed in the Tools area right after
    the `--by <who>` paragraph (line 63) and before "Record an answer that
    arrives in chat", containing the template, rules and table above.
  - Step 2 (line 115-119): the ask is built to the format; rewrite the `printf`
    example as a single multi-line `printf` still piped straight into
    `ag-store checkpoint_open` (the headless allowlist only permits that pipe
    shape, line 59), e.g.
    `printf '%s\n\n%s\n\nOptions:\n1. approved\n2. Send it back: answer with a different instruction saying what to change\n\n---\n\n%s' "Plan ready for <slug>: <one-line summary>." "Review or amend plan.md in place, then answer." "<summary from /ag-plan>" | ag-store checkpoint_open "<slug>" plan_review --session "${CLAUDE_SESSION_ID}" --by plan`.
  - Step 3 (lines 128-131): build_blocked ask = the builder's `blocked` report
    after its first line (it now starts with the headline and has `Options:`);
    question ask = the `## Question` block's content without the heading line;
    build_checkpoint ask = headline + approved/send-back Options + `---` +
    builder's summary. Each bullet names its sections ("headline, context,
    Options, Details").
  - Step 4 (lines 140-143): gate_failure ask = the reviewer's final `fail`
    report after its first line, plus the gate_failure Options if the reviewer
    omitted them; verify_checkpoint likewise named.
  - Step 5 (line 151): replace "three lines" with the ship_approval layout:
    headline, the two context sentences, `Before approving:` checklist (what to
    open/look at, including the visual evidence path or link from line 149 —
    never in the headline), Options, `---`, Details. The end-of-turn text keeps
    "Approve to ship `<slug>`?" and the status line.
  - "Questions instead of guesses" (line 196): "with options and a
    recommendation" → "in the Checkpoint ask format, with `(recommended)` on
    one option".
- `agents/ag-builder.md` line 45: `blocked` report — the line after
  `BUILD: blocked` is the headline (why you stopped, one sentence), then a
  blank line, `Options:` with what the human could do (e.g. amend the spec, then
  answer 'resume'), `---`, then the terse report bullets. `question` — the
  `## Question` block holds the question as its first line, a blank line, then
  `Options:` with two to four numbered options written as the reply each sends,
  a one-line consequence after ` — `, `(recommended)` on one. Say
  `Recommendation: <n>` is still accepted but no longer the form to write.
  Point at the format section in `skills/ag-build/SKILL.md` rather than
  restating every rule.
- `agents/ag-reviewer.md` line 46 (question block, same change as the builder)
  and line 48: a `fail` report's line after `VERDICT: fail` is a headline
  (what must be fixed, one sentence), then `Options:` (retry with the fixes /
  `release` / abandon yourself with: `/ag-abandon <slug>`), `---`, then the
  prioritised findings list. Note that this report is what ends up in a
  gate_failure ask.
- `templates/factory-worker.md` line 7: append "Write every ask in the
  Checkpoint ask format defined in the `/ag-build` skill." One sentence, no
  restated rules.
- `bin/ag-store`
  - Add `AgStore.ask_warnings(reason, ask)` next to `coerce_list`/`enc` (module
    functions near the top): returns an array of messages, empty when fine.
    `ask.length > 200 && !ask.match?(/\n[ \t]*\n/)` → over-length message;
    `!%w[plan_review ship_approval].include?(reason) && !ask.match?(/^[ \t]*Options:/)`
    → missing-Options message. Body wrapped in `rescue StandardError` → `[]` so
    the check can never raise. Add a constant `OPTIONS_EXEMPT_REASONS`.
  - `checkpoint_open` (line 356-363): read stdin once into `ask =
    $stdin.read.to_s.strip`, validate the reason first (unchanged), then
    `AgStore.ask_warnings(reason, ask).each { |m| warn "ag-store: warning: #{m}" }`,
    then post `ask` unchanged. Messages name the fix: "checkpoint ask is N
    characters with no blank line — split headline from details (see Checkpoint
    ask format in /ag-build)" and "<reason> ask has no Options: line — list the
    replies (see Checkpoint ask format in /ag-build)".
  - Header usage comment (line 52): note that checkpoint_open warns on stderr
    for unformatted asks and still posts them.
- `templates/checkpoint-asks/` (new): `plan_review.md`, `build_blocked.md`,
  `question.md`, `build_checkpoint.md`, `gate_failure.md`,
  `verify_checkpoint.md`, `ship_approval.md`. Raw ask text only (no
  frontmatter, no commentary: the file contents are the ask). Realistic, each
  over 200 chars with blank lines, each with `Options:` and two or more items,
  exactly one `Options:`, a `---` line. ship_approval models the 2026-10-03
  frontdesk/portal-live-updates case: headline, two context sentences,
  `Before approving:` with four checks, Options, `---`, Details with a
  screenshot path. question and gate_failure include a `(recommended)` option,
  and build_blocked includes one act-elsewhere option.
- `dev/test-ag-store-http.rb`: new offline section `# 24.` before `api.close`
  (line 434), reusing section 16's routes (`POST #{P}/runs/1/checkpoints`
  echoes the body; run 1 for spec `a`/`runner-1` stays active in `runs`):
  1. 201+ char single-paragraph ask, reason `build_blocked`, with an
     `Options:` line inline → stderr includes the over-length warning, exit 0,
     echoed `ask` equals the input stripped.
  2. short ask, reason `build_blocked`, no Options → missing-Options warning,
     exit 0, posted unchanged.
  3. long ask with no blank line and no Options, reason `gate_failure` → both
     warnings.
  4. reasons `plan_review` and `ship_approval`, short, no Options → stderr empty.
  5. a short ask with `Options:` (e.g. `question`) → stderr empty.
  6. fixtures: `Dir[templates/checkpoint-asks/*.md]` basenames equal
     `CHECKPOINT_REASONS` as a set (hard-code the seven names in the test, as
     section 16 hard-codes `ship_approval`); each file goes through
     `checkpoint_open a <basename>` with stderr empty, exit 0, and echoed `ask`
     equal to the file contents stripped; each has exactly one
     `/\bOptions?\s*:/i` match and a `^---$` line.
  Use `run_store` (not `store!`) for these, since it returns stderr.
- `CHANGELOG.md`: a new `## 0.21.0 — <ship date>` section directly below
  `## Unreleased` (leave the existing Unreleased docs entry where it is),
  describing the format section, agent wording, fixtures and the warning.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
  (`plugins[0].version`): `0.20.1` → `0.21.0`, same commit (README
  "Versioning" convention). Minor bump: new contract plus new CLI behaviour,
  nothing removed.

## Approach

1. Write the fixtures first. They are the concrete form of the format and make
   the SKILL.md wording easy to check against.
2. Add `ask_warnings` and wire it into `checkpoint_open`; add test section 24.
   Run the test file until it prints `OFFLINE PASS`.
3. Write the SKILL.md format section and the Step edits, then the two agent
   files and the worker template. Keep each Step edit to the sentence that
   names the ask; the table carries the detail.
4. Optional, not a gate: run each fixture through the Factory parser to confirm
   it yields a layout with 2+ options and the intended `problem`, e.g.
   `ruby -e 'load "/home/keith/.local/share/agentile-factory/current/lib/factory/ask_layout.rb"; require "json"; Dir["templates/checkpoint-asks/*.md"].each { |f| l = Factory::AskLayout.parse(File.read(f)); puts f, (l ? [l["problem"], l["options"].map { _1["label"] }].inspect : "NIL") }'`.
   If a fixture comes back nil, fix the fixture (not the Factory, which is out
   of scope).
5. CHANGELOG and version bump last, in the same commit as the rest.

No speculative generality: no new `ag-store` op for the check (the test drives
the real `checkpoint_open` path, which is "the same check"), no server-side
validation, no parser in this repo.

## Test strategy

`.agentile/gates.json` has every gate (`format`, `lint`, `test`, `build`)
blank, so no configured gate proves this work. The proof is the repo's existing
test script and a syntax check, run by the builder and the reviewer:

- `ruby dev/test-ag-store-http.rb` — must print `OFFLINE PASS` (the online
  section is skipped unless `AGENTILE_PROJECTS_URL`/`AGENTILE_PROJECTS_TOKEN`
  are set). Section 24 proves the warning AC (both cases, exempt reasons, short
  ask, still posted, exit 0) and the fixtures AC (one per reason, no warnings).
- `ruby -c bin/ag-store` — syntax.
- `ruby dev/test-ag-run.rb` — unchanged, run it to show nothing regressed.
- The optional Factory parser run in Approach step 4.
- Reviewer reads the SKILL.md and agent diffs against the AC checklist (every
  Step names its sections; the plan_review printf and ship_approval wording
  are rewritten; `(recommended)` and legacy `Recommendation:` are both covered).
- Post-ship (spec Verification, not checkable in this PR): the next real
  ship_approval ask from `/ag-build` follows the format.

## Risks and unknowns

- **The format block is missing from the store copy of the spec.** The plan
  reconstructs it from the outcome line, the sibling spec and the Factory
  parser. If Keith had a different layout in mind (e.g. a numbered
  "Before approving" list, or Options on ship_approval omitted), the fixtures
  and SKILL.md section are where to change it; nothing downstream has shipped
  against it yet.
- **Parser compatibility.** The Factory and the store's planned port take the
  last `Options:` match and the first sentence of the head. A Details section
  that says "Options:" or a headline with two sentences would mis-parse. The
  rules and the fixture assertion (exactly one `Options?:`) cover the fixtures;
  real asks rely on the wording.
- **Headless printf.** The plan_review example must stay one `printf … |
  ag-store checkpoint_open …` pipe with no `;`/`&&`, or headless runs are
  denied. Escaped `\n` inside the format string keeps it one command.
- **The 200-character threshold counts characters after `strip`.** A long
  headline-only ask warns; that is intended.
- **Answer matching.** Standard replies (`approved`, `release`, `resume`) must
  still route through Step 0 as today. `approved` already does; a gate_failure
  answer of `release` already matches "says to release". No routing change.
- **Agent report shape change.** The builder's `blocked` report and the
  reviewer's `fail` report now begin with a headline instead of bullets.
  `/ag-build` and the factory only read the first line (`BUILD:`/`VERDICT:`),
  so nothing parses the second line; the retry loop passes the reviewer's
  findings to the builder, and the extra headline and Options do no harm there.
- **Concurrent edits.** Other builds may touch `CHANGELOG.md`/version; rebase
  and re-bump if trunk moved.

## ADR

None drafted. The format is a cross-client convention, but it is advisory
(warnings only), stated in one section of `skills/ag-build/SKILL.md` and pinned
by the fixtures, and old asks keep working, so it is cheap to revise. If a
later spec makes the store reject unformatted asks, that is the point to record
an ADR.
