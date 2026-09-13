# Agentile — Workspaces, Participants, and Backlog Stores

Design spec. Status: **proposed** 2026-09-03, **§3 (Stores) implemented 2026-09-13** — the `local`/`airtable` store split shipped (minus the `Jira`/`azure-devops` packs and the `migrate` operation, both still proposed); §1 (Workspaces) and §2 (Participants) remain proposed and unbuilt. Extends the customisation-and-concurrency contract (`agentile-customisation-and-concurrency.md`) and the backlog layout (`agentile-backlog-layout-and-abandon.md`). Nothing here changes the loop's stages; it changes *where the loop runs*, *who may act at each stage*, and *where the backlog lives*.

**What actually shipped vs. this spec, for §3**: `bin/ag-store` (the dispatcher) plus `bin/ag-store-adapters/{local,airtable}.rb` implement the store contract with a trimmed op set (no `migrate`, no `approve`/`comment` — those are §2 Participants concerns, not built). The `airtable` adapter deviates from this doc's §3.1 in one deliberate way: **no blob field** — every frontmatter key and spec-template body section is a real, independently-typed Airtable field (see `bin/ag-store-adapters/airtable/schema.rb`), not the single long-text projection sketched here. The skill-facing contract (`spec_read`/`spec_create`/`spec_write` exchange canonical markdown) still holds — only the airtable adapter's *internal* storage is fully decomposed. A `Members` table was added for attribution (`Captured By`/`Shaped By`/`Claimed By (Member)`, resolved via `ag-store whoami` matching `git config user.email`) — this is §3's territory, not §2's `team.md` permissions, which remains unbuilt.

## Context

Agentile today makes three assumptions that hold for a solo developer in one repository and break for the teams it is meant to serve:

1. **One repository.** The README says so outright: "Agentile is single-repo by design; cross-repo coordination is out of scope." The builder's worktree isolation, the claim lock in the specs directory, `gates.json`, and the ship step all assume the backlog and the code share one checkout. Real small-team products are routinely an API repo, one or more front-end repos, and an infrastructure repo, and most features touch two of them at once.
2. **One implicit human.** Every checkpoint says "a human approves". The plugin has no idea *which* human, so any session that types "approved" is the approver. A five-person team has a lead who signs off on plans, product owners who shape, a coordinator who prioritises, and developers who build. The methodology's "accountability stays human" needs a name attached to be true.
3. **The backlog is files, and the skills touch them directly.** Every skill reads `docs/agentile/inbox.md` and `specs/*.md` itself. That is the right default, and it is also why nobody outside the developers can capture or shape: product owners and coordinators live in Jira, Azure DevOps, or Airtable, not in a git checkout.

This spec introduces three concepts to remove those assumptions while keeping the loop, the fixed-core-versus-tailorable-content split, and the light ceremony intact:

- a **workspace** — one Agentile directory and config governing one or more member repositories;
- **participants** — named people and agents, with per-stage permissions to *perform* and to *approve*;
- a **store** — the place the backlog lives, behind one interface, with local files as the default and setup packs for Jira, Azure DevOps, and Airtable.

Every one of them is opt-in by presence of a file. A project with no `workspace.md`, no `team.md`, and no `store.md` behaves exactly as it does today.

## Governing principles (unchanged, restated where they bite)

- **Fixed core, tailorable content.** Skills, agents, and hooks stay fixed. Workspace, team, and store are content the skills read at runtime.
- **The spec markdown is the canonical format.** A store is a *projection* of that format into a tool, never a second format. Every skill and agent sees a spec as frontmatter-plus-body regardless of where it is kept.
- **Accountability stays human, and now named.** Every approval is recorded against a participant id in the spec's own metadata, which remains the flow record.
- **Reduce agency with determinism.** Workspace resolution, identity resolution, claiming, and store access are deterministic helpers in `bin/`, not prose the model improvises.
- **Light by design.** Three optional files. No server, no daemon, no new UI.

