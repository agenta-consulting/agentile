# Agentile Projects — design

**Date:** 2026-09-21
**Status:** approved in conversation, awaiting written review
**Scope:** a Rails web app that becomes Agentile's only backlog store, plus the plugin branch that talks to it. The factory daemon rewrite, an MCP layer and the website redo are follow-up specs (see §12).

## 1. Why

Agentile's Team store is an Airtable base per project, driven by `bin/ag-store` with a local-files adapter beside it. That gives shared visibility but no users, no roles, no transactions (claim and rank are read→check→patch), no dashboards, and business logic (map, flow, brief sync, dependency walks, checkpoint sequencing) living in a CLI. Runs and checkpoints exist as rows but nothing shows "which projects have a build waiting on me".

Agentile Projects replaces both adapters with one multi-user, multi-project app. Skills keep calling `ag-store`; the CLI becomes a thin HTTP client. Business logic moves server-side where it can be transactional, tested once, and augmented with Jev judgments.

## 2. Decisions taken

| Question | Decision |
|---|---|
| Sequencing | App + plugin branch first, cut over, then the website |
| Repo | Sibling repo `~/projects/agentile_projects` (not nested in the plugin repo) |
| Skill interface | REST JSON API, `ag-store` rewritten as HTTP client with the same subcommands and JSON output; services structured so an MCP layer is a later thin addition |
| Local vs app | Inbox, Specs, Outcomes, Checkpoints, Runs and the **brief** live in the app. `plan.md`, `SPEC.md` snapshot, findings, ADRs stay git-tracked in each project repo. `docs/agentile/brief.md` becomes a read-only copy refreshed by the plugin so `CLAUDE.md`'s `@docs/agentile/brief.md` import keeps working. `runs.md` is dropped (the app is the run log). |
| Roles | App-level `admin` (invites users). Per-project membership role: `owner` / `member` / `viewer` |
| Factory | App owns Runs and Checkpoints; the factory becomes a thin local daemon using the API (rewrite is a follow-up spec; this spec keeps the API sufficient for it) |
| Inbox assist | Tidy + classify, human confirms; exposed to `/ag-capture` too |
| Adapters | Local and Airtable adapters deleted; the app is the only store |
| Migration | `rails agentile:import[base_id,project_slug]` for any existing base |
| Stack | Copy of `~/projects/demo-app-practice-manager`: Rails 8.1, Ruby 3.4, SQLite, DaisyStack (Matestack 4 page classes + Vue sidecars, DaisyUI 5, Tailwind 4), Devise + `devise_invitable`, Pundit (new), solid_cable, Kamal to server1 |

## 3. Repos and branches

- **`~/projects/agentile_projects`** — new app. Bootstrapped by copying the practice-manager demo per DaisyStack's README (module rename, `vendor/matestack-ui-*` and `package.json` esbuild aliases copied verbatim, `bin/link-daisy-stack`, `bin/setup`). Own Kamal service.
- **`~/projects/agentile`** branch **`store/agentile-projects`** → plugin **0.20.0**. Merges to `main` once the cut-over check in §11 passes.
- **`~/lab/agentile_site`** — untouched by this spec.

## 4. Data model

All tables have Rails `id`, `created_at`, `updated_at`. Airtable field names map 1:1 to snake_case columns; select values are Rails enums with the same strings.

