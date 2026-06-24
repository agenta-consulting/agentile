# Agentile Website Copy Review

Date: 2026-06-13. Reviewer scope: `agentile_site/app/views/pages/home.html.erb`, `app/views/layouts/application.html.erb`, `app/frontend/components/LoopDiagram.vue`. Ground truth: `lean_agentic_loop/lean-agentic-loop.md`, `lean_agentic_loop/README.md`, `lean_agentic_loop/docs/agentile-customisation-and-concurrency.md`. No site files were edited; findings and rewrites only.

## Executive summary

The site is in better factual shape than feared. Almost every concrete claim checks out against the methodology docs: the eight stage names, "hours to a day, not a two-week sprint", thirteen skills (counted and verified against the README list), three agents, two hooks, the install commands, "one trunk, small batches", and the deterministic-gates language are all accurate, often near-verbatim. The problems are tonal and structural, not factual. Four systemic patterns:

1. **Quips in load-bearing positions.** The two most prominent slots on the page — the line directly under the hero CTAs, and the closing pull-quote of the manifesto — are both occupied by wordplay ("stand down", the "amplifies / amplifies" repetition trick). The substance behind each is real and documented; the delivery devalues it. Two smaller instances ("you are looping", the wink at agent readers) follow the same pattern.
2. **Accidental narrowness around customisation.** The site repeatedly singles out Capture and Shape as the only "yours" stages — in principle 3, the phase strip, the LoopDiagram component, the "Light by design" card, and the "∞ Yours" stat. The customisation spec is explicit that this is wrong: "Customisation is a property of the methodology, not a feature of particular stages" (docs/agentile-customisation-and-concurrency.md, §1). All five instances need the same generalisation. This is the single biggest content fix.
3. **Aphorism drift in the principles.** Most principle headings are genuine principles with doc backing. Two drift toward slogan ("Capture is free; building is earned" drops the load-bearing half of its source principle; "Reduce agency with determinism" collides with the brand tagline without explanation), and one documented principle — human accountability — is missing entirely, demoted to a trailing clause in a card.
4. **Minor precision drift.** "Verify-gate hooks" mislabels the format hook; the `/ag-loop` comment omits the claim step and the human sign-off (which is a differentiator, not a detail); "turn" is used where the docs say "cycle".

Finding counts: 4 gimmick/quip, 5 accidentally narrow, 3 precision drift, 4 principle-level (1 replace, 1 reword, 1 clarify, 1 add), plus a values review (keep all four pairs; one optional addition). 16 findings, 13 requiring change.

One note of record on the canonical example: the *digest* concept does in fact exist in the methodology ("Replace standups with the LEARN digest", lean-agentic-loop.md, "What you deliberately drop"; the README also carries the identical "stand down" line at line 5). So the substance is supportable — the pun is still the failure, and the line should still go. If the site line is cut, the same line in README.md line 5 should be cut in the same pass for consistency.

## Hero (home.html.erb, lines 1–27)

### Finding 1 — the standup/digest pun

- **Location:** home.html.erb line 24, hero section, directly beneath the CTAs.
- **Current copy:** "We replaced the standup with a digest, so you can stand down."
- **Problem:** Pun-for-pun's-sake in the single most prominent supporting slot on the page. The underlying claim is documented (the LEARN digest replaces standups), but "stand down" exists only to complete the joke, and a joke is the first thing a sceptical reader meets after the headline.
- **Proposed rewrite:** "No standups, no sprint ceremonies, no story points. A short loop with deterministic gates, measured in hours." (Every clause is backed by "What you deliberately drop" in lean-agentic-loop.md.) Alternative: CUT entirely — the hero already has a tagline, a paragraph, and two CTAs; it does not need a footnote.

### Finding 2 — hero paragraph

- **Location:** home.html.erb lines 12–16.
- **Current copy:** "A deliberately light methodology for small teams who build software with AI agents…"
- **Problem:** None. Accurate, plain, confident. Noted so it isn't churned in the rewrite pass.
- **Proposed rewrite:** Keep as is.

## Manifesto — intro (home.html.erb, lines 33–38)

### Finding 3 — the wink at agent readers