## 1. Workspaces — running the loop across several repositories

### 1.1 Concepts

A **workspace** is the directory that holds `.agentile/` and the Agentile directory (`docs/agentile/` by default). A **member repo** is a git repository the workspace's specs may change. A single-repo project is a workspace with one implicit member: itself.

Members are declared in `.agentile/workspace.md`:

```markdown
---
repos:
  api:
    path: ../api            # relative to the workspace root
    trunk: develop          # the branch builders branch from and ship merges into
    protected: [develop, staging, main]
    ship_order: 1           # lower ships first; equal values may ship in any order
  web:
    path: ../web
    trunk: develop
    protected: [develop, staging, main]
    ship_order: 2
  infra:
    path: ../infra
    trunk: main
    ship_order: 3
branch_prefix: ag/          # builder branches are ag/<NNNN>-<slug> in every touched repo
---

# Workspace

Prose: what the repos are, which one owns the API contract, anything the
planner should know about cross-repo change (e.g. "regenerate the client
types in `web` whenever the GraphQL schema in `api` changes").
```

Two placements are supported. The workspace root may be **inside one member repo** (the "anchor" layout: the backlog lives in, say, the API repo, and other members are siblings) or a **dedicated control repo** whose only contents are the backlog, `.agentile/`, ADRs, and a workspace-level `CLAUDE.md`. The control-repo layout is recommended for multi-repo products because the backlog's history is then not entangled with any one codebase's history, and because a coordinator can hold the control repo without holding the code. Submodules are neither required nor forbidden; paths are resolved relative to the workspace root and `bin/ag-doctor` reports any member that is not checked out.

### 1.2 What changes in the spec

Shaping asks which repos the work touches, and the answer is recorded:

```yaml
repos: [api, web]          # member names from workspace.md; required when a workspace has >1 member
```

`plan.md` gains one section per touched repo ("Files to touch" is per repo). Shipping records where the work landed:

```yaml
shipped:
  api: 3f9c2a1             # merge commit on the repo's trunk
  web: 8b01d77
shipped_at: 2026-09-03T04:12:00Z
```

### 1.3 Build

The builder still runs with `isolation: worktree`, but the unit is now the *workspace*: `bin/ag-worktree create <spec>` makes one worktree per touched repo, all on the same branch name `ag/<NNNN>-<slug>`, under one temporary directory, and prints the mapping. The builder works in that directory tree. `bin/ag-worktree remove <spec>` tears it down. Where `.agentile/build.md` delegates to another skill, that skill receives the mapping and owns worktree creation.

### 1.4 Gates and hooks

`gates.json` gains a per-repo form. The flat form stays valid and means "the one implicit repo":

```json
{
  "repos": {
    "api": { "format": "yarn prettier --write {file}", "lint": "yarn lint", "test": "yarn test", "build": "yarn compile" },
    "web": { "format": "pnpm prettier --write {file}", "lint": "pnpm lint", "test": "", "build": "pnpm build" }
  },
  "protected_branches": ["develop", "staging", "main"]
}
```

`format-on-edit` resolves the edited path to a member repo (longest matching `path`) and runs that repo's formatter. `test-gate` runs the `test` gate of every member with uncommitted changes, in `ship_order`, and blocks on the first failure. A member with a blank `test` is skipped, as today. The reviewer runs every touched repo's `lint`, `test`, and `build`.

### 1.5 Ship

Ship merges each touched repo's branch into that repo's `trunk` in ascending `ship_order`, stamping `shipped.<repo>` after each merge. The spec's status is `shipping` between the first and last merge, so a failure part-way is visible in `/ag-wip` rather than silent. Cross-repo atomicity is out of scope; the mitigation is ordering (contract producers before consumers), the recorded SHAs, and the methodology's existing advice to ship behind a flag. Rollback guidance in `ship.md`: revert in descending `ship_order`.

### 1.6 Claim, context, and init

