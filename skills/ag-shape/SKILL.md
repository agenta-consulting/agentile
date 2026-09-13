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

## Step 1 — Load the project's definitions

- Read `.agentile/shape.md` — this is **this project's Definition of Ready**: the exact questions a stub must answer, plus any house additions. Drive the interview against *this* list, not a generic one.
- Read `.agentile/config.md` for the **Agentile directory** (default `docs/agentile/`) and the two-axis triage table. If the project still uses the old `Inbox:` / `Specs directory:` keys (or root-level `inbox.md` / `specs/`) with no `Agentile directory` key, honour those paths and note that `/ag-init` can migrate the layout.
- Resolve which store answers this project: read `store:` from `.agentile/store.md` if it exists, default `local`. Every inbox/spec operation below goes through `ag-store --dir "<Agentile directory>" --store "<store>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`) rather than touching files directly.
- Read `<dir>/brief.md` if present — the project's prioritised outcomes, users, and constraints. Score Business Value in the triage against the brief's outcomes, and let it inform the shaping questions.
- Read the project's `CLAUDE.md` (and `docs/adr/`) for standing context so your questions fit the architecture.

## Step 2 — Pick the stub

- Run `ag-store inbox_list ...` and parse the JSON array of `{id, text, captured_at, captured_by}`.
- The user may name the stub by id or text (`$ARGUMENTS`). If they did not, present the numbered list (by `id`) and ask which one to shape.

## Step 3 — Interview

- Ask **one or two questions at a time**, using `AskUserQuestion` where the choices are discrete. Let each answer shape the next question.
- Work through every required item in `.agentile/shape.md` — typically problem/who/why-now, acceptance criteria, the observable **outcome** (the one metric or check that will prove the change worked — written to the `outcome:` frontmatter field), edge cases and failure paths, scope boundary, affected areas, open questions, and dependencies — plus any house additions.
- Prefer concrete examples over abstractions. Push back gently on vague acceptance criteria.
- **Dependencies**: ask whether this item depends on any other specs being shipped first. Run `ag-store spec_list ...` and offer the existing slugs as candidates. Write the chosen slugs to `depends_on` in the spec's frontmatter; default is `[]`. Note that newly shaped specs are written **unprefixed** (they are Ready but not yet prioritised).

## Step 4 — Triage

- Estimate **Business Value** and **Technical Certainty** (guidance in `.agentile/config.md`).
- Recommend a **route** from the triage table: foreground pair, background agent, spike, or drop.
- A low-certainty item usually leaves shaping as a **spike**, not a build.

## Step 5 — Decide the outcome

Based on the conversation, do **one** of:

- **Graduate to a spec** — build the markdown from `.agentile/spec-template.md`, filling every field from the interview, and set `route`, `business_value`, `technical_certainty`. Keep every frontmatter value valid YAML: no unquoted colons in `title`, `outcome` or any other field (`title: Foo: bar` breaks the claim tooling); reword with a dash or comma, or quote the value. Write it with `ag-store spec_create <slug> --dir "<dir>" --store "<store>"`, piping the markdown on stdin. Newly shaped specs are always unprefixed; the plan stage promotes one to a directory (`NNNN-<slug>/SPEC.md`) when `plan.md` is written. If the shaping session itself produced supporting material (a sketch, a data sample), that still belongs on disk beside where the spec will live once planning promotes it — note it in the spec body for `/ag-plan` to pick up.
- **Spike** — same as above with `type: spike` and `status: ready`, framing the open questions as the timeboxed exploration goal. A spike's deliverable is a written answer, not code: its build is the timeboxed exploration, its verify is 'question answered within the timebox', and on ship its findings (`findings.md` in the spec's directory, or an ADR) move to `done/` — satisfying dependencies like any spec.
- **Split** — capture multiple new stubs (`ag-store inbox_add`) or write multiple specs.
- **Merge** — fold the stub into an existing stub or spec.
- **Drop** — just drop the stub, with a one-line note to the user on why.

Always **drop the original stub** (`ag-store inbox_drop <id> --dir "<dir>" --store "<store>"`) once its fate is decided — the inbox is the list of what still needs shaping.

## Step 6 — Report

Confirm what you wrote (path), the recommended route, and the next step (usually `/ag-plan <dir>/specs/<slug>.md`). Do not start building.