- **Location:** home.html.erb line 37, end of the manifesto intro paragraph.
- **Current copy:** "Whether you are a person or an agent reading this, the loop is yours to run."
- **Problem:** Direct-address-to-the-AI is a well-worn landing-page trope; it reads as a wink rather than a claim. The genuine point underneath (the methodology's artefacts are written to be machine-readable — specs, playbooks, standing context) deserves plainer treatment.
- **Proposed rewrite:** "Agentile gives that team — humans and agents alike — one loop to run." Alternative: CUT the sentence; the paragraph stands without it.

## Manifesto — values (home.html.erb, lines 41–58)

The "We have come to value X over Y" framing is protected per the owner. Reviewed each pair for backing and quality:

- **"Shaped intent over hopeful prompts"** — Backed (shaping, "hopeful sentence in a prompt", "story writing is prompting"). Strong; the best pair of the four. Keep.
- **"Determinism over instruction"** — Verbatim governing principle 3. Keep.
- **"Verification over trust"** — Backed ("Trust but verify, automatically", "nothing merges unverified"). Keep.
- **"Flow over output"** — Verbatim from governing principle 7 ("Measure flow, not output"). Keep.

**Optional addition (Finding 4):** the methodology's accountability theme ("Accountability stays human"; "AI redistributes work; it does not move accountability") has no value pair. A fifth pair would carry it at manifesto altitude: **"Human accountability over agent autonomy"**. Only add if a fifth doesn't dilute the set — the agile manifesto's four-pair rhythm is part of what makes the framing land. If not added here, it must land as a principle (see Finding 9).

## Manifesto — principles (home.html.erb, lines 61–80): dedicated review

Test applied to each: is it a principle (a rule you could decide with), distinct from its neighbours, backed by the docs, and phrased with gravitas?

### Principle 1 — "One trunk, small batches."

- **Current copy:** "One trunk, small batches. Humans and agents integrate continuously. Small diffs are reviewable; large ones are not."
- **Verdict:** Keep. Verbatim governing principle 1; body is a faithful compression. The doc adds "behind feature flags" — optional to include, not required at this altitude.

### Finding 5 — Principle 2: "Capture is free; building is earned."

- **Current copy:** "Capture is free; building is earned. Every idea enters in a single line. Nothing is built from an unshaped one."
- **Problem:** "Building is earned" is slogan-shaped and drops the load-bearing half of its source principle: "The spec is the unit of work — but capture is free" (governing principle 2). The spec — not earning — is the actual rule; the current head tells you the vibe but not the mechanism.
- **Proposed rewrite:** "The spec is the unit of work; capture is free. Ideas enter as one-line stubs with zero ceremony. Nothing is built without a shaped spec."

### Finding 6 — Principle 3: "Capture and shaping are yours to define." (accidentally narrow — owner item 2)

- **Current copy:** "Capture and shaping are yours to define. Agentile insists they exist — not what they contain. Lay your own process on top."
- **Problem:** Accidentally narrow. The customisation contract is uniform: every stage takes a `.agentile/<stage>.md` playbook ("Customisation is a property of the methodology, not a feature of particular stages" — customisation spec §1; README "Customising any stage"). Singling out two stages misrepresents a core design property.
- **Proposed rewrite:** "Stages are yours to define. Agentile fixes the shape of the loop and ships a sensible default for every stage; any stage can be tailored or replaced through a per-project playbook."

### Principle 4 — "Context is infrastructure."

- **Current copy:** "Context is infrastructure. Decisions, conventions, and domain rules live where every agent reads them, versioned with the code."
- **Verdict:** Keep. Verbatim governing principle 4; the best-phrased principle on the page.

### Finding 7 — Principle 5: "Reduce agency with determinism."

- **Current copy:** "Reduce agency with determinism. Anything you would repeat — build, test, scan, deploy — is a gate, not a hope."
- **Problem:** The head is the docs' own term (cross-cutting theme; danicat's "reduce the agent's agency"), so it stays — but on a page whose tagline is "Agile, with agency" it reads as a contradiction unless the body resolves it. "A gate, not a hope" is borderline-cute but carries meaning; acceptable.
- **Proposed rewrite (body only):** "Reduce agency with determinism. Agents get judgement where it matters; anything you would repeat — build, test, scan, deploy — runs as a deterministic gate, never a request in prose."

### Principle 6 — "A fresh reviewer beats a confident author."