The claim lock moves with the specs directory to the workspace root; semantics are unchanged. The planner reads the workspace `CLAUDE.md` and each touched repo's `CLAUDE.md`. `/ag-init` gains a workspace interview: it looks for sibling git repositories, offers to declare them as members, and writes `workspace.md`; `bin/ag-doctor` checks that every member resolves and that its trunk exists.

## 2. Participants — who may perform and who may approve

### 2.1 The team file

`.agentile/team.md` names the people and agents in the loop and the policy for each stage:

```markdown
---
participants:
  lead:  { name: "A. Lead",  git: ["lead@example.com"], github: alead }
  po1:   { name: "B. Owner", email: "b.owner@example.com" }        # never opens a terminal
  coord: { name: "C. Coord", email: "c.coord@example.com" }
  dev1:  { name: "D. Dev",   git: ["d.dev@example.com"] }
  dev2:  { name: "E. Dev",   git: ["e.dev@example.com", "e@personal.example"] }
roles:
  owners: [po1]
  devs:   [lead, dev1, dev2]
  agents: [ag-planner, ag-builder, ag-reviewer]
stages:
  capture:    { perform: everyone }
  shape:      { perform: [owners, lead, coord], require: 2 }   # two of these must be present, e.g. an owner and a dev
  spec:       { perform: devs }
  prioritise: { perform: [coord, lead] }
  next:       { perform: [devs, agents] }
  plan:       { perform: [devs, ag-planner], approve: [lead] }
  build:      { perform: [devs, ag-builder] }
  verify:     { perform: [ag-reviewer, devs], approve: [lead, dev1] }
  ship:       { approve: [lead] }
  learn:      { perform: [lead], approve: [lead] }
---

# Team

Prose: working agreements — who covers for the lead, response-time
expectations on approvals, what "present at shaping" means.
```

The vocabulary is deliberately small:

- `perform` — who may run the stage. Accepts participant ids, role names, `everyone`, `humans`, `agents`.
- `approve` — who may sign off at that stage's human checkpoint. Only meaningful for stages that pause.
- `require` — for stages that are conversations (shaping), how many of the `perform` list must take part before the output counts as Ready.
- `notify` (optional) — where to tell people a checkpoint is waiting; resolved by the store (a comment or assignment) or by a `notify.md` playbook.

Absent `team.md`, every stage is `perform: everyone, approve: everyone`, which is today's behaviour.

### 2.2 Identity

Skills resolve the current participant deterministically with `bin/ag-whoami`: `AGENTILE_USER` if set; otherwise the git `user.email` of the workspace matched against `participants.*.git`; otherwise the store's authenticated account (section 3); otherwise `unknown`. Agents identify as their agent name. An `unknown` participant may still capture; any stage with an explicit `perform` or `approve` list refuses `unknown` and says why. Enforcement in the plugin is *soft*: it refuses and records, it cannot stop someone editing a markdown file. Hard enforcement is the store's job where the store has it (Jira and Azure DevOps workflow permissions, Airtable interface permissions), which is one of the reasons to use a store for a mixed team.

### 2.3 Recording

The spec's frontmatter becomes the accountability record:

```yaml
captured_by: po1
shaped_by: [po1, lead]
prioritised_by: coord
plan_approved_by: lead        # set when the plan pause is released
verified_by: [ag-reviewer, dev1]
ship_approved_by: lead
learn_approved_by: lead
```

`/ag-retro` reports on these fields (who approved what, how long checkpoints waited) alongside the timing fields it already uses.

### 2.4 Checkpoints with named approvers

The loop's pauses are unchanged in shape; what changes is *whose* "approved" releases them. When a stage has an `approve` list:

- If the current session's participant is on the list, "approved" in the session releases the pause and records them.
- If not, the loop pauses, records that approval is pending, notifies per `notify`, and ends the turn. The pause is released when an allowed approver either resumes the session (`claude --resume`) and approves, or, with a store configured, sets the approval in the tool (a transition or field change by that person — section 3.6). `/ag-loop` checks pending approvals on each pass and under `/loop` this is the poll.

