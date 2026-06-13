# Lean Agentic Loop — source notes

The ten sources the methodology was synthesised from, summarised at the time of writing (2026-06). The cross-cutting themes they yielded live in [`../methodology.md`](../methodology.md).

**1. CIO — "5 ways agentic engineering transforms agile practices" (Derek Ashmore).**
Agile survives the agentic era but must level up. Five shifts: (1) roles converge — every human becomes a "specifier"/product manager directing agents; (2) stories can be larger because agents do more per unit time; (3) concurrency matters more, so trunk-based development is essential to stop agents clobbering each other; (4) end-to-end testing becomes critical because agents hallucinate and lack whole-system context; (5) double down on metrics (DORA) because agents add moving parts and risk.

**2. INNOQ — "First Agile, Then Agentic" (Daniel Westheide).**
AI won't rescue an immature org. Agentic speed only pays off if you already have the agile/DevOps capabilities (short feedback loops, autonomous cross-functional teams, fast deploys). If your bottleneck is requirements, validation, or ops — not coding — giving developers agents just produces wrong work faster. "Agency" (autonomy + capability to act) must exist in the team before you delegate it to software agents.

**3. danicat.dev — "From Agile to Agentic" (Daniela Petruzalek).**
The most practitioner-concrete piece. Three core practices: (1) *story writing is prompting* — a good story = good context = Definition of Ready; (2) *prioritisation dictates workflow* — sort by Business Value × Technical Certainty to decide foreground pairing vs. background async agents; (3) *reduce the agent's agency* — package deterministic steps (build/test/lint/deploy) as tools, not prompts, so the agent can't "forget." Scale via ADRs and institutional knowledge injected into agents through MCP servers, non-coding agents that automate ceremonies (refinement, DoR/DoD audits, retros), and "agent managers" orchestrating fleets. Ends with a vision of "agentic kanban."

**4. Medium / Pablo Torre — "The Agentic Revolution: Beyond Agile."**
Proposes an agent-driven SDLC of iterative loops: generate Markdown specs → prototype in a flexible language (Python/JS) → reimplement in a high-performance language (TS/Rust/SQL) → continuous performance optimization → automated security hardening. The economic argument: when agents make refactoring and migration cheap, the cost of change collapses, technical debt stays low, and adaptability becomes the competitive edge. More visionary/economic than operational.

**5. Sonar — "AC/DC: Agent-Centric Development Cycle."** *(page is JS-rendered; summarized from title/positioning)*
Sonar's framing of a development cycle built around AI agents writing the code, with automated quality and security gates as the control layer. Consistent with Sonar's "trust but verify" stance: agent output must pass deterministic analysis (bugs, vulnerabilities, maintainability) before it earns release confidence. *Note: full body not retrievable; treat as directional.*

**6. Outsourced Staff — "Agile Development" blog.** *(JS-gated; not retrievable)*
General agency-style overview of agile development services/benefits. Could not extract substantive content; excluded from synthesis.

**7. Reddit r/ProductManagement — "Are full Agile processes becoming outdated for [AI teams]?"** *(URL blocklisted; not retrievable)*
Community debate thread on whether heavyweight agile ceremony still earns its keep when AI compresses delivery. Could not extract; the theme (ceremony fatigue vs. retained fundamentals) is well covered by sources 3, 9, and 10.

**8. Glean — "Glean Agents" whitepaper (landing page).** *(gated; summarized from abstract)*
Agents go beyond single LLM calls by combining tools, workflows, and memory to perform enterprise tasks reliably. Glean routes queries to "golden" workflows via search, designs around common query classes (data lookup, progress summarization, request handling), and evaluates agents at scale using task-specific LLM judges and real eval sets. Takeaway for us: reliability comes from *reusable workflows + memory/context + systematic evaluation*, not raw model power.

**9. Medium / Rethink Your Understanding — "Agile Isn't Dead and AI Isn't Killing It Either."**
AI isn't killing agile — it's exposing constraints that were always upstream of engineering. If coding gets faster but lead time doesn't, the bottleneck was prioritization, dependencies, validation, ops, or decision latency. Teams shrink and roles "rebundle," but the *load-bearing responsibilities* never disappear: outcome clarity, discovery/validation, work design, engineering coherence, verification/resilience, delivery/ops, and learning loops. AI redistributes work; it does not move accountability. Value Stream Management and flow metrics matter *more*, not less. What dies is "agile theater."

**10. Atlassian Community — "How AI is Quietly Reshaping Agile" (John D. Patton).**
Field notes: AI augments rather than replaces agile teams. Backlog intelligence (summarizing stale tickets, grouping issues, risk-flagging), human-in-the-loop workflows (AI drafts acceptance criteria/tickets, humans edit to keep ownership and trust), a shift from velocity to flow metrics (cycle time, flow efficiency, AI bottleneck summaries), and emerging hybrid roles ("the developer who codes *and* prompts"). Advice: start small, keep the human in the loop.