- **users** — Devise (`database_authenticatable`, `recoverable`, `rememberable`, `validatable`, `invitable`, `trackable`), `name`, `admin:boolean`, `git_email` (attribution fallback for imports).
- **api_tokens** — `user_id`, `name`, `token_digest` (SHA-256 of a random 32-byte token shown once), `last_used_at`, `revoked_at`. A user may hold several (one per machine).
- **projects** — `name`, `slug` (unique), `brief:text` (markdown), `trunk` (default `main`), `wip_limit:integer` (default 1), `archived_at`.
- **memberships** — `user_id`, `project_id`, `role` enum `owner|member|viewer`; unique on `(user_id, project_id)`. Creating a project makes its creator `owner`.
- **inbox_items** — `project_id`, `title`, `text`, `kind` enum `feature|bug|chore|spike`, `status` enum `open|shaped|dropped`, `captured_at`, `captured_by_id → users`, `serves_outcome_id → outcomes`, `suggested_kind`, `suggested_outcome_id`, `duplicate_of_id → inbox_items`, `duplicate_probability:float`.
- **outcomes** — `project_id`, `slug`, `title`, `status` enum `open|achieved|abandoned`, `rank:integer`, `claim`, `measure`, `stop_rule`, `notes`, `abandoned_reason` (text), `achieved_at`, `abandoned_at`, `created_by_id → users`. Unique `(project_id, slug)`.
- **specs** — `project_id`, `slug`, `title`, `status` enum `ready|in_progress|shipped|abandoned`, `kind` enum `feature|spike|bug|chore`, `route` enum `foreground|background|spike`, `business_value` / `technical_certainty` enum `high|medium|low`, `rank:integer` (null = unranked = unclaimable), `tags:json`, sections as text columns: `outcome`, `problem_why_now`, `acceptance_criteria`, `scope_in`, `scope_out`, `edge_cases`, `affected_areas`, `open_questions`, `verification`, `abandoned_reason`; `claimed_at`, `shipped_at`, `abandoned_at`, `claimed_by_session`, `claimed_by_user_id`, `label`, `captured_by_id`, `serves_outcome_id`, `source_inbox_item_id`, `needs_review:boolean`, `needs_review_reason`. Unique `(project_id, slug)`. Multi-select `Shaped By` becomes **spec_shapers** (`spec_id`, `user_id`). `Depends On` becomes **spec_dependencies** (`spec_id`, `depends_on_spec_id`, unique pair, same project enforced).
- **runs** — `project_id`, `spec_id`, `runner_id`, `session_id`, `status` enum `active|paused|shipped|failed|handed_over|closed`, `started_at`, `ended_at`, `last_event_at`, `detail`. Status is a real column: `paused` while the newest checkpoint is open; `closed` on `run_close`.
- **run_events** — `run_id`, `event` enum `started|claimed|shipped|paused|failed|idle|deployed|closed`, `at`, `detail`. Append-only.
- **checkpoints** — `run_id`, `spec_id`, `seq:integer` (server-assigned, unique per spec), `reason` enum `plan_review|build_blocked|build_checkpoint|gate_failure|verify_checkpoint|ship_approval|question`, `asked_by` (`plan|build|builder|reviewer|verify|ship`), `asked_at`, `session_id`, `status` enum `open|answered`, `ask`, `answer`, `answered_at`, `answered_by_id → users`, `priority` enum `needs_human|routine|unclear` (Jev), `ref` (display: `<slug> #NNN <reason>`).
- **judgments** — `subject_type/subject_id` (polymorphic), `purpose`, `request:json`, `response:json`, `tokens:integer`, `latency_ms`, `transport`. Every Jev call is recorded here for the "why" panel and for debugging.

### Concurrency

- **Claim** is one transaction: `SELECT … FOR UPDATE`-equivalent under SQLite's write lock — choose the lowest-rank `ready` spec in the project whose `spec_dependencies` are all `shipped` (or the named slug), check the project's active in-progress count against the requested WIP limit, then `UPDATE specs SET status='in_progress', claimed_by_session=?, claimed_by_user_id=?, claimed_at=?, label=? WHERE id=? AND status='ready'`. Zero rows affected → retry the selection once, then return `TAKEN`. Return codes match today's CLI: slug, or `WIP_FULL | BLOCKED | UNPRIORITISED | NONE | NOT_FOUND | TAKEN`.
- **Rank** writes all positions in one transaction; only `ready` specs may be ranked; unlisted ready specs keep their relative order after the listed ones.
- **Checkpoint seq** is `max(seq)+1` under the spec row's lock; opening a checkpoint also sets its run to `paused`. Answering sets the run back to `active` if no other open checkpoint remains.
- No `.pull.lock`, no `ag-lock` around claim. (`ag-lock` stays available for gate commands that touch shared state; that concern is unchanged.)

### Markdown contract