The existing `human_checkpoint: true` playbook directive is preserved and now means "pause for anyone on this stage's `approve` list", falling back to anyone when `team.md` is absent.

### 2.5 Roles and the methodology

This adds nothing to the loop. It makes explicit what the methodology already says: shaping is a conversation between the person who wants the outcome and the person who will build it; prioritisation is editorial and belongs to whoever owns the order; approval belongs to a named accountable person. The `methodology.md` line "a named person approves the plan and signs off before anything ships" becomes literally enforceable.

## 3. Stores — where the backlog lives

### 3.1 The interface

A store is anything that can hold stubs and specs and answer these operations. The list is the whole contract; adapters implement all of it or declare which operations they cannot honour:

| Operation | Meaning |
|---|---|
| `inbox list` / `inbox add <text>` / `inbox drop <id>` | stubs |
| `spec list [--status] [--claimable]` / `spec read <id>` / `spec write <id> <markdown>` | specs, always exchanged as canonical spec markdown |
| `spec create <markdown>` | a shaped spec enters the store |
| `rank <ordered ids>` | the editorial order (today: rename to `NNNN-` prefixes) |
| `claim <session> [label] [wip]` / `release <id>` | the transactional pull; returns the path or `NONE`, `WIP_FULL`, `BLOCKED`, `UNPRIORITISED` exactly as `bin/ag-claim` does today |
| `ship <id> <shipped-map>` / `abandon <id> <reason>` | terminal transitions |
| `deps <id>` / `dependents <id>` | the dependency graph |
| `attach <id> <file>` / `link <id> <url>` | plans and supporting material |
| `approve <id> <stage> [--by <participant>]` / `approvals <id>` | named approvals (section 2) |
| `comment <id> <text>` | notification surface |
| `whoami` | the store's authenticated account, for identity resolution |
| `doctor` | connectivity, schema, and mapping check |
| `migrate <from> <to>` | move a backlog between stores |

`bin/ag-store` is a Ruby CLI that dispatches to an adapter. **Every skill and agent stops touching backlog files directly and calls `bin/ag-store` instead.** The `local` adapter reproduces today's behaviour byte for byte (same paths, same prefixes, same `done/` and `abandoned/` moves, same file lock), so the refactor is behaviour-preserving and testable against the existing layout. `bin/ag-claim` and `bin/ag-dependents` become the `local` adapter's implementation of `claim` and `dependents`.

### 3.2 Configuration and setup packs

`.agentile/store.md` selects the store; a pack file holds the mapping:

```markdown
---
store: airtable            # local | airtable | jira | azure-devops
plans: repo                # repo (default) | store — where plan.md and supporting files live
---
```

Packs ship in the plugin under `templates/stores/<name>/` and are scaffolded to `.agentile/stores/<name>.md` by `/ag-init --store <name>` or `/ag-customise store`. Each pack contains: the mapping template, a `doctor` check, a provisioning script where the tool's API allows creating fields (Airtable can; Jira and Azure DevOps mostly print what an admin must create), and a short README. Credentials are environment variables named in the pack (`AGENTILE_JIRA_TOKEN`, `AGENTILE_ADO_PAT`, `AGENTILE_AIRTABLE_TOKEN`) and are never written to the repo.

### 3.3 The mapping model

The canonical spec maps onto a tool the same way in every pack, with the pack naming the tool-specific fields:

