<!-- SNAPSHOT — not the source of truth.
     Spec structured-checkpoint-asks read from Agentile Projects at 2026-10-03T05:16:46Z.
     Rank, claim and status live in the store; re-run /ag-plan to refresh.
     Never edit this file: edits are lost, and the store will not see them. -->

---
title: /ag-build writes every checkpoint ask in one structured format
slug: structured-checkpoint-asks
status: in_progress
type: feature
route: background
business_value: high
technical_certainty: high
rank: 1
created_at: 2026-10-02T21:04:52Z
tags: [checkpoints, ag-build, asks]
outcome: Every example ask in templates/checkpoint-asks/ passes the checkpoint_open format check with no warning, and the next ship_approval ask /ag-build writes opens with a one-line headline, then a Before approving checklist, an Options list and a --- line before the details
claimed_by: factory-next/agentile/structured-checkpoint-asks
label: factory-next
claimed_at: 2026-10-03T05:14:07Z
claimed_by_member: keith@keithrowell.com
captured_by: keith@keithrowell.com
shaped_by: [keith@keithrowell.com]
source_inbox: /ag-build writes every checkpoint ask in one structured format
---

# /ag-build writes every checkpoint ask in one structured format

## Problem / why now

Checkpoint asks reach Keith in several clients: the Factory overlay and Asks view, the Agentile Projects dashboard, the Hooman Input page and bell, the iOS app and the Shaper. He wants to answer them the same way in every one. At the moment `/ag-build` writes most asks as free prose, so each client has to guess at the layout:

- `skills/ag-build/SKILL.md` writes plan_review as `<summary>. Review or amend plan.md...`.
- build_blocked uses "the builder's reason as the ask", and `agents/ag-builder.md:45` only says "say why".
- build_checkpoint and verify_checkpoint use the builder's or reviewer's summary, and gate_failure uses "the findings".
- ship_approval is "three lines" plus visual evidence.

Only the `## Question` block (`ag-builder.md:45`, `ag-reviewer.md:46`) has any structure, and the Factory parser misses even that. On 2026-10-03 the ship approval for frontdesk/portal-live-updates (Factory ask 203) still showed as a monospace wall of text, with its "Before approving, please: 1-4" checklist buried and scrolling under the buttons.

`readable-checkpoint-asks` (agentile-factory, shipped 2026-10-01) set the target layout but only for build_blocked. It explicitly left plan review and ship approval out, and its follow-ups were never captured. This spec is the root fix: the Factory, Agentile Projects, Shaper and iOS stubs captured alongside it render the format defined here.

## Acceptance criteria

- [ ] `skills/ag-build/SKILL.md` has a **Checkpoint ask format** section with the format above.
- [ ] Every Step that writes a checkpoint names the sections that apply to its reason. This covers plan_review, build_blocked, question, build_checkpoint, gate_failure, verify_checkpoint and ship_approval.
- [ ] The plan_review `printf` example and the ship_approval "three lines" wording are rewritten to the format.
- [ ] `agents/ag-builder.md`: a `blocked` report starts with the headline and gives `Options:`.
- [ ] `agents/ag-builder.md` and `agents/ag-reviewer.md`: the `## Question` block becomes `Options:`, with `(recommended)` on one option. `Recommendation: <n>` is still accepted as a legacy form.
- [ ] `agents/ag-reviewer.md`: a `fail` findings report starts with the headline and gives `Options:`. That report is what ends up in a gate_failure ask.
- [ ] `templates/factory-worker.md` points at the format section rather than restating it.
- [ ] `ag-store checkpoint_open` prints a warning on stderr, and never fails, in two cases. The first is an ask over 200 chars with no blank line. The second is an ask with no `Options:` line whose reason is anything other than plan_review or ship_approval. The ask is posted unchanged either way and the exit code stays 0.
- [ ] `dev/test-ag-store-http.rb` covers each warning case, the exempt reasons, a short ask (no warning), and that the ask is still posted.
- [ ] `templates/checkpoint-asks/` holds one example ask per reason (`<reason>.md`), each passing the warning check with nothing printed. These are the shared fixtures client repos test their parsers against.
- [ ] Old prose asks still go through `checkpoint_open` (they only warn). The README or format section says clients keep their heuristics as the fallback.
- [ ] CHANGELOG entry and version bump in `.claude-plugin/plugin.json`, plus the matching marketplace entry.

## Scope boundary

**In scope:** this plugin repo only. That means the format's definition, the skill and agent wording, the factory-worker template, the warning in `checkpoint_open`, the fixtures, and the CHANGELOG and version.

**Out of scope:** - The `factory_ask` MCP tool description ("first line is the headline") lives in the agentile-factory repo, so that change belongs in the agentile-factory stub.
- Rendering the format in any client (Factory, Agentile Projects, Hooman Input, iOS, Shaper). Those are their own stubs.
- Permission request layout, which is already structured.
- Validating or rejecting asks on the server side.

## Edge cases and failure paths

- The warning must never block a checkpoint. If a warning stops a checkpoint opening, the human is stranded, so it goes to stderr only and the exit code is unchanged.
- An ask with no `Options:` is normal for plan_review and ship_approval, because their replies are fixed (approve, or send back with a note). Don't warn for those reasons.
- Asks over 200 chars are the only ones checked for a blank line. A short one-line ask is valid as it stands.
- The worker matches the answer text against the option wording, so options must be written exactly as the reply they send. Act-elsewhere options get no button in clients, and their wording has to make that obvious.
- Visual evidence in ship_approval (a path or link to a screenshot) goes in the context or Details, not in the headline.
- Answers in the legacy `Recommendation: <n>` form keep working.

## Affected areas

- `skills/ag-build/SKILL.md` (new format section; Steps 2–5)
- `agents/ag-builder.md`, `agents/ag-reviewer.md`
- `templates/factory-worker.md`
- `bin/ag-store` (`checkpoint_open`), `dev/test-ag-store-http.rb`
- `templates/checkpoint-asks/*.md` (new)
- `CHANGELOG.md`, `.claude-plugin/plugin.json`, marketplace entry

## Open questions

None blocking.

## Verification

- `dev/test-ag-store-http.rb` passes with the new warning cases.
- A script or test runs every file in `templates/checkpoint-asks/` through the same check and gets no warnings.
- Read the next real ship_approval ask from `/ag-build`: it follows the format.
