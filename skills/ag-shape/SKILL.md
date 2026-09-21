---
name: ag-shape
description: Promote a stub from the Agentile inbox to a Ready spec through a conversation — interview the user against the project's Definition of Ready, run the Business Value × Technical Certainty triage, then write the spec and remove the stub. Non-coding. Trigger phrases include "/ag-shape", "shape this stub", "shape an inbox item", "turn this into a spec", "make this Ready".
allowed-tools: AskUserQuestion, Bash, Read
---

# ag-shape

Shaping is the bridge between a one-line stub and a buildable spec. It is **a conversation, not a form**: you interview the user until the idea is concrete enough to be Ready, then write it up. Shaping is the cheapest place to kill or reshape an idea — do it here, in words, before any code exists.

**You do not write any code in this skill.** You only produce a spec (or split/merge/drop the stub, or emit a spike).

## Apply this project's playbook

Before doing anything else, check for `.agentile/shape.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Refresh the brief

Before anything else, resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). It rewrites `<dir>/brief.md` from the store so this session reads the current brief, and prints the path. If it exits 2 because the project is not linked (no `.agentile/store.md`, or no token), tell the user to run `/ag-init` (or export `AGENTILE_PROJECTS_TOKEN`) and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.

## Step 1 — Load the project's definitions

- Read `.agentile/shape.md` — this is **this project's Definition of Ready**: the exact questions a stub must answer, plus any house additions. Drive the interview against *this* list, not a generic one.
- Read `.agentile/config.md` for the two-axis triage table.
- Read `<dir>/brief.md` (just refreshed) — the project's users, constraints and prioritised outcomes. Run `ag-store outcome_list --status open`; if any Outcomes exist, Business Value is scored as **contribution to the Outcome this spec serves** (Step 3); with none, score against the brief's prose outcomes. Let both inform the shaping questions.
- Read the project's `CLAUDE.md` (and `docs/adr/`) for standing context so your questions fit the architecture.

## Step 2 — Pick the stub

- Run `ag-store inbox_list` and parse the JSON array of `{id, title, type, text, captured_at, captured_by, serves, suggested_kind, duplicate_of}`. Attribution is carried by the store when the stub is shaped — nothing to copy by hand.
- The stub's `type` selects which interview runs below. Treat it as a starting
  point, not a verdict: if the conversation shows the stub was mistyped at
  capture (a "bug" that is really a missing feature), say so in one line and
  switch interviews. A null `type` (a stub captured before the field existed) means re-derive it from the text.
- The user may name the stub by id or text (`$ARGUMENTS`). If they did not, present the numbered list (by `id`) and ask which one to shape.

## Step 3 — Interview

### Bugs take the short interview

A `bug` is a defect in shipped behaviour, so most of the Definition of Ready is
already settled — the outcome is "it stops doing the wrong thing". Asking a
feature's questions about it wastes the user's time and produces a padded spec.
Ask only:

1. **Repro** — the exact steps, on which screen/route, with what data.
2. **Expected vs actual** — what should happen, what happens instead.
3. **The failing check** — which test (and at which layer) will reproduce this
   and go green when it is fixed. If the project's `CLAUDE.md` mandates
   test-first bug fixes, this is the acceptance criterion; write it as one.
4. **Blast radius** — the affected area, and whether anything else shares that
   code path.

Skip the outcome metric, the scope boundary, and the edge-case sweep unless an
answer above opens a real question. Then go straight to Step 5 — **bugs are not
scored** (see Step 4). Everything else — `feature`, `chore`, `spike` — takes the
full interview below.

### Everything else

- Ask **one or two questions at a time**, using `AskUserQuestion` where the choices are discrete. Let each answer shape the next question.
- Work through every required item in `.agentile/shape.md` — typically problem/who/why-now, acceptance criteria, the observable **outcome** (the one metric or check that will prove the change worked — written to the `outcome:` frontmatter field), edge cases and failure paths, scope boundary, affected areas, open questions, and dependencies — plus any house additions.
- Prefer concrete examples over abstractions. Push back gently on vague acceptance criteria.
- **Dependencies**: ask whether this item depends on any other specs being shipped first. Run `ag-store spec_list` and offer the existing slugs as candidates. Write the chosen slugs to `depends_on` in the spec's frontmatter; default is `[]`. Newly shaped specs are Ready but **unranked** until `/ag-prioritise` places them.
- **Serves**: ask which Outcome this spec serves, offering the open slugs from `outcome_list` plus "none — free-standing". A stub that arrived from `/ag-decompose` already carries `serves` (shown by `inbox_list`); offer it as the default. Write the slug to `serves:`; blank means free-standing and is always allowed — a parent never gates a spec. If the conversation surfaced natural themes (an area, a layer), write two or three as `tags: [...]`; never invent tags to fill the field.

## Step 4 — Triage

- **Bugs skip this step.** Scoring a defect's business value against the brief's
  outcomes is theatre — it is broken, and the only real question is whether it
  is worth fixing now, which is a ranking decision the human makes in
  `/ag-prioritise`. Leave `business_value` and `technical_certainty` unset,
  set `route: background` (a bug with a failing test is the most delegable work
  there is), and go to Step 5. A bug still gets ranked like everything else —
  unranked means unclaimable — it just arrives at ranking unscored.
- Estimate **Business Value** and **Technical Certainty** (guidance in `.agentile/config.md`).
- Recommend a **route** from the triage table: foreground pair, background agent, spike, or drop.
- A low-certainty item usually leaves shaping as a **spike**, not a build.

## Step 5 — Decide the outcome

Based on the conversation, do **one** of:

- **Graduate to a spec** — build the markdown from `.agentile/spec-template.md`, filling every field from the interview, and set `type` (carried from the stub), `route`, `business_value`, `technical_certainty` (the last two left unset for a bug), `serves`, and `tags` (both blank when the interview gave none). Keep every frontmatter value valid YAML: no unquoted colons in `title`, `outcome` or any other field (quote `created_at`, which contains them) (`title: Foo: bar` breaks the claim tooling); reword with a dash or comma, or quote the value. Write it in one call that also retires the stub and records provenance and attribution:

  ```
  ag-store inbox_shape <stub-id>
  ```

  piping the markdown on stdin. The store creates the spec (`slug` from the frontmatter), links it to the stub, marks the stub `shaped`, copies `captured_by` from the stub and records you as `shaped_by` from the token. Newly shaped specs are unranked; the plan stage creates the spec's directory (`<dir>/specs/<slug>/`) when `plan.md` is written. If the shaping session itself produced supporting material (a sketch, a data sample), it belongs on disk in that directory — note it in the spec body for `/ag-plan` to pick up.

  If the call fails with a 422 (a validation error — e.g. a `depends_on` slug that doesn't exist), show the response's `detail` to the user and fix the markdown accordingly before calling `inbox_shape` again; don't retry blindly.
- **Spike** — same as above with `type: spike` and `status: ready`, framing the open questions as the timeboxed exploration goal. A spike's deliverable is a written answer, not code: its build is the timeboxed exploration, its verify is 'question answered within the timebox', and on ship its findings (`findings.md` in the spec's directory, or an ADR) stay in the repo and the spec is `shipped` in the store — satisfying dependencies like any spec.
- **Split** — capture the extra stubs with `ag-store inbox_add "<text>" --title "<title>" --type "<kind>"`, or shape several specs from one stub: use `inbox_shape <stub-id>` for the first and `ag-store spec_create <slug>` (markdown on stdin, with `source_inbox: <stub-id>` in the frontmatter) for the rest — one stub may link to several specs by design.
- **Merge** — fold the stub into an existing stub or spec.
- **Drop** — just drop the stub, with a one-line note to the user on why.

`inbox_shape` retires the stub itself. For **Merge** and **Drop**, retire it with `ag-store inbox_drop <id>` — the inbox is the list of what still needs shaping.

## Step 6 — Report

Confirm what you wrote (slug) — the spec now lives in the store, viewable at `<url>/p/<project>/specs` (`url:`/`project:` from `.agentile/store.md`) — the recommended route, and the next step (usually `/ag-plan <slug>`). Do not start building.