| Canonical | Jira | Azure DevOps | Airtable |
|---|---|---|---|
| stub | issue of type *Idea* in status *Captured*, or a dedicated *Inbox* filter | work item type *Idea* | *Inbox* table row |
| spec body | description | description | long-text field |
| `status` | workflow states mapped in the pack (`ready`, `in_progress`, `shipping`, `shipped`, `abandoned`) | states | single-select |
| rank (`NNNN`) | Jira rank field or a numeric custom field | backlog priority / stack rank | number field, plus a view sorted by it |
| `depends_on` | issue links of type *blocks* | *Predecessor* links | linked-record field |
| `route`, `business_value`, `technical_certainty`, `repos` | custom fields or labels | fields or tags | single-select and multi-select |
| claim (`claimed_by`, `claimed_at`, `label`) | assignee plus a custom *Session* field | assignee plus field | text fields |
| approvals | transitions performed by an allowed account, or checkbox custom fields | field changes with revision author | checkbox fields, with *last modified by* as the approver |
| `shipped`, `shipped_at`, `superseded_by` | fields set at ship; resolution *Done* | fields; state *Closed* | fields |

The pack documents which of these the tool enforces itself (workflow permissions, required fields) and which are Agentile's soft checks.

### 3.4 Plans and code-adjacent material

`plan.md`, `findings.md`, and ADRs are reviewed as diffs, so by default they stay in the workspace repo under the spec's directory and the store holds a link (`plans: repo`). `plans: store` attaches them to the issue instead, for teams that want everything in one tool. ADRs always live in the repo; they are architecture, not backlog.

### 3.5 Concurrency and truth

The store is the single source of truth; there is no local cache in v1. If the store is unreachable the skill stops with a clear error rather than falling back to files, because a silent fallback forks the backlog. Claim guarantees differ by adapter and are stated honestly in each pack:

- `local` — file lock, per checkout, as today.
- `jira` — a transition to *In progress* with assignee set, then a re-read; if the re-read shows a different session id, the claim is lost and the caller retries the next item.
- `azure-devops` — optimistic concurrency on the work item revision; a conflict is a lost claim.
- `airtable` — read, conditional update on the `claimed_by` field being empty, re-read to confirm. Airtable has no server-side conditional write, so two claims within the same second can both appear to succeed; the re-read plus a random back-off makes this rare, and the pack says so.

### 3.6 Approvals from people who never open Claude

This is the reason a mixed team wants a store. A product owner shapes in an Airtable form or a Jira issue; a lead approves a plan by ticking a field or moving a card. `bin/ag-store approvals <id>` reads those back with the acting account, `bin/ag-whoami` maps the account to a participant, and the loop's checkpoint (section 2.4) is released only if that participant is on the stage's `approve` list.

### 3.7 Visibility and other clients

Because every read goes through `bin/ag-store`, anything that wants to show the loop's state reads the same interface: `/ag-retro`, a progress page, the Omarchy board app (which becomes a thin client rather than a file parser), and, with a tool store, the tool's own views. An Airtable interface or a Jira board is the free progress dashboard.

## 4. What changes in the plugin

| Component | Today | After |
|---|---|---|
| `bin/ag-claim`, `bin/ag-dependents` | file-based helpers called by skills | the `local` adapter inside `bin/ag-store` |
| `bin/ag-store` | — | new: store CLI with `local`, `airtable`, `jira`, `azure-devops` adapters |
| `bin/ag-whoami`, `bin/ag-worktree`, `bin/ag-doctor` | — | new deterministic helpers |
| All 13 skills | read and write backlog files directly | call `bin/ag-store`; consult `team.md` for `perform`/`approve`; consult `workspace.md` for repos |
| `ag-planner` | reads one repo | reads the workspace and every touched repo |
| `ag-builder` | one worktree | one worktree per touched repo via `bin/ag-worktree` |
| `ag-reviewer` | one repo's gates | every touched repo's gates, combined diff |
| `format-on-edit`, `test-gate` | flat `gates.json` | per-repo `gates.json`; resolve the repo from the path |
| `/ag-init` | scaffolds one repo | adds the workspace interview and `--store <name>` |
| `/ag-customise` | stage playbooks | also `store`, `team`, `workspace` |
| Templates | `.agentile/*` | plus `workspace.md`, `team.md`, `store.md`, `stores/<name>/` |
| `methodology.md` | "one trunk" | "one trunk per repo, one workspace"; "a named person approves" |

