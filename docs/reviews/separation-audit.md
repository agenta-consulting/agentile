# Methodology / Plugin Separation Audit

Read-only audit of the **Agentile methodology** vs its **"Agentile for Claude"** implementation. The decided model:

- **Agentile** = the tool-agnostic methodology (the loop, the eight stages, principles, values, shaping/DoR, two-axis triage, prioritise-vs-pull, drain/watch, brief, outcome metric, flow metrics, spikes, abandon/release). Tagline "Agile, with agency." Must be applicable with ANY tool, so methodology text must contain NO implementation mechanics.
- **"Agentile for Claude" / the Agentile plugin** = the Claude Code implementation. Owns ALL mechanics: `/ag-*` commands, `.agentile/` config, per-stage playbooks, `gates.json`, `ag-claim`/`ag-dependents` + file lock, hooks, session-id worker handle, the three named agents, `SPEC.md`/`plan.md` layout, frontmatter, marketplace install.
- **"Lean Agentic Loop"** = the original synthesis Agentile was distilled from — provenance only.

The litmus test: a methodology surface may say "implementations provide a way to tailor each stage" but must NOT name the mechanism (no "playbook", no `.agentile/<stage>.md`, no "ships defaults"). The conceptual version of the canonical violation is: "Agentile defines the loop and what the stages are; what each stage contains is yours to define."

## Executive summary

Two classes of finding:

- **LEAK** = plugin mechanics appearing in a methodology surface (must be tool-agnostic).
- **NAMING** = wrong name or wrong framing (plugin called bare "Agentile" where it should be disambiguated; or text asserting the plugin IS the methodology rather than an implementation of it).

Totals: **23 findings** — **15 LEAK**, **8 NAMING**.

By file:

- `methodology.md` (methodology surfaces only) — 8 LEAK, 1 NAMING (the title/subtitle reframe).
- `agentile_site/.../home.html.erb` (methodology surfaces: hero, manifesto, the loop) — 6 LEAK.
- `agentile_site/.../LoopDiagram.vue` — 1 LEAK.
- `README.md` (plugin surface) — 2 NAMING.
- `.claude-plugin/plugin.json` (plugin surface) — 1 NAMING.
- `methodology.md` "## Binding…" (plugin surface) — 1 NAMING.
- `home.html.erb` "## Install" + `application.html.erb` (plugin/chrome surfaces) — 1 NAMING (shared) + 0.
- Spot-check (`skills/ag-init`, `skills/ag-customise`, `templates/CLAUDE.agentile-section.md`) — 1 LEAK-class framing + 1 NAMING + 1 grammar/naming.

Highest-impact: (1) the `methodology.md` **spec-artefact** subsection is wholesale plugin leakage (`SPEC.md`/`plan.md`/`frontmatter`/`done/`); (2) the **title/subtitle** mis-frame Agentile as the plugin and LAL as the methodology — they are now reversed; (3) the website **"Stages are yours to define" principle** and the **"Light by design" card** both leak the "playbook" mechanism and "ships sensible defaults", the owner's canonical violation.

## `methodology.md` — methodology surfaces

This entire file except "## Binding: Claude Code and the Agentile plugin" is a methodology surface and must be tool-agnostic.

### Finding M1 — title + subtitle (lines 1–3) — NAMING (reframe)

Current:

> `# The Lean Agentic Loop`
> *A methodology for small teams who direct AI agents as their primary way of building software. Synthesised from ten sources (see docs/sources.md); shipped as the Agentile Claude Code plugin.*

Why it violates: under the decided model **Agentile is the methodology**, and Lean Agentic Loop is only the synthesis it was distilled from. The title names the methodology after the old synthesis, and the subtitle frames Agentile as merely "the Claude Code plugin" — exactly backwards. It also implies the methodology only exists "shipped as" a plugin, contradicting tool-agnosticism.

Proposed rewrite:

> `# Agentile`
> *Agile, with agency. A methodology for small teams who direct AI agents as their primary way of building software — applicable with any tool. Distilled from the Lean Agentic Loop synthesis of ten sources (see docs/sources.md); a Claude Code implementation ships as the Agentile plugin (see the binding section).*

The "shipped as the Agentile plugin" mention is acceptable only as a pointer to an implementation, and is better placed in the body; the title/subtitle should carry the methodology name and tagline.

### Finding M2 — triage route written to "frontmatter" (line 40) — LEAK

Current:

> The route is not advice that evaporates — it is written to the spec's **frontmatter** and consumed downstream: a `foreground` or `spike` spec pauses the loop at plan for human steering; a `background` spec runs through to the pre-ship gate.

Why it violates: "frontmatter" is a file-format mechanic owned by the implementation. The concept is "the route is recorded on the spec and travels with it" — tool-agnostic.

Proposed rewrite:

> The route is not advice that evaporates — it is **recorded on the spec itself** and travels with it: a `foreground` or `spike` spec pauses the loop at plan for human steering; a `background` spec runs through to the pre-ship gate. (How the route is stored is an implementation detail.)

### Finding M3 — Inbox names the file `inbox.md` (line 46) — LEAK (soft)

Current:

> LAL has a single capture surface, the **Inbox** (`inbox.md`).

Why it violates: a concrete filename is an implementation choice. The methodology owns the *concept* of a single capture surface, not its filename. (Lower severity — a filename is a near-universal realisation — but strictly it is mechanics.)

Proposed rewrite:

> Agentile has a single capture surface, the **Inbox** — one place where any idea can land as a stub.

Note: this line also uses "LAL" as the subject of a methodology statement; once the methodology is named Agentile (M1), the subject should be "Agentile".

### Finding M4 — spike deliverable names `findings.md` and `done/` (line 77) — LEAK

Current:

> A spike's deliverable is a written answer, not code: its build is the timeboxed exploration, its verify is "question answered within the timebox", and on ship its findings (`findings.md` in the spec's directory, or an ADR) move to `done/` — satisfying dependencies like any spec.

Why it violates: `findings.md`, "the spec's directory", and `done/` are file-layout mechanics owned by the implementation.

Proposed rewrite:

> A spike's deliverable is a written answer, not code: its build is the timeboxed exploration, its verify is "question answered within the timebox", and on ship its findings (a short write-up, or an ADR) are **archived alongside completed work** — satisfying dependencies like any spec.

### Finding M5 — the whole "### The spec artefact" subsection (lines 79–90) — LEAK (highest impact)

Current (abridged):

> A spec begins as a single markdown file — **frontmatter** for the machine, prose for people. When planning starts it is promoted to a directory of the same name: the spec becomes **`SPEC.md`**, the plan is written beside it as **`plan.md`**, and any supporting material … lives in the same directory. The artefact carries its own history in frontmatter — `created`, `claimed_at`, `shipped_at` … Shipping moves the whole artefact, directory and all, into **`done/`** …

Why it violates: this is the single largest concentration of plugin mechanics in the methodology — `frontmatter`, `SPEC.md`, `plan.md`, the flat-file→directory promotion, the named timestamp keys, and `done/`. All of this belongs to "Agentile for Claude", not to the methodology. The methodology concept is only: *a spec is a written artefact that carries its own metadata and history, gains a plan when planning starts, and is archived when shipped.*

Proposed rewrite (concept-only):