- **Current copy:** "A fresh reviewer beats a confident author. Agents find others' mistakes better than their own. Nothing merges unverified."
- **Verdict:** Keep. Aphoristic, but it earns it — every clause is backed (VERIFY step: "agents are better at finding others' mistakes than their own"; principle 5: nothing merges until it passes the gates). This is wit that carries meaning.

### Principle 8 (site #7) — "The loop learns."

- **Current copy:** "The loop learns. Each turn encodes its lessons, so the next turn is cheaper."
- **Verdict:** Keep, with one word swapped: the docs consistently say **cycle**, not turn ("a 'cycle' is hours to a day"; "the next cycle is cheaper"). Rewrite body: "Each cycle encodes its lessons, so the next one is cheaper."

### Finding 8 — distinctness check across the set

- **Problem (minor, no change forced):** Principle 5 (determinism) restates the "Determinism over instruction" value pair, and principle 6 restates "Verification over trust". This mirrors the agile manifesto's own values-then-principles structure, where principles elaborate values — acceptable, flagged so it's a deliberate choice rather than an accident.

### Finding 9 — missing principle: accountability stays human

- **Problem:** Governing principle 6 ("Name the anchors") and the strongest cross-cutting theme ("Accountability stays human") have no principle on the site — human accountability appears only as a trailing clause in the "Trust, but verify" card. For a methodology whose default posture is pause-before-ship, this is a differentiator hiding in a footnote.
- **Proposed addition (new principle, suggested position 7, before "The loop learns"):** "Accountability stays human. Agents draft, plan, build, and review; a named person approves the plan and signs off before anything ships." (Backed by governing principle 6, the pause-before-ship default in README "Running the loop", and "AI redistributes work; it does not move accountability.")

## Manifesto — closing pull-quote (home.html.erb, lines 82–84)

### Finding 10 — "amplifies a healthy loop — and amplifies a broken one" (owner item 3)

- **Location:** home.html.erb line 83, the bordered pull-quote closing the manifesto.
- **Current copy:** "First be agile, then agentic. Agentile amplifies a healthy loop — and amplifies a broken one."
- **Problem:** The repetition device reads as a rhetorical trick, and it ends the manifesto on an unexplained warning. Note: the line is lifted verbatim from the methodology (README "The one rule"; lean-agentic-loop.md line 219) — but the docs immediately follow it with the explanation, and the site quotes the trick without the payoff.
- **Proposed rewrite:** "First be agile, then agentic. Get the trunk, the gates, and the written spec right first — agents make a good loop fast, not a bad loop safe." (Near-verbatim from the same doc paragraph; the second clause is the strongest sentence in the methodology and currently appears nowhere on the site.)

## The Loop section (home.html.erb, lines 89–139)

### Finding 11 — "turn" vs "cycle"

- **Location:** home.html.erb lines 93–96, section intro.
- **Current copy:** "Work flows around a single loop — hours to a day per turn, not a two-week sprint. Each turn ends by teaching the next one."
- **Problem:** Terminology drift — the docs consistently say "cycle". "Teaching the next one" is fine; "encodes" is the docs' stronger verb.
- **Proposed rewrite:** "Work flows around a single loop — a cycle is hours to a day, not a two-week sprint. Each cycle ends by encoding what it learned, so the next one is cheaper."

### Finding 12 — phase strip singles out Capture and Shape (accidentally narrow)

- **Location:** home.html.erb lines 103–117 (the horizontal stage strip; Capture and Shape rendered with dashed accent borders via the `yours` flag).
- **Current copy:** (visual) Capture and Shape styled as "yours"; the other six styled as fixed.
- **Problem:** Same narrowness as Finding 6, in visual form — it teaches the reader that only two stages are tailorable, contradicting the uniform playbook contract.
- **Proposed rewrite:** Render all eight stages uniformly (drop the `yours` flag from the data array). If a customisation callout is wanted, add a caption beneath the strip: "Every stage can be tailored through a per-project playbook."

### Finding 13 — LoopDiagram.vue encodes the same narrowness