## 5. Backward compatibility

- No `workspace.md`: the workspace is the current repo, one implicit member, flat `gates.json`.
- No `team.md`: every stage is open to everyone; `human_checkpoint` means anyone.
- No `store.md`: the `local` adapter with today's paths and prefixes.
- Existing frontmatter fields keep their meaning; new fields are additive.
- `/ag-init` on an existing project changes nothing unless asked.

## 6. Phasing

Each phase ships independently and is invisible unless its file is present.

1. **Store abstraction, local only.** Introduce `bin/ag-store` with the `local` adapter, port every skill to it, and prove no behaviour change against the existing test scripts and a fixture backlog. This is the foundation for everything else and the largest single change.
2. **Workspaces.** `workspace.md`, per-repo gates, `bin/ag-worktree`, the multi-repo ship step, `bin/ag-doctor`, the init interview.
3. **Participants.** `team.md`, `bin/ag-whoami`, recorded approvals, named checkpoints, retro reporting.
4. **Airtable pack.** First because its API can provision the schema, it is the cheapest to test end to end, and it suits product owners who will never use a developer tool.
5. **Jira pack**, then **Azure DevOps pack.** Same mapping model; the packs differ in field provisioning, transitions, and concurrency guarantees.

## 7. Out of scope

- Atomic cross-repo ship (ordering, recording, and flags are the mitigation).
- Two stores at once, or two-way sync between a store and local files.
- Hard permission enforcement in the `local` store.
- Cross-workspace coordination and multi-team portfolio views.
- A general-purpose kanban UI in the plugin; tool stores bring their own.
- Offline operation against a tool store.

## 8. Open decisions

- **Default placement for multi-repo:** control repo or anchor repo. This spec recommends the control repo; `/ag-init` should offer both.
- **Is `repos:` mandatory on every spec in a workspace?** Proposed yes for workspaces with more than one member, so the builder never guesses.
- **Poll cadence for store-side approvals under `/loop`.** Proposed: check on every loop pass, self-paced; no push notifications in v1.
- **Agent identity strings.** Proposed `ag-planner`, `ag-builder`, `ag-reviewer` as participant ids reserved by the plugin.
- **Which adapter language.** Ruby, matching the existing `bin/` and hooks; each adapter uses the tool's REST API directly to avoid gem dependencies.
- **Rate limits.** Airtable and Jira both throttle; `bin/ag-store` should batch reads (`spec list` returns full specs in one call) and cache within a single invocation only.

## Appendix — a worked example

A product made of three repos (`api`, `web`, `scanner`) plus `infra`, built by a five-person team: a lead developer, two developers, a coordinator, and a product owner from the business who works in Airtable.

- The team creates a control repo `product-loop` beside the four code repos and runs `/ag-init` there, declaring the four members with `api` shipping before `web` and `scanner`.
- `team.md` gives capture to everyone, shaping to the owner plus any developer (`require: 2`), prioritisation to the coordinator, plan approval and ship approval to the lead.
- `store.md` selects `airtable`; the pack provisions *Inbox* and *Specs* tables and an interface. The owner captures and shapes from a form and a record view; developers run `/ag-shape` from the terminal against the same records.
- A developer runs `/loop /ag-loop`. It claims a spec touching `api` and `web`, plans across both, pauses because the spec is routed `foreground`, and posts a comment. The lead ticks *Plan approved* in Airtable that afternoon; the next loop pass sees it, builds in two worktrees on `ag/0007-…`, runs each repo's gates, has the reviewer check the combined diff including the regenerated client types, and pauses again before ship. The lead approves; `api` merges first, then `web`; both SHAs are recorded; the spec moves to done.
- `/ag-retro` at the end of the week reports cycle time, who approved what, and how long each approval waited, from the same records the owner sees in Airtable.