`spec_read` today returns canonical markdown (frontmatter + `## ` sections) and `spec_create` accepts it. The server owns `Spec#to_markdown` and `Spec.from_markdown` (ported from `bin/ag-store-adapters/airtable/schema.rb`'s `render_spec_markdown` / `parse_spec_markdown`), so skills that read or write specs as markdown are unaffected.

## 5. API

Base `/api/v1`. Auth: `Authorization: Bearer <token>`; the token's user and their project role drive Pundit. JSON in/out; markdown where noted. Every write emits on the project's push stream (§8).

Project-scoped routes under `/projects/:slug`:

| Today (`ag-store …`) | Endpoint |
|---|---|
| `inbox_list` | `GET /inbox` (open only; `?status=` for others) |
| `inbox_add <text> [--title --type --serves]` | `POST /inbox` |
| `inbox_drop <id>` | `POST /inbox/:id/drop` |
| *new* | `POST /inbox/assist` `{text}` → `{title, text, kind, serves_outcome_slug, duplicate_of, duplicate_probability, judgment_id}` — does not save |
| *new* | `POST /inbox/:id/shape` (markdown body) → creates the spec with `source_inbox_item`, `captured_by` copied, marks the stub `shaped`, records the caller in `spec_shapers` |
| `spec_list [--status --pool]` | `GET /specs?status=&pool=active\|done\|abandoned` — same JSON keys as today (`slug, prefix, path, status, title, created_at, business_value, technical_certainty, route, depends_on[], claimed_by, claimed_at, label, shipped_at, serves, tags[]`); `path` returns `docs/agentile/specs/<slug>` |
| `spec_read <id>` | `GET /specs/:slug` (JSON) · `GET /specs/:slug.md` (canonical markdown) |
| `spec_create <slug>` (stdin md) | `POST /specs` (markdown body, `text/markdown`) |
| `spec_write <id> --set k=v` | `PATCH /specs/:slug` `{field: value, …}`; list fields accept arrays |
| `rank <slug>…` | `PUT /specs/rank` `{slugs: […]}` |
| `claim <identity> [label] [wip] [--spec]` | `POST /specs/claim` `{identity, label, wip, slug}` → `{result: "<slug>" \| "WIP_FULL" …, run_id}` (claiming opens a Run) |
| `release` / `ship` / `abandon --reason` | `POST /specs/:slug/release`, `/ship`, `/abandon {reason}` — cascade options for abandon: `{cascade: [slugs]}` |
| `deps` / `dependents` | `GET /specs/:slug/deps`, `GET /specs/:slug/dependents` (transitive, active only) |
| `map` | `GET /map` |
| `flow [<slug>]` | `GET /flow`, `GET /flow/:slug` |
| `outcome_list/read/create/write` | `GET /outcomes`, `GET /outcomes/:slug`, `POST /outcomes`, `PATCH /outcomes/:slug` |
| `outcome_rank` / `achieve` / `abandon` | `PUT /outcomes/rank`, `POST /outcomes/:slug/achieve`, `/abandon {reason}` |
| `checkpoint_open <slug> <reason> --session --by` (stdin ask) | `POST /runs/:id/checkpoints` `{reason, asked_by, session_id, ask}` → `{id, seq, ref}` |
| `checkpoint_list <slug>` / `checkpoint_open_count` | `GET /specs/:slug/checkpoints` (oldest first, same keys as today) |
| `checkpoint_answer <id> --by` (stdin answer) | `POST /checkpoints/:id/answer` `{answer, by}` |
| `run_event <event> --spec --runner --detail` | `POST /runs` `{spec, runner_id, session_id}` (start; also done implicitly by claim) and `POST /runs/:id/events` `{event, detail}` |
| `run_list [--spec --status]` | `GET /runs?spec=&status=` |
| `run_close` | `POST /runs/:id/close` |
| `brief_sync` | `GET /brief` → markdown of the project brief with `## Prioritised outcomes` regenerated from open outcomes by rank |
| `doctor` | `GET /doctor` → `{project, role, reachable: true}` |

Unscoped: `GET /me` → `{user_id, name, email, projects: [{slug, role}]}` (replaces `whoami`). Project creation stays in the web UI for now; `/ag-init` links an existing project.

Errors: 401 bad token, 403 role, 404 unknown project/slug, 409 state conflict (e.g. ranking a non-ready spec), 422 validation — all `{error, detail}`. `ag-store` prints `detail` to stderr and exits non-zero, as today.

## 6. Plugin branch `store/agentile-projects` (0.20.0)

- `.agentile/store.md`:
  ```yaml
  ---
  url: https://agentile-projects.agentaconsulting.com
  project: tekmore
  ---
  ```
  Token from `AGENTILE_PROJECTS_TOKEN` (env, never a tracked file). `AGENTILE_PROJECTS_URL` env overrides `url` for local development.
- `bin/ag-store` → one Ruby file (`Net::HTTP`, `json`), same subcommand names, args and JSON stdout, mapping 1:1 to §5. `whoami` calls `/me`. `--store`/`--airtable-base` flags removed. Subcommands `provision`, `create_base` removed; `doctor` kept.
- Deleted: `bin/ag-store-adapters/`, `bin/ag-claim`, `bin/ag-checkpoint`, `bin/ag-dependents`, `templates/stores/`, `templates/inbox.md`, `templates/agentile/runs.md`, `dev/test-ag-store-{local,airtable}.rb`, `dev/test-ag-claim.rb`, `dev/test-ag-checkpoint.rb`, `dev/test-ag-dependents.rb`.
- Skills:
  - `/ag-init` — asks for the project slug (or lists the user's projects from `/me`), checks the token, writes `store.md`, refreshes `brief.md`, creates only `docs/agentile/specs/` and `docs/adr/`. No inbox.md, runs.md, `specs/done|abandoned`, `.pull.lock`, `ag-lock` wrapping. Team/Solo question removed. `CLAUDE.agentile-section.md` rewritten for the single store.
  - `/ag-capture` — `POST /inbox/assist`, shows the tidied stub and suggestions, saves on confirmation (a `--yes`/no-questions path saves the raw line with suggestions attached, keeping capture instant).
  - `/ag-shape` — writes the spec via `/inbox/:id/shape`.
  - `/ag-build`, `/ag-next`, `/ag-wip` — use the `run_id` returned by claim for checkpoints and events; the `AG_BUILD: <outcome> <slug> [reason] [checkpoint-id]` line is unchanged.
  - Every `/ag-*` skill refreshes `docs/agentile/brief.md` from `GET /brief` at start (cheap, keeps the CLAUDE.md import current).
  - `/ag-outcome` no longer calls `brief_sync`; the brief is edited in the app.
- Docs: `README.md`, `methodology.md`, `docs/agentile-workspaces-participants-and-stores.md`, `docs/agentile-factory.md` §7/§9, `CHANGELOG.md` updated; `hooks/test-gate.rb` hint text updated.
- Version bump to 0.20.0 in `.claude-plugin/plugin.json` and `/ag-version`.

## 7. Web UI

DaisyStack page classes under `app/matestack/web/`, shell copied from the demo (sidebar drawer, top bar with theme toggle and account menu, flash toasts).

- **Home dashboard** `/` — one card per project the user belongs to: role pill; counts (open inbox, ready, in progress, shipped last 7 days); **attention badge** = open checkpoints + failed runs; "next up" (top ranked claimable spec). Subscribes to `user:<id>`; the server emits there for every project the user belongs to.
- **Project dashboard** `/projects/:slug` — stat tiles (queue depth, WIP vs limit, shipped 7d/30d, median lead time from `flow`); **Attention** list (open checkpoints with ask and an inline answer form; failed/crashed runs); **In progress** (spec, runner, session, since, last event); **Up next** (ranked ready specs with dependency state); recent run events; brief excerpt with edit link (owner). Subscribes to `project:<slug>`.
- **Resources** (`DataPage::Resource`, controller `include DataPages`, routes `daisy_stack_pages`): Inbox (grid; capture form with an assist panel that calls `/inbox/assist` and fills the fields); Specs (grid by status; detail with sections, dependencies, checkpoints, runs; ready view has a rank editor); Outcomes (grid/detail with served specs); Runs (grid/detail with events and checkpoints); Checkpoints (attention-first grid); Members (owner: invite by email, role select, remove); Project settings (brief editor, WIP limit, trunk, archive). Personal settings: API tokens (create with name, shown once, revoke). Admin: users (invite, admin flag) — copied from the demo.
- **Colour system** — `Web::Colors` is the single source; every pill (`ds_badge`), grid `format: :badge`, stat tile and chart series reads it. `application.tailwind.css` carries the `@source inline(...)` safelist for the badge classes.

  | Concept | Value → colour |
  |---|---|
  | Spec status | `ready` info · `in_progress` primary · `shipped` success · `abandoned` neutral |
  | Route | `spike` **accent** · `foreground` warning · `background` info |
  | Kind | `feature` primary · `bug` error · `chore` neutral · `spike` **accent** |
  | Value / certainty | `high` success · `medium` warning · `low` error |
  | Role | `owner` primary · `member` info · `viewer` neutral |
  | Checkpoint reason | `ship_approval`, `plan_review` warning · `gate_failure`, `build_blocked` error · `build_checkpoint`, `verify_checkpoint` info · `question` info |
  | Checkpoint priority | `needs_human` error · `unclear` warning · `routine` neutral |
  | Run status | `active` success · `paused` warning · `failed` error · `shipped` success · `handed_over` info · `closed` neutral |
  | Inbox status | `open` info · `shaped` success · `dropped` neutral |
  | Outcome status | `open` info · `achieved` success · `abandoned` neutral |

  Theme: two DaisyUI themes declared in CSS — a warm slate light theme and a charcoal dark theme (distinct from the demo's Catppuccin/Tokyo Night and the site's Nord/agenta-dark), hairline flat cards, IBM Plex Sans + JetBrains Mono as in the demo.

## 8. Realtime

- `DaisyStack::Push.emit(event, {}, to: "project:<slug>")` after every API and UI write, coalesced per request; payload-free, pages re-read (`async rerender_on:`), matching the factory's pattern.
- Events: `inbox_changed`, `specs_changed`, `outcomes_changed`, `runs_changed`, `checkpoint_opened`, `checkpoint_answered`. `checkpoint_opened` also emits on each member's `user:<id>` stream and shows a `toggle`-driven toast.
- `DaisyStack::Push::Channel` subclassed: `project:<slug>` requires membership; `user:<id>` requires `current_user.id == id`.
- Cable adapter: `solid_cable` in production, `async` in development/test.

## 9. Jev and RubyLLM

- `app/services/jev.rb` copied from Jev Lab (`Jev.ask`, `Jev.record` → `judgments`, `FakeTransport`, `JEV_FAKE=1`), gems `ruby_decision_model`, `decide`, `feelings`. `app/services/llm.rb` wraps `ruby_llm` (model configurable; default the latest Claude Sonnet) with a stub in test.
- **Capture assist** (`POST /inbox/assist`, also used by the web form): RubyLLM rewrites the raw line into `title` + one-paragraph `text` (no invention beyond the line); then one Jev request over `{text, outcomes, recent_items}`: `kind` Choice (feature/bug/chore/spike + "unclear"), `serves_outcome` Choice over open outcome slugs + "none", `duplicate` Noul against the ten most recent open stubs and ready specs (title + first line). Thresholds in Ruby: apply `kind` only ≥ 0.6, outcome only ≥ 0.6, show duplicate warning ≥ 0.5. Suggestions are returned and, on save, stored on the stub.
- **Checkpoint triage** (on open): Jev Choice `needs_human / routine / unclear` over `{reason, asked_by, ask}` → `priority`; orders the attention list. Never auto-answers. `fail_mode: :open` (an outage yields `unclear`).
- **Claim-time sanity** (`Decide::Decision`, `fail_mode: :closed`): Noul "are the acceptance criteria concrete and verifiable?" over the spec sections; below floor 0.6 → `needs_review = true` with the reason. Shown as a pill on the dashboard and detail; does not block claiming.
- All calls are asynchronous where latency would block a write (checkpoint triage and claim sanity run in an `ActiveJob` on the async adapter and emit a push when done); capture assist is synchronous because the user is waiting for it.

## 10. Auth, roles, import, hosting, testing

**Auth.** Devise + `devise_invitable` exactly as the demo: no public registration; admins invite from `/admin/users`; accept sets a password. Project owners add existing users by email (admins can invite-and-add). Pundit policies: `ProjectPolicy` (`show?` member/viewer/owner; `update?`, `manage_members?`, `archive?` owner), `InboxItemPolicy`/`SpecPolicy`/`OutcomePolicy`/`CheckpointPolicy`/`RunPolicy` (`index?/show?` any role; create/update/transition owner or member), `ApiTokenPolicy` (own only), `UserPolicy` (admin). `DataPage::Resource#scoped_collection` and `find_object` use `policy_scope`. API controllers `include Pundit::Authorization` and resolve `current_user` from the bearer token.

**Import.** `bin/rails "agentile:import[base_id,project_slug]"` using the existing Airtable schema knowledge (ported from the adapter, kept only in the app): creates/finds the project, maps Members → users by `email`/`git_email` (unknown emails become invited users), then Outcomes, Inbox, Specs (dependencies resolved after all specs exist, ranks preserved), Checkpoints (seq from `Seq`), Runs/RunEvents (grouped by `(spec, runner)`). Idempotent on `(project, slug)`, checkpoint `ref`, and run event `(spec, runner, at, event)`. Requires `AGENTILE_AIRTABLE_TOKEN`. Targets: `app2UtMqMAvvqvbMF` (practice manager), Tekmore's base.

**Hosting.** Dockerfile (arm64, Node for esbuild/Tailwind), Kamal `config/deploy.yml`: service `agentile-projects`, image `keithrowell/agentile-projects`, server `server1.agentaconsulting.com`, proxy host `agentile-projects.agentaconsulting.com` with SSL, volume `agentile-projects-storage:/rails/storage` (SQLite, cache, cable), `SOLID_QUEUE_IN_PUMA=false` and the async job adapter. Secrets: `RAILS_MASTER_KEY`, `KAMAL_REGISTRY_PASSWORD`, `TYPESAFE_API_KEY`, `ANTHROPIC_API_KEY`.

**Testing.** Minitest. Models: claim (two threads, one wins; WIP limit; blocked deps; named slug), rank, dependents BFS, flow metrics, checkpoint seq and run status transitions, markdown round-trip. Policies: one test per role per policy. API integration: every endpoint in §5 with the cases from `dev/test-ag-store-airtable.rb`. Jev/LLM: `FakeTransport` and stubbed RubyLLM; suite runs keyless. System (Capybara): sign in via invitation, capture with assist, answer a checkpoint from the project dashboard and see the run resume state, home dashboard attention badge. Plugin branch: `dev/test-ag-store-http.rb` runs `bin/ag-store` against a local app on a test project.

## 11. Cut-over check (definition of done)

From a fresh clone of `demo-app-practice-manager` on plugin branch `store/agentile-projects`, with the app running (local or hosted) and its base imported:

1. `/ag-init` links the clone to the project and refreshes `brief.md`.
2. `/ag-capture` shows assist suggestions and saves a stub; it appears live in the web Inbox.
3. `/ag-shape` turns it into a `ready` spec; `/ag-prioritise` ranks it.
4. `/ag-build` claims it (a Run appears as active on both dashboards), plans, builds, and pauses at `ship_approval` — both dashboards show the project as needing attention.
5. The checkpoint is answered in the web UI; `claude --resume <session>` ships; the run shows `shipped`, the spec `shipped`.
6. `agentile` and `demo-app-practice-manager` switch their `store.md` to the app; the plugin branch merges to `main` as 0.20.0.

## 12. Out of scope (follow-up specs)

- Factory daemon rewrite against the API (API here is sufficient: runs, run events, checkpoints, claim).
- MCP layer over the same service objects (`fast-mcp`).
- Website redo (`~/lab/agentile_site`) — two-loop narrative, once the product is real.
- Editing `gates.json`/playbooks in the web UI; attachments; project creation via API; SSO.