- **Location:** LoopDiagram.vue lines 4–15 (`yours: true` on capture and shape, plus the explanatory comment), lines 78–96 ("YOURS" sublabels and dashed styling), line 5 comment: "Agentile insists they exist, but each organisation defines what they contain."
- **Current copy:** (visual) Capture and Shape ringed dashed-accent with a "YOURS" sublabel; comment asserts the two-stage version of the claim.
- **Problem:** Same as Finding 12; the diagram is the page's centrepiece, so it is the most prominent carrier of the wrong claim. The centre text ("The Agentile Loop / one trunk · small batches") is good and should be kept.
- **Proposed rewrite:** Remove the `yours` property, the "YOURS" sublabels, and the dashed special-casing; update the comment to: "The eight stages of the Agentile loop. Every stage is tailorable per project via a playbook."

### Finding 14 — "Light by design" card (narrow, plus off-message "rituals")

- **Location:** home.html.erb lines 120–125.
- **Current copy:** "Light by design — Capture and shaping exist — how you run them is yours. Drop your own questions, gates, and rituals on top."
- **Problem:** Two issues. (a) Same two-stage narrowness. (b) "Rituals" is off-message: the methodology's pitch is *dropping* ceremony ("dropping the ceremony small teams can't justify"); inviting readers to add rituals undercuts that.
- **Proposed rewrite:** "Light by design — Agentile fixes the loop's shape and ships sensible defaults. Tailor any stage through a playbook: your Definition of Ready, your gates, your sign-off points."

### The other two cards

- **"Deterministic gates"** (lines 126–131) — keep; near-verbatim from the docs ("never a hopeful sentence in a prompt").
- **"Trust, but verify"** (lines 132–137) — keep; backed by the VERIFY step. (Its "Accountability stays human" clause is promoted to a full principle under Finding 9; fine to keep here too.)

## Install section (home.html.erb, lines 142–188)

### Finding 15 — "and you are looping" + "verify-gate hooks"

- **Location:** home.html.erb lines 146–149.
- **Current copy:** "Agentile ships as a Claude Code plugin — thirteen /ag- commands, three agents, and the verify-gate hooks. Add the marketplace, install, and you are looping."
- **Problem:** (a) "You are looping" is a mild quip that also overpromises — after install you still need `/ag-init`, shaped specs, and a prioritised queue before the loop has anything to do (README: "the loop only has anything to do once there are prioritised, dependency-satisfied ready specs"). (b) "Verify-gate hooks" mislabels the pair: format-on-edit is not a verify gate; the docs call them enforcement hooks (format-on-edit, test-gate). Counts otherwise verified: 13 skills, 3 agents, 2 hooks.
- **Proposed rewrite:** "Agentile ships as a Claude Code plugin — thirteen /ag- commands, three agents, and two enforcement hooks. Add the marketplace, install, then initialise your project."

### Finding 16 — `/ag-loop` comment omits claim and the human sign-off

- **Location:** home.html.erb line 162.
- **Current copy:** "/ag-loop       # work the queue: plan → build → verify → ship"
- **Problem:** Drops the claim step and — more importantly — the pause-before-ship sign-off, which is the default posture and a trust differentiator the site should be advertising, not eliding (README: "pause-before-ship is the default — nothing merges without your approval").
- **Proposed rewrite:** "/ag-loop       # work the queue: claim → build → verify → your sign-off → ship"

### Finding 17 — "∞ Yours" stat is narrow

- **Location:** home.html.erb lines 183–186.
- **Current copy:** "∞ Yours — tailor every gate and the shaping questions per project"
- **Problem:** Understates the customisation contract (gates and shaping questions are two of ten-plus tailorable surfaces). The "∞" glyph in a stats row is borderline-cute but defensible; the copy is the fix.
- **Proposed rewrite:** "∞ Yours — every stage takes a playbook: tailor gates, shaping questions, and sign-off points per project"

## Layout (application.html.erb)

No findings. The meta description, navbar, and footer are plain and accurate. "Agile, with agency" appears three times across the site (title, hero, footer) — it is the brand line, it carries meaning, and it should stay.

## Out-of-scope consistency notes (no site change)

- README.md line 5 carries the identical "stand down" line; cut it in the same pass or the site and repo will disagree about the project's voice.
- README.md line 125 and lean-agentic-loop.md line 219 carry the "amplifies / amplifies" formulation; if the owner dislikes it on the site, consider tightening it at the source too, since the site was quoting faithfully.