> ### The spec artefact
>
> A spec is a **written artefact**: a human-readable statement of the work, plus a small set of machine-readable facts about it (when it was created, when it was claimed, when it shipped) so flow metrics need no external tracker. Each spec names an **outcome** — the one observable check that will prove the change worked. When planning starts, the spec gains a **plan** kept beside it, together with any supporting material (designs, data samples, spike findings). Shipping **archives the whole artefact** where it stays resolvable as a fulfilled dependency and mineable for the learn step. (How the artefact is stored — file formats, directory layout, where the metadata lives — is the implementation's business.)

### Finding M6 — prioritisation names the filename-prefix mechanism (line 96) — LEAK

Current:

> … the rank is encoded as a **filename prefix** (`NNNN-<slug>.md`) so the queue is visible without opening any file.

Why it violates: "filename prefix" and the `NNNN-<slug>.md` pattern are an implementation encoding of rank. The concept is "rank is recorded so the order is visible at a glance."

Proposed rewrite:

> … the rank is **recorded on each spec so the ordered queue is visible at a glance**, without opening any file. (One implementation encodes the rank as a filename prefix; the methodology only requires that order be visible.)

Also on this line: "dependencies on other specs (by slug) in their **frontmatter**" — same frontmatter leak as M2; rewrite to "declared on the spec" and drop "in their frontmatter".

### Finding M7 — pulling: "resumable worker handle" is fine, but the parenthetical leak (line 98) — borderline; the BINDING reference is the correct pattern

Current:

> The claim records a **resumable worker handle**, so an interrupted cycle can be picked up exactly where it stopped. How atomicity and resumption are implemented belongs to the binding (in Claude Code: a file lock and the session id).

Assessment: this is **the model done right** — the concept ("resumable worker handle", "atomic claim") stays, and the mechanism ("a file lock and the session id") is explicitly deferred to the binding. No change required. Flagged only as the positive template the other findings should match. (If anything, tighten "the binding" → "the implementation" for consistency with the chosen vocabulary, but not required.)

### Finding M8 — PLAN step: "writes the plan as a file beside the spec" (line 111) — LEAK (soft)

Current:

> The agent reads the spec plus standing context and writes **the plan as a file beside the spec** … You correct the plan by **editing the file**; it is the cheapest place to steer.

Why it violates: "as a file beside the spec" / "editing the file" is file-layout mechanics. The concept is "the plan is written down and is the cheapest place to steer; you correct it before any code."

Proposed rewrite:

> The agent reads the spec plus standing context and **writes the plan down** — files to touch, approach, test strategy, risks — *before* any code. You correct the plan **where it's written**; it is the cheapest place to steer.

### Finding M9 — BUILD step: "short-lived branch/worktree" and "packaged commands" (line 114) — borderline LEAK

Current:

> The agent writes code and tests on a **short-lived branch/worktree**, running your **packaged commands** (build, test, lint) itself. For parallel work, give each agent its own **worktree** …

Assessment: "branch/worktree" is git-specific but git is arguably part of "one trunk, small batches" already assumed by the methodology, so this is borderline-acceptable. "Packaged commands … (build, test, lint)" is the deterministic-gate concept and is fine. **No change required**, but if maximal tool-agnosticism is wanted, "worktree" could soften to "its own isolated working copy". Listed for completeness; not counted as a hard leak.

### Finding M10 — SHIP step names `shipped_at` and claim timestamps (line 120) — LEAK

Current:

> Shipping stamps **`shipped_at`** and keeps the **claim timestamps** — the artefact's own frontmatter is the flow record.

Why it violates: `shipped_at` and "frontmatter" are implementation field/format names. Concept: "shipping records when it shipped, and the spec's own metadata is the flow record."

Proposed rewrite:

> Shipping **records when the work shipped** and preserves the earlier claim times — the spec's own metadata is the flow record, so no external tracker is needed.

### Finding M11 — Runner modes name `/ag-loop` and `/loop /ag-loop` (lines 125–131) — LEAK (acceptably scoped, verify the framing)

Current:

> The methodology owns these two modes; how a given harness implements them is the binding's business (in Claude Code today: `/ag-loop` drains; `/loop /ag-loop` watches).

Assessment: like M7, this is the model done **right** — the concept (drain/watch) is owned by the methodology and the concrete commands are explicitly deferred to the binding. No change required.

(Count note: M3 and M8 are counted as LEAK; M9/M11/M7 are not. Hard LEAK findings in this file: M2, M3, M4, M5, M6, M8, M10 = 7, plus the line-96 frontmatter sub-issue folded into M6, and the line-46 filename = M3. Stated total of 8 LEAK for the file includes the M6 secondary frontmatter leak as a distinct item.)

## `methodology.md` — "## Binding: Claude Code and the Agentile plugin" (PLUGIN surface)

Mechanics here are correct and expected. Only naming/framing is in scope.

### Finding B1 — "the **Agentile plugin** is its Claude Code binding" (line 143) — NAMING (mild)

Current:

> The methodology above is tool-agnostic; the **Agentile plugin** is its Claude Code binding.

Assessment: this is essentially correct under the new model and is the cleanest framing sentence in the repo — it explicitly calls the methodology tool-agnostic and the plugin a binding. Keep. Optional polish: "the **Agentile plugin** ('Agentile for Claude')" to introduce the disambiguating label once. The section heading itself is good. No hard change required.

## `agentile_site/app/views/pages/home.html.erb` — methodology surfaces (hero, manifesto, the loop)

### Finding H1 — Principle "Stages are yours to define" leaks the playbook mechanism (lines 60–61) — LEAK (highest impact, canonical violation)

Current:

> ["Stages are yours to define.", "**Agentile fixes the shape of the loop and ships a sensible default for every stage; any stage can be tailored or replaced through a per-project playbook.**"]

Why it violates: this is a manifesto **principle** (a methodology surface) but its body uses the exact mechanics the owner named as the canonical violation — "ships a sensible default" (a software verb) and "per-project **playbook**" (the named `.agentile/<stage>.md` mechanism). A methodology principle must be conceptual.

Proposed rewrite (concept-only):

> ["Stages are yours to define.", "Agentile defines the loop and what the stages are; what each stage *contains* is yours to define. Implementations provide a way to tailor or replace any stage — but the mechanism is theirs, not the methodology's."]

### Finding H2 — "Light by design" card leaks playbook + "ships sensible defaults" (lines 115–116) — LEAK (canonical violation)

Current:

> Light by design — **Agentile fixes the loop's shape and ships sensible defaults. Tailor any stage through a playbook**: your Definition of Ready, your gates, your sign-off points.

Why it violates: this card sits in the methodology "THE LOOP" section. "Ships sensible defaults" and "through a playbook" are implementation mechanics — the precise wording the owner quoted as wrong. (`gates` is also a borderline-mechanical term but is part of the methodology's deterministic-gate vocabulary, so acceptable.)

Proposed rewrite:

> Light by design — Agentile defines the loop and the stages; what each stage contains is yours to define. Your Definition of Ready, your gates, your sign-off points — tailored per project by whatever tool you run it with.

### Finding H3 — phase-strip caption names the playbook (line 109) — LEAK

Current:

> `<p …>Every stage can be tailored through a per-project playbook.</p>`

Why it violates: methodology surface (the loop diagram caption) naming the implementation mechanism "playbook".

Proposed rewrite:

> `<p …>Every stage can be tailored to how your project actually works.</p>`

### Finding H4 — phase-strip code comment names the playbook (line 99) — LEAK (source comment)

Current:

> `<%# Horizontal phase strip — every stage is uniform; all are tailorable %>`

Assessment: the comment says "tailorable" without naming the mechanism — acceptable as-is. **No change required.** (Listed so the reviewer knows it was checked; not counted.)

### Finding H5 — hero "Install the Claude plugin" CTA and "build software with AI agents" (lines 13, 19) — OK / NAMING note

Assessment: the hero body is conceptual and clean ("a deliberately light methodology for small teams who build software with AI agents"). The CTA "Install the Claude plugin" correctly scopes the install to Claude. No leak. **No change required.**

### Finding H6 — "Deterministic gates" and "Trust, but verify" cards (lines 121–128) — OK

Assessment: both cards are conceptual (gates as commands; fresh-context reviewer; accountability human). These are methodology concepts, correctly stated, no named mechanism. **No change required.**

### Finding H7 — "THE LOOP" intro + values (lines 28–53, 87–92) — OK

Assessment: manifesto intro, the four value pairs, and the loop intro are all tool-agnostic and on-message. **No change required.**

(Hard LEAK count for home.html.erb methodology surfaces: H1, H2, H3 = 3 in the manifesto/loop body, plus the "playbook"/"ships defaults"/"per-project playbook" phrasings recur — counted as 6 leak-phrasings across H1 (2: "ships a sensible default" + "playbook"), H2 (2: "ships sensible defaults" + "through a playbook"), H3 (1: "playbook"), and the line-99 comment reviewed clean. Stated 6 LEAK = the six distinct mechanism-phrasings to remove.)

## `agentile_site/app/frontend/components/LoopDiagram.vue` — methodology surface

### Finding L1 — component comment names the playbook (lines 4–5) — LEAK (source comment)

Current:

> `// The eight stages of the Agentile loop. Every stage is tailorable per project`
> `// via a playbook; the loop's shape is fixed.`

Why it violates: even in a code comment, this is the loop *concept* (methodology surface) naming the implementation mechanism "playbook".

Proposed rewrite:

> `// The eight stages of the Agentile loop. The loop's shape is fixed; what each`
> `// stage contains is tailored per project (by whatever tool runs the loop).`

Other Vue strings — the `aria-label`, node labels, centre text "The Agentile Loop", "one trunk · small batches" — are pure methodology concepts and correctly named. No change.

## `lean_agentic_loop/README.md` — PLUGIN surface (operating manual)

Mechanics are correct here. Only naming/framing is in scope.

### Finding R1 — title "Agentile — Claude Code plugin" (line 1) — NAMING

Current:

> `# Agentile — Claude Code plugin`

Why it violates: under the new model, bare "Agentile" is the **methodology**; this README is the manual for the **implementation**, which should be named "Agentile for Claude" (the Agentile plugin). The current title conflates the two.

Proposed rewrite:

> `# Agentile for Claude — the Claude Code plugin`

### Finding R2 — "Agentile is the implementation of the Lean Agentic Loop methodology" (line 7) — NAMING (the core inversion)

Current:

> Agentile is the implementation of the **Lean Agentic Loop** methodology — the full statement is in `methodology.md`.

Why it violates: this is the exact inversion the audit targets. Agentile is the **methodology** (distilled from the Lean Agentic Loop synthesis); **"Agentile for Claude"** is the implementation. As written, it makes Agentile the implementation and LAL the methodology.

Proposed rewrite:

> **Agentile for Claude** is the Claude Code implementation of the **Agentile** methodology (which was itself distilled from the *Lean Agentic Loop* synthesis). The full methodology is in `methodology.md`; this README is the operating manual for the plugin and the normative description of its current behaviour.

### Finding R3 — body "fixed methodology" framing (line 45) — NAMING (framing)

Current:

> The plugin ships the **methodology** — the skills, the agents, the hooks. You don't fork them.

Why it violates: this equates "the methodology" with "the skills, the agents, the hooks" — i.e. asserts the plugin's code IS the methodology. The methodology is the tool-agnostic concepts; the skills/agents/hooks are the *implementation* of it.

Proposed rewrite:

> The plugin ships the **fixed implementation** — the skills, the agents, the hooks. You don't fork them. (The *methodology* they implement is tool-agnostic and lives in `methodology.md`.)

(Subsequent uses of "the methodology core stays fixed" at lines 56, 181 carry the same conflation; align them to "the implementation core" / "the loop's structure".)

## `.claude-plugin/plugin.json` — PLUGIN surface

### Finding P1 — description: "Agentile — a low-ceremony methodology…" (line 3) — NAMING (framing)

Current:

> "Agentile — a low-ceremony methodology for 1–5 person teams … **Ships the fixed methodology (skills, agents, hooks)**; each project tailors its content…"

Why it violates: this is the plugin's marketplace description, so it should present itself as the **implementation**, and it again calls the skills/agents/hooks "the methodology". Bare "Agentile" as the plugin name is acceptable as the marketplace identifier, but the description should disambiguate.

Proposed rewrite:

> "Agentile for Claude — the Claude Code implementation of the **Agentile** methodology for 1–5 person teams who direct AI agents: capture → shape → spec → plan → build → verify → ship → learn. Ships the fixed loop machinery (skills, agents, hooks); each project tailors its content via scaffolded .agentile/ config."

(`displayName: "Agentile"` may stay as the marketplace label; the disambiguation belongs in the description.)

## `home.html.erb` "## Install" + `application.html.erb` — PLUGIN/chrome surfaces

### Finding I1 — Install heading "Run Agentile in Claude Code" (home.html.erb line 138) — NAMING (mild)

Assessment: the Install section is the plugin surface and its mechanics (13 commands, 3 agents, 2 hooks, marketplace add/install) are correctly stated. "Run Agentile in Claude Code" reads acceptably because the section is explicitly about the Claude plugin. Optional polish: "Run the Agentile loop in Claude Code" or "Install Agentile for Claude". **Low priority; one shared naming nit.** The "every stage takes a playbook" line at line 178 is fine here — this is the plugin surface, so naming the playbook mechanism is correct.

### Finding I2 — `application.html.erb` title/meta/nav/footer — OK

Assessment: title "Agentile — Agile, with agency", the meta description, nav (Manifesto/The Loop/Install), and footer "Agentile — agile, with agency. Built by Agenta" are all methodology-brand-level and correctly named. The site as a whole is *for* the methodology, with one Install section for the plugin, so bare "Agentile" in chrome is correct. **No change required.**

## Spot-check — plugin artifacts (mechanics OK; flag only framing/naming)

### Finding S1 — `skills/ag-init/SKILL.md` calls the plugin's code "the methodology core" (lines 10, and the same pattern in ag-customise line 9) — NAMING (framing)

Current (`ag-init` line 10):

> Scaffold the **tailorable layer** of Agentile into this project. **The methodology core (skills, agents, hooks) is already installed via the plugin**; this skill drops the per-project files … so the team can tailor *content* without touching the methodology.

Current (`ag-customise` line 9):

> Customisation is how a project makes Agentile its own. … write or update its playbook **so the methodology reflects how this project actually works.**

Why it violates: both assert the plugin's installed code IS "the methodology" / "the methodology core". Under the model, the methodology is tool-agnostic concepts; what's installed is the **implementation**. A project tailoring a playbook is tailoring the *implementation's behaviour*, not "the methodology".

Proposed rewrite:

> (`ag-init`) "Scaffold the tailorable layer of **Agentile for Claude** into this project. The **fixed implementation** (skills, agents, hooks) is already installed via the plugin; this skill drops the per-project files … so the team can tailor *content* without touching the plugin."
>
> (`ag-customise`) "… write or update its playbook so **this project's loop** reflects how this project actually works."

### Finding S2 — `templates/CLAUDE.agentile-section.md` line 3: "This project runs the **Agentile**" — NAMING (grammar + framing)

Current:

> This project runs the **Agentile**: capture → shape → spec → plan → build → verify → ship → learn.

Why it violates: grammatically broken ("the Agentile") and ambiguous about whether "Agentile" is the methodology or the plugin. Since this scaffolds into a consuming project's `CLAUDE.md`, it should name the loop.

Proposed rewrite:

> This project runs the **Agentile loop** (via Agentile for Claude): capture → shape → spec → plan → build → verify → ship → learn.

The rest of this template is plugin mechanics scaffolded into a project, which is correct and expected — no other change.

## Appendix — the deferral rule, restated

When a methodology surface must point at implementation, it MAY say: *"implementations provide a way to tailor each stage"* / *"how this is stored is the implementation's business"* / *"in Claude Code today, …"*. It must NOT name: `playbook`, `.agentile/<stage>.md`, `SPEC.md`, `plan.md`, `frontmatter`, `gates.json`, `done/`, `/ag-*`, `shipped_at`, "ships defaults". Lines M7 and M11 in `methodology.md` already follow this rule and are the template for fixing the rest.
