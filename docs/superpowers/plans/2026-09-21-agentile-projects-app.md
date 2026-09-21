# Agentile Projects (Rails app) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `~/projects/agentile_projects`, the multi-user, multi-project Rails app that becomes Agentile's only backlog store: Inbox, Specs, Outcomes, Runs, Checkpoints and the brief behind a bearer-token REST API, with DaisyStack dashboards, Pundit roles, Jev/RubyLLM assistance, live push, and an Airtable importer.

**Architecture:** A copy of `~/projects/demo-app-practice-manager` (Rails 8.1 + DaisyStack/Matestack 4 + DaisyUI 5 + SQLite + Devise invitable + Kamal). Every screen is a Ruby page class; every data section is a `DataPage::Resource`. Business logic lives in `app/services/**` service objects (transactional claim/rank/checkpoints/runs, flow, map, brief), which both the `Api::V1::*` controllers and the web pages call. Every write emits `DaisyStack::Push.emit` on `project:<slug>` / `user:<id>` streams. Jev calls go through one door (`Jev.ask`) and are recorded in `judgments`; RubyLLM through `Llm.chat`.

**Tech Stack:** Ruby 3.4.6, Rails 8.1.3, SQLite, propshaft, esbuild + Tailwind v4 CLI, DaisyStack (git gem) + vendored `matestack-ui-core`/`matestack-ui-vuejs` 4.0.0.beta1, DaisyUI 5, Vue 3.5, Devise 5 + devise_invitable 2, Pundit 2.5, ruby_llm 2.0, ruby_decision_model 0.1 + decide 0.0.1 + feelings 0.1, solid_cable, solid_cache, minitest + Capybara/Selenium + WebMock, Kamal.

**Spec:** `docs/superpowers/specs/2026-09-21-agentile-projects-design.md` (in `~/projects/agentile`). Read it first; §4 (data model), §5 (API), §7 (UI + colours), §8 (push), §9 (Jev/LLM), §10 (auth/import/hosting/testing).

## Global Constraints

- Rails `~> 8.1.3`, Ruby `3.4.6`, SQLite `>= 2.1`, `gem "json", "< 3"` pin kept (json 3 breaks AS 8.1.3 cookie sessions and JSON bodies).
- DaisyStack idiom: every screen is a `DaisyStack::Ui::Page` / `DataPage::Resource` class under `app/matestack/web/`; no ERB beyond the HTML shell; every form is `matestack_form` (never bare `form`); `ds_*` names are reserved for the gem — app components register bare names.
- `vendor/matestack-ui-core`, `vendor/matestack-ui-vuejs` and the esbuild alias flags in `package.json` are copied verbatim from the demo; `bin/link-daisy-stack` must run before any asset build.
- No SolidQueue polling: `SOLID_QUEUE_IN_PUMA: false` in `config/deploy.yml`, `config.active_job.queue_adapter = :async` in production; `:test` adapter in test.
- Pundit on every controller: `ApplicationController` and `Api::V1::BaseController` both `include Pundit::Authorization` with `after_action :verify_authorized` (web CRUD controllers verify via `authorize` in the DataPages concern; `verify_policy_scoped` on index).
- `Web::Colors` (`app/matestack/web/colors.rb`) is the only source of pill/tile colours; the spec §7 table is copied there verbatim and every `ds_badge`/`format: :badge`/stat colour reads it.
- Every Jev call is recorded in the `judgments` table via `Jev.ask` (no direct `RubyDecisionModel::Client` use outside `app/services/jev.rb`).
- Test suite is keyless and deterministic: `Jev.transport = Jev::FakeTransport.new` in `test_helper.rb`, `Llm.client = Llm::Fake.new`, `WebMock.disable_net_connect!(allow_localhost: true)`.
- Spec select values are Rails string enums with exactly the spec's strings (`ready in_progress shipped abandoned`, etc.).
- Timestamps in API JSON are ISO-8601 UTC `%Y-%m-%dT%H:%M:%SZ`, matching `ag-store` today.
- Commit after every task with a message in the form `<area>: <what>` (e.g. `models: add specs and dependencies`).
- Cross-plan wire contract: the plugin's `bin/ag-store` (plan `2026-09-21-agentile-plugin-store-http.md`) is the reference client. These keys are load-bearing and must not be renamed: run rows carry `runner_id` (the client picks its own active run by it via `GET /runs?spec=&status=active`); `POST /inbox` reads `kind` (`type` accepted as a fallback) and `serves` (outcome slug); `POST /specs/claim` returns `{result, run_id}`; `GET /outcomes/:slug.md` serves canonical markdown like specs; `POST /specs/:slug/abandon` accepts `{reason, cascade: [slugs]}`; `POST /runs` accepts `{spec, runner_id, session_id}`; every error body is `{error, detail}`.

---

### Task 1: Bootstrap the app from the Practice Manager demo

**Files:**
- Create: `~/projects/agentile_projects/` (copy of `~/projects/demo-app-practice-manager`)
- Modify: `config/application.rb`, `Gemfile`, `package.json`, `app/matestack/web/layout.rb`, `app/matestack/web/auth_layout.rb`, `app/assets/stylesheets/application.tailwind.css`, `db/seeds.rb`, `README.md`
- Create: `app/matestack/web/colors.rb`, `test/models/web_colors_test.rb`
- Delete: practice-manager domain code (see Step 3)

**Interfaces:**
- Produces: module `AgentileProjects`; `Web::Colors.for(concept, value) -> Symbol` and the constant hashes `Web::Colors::SPEC_STATUS`, `ROUTE`, `KIND`, `LEVEL`, `ROLE`, `CHECKPOINT_REASON`, `CHECKPOINT_PRIORITY`, `RUN_STATUS`, `INBOX_STATUS`, `OUTCOME_STATUS`; themes `agentile-light` / `agentile-dark`.

- [ ] **Step 1: Copy the demo and re-init git**

```bash
cp -r ~/projects/demo-app-practice-manager ~/projects/agentile_projects
cd ~/projects/agentile_projects
rm -rf .git storage/*.sqlite3 tmp/* log/* node_modules app/assets/builds/* vendor/daisy_stack
git init -b main
bundle config set --local github.com "x-access-token:$(gh auth token)"
```

- [ ] **Step 2: Rename the app module**

`config/application.rb`: replace `module PracticeManager` with `module AgentileProjects`. `package.json`: `"name": "agentile_projects"`. Grep and fix the remaining references:

```bash
grep -rl "PracticeManager\|practice_manager\|practice-manager\|Practice Manager" --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git . 
```

Replace each with `AgentileProjects` / `agentile_projects` / `agentile-projects` / `Agentile Projects` (config/deploy.yml and .kamal/secrets are rewritten fully in Task 14; fix names only now).

- [ ] **Step 3: Remove the practice-manager domain**

Delete these files and directories (they are the demo's domain, not ours):

```bash
git rm -rq --cached . 2>/dev/null; true
rm -rf app/models/{client,contact,project,time_entry,expense,invoice,invoice_item,setting,dashboard_metrics}.rb \
  app/controllers/{clients,projects,time_entries,expenses,invoices,invoice_items,contacts,about}_controller.rb \
  app/controllers/projects app/controllers/admin/settings_controller.rb \
  app/matestack/web/resources/*.rb app/matestack/web/pages/{clients,expenses,invoices,time_entries,about.rb} \
  app/matestack/web/pages/admin/settings* app/matestack/web/components/*.rb \
  app/javascript/{description_advisory_input,category_suggestion_input}.js \
  db/migrate/* db/schema.rb test/fixtures/{clients,expenses,invoice_items,invoices,projects,settings,time_entries}.yml \
  test/models/{dashboard_metrics_test,invoice_test}.rb test/controllers/*.rb test/system/*.rb test/integration/*.rb
```

Keep: `app/models/user.rb` (edit below), `app/models/application_record.rb`, `app/controllers/{application,dashboard}_controller.rb`, `app/controllers/admin/users_controller.rb`, `app/controllers/users/*`, `app/controllers/account/*`, `app/controllers/concerns/data_pages.rb`, `app/matestack/web/{layout,auth_layout}.rb`, `app/matestack/web/pages/{dashboard.rb,auth/*,account/*,admin/users*}`, `app/services/jev_client.rb` (deleted in Task 10 when `Jev` replaces it), `app/javascript/application.js` (edit below), `bin/*`, `vendor/matestack-ui-*`, `config/*`, `test/test_helper.rb`, `test/application_system_test_case.rb`, `test/fixtures/users.yml`.

Edit `app/models/user.rb` to only:

```ruby
class User < ApplicationRecord
  devise :invitable, :database_authenticatable, :recoverable, :rememberable, :validatable, :trackable

  validates :name, presence: true, unless: :invitation_pending?

  scope :ordered, -> { order(:name, :email) }

  def display_name
    name.presence || email
  end

  def initials
    display_name.split(/[\s@._-]+/).first(2).map { |w| w[0] }.join.upcase
  end

  def invitation_pending?
    invitation_token.present? && invitation_accepted_at.nil?
  end

  def status
    invitation_pending? ? "invited" : "active"
  end
end
```

Edit `app/javascript/application.js` to drop the two deleted sidecar imports/registrations (keep `dsApexChart` and `dsPush`). Edit `app/matestack/web/pages/dashboard.rb` to a placeholder page (rewritten in Task 11):

```ruby
class Web::Pages::Dashboard < DaisyStack::Ui::Page
  def response
    ds_page_header title: "Dashboard", icon: "squares-2x2"
  end
end
```

Edit `config/routes.rb` to:

```ruby
Rails.application.routes.draw do
  devise_for :users, path: "", controllers: {
    sessions: "users/sessions",
    passwords: "users/passwords",
    invitations: "users/invitations"
  }

  root "dashboard#index"

  namespace :admin do
    daisy_stack_pages :users do
      member { patch :resend_invitation }
    end
  end

  namespace :account do
    resource :profile, only: [ :show, :update ]
    resource :password, only: [ :show, :update ]
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

Replace `db/seeds.rb` with:

```ruby
admin = User.find_or_initialize_by(email: ENV.fetch("ADMIN_EMAIL", "admin@agentaconsulting.com"))
admin.name ||= "Admin"
admin.admin = true
admin.password = ENV.fetch("ADMIN_PASSWORD", "changeme123") if admin.new_record?
admin.save!
puts "Admin: #{admin.email}"
```

- [ ] **Step 4: Add the new gems**

In `Gemfile`, after `gem "devise_invitable"`:

```ruby
# Authorization: per-project roles (owner/member/viewer) and the admin flag
gem "pundit", "~> 2.5"
# Generative LLM calls (capture assist tidy-up)
gem "ruby_llm", "~> 2.0"
```

Replace the `ruby_decision_model` git line with the released gems (the Jev Lab stack):

```ruby
# Typed judgments (TypeSafe Jev): client, named decisions, feels DSL
gem "ruby_decision_model", "~> 0.1.0"
gem "decide", "~> 0.0.1"
gem "feelings", "~> 0.1.0"
```

Run `bundle install`, then `bin/link-daisy-stack`, `npm install`, `npm run build && npm run build:css`.

- [ ] **Step 5: Write the failing colour test**

`test/models/web_colors_test.rb`:

```ruby
require "test_helper"

class WebColorsTest < ActiveSupport::TestCase
  test "spike is the same colour as a route and as a kind" do
    assert_equal :accent, Web::Colors.for(:route, "spike")
    assert_equal :accent, Web::Colors.for(:kind, "spike")
  end

  test "unknown values fall back to neutral" do
    assert_equal :neutral, Web::Colors.for(:spec_status, "bogus")
    assert_equal :neutral, Web::Colors.for(:spec_status, nil)
  end

  test "every table covers the model's enum values" do
    assert_equal %w[ready in_progress shipped abandoned].sort, Web::Colors::SPEC_STATUS.keys.map(&:to_s).sort
    assert_equal %w[foreground background spike].sort, Web::Colors::ROUTE.keys.map(&:to_s).sort
    assert_equal %w[feature bug chore spike].sort, Web::Colors::KIND.keys.map(&:to_s).sort
    assert_equal %w[owner member viewer].sort, Web::Colors::ROLE.keys.map(&:to_s).sort
    assert_equal %w[plan_review build_blocked build_checkpoint gate_failure verify_checkpoint ship_approval question].sort,
                 Web::Colors::CHECKPOINT_REASON.keys.map(&:to_s).sort
    assert_equal %w[active paused failed shipped handed_over closed].sort, Web::Colors::RUN_STATUS.keys.map(&:to_s).sort
  end
end
```

- [ ] **Step 6: Run it to see it fail**

Run: `bin/rails test test/models/web_colors_test.rb`
Expected: FAIL with `uninitialized constant Web::Colors`

- [ ] **Step 7: Write `Web::Colors`**

`app/matestack/web/colors.rb`:

```ruby
# The single source of every pill, tile and chart colour. One concept, one
# DaisyUI brand colour, everywhere it appears (spec §7).
module Web::Colors
  SPEC_STATUS = { ready: :info, in_progress: :primary, shipped: :success, abandoned: :neutral }.freeze
  ROUTE = { spike: :accent, foreground: :warning, background: :info }.freeze
  KIND = { feature: :primary, bug: :error, chore: :neutral, spike: :accent }.freeze
  LEVEL = { high: :success, medium: :warning, low: :error }.freeze
  ROLE = { owner: :primary, member: :info, viewer: :neutral }.freeze
  CHECKPOINT_REASON = { ship_approval: :warning, plan_review: :warning,
                        gate_failure: :error, build_blocked: :error,
                        build_checkpoint: :info, verify_checkpoint: :info, question: :info }.freeze
  CHECKPOINT_PRIORITY = { needs_human: :error, unclear: :warning, routine: :neutral }.freeze
  RUN_STATUS = { active: :success, paused: :warning, failed: :error, shipped: :success,
                 handed_over: :info, closed: :neutral }.freeze
  INBOX_STATUS = { open: :info, shaped: :success, dropped: :neutral }.freeze
  OUTCOME_STATUS = { open: :info, achieved: :success, abandoned: :neutral }.freeze

  TABLES = {
    spec_status: SPEC_STATUS, route: ROUTE, kind: KIND, level: LEVEL, role: ROLE,
    checkpoint_reason: CHECKPOINT_REASON, checkpoint_priority: CHECKPOINT_PRIORITY,
    run_status: RUN_STATUS, inbox_status: INBOX_STATUS, outcome_status: OUTCOME_STATUS
  }.freeze

  def self.for(concept, value)
    TABLES.fetch(concept)[value.to_s.to_sym] || :neutral
  end
end
```

- [ ] **Step 8: Define the two themes and the shell brand**

In `app/assets/stylesheets/application.tailwind.css` replace the `@plugin "daisyui" { themes: ... }` block and both `@plugin "daisyui/theme"` blocks with:

```css
@plugin "daisyui" {
  themes: agentile-light --default, agentile-dark --prefersdark;
}

/* Warm slate light / charcoal dark. accent is reserved for "spike". */
@plugin "daisyui/theme" {
  name: "agentile-light";
  default: true;
  prefersdark: false;
  color-scheme: light;
  --color-base-100: #f6f4f0;
  --color-base-200: #ece9e3;
  --color-base-300: #d6d1c8;
  --color-base-content: #2f3136;
  --color-primary: #2f5d8a;
  --color-primary-content: #ffffff;
  --color-secondary: #6b7b8c;
  --color-secondary-content: #ffffff;
  --color-accent: #9a4f9e;
  --color-accent-content: #ffffff;
  --color-neutral: #5d6068;
  --color-neutral-content: #f6f4f0;
  --color-info: #2a7f9e;
  --color-info-content: #ffffff;
  --color-success: #3f8a4f;
  --color-success-content: #ffffff;
  --color-warning: #c27c1a;
  --color-warning-content: #ffffff;
  --color-error: #b93b3b;
  --color-error-content: #ffffff;
  --radius-selector: 0.25rem;
  --radius-field: 0.375rem;
  --radius-box: 0.5rem;
  --size-selector: 0.25rem;
  --size-field: 0.25rem;
  --border: 1px;
  --depth: 0;
  --noise: 0;
}

@plugin "daisyui/theme" {
  name: "agentile-dark";
  default: false;
  prefersdark: true;
  color-scheme: dark;
  --color-base-100: #1f2023;
  --color-base-200: #18191c;
  --color-base-300: #34363b;
  --color-base-content: #d7d4cd;
  --color-primary: #7fa7d1;
  --color-primary-content: #18191c;
  --color-secondary: #9aa8b8;
  --color-secondary-content: #18191c;
  --color-accent: #c78bcb;
  --color-accent-content: #18191c;
  --color-neutral: #45474d;
  --color-neutral-content: #d7d4cd;
  --color-info: #6fc0dc;
  --color-info-content: #18191c;
  --color-success: #8fcb98;
  --color-success-content: #18191c;
  --color-warning: #e2b06a;
  --color-warning-content: #18191c;
  --color-error: #e07a7a;
  --color-error-content: #18191c;
  --radius-selector: 0.25rem;
  --radius-field: 0.375rem;
  --radius-box: 0.5rem;
  --size-selector: 0.25rem;
  --size-field: 0.25rem;
  --border: 1px;
  --depth: 0;
  --noise: 0;
}
```

Also change `[data-theme="omarchy-dark"]` to `[data-theme="agentile-dark"]` and its `--surface-raised: #26272b; --text-muted: #8a8d95;`, and light `:root { --surface-raised: #ffffff; --text-muted: #8a8d95; }`. Extend the badge safelist to `@source inline("badge-{neutral,info,warning,error,success,primary,secondary,accent}");`.

In `app/matestack/web/layout.rb`: `brand "Agentile Projects", icon: "rectangle-stack", path: "/"`, `themes light: "agentile-light", dark: "agentile-dark"`, `ACTION_FAILURE_EVENTS = "specs-action-failed"`, replace the "Practice" menu with an empty `menu "Projects" do ... end` placeholder holding only `item "Dashboard", path: "/", icon: "squares-2x2", match: :exact` (Task 11 fills it), remove the About item, `footer "Agentile Projects · DaisyStack #{DaisyStack::VERSION}"`. In `auth_layout.rb` swap the brand text and icon.

- [ ] **Step 9: Run the test and boot**

Run: `bin/rails db:prepare && bin/rails test test/models/web_colors_test.rb`
Expected: PASS (3 tests). Then `bin/rails runner 'puts DaisyStack::Lib::Registry.components.size'` prints a number > 50, and `bin/dev` serves the sign-in page at http://localhost:3300.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "bootstrap: copy Practice Manager shell, rename to AgentileProjects, themes and Web::Colors"
```

---

### Task 2: Migrations, models and fixtures for every table

**Files:**
- Create: `db/migrate/20260921000001_create_agentile_tables.rb`
- Create: `app/models/{api_token,project,membership,inbox_item,outcome,spec,spec_dependency,spec_shaper,run,run_event,checkpoint,judgment}.rb`
- Modify: `app/models/user.rb`
- Create: `test/fixtures/{users,api_tokens,projects,memberships,inbox_items,outcomes,specs,spec_dependencies,runs,run_events,checkpoints}.yml`
- Test: `test/models/{project_test,spec_test,checkpoint_test,run_test,membership_test}.rb`

**Interfaces:**
- Produces: models with enums (`Spec.statuses` = ready/in_progress/shipped/abandoned; `Spec.kinds`, `Spec.routes`, `Spec.business_values`/`technical_certainties` = high/medium/low; `InboxItem.statuses` open/shaped/dropped, `InboxItem.kinds`; `Outcome.statuses`; `Run.statuses` active/paused/shipped/failed/handed_over/closed; `RunEvent.events`; `Checkpoint.reasons`, `Checkpoint.statuses`, `Checkpoint.priorities`; `Membership.roles` owner/member/viewer); associations `Project#specs/#inbox_items/#outcomes/#runs/#memberships/#users`, `Spec#dependencies` (Spec records), `Spec#dependents`, `Spec#shapers`, `Spec#checkpoints`, `Spec#runs`, `Run#checkpoints/#events`; `Project#member?(user)`, `Project#role_for(user)`; `Spec#claimable?`, `Spec#deps_shipped?`; `Checkpoint#ref`; `Time#ag_iso` helper via `AgTime.iso(t)`.

- [ ] **Step 1: Write the migration**

`db/migrate/20260921000001_create_agentile_tables.rb`:

```ruby
class CreateAgentileTables < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :git_email, :string

    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :api_tokens, :token_digest, unique: true

    create_table :projects do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :brief
      t.string :trunk, null: false, default: "main"
      t.integer :wip_limit, null: false, default: 1
      t.datetime :archived_at
      t.timestamps
    end
    add_index :projects, :slug, unique: true

    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :memberships, [ :user_id, :project_id ], unique: true

    create_table :outcomes do |t|
      t.references :project, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "open"
      t.integer :rank
      t.text :claim
      t.text :measure
      t.text :stop_rule
      t.text :notes
      t.text :abandoned_reason
      t.datetime :achieved_at
      t.datetime :abandoned_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :outcomes, [ :project_id, :slug ], unique: true

    create_table :inbox_items do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.text :text
      t.string :kind, null: false, default: "feature"
      t.string :status, null: false, default: "open"
      t.datetime :captured_at, null: false
      t.references :captured_by, foreign_key: { to_table: :users }
      t.references :serves_outcome, foreign_key: { to_table: :outcomes }
      t.string :suggested_kind
      t.references :suggested_outcome, foreign_key: { to_table: :outcomes }
      t.references :duplicate_of, foreign_key: { to_table: :inbox_items }
      t.float :duplicate_probability
      t.timestamps
    end

    create_table :specs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "ready"
      t.string :kind, null: false, default: "feature"
      t.string :route
      t.string :business_value
      t.string :technical_certainty
      t.integer :rank
      t.json :tags, null: false, default: []
      t.text :outcome
      t.text :problem_why_now
      t.text :acceptance_criteria
      t.text :scope_in
      t.text :scope_out
      t.text :edge_cases
      t.text :affected_areas
      t.text :open_questions
      t.text :verification
      t.text :abandoned_reason
      t.datetime :claimed_at
      t.datetime :shipped_at
      t.datetime :abandoned_at
      t.string :claimed_by_session
      t.references :claimed_by_user, foreign_key: { to_table: :users }
      t.string :label
      t.references :captured_by, foreign_key: { to_table: :users }
      t.references :serves_outcome, foreign_key: { to_table: :outcomes }
      t.references :source_inbox_item, foreign_key: { to_table: :inbox_items }
      t.boolean :needs_review, null: false, default: false
      t.text :needs_review_reason
      t.timestamps
    end
    add_index :specs, [ :project_id, :slug ], unique: true
    add_index :specs, [ :project_id, :status, :rank ]

    create_table :spec_dependencies do |t|
      t.references :spec, null: false, foreign_key: true
      t.references :depends_on_spec, null: false, foreign_key: { to_table: :specs }
      t.timestamps
    end
    add_index :spec_dependencies, [ :spec_id, :depends_on_spec_id ], unique: true

    create_table :spec_shapers do |t|
      t.references :spec, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :spec_shapers, [ :spec_id, :user_id ], unique: true

    create_table :runs do |t|
      t.references :project, null: false, foreign_key: true
      t.references :spec, null: false, foreign_key: true
      t.string :runner_id, null: false
      t.string :session_id
      t.string :status, null: false, default: "active"
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.datetime :last_event_at
      t.text :detail
      t.timestamps
    end
    add_index :runs, [ :project_id, :status ]

    create_table :run_events do |t|
      t.references :run, null: false, foreign_key: true
      t.string :event, null: false
      t.datetime :at, null: false
      t.text :detail
      t.timestamps
    end

    create_table :checkpoints do |t|
      t.references :run, null: false, foreign_key: true
      t.references :spec, null: false, foreign_key: true
      t.integer :seq, null: false
      t.string :reason, null: false
      t.string :asked_by, null: false
      t.datetime :asked_at, null: false
      t.string :session_id
      t.string :status, null: false, default: "open"
      t.text :ask
      t.text :answer
      t.datetime :answered_at
      t.references :answered_by, foreign_key: { to_table: :users }
      t.string :priority
      t.timestamps
    end
    add_index :checkpoints, [ :spec_id, :seq ], unique: true
    add_index :checkpoints, [ :spec_id, :status ]

    create_table :judgments do |t|
      t.string :subject_type
      t.integer :subject_id
      t.string :purpose, null: false
      t.json :request
      t.json :response
      t.integer :tokens
      t.integer :latency_ms
      t.string :transport
      t.timestamps
    end
    add_index :judgments, [ :subject_type, :subject_id ]
  end
end
```

- [ ] **Step 2: Write the failing model tests**

`test/models/spec_test.rb`:

```ruby
require "test_helper"

class SpecTest < ActiveSupport::TestCase
  test "slug is unique per project, not globally" do
    dup = specs(:tek_ready_a).dup
    assert_not dup.valid?
    dup.project = projects(:other)
    assert dup.valid?
  end

  test "deps_shipped? reflects dependency status" do
    assert specs(:tek_ready_a).deps_shipped?
    assert_not specs(:tek_blocked).deps_shipped?
  end

  test "claimable? needs ready, ranked, unclaimed and deps shipped" do
    assert specs(:tek_ready_a).claimable?
    assert_not specs(:tek_unranked).claimable?
    assert_not specs(:tek_blocked).claimable?
    assert_not specs(:tek_in_progress).claimable?
  end

  test "dependents lists specs that depend on this one" do
    assert_includes specs(:tek_ready_a).dependents, specs(:tek_dependent)
  end
end
```

`test/models/checkpoint_test.rb`:

```ruby
require "test_helper"

class CheckpointTest < ActiveSupport::TestCase
  test "ref is slug, seq and reason" do
    assert_equal "in-progress-spec #001 ship_approval", checkpoints(:open_ship).ref
  end

  test "seq is unique per spec" do
    dup = checkpoints(:open_ship).dup
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end
end
```

`test/models/project_test.rb`:

```ruby
require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "role_for returns the membership role or nil" do
    assert_equal "owner", projects(:tekmore).role_for(users(:keith))
    assert_equal "member", projects(:tekmore).role_for(users(:danny))
    assert_nil projects(:tekmore).role_for(users(:outsider))
  end

  test "slug is required and unique" do
    assert_not Project.new(name: "X", slug: "tekmore").valid?
  end
end
```

`test/models/run_test.rb`:

```ruby
require "test_helper"

class RunTest < ActiveSupport::TestCase
  test "active scope excludes closed and failed" do
    assert_includes Run.live, runs(:active_run)
    assert_not_includes Run.live, runs(:closed_run)
  end
end
```

- [ ] **Step 3: Write the fixtures**

`test/fixtures/users.yml`:

```yaml
keith:
  email: keith@example.com
  name: Keith
  admin: true
  git_email: keith@example.com
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
danny:
  email: danny@example.com
  name: Danny
  admin: false
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
viewer:
  email: viewer@example.com
  name: Vee
  admin: false
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
outsider:
  email: out@example.com
  name: Out
  admin: false
  encrypted_password: <%= Devise::Encryptor.digest(User, "password123") %>
```

`test/fixtures/projects.yml`:

```yaml
tekmore:
  name: Tekmore
  slug: tekmore
  brief: "# Tekmore\n\nWho it's for.\n\n## Prioritised outcomes\n\n- old\n\n## Constraints\n\nnone\n"
  trunk: main
  wip_limit: 2
other:
  name: Other
  slug: other
  wip_limit: 1
```

`test/fixtures/memberships.yml`:

```yaml
keith_tekmore: { user: keith, project: tekmore, role: owner }
danny_tekmore: { user: danny, project: tekmore, role: member }
viewer_tekmore: { user: viewer, project: tekmore, role: viewer }
keith_other: { user: keith, project: other, role: owner }
```

`test/fixtures/api_tokens.yml` (raw tokens used by tests: `keith-token`, `danny-token`, `viewer-token`, `outsider-token`):

```yaml
keith: { user: keith, name: laptop, token_digest: <%= Digest::SHA256.hexdigest("keith-token") %> }
danny: { user: danny, name: laptop, token_digest: <%= Digest::SHA256.hexdigest("danny-token") %> }
viewer: { user: viewer, name: laptop, token_digest: <%= Digest::SHA256.hexdigest("viewer-token") %> }
outsider: { user: outsider, name: laptop, token_digest: <%= Digest::SHA256.hexdigest("outsider-token") %> }
revoked: { user: keith, name: old, token_digest: <%= Digest::SHA256.hexdigest("revoked-token") %>, revoked_at: <%= 1.day.ago.iso8601 %> }
```

`test/fixtures/outcomes.yml`:

```yaml
faster_onboarding:
  project: tekmore
  slug: faster-onboarding
  title: Faster onboarding
  status: open
  rank: 1
  claim: New users reach first value in under a day
  measure: Median time-to-first-value
  stop_rule: If no change after 3 specs
  created_by: keith
second_outcome:
  project: tekmore
  slug: fewer-tickets
  title: Fewer support tickets
  status: open
  rank: 2
  claim: Tickets fall by a third
  measure: Weekly ticket count
  stop_rule: Two months
achieved_outcome:
  project: tekmore
  slug: done-thing
  title: Done thing
  status: achieved
  achieved_at: <%= 2.days.ago.iso8601 %>
```

`test/fixtures/inbox_items.yml`:

```yaml
open_one:
  project: tekmore
  title: Add CSV export
  text: Users want to export the report as CSV
  kind: feature
  status: open
  captured_at: <%= 3.days.ago.iso8601 %>
  captured_by: keith
open_two:
  project: tekmore
  title: Login page slow
  text: Login takes 4s on mobile
  kind: bug
  status: open
  captured_at: <%= 2.days.ago.iso8601 %>
shaped_one:
  project: tekmore
  title: Old shaped stub
  text: already shaped
  kind: feature
  status: shaped
  captured_at: <%= 9.days.ago.iso8601 %>
```

`test/fixtures/specs.yml`:

```yaml
tek_ready_a:
  project: tekmore
  slug: ready-a
  title: Ready A
  status: ready
  kind: feature
  route: background
  business_value: high
  technical_certainty: high
  rank: 1
  tags: ["api", "export"]
  problem_why_now: Why A
  acceptance_criteria: "- does A"
  scope_in: In A
  scope_out: Out A
  edge_cases: Edge A
  affected_areas: Area A
  open_questions: None
  verification: Test A
  serves_outcome: faster_onboarding
  captured_by: keith
  created_at: <%= 5.days.ago.iso8601 %>
tek_ready_b:
  project: tekmore
  slug: ready-b
  title: Ready B
  status: ready
  kind: chore
  route: foreground
  rank: 2
  acceptance_criteria: "- does B"
  created_at: <%= 4.days.ago.iso8601 %>
tek_unranked:
  project: tekmore
  slug: unranked
  title: Unranked
  status: ready
  kind: feature
  created_at: <%= 4.days.ago.iso8601 %>
tek_blocked:
  project: tekmore
  slug: blocked
  title: Blocked by unranked
  status: ready
  kind: feature
  rank: 3
  created_at: <%= 4.days.ago.iso8601 %>
tek_dependent:
  project: tekmore
  slug: dependent
  title: Depends on ready-a
  status: ready
  kind: feature
  rank: 4
  created_at: <%= 4.days.ago.iso8601 %>
tek_in_progress:
  project: tekmore
  slug: in-progress-spec
  title: In progress
  status: in_progress
  kind: feature
  route: background
  rank: 0
  claimed_by_session: sess-1
  claimed_by_user: danny
  claimed_at: <%= 1.day.ago.iso8601 %>
  created_at: <%= 6.days.ago.iso8601 %>
tek_shipped:
  project: tekmore
  slug: shipped-one
  title: Shipped one
  status: shipped
  kind: feature
  claimed_at: <%= 3.days.ago.iso8601 %>
  shipped_at: <%= 2.days.ago.iso8601 %>
  created_at: <%= 7.days.ago.iso8601 %>
  serves_outcome: faster_onboarding
tek_abandoned:
  project: tekmore
  slug: abandoned-one
  title: Abandoned
  status: abandoned
  kind: feature
  abandoned_reason: nope
  abandoned_at: <%= 2.days.ago.iso8601 %>
  created_at: <%= 7.days.ago.iso8601 %>
other_ready:
  project: other
  slug: ready-a
  title: Other project's ready-a
  status: ready
  kind: feature
  rank: 1
```

`test/fixtures/spec_dependencies.yml`:

```yaml
blocked_on_unranked: { spec: tek_blocked, depends_on_spec: tek_unranked }
dependent_on_a: { spec: tek_dependent, depends_on_spec: tek_ready_a }
```

`test/fixtures/runs.yml`:

```yaml
active_run:
  project: tekmore
  spec: tek_in_progress
  runner_id: factory/tekmore/in-progress-spec
  session_id: sess-1
  status: paused
  started_at: <%= 1.day.ago.iso8601 %>
  last_event_at: <%= 2.hours.ago.iso8601 %>
closed_run:
  project: tekmore
  spec: tek_shipped
  runner_id: ag-run@host/1
  session_id: sess-0
  status: shipped
  started_at: <%= 3.days.ago.iso8601 %>
  ended_at: <%= 2.days.ago.iso8601 %>
```

`test/fixtures/run_events.yml`:

```yaml
a1: { run: active_run, event: started, at: <%= 1.day.ago.iso8601 %> }
a2: { run: active_run, event: claimed, at: <%= 1.day.ago.iso8601 %> }
a3: { run: active_run, event: paused, at: <%= 2.hours.ago.iso8601 %>, detail: ship_approval }
c1: { run: closed_run, event: started, at: <%= 3.days.ago.iso8601 %> }
c2: { run: closed_run, event: shipped, at: <%= 2.days.ago.iso8601 %> }
```

`test/fixtures/checkpoints.yml`:

```yaml
open_ship:
  run: active_run
  spec: tek_in_progress
  seq: 1
  reason: ship_approval
  asked_by: ship
  asked_at: <%= 2.hours.ago.iso8601 %>
  session_id: sess-1
  status: open
  ask: "Diff is green. Ship it?"
  priority: needs_human
answered_plan:
  run: closed_run
  spec: tek_shipped
  seq: 1
  reason: plan_review
  asked_by: plan
  asked_at: <%= 3.days.ago.iso8601 %>
  status: answered
  ask: "Plan ok?"
  answer: approved
  answered_at: <%= 3.days.ago.iso8601 %>
  answered_by: keith
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `bin/rails db:migrate && bin/rails test test/models`
Expected: FAIL with `uninitialized constant Spec` (or fixture load errors for missing tables/models)

- [ ] **Step 5: Write the models**

`app/models/concerns/ag_time.rb`:

```ruby
module AgTime
  FORMAT = "%Y-%m-%dT%H:%M:%SZ".freeze

  def self.iso(time)
    time&.utc&.strftime(FORMAT)
  end
end
```

`app/models/user.rb` — add after the `devise` line:

```ruby
  has_many :memberships, dependent: :destroy
  has_many :projects, through: :memberships
  has_many :api_tokens, dependent: :destroy
```

`app/models/api_token.rb`:

```ruby
class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  attr_reader :raw_token

  # Generates a token once; the raw value is only readable on the instance
  # that created it (shown once in the UI).
  def self.generate!(user:, name:)
    raw = SecureRandom.hex(32)
    create!(user: user, name: name, token_digest: digest(raw)).tap { |t| t.instance_variable_set(:@raw_token, raw) }
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw)
  end

  def self.authenticate(raw)
    return nil if raw.blank?
    active.find_by(token_digest: digest(raw))&.tap { |t| t.update_column(:last_used_at, Time.current) }
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
```

`app/models/project.rb`:

```ruby
class Project < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :specs, dependent: :destroy
  has_many :inbox_items, dependent: :destroy
  has_many :outcomes, dependent: :destroy
  has_many :runs, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :wip_limit, numericality: { greater_than_or_equal_to: 0 }

  scope :live, -> { where(archived_at: nil) }

  def to_param = slug

  def role_for(user)
    memberships.find_by(user: user)&.role
  end

  def member?(user)
    role_for(user).present?
  end

  def archived? = archived_at.present?

  def to_s = name
end
```

`app/models/membership.rb`:

```ruby
class Membership < ApplicationRecord
  ROLES = %w[owner member viewer].freeze

  belongs_to :user
  belongs_to :project

  enum :role, ROLES.index_by(&:itself), validate: true

  validates :user_id, uniqueness: { scope: :project_id }

  def writer? = owner? || member?
end
```

`app/models/outcome.rb`:

```ruby
class Outcome < ApplicationRecord
  STATUSES = %w[open achieved abandoned].freeze

  belongs_to :project
  belongs_to :created_by, class_name: "User", optional: true
  has_many :specs, foreign_key: :serves_outcome_id, dependent: :nullify
  has_many :inbox_items, foreign_key: :serves_outcome_id, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :slug, presence: true, uniqueness: { scope: :project_id }
  validates :title, presence: true

  scope :ranked, -> { order(Arel.sql("rank IS NULL, rank ASC, slug ASC")) }

  def to_param = slug
  def to_s = title
end
```

`app/models/inbox_item.rb`:

```ruby
class InboxItem < ApplicationRecord
  KINDS = %w[feature bug chore spike].freeze
  STATUSES = %w[open shaped dropped].freeze

  belongs_to :project
  belongs_to :captured_by, class_name: "User", optional: true
  belongs_to :serves_outcome, class_name: "Outcome", optional: true
  belongs_to :suggested_outcome, class_name: "Outcome", optional: true
  belongs_to :duplicate_of, class_name: "InboxItem", optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :title, presence: true
  before_validation { self.captured_at ||= Time.current }

  scope :recent_first, -> { order(captured_at: :desc) }

  def to_s = title
end
```

`app/models/spec.rb`:

```ruby
class Spec < ApplicationRecord
  STATUSES = %w[ready in_progress shipped abandoned].freeze
  KINDS = %w[feature spike bug chore].freeze
  ROUTES = %w[foreground background spike].freeze
  LEVELS = %w[high medium low].freeze
  SECTIONS = %i[outcome problem_why_now acceptance_criteria scope_in scope_out edge_cases
                affected_areas open_questions verification].freeze

  belongs_to :project
  belongs_to :claimed_by_user, class_name: "User", optional: true
  belongs_to :captured_by, class_name: "User", optional: true
  belongs_to :serves_outcome, class_name: "Outcome", optional: true
  belongs_to :source_inbox_item, class_name: "InboxItem", optional: true

  has_many :spec_dependencies, dependent: :destroy
  has_many :dependencies, through: :spec_dependencies, source: :depends_on_spec
  has_many :inverse_dependencies, class_name: "SpecDependency", foreign_key: :depends_on_spec_id, dependent: :destroy
  has_many :dependents, through: :inverse_dependencies, source: :spec
  has_many :spec_shapers, dependent: :destroy
  has_many :shapers, through: :spec_shapers, source: :user
  has_many :runs, dependent: :destroy
  has_many :checkpoints, dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), validate: true
  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :route, ROUTES.index_by(&:itself), validate: { allow_nil: true }
  enum :business_value, LEVELS.index_by(&:itself), validate: { allow_nil: true }, prefix: :value
  enum :technical_certainty, LEVELS.index_by(&:itself), validate: { allow_nil: true }, prefix: :certainty

  validates :slug, presence: true, uniqueness: { scope: :project_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :title, presence: true

  scope :active, -> { where(status: %w[ready in_progress]) }
  scope :done, -> { where(status: "shipped") }
  scope :ranked, -> { order(Arel.sql("rank IS NULL, rank ASC, slug ASC")) }
  scope :unclaimed, -> { where(claimed_by_session: [ nil, "" ]) }

  def to_param = slug
  def to_s = title

  def deps_shipped?
    dependencies.all?(&:shipped?)
  end

  def claimable?
    ready? && rank.present? && claimed_by_session.blank? && deps_shipped?
  end

  def blocked?
    ready? && !deps_shipped?
  end

  def plan_path
    "docs/agentile/specs/#{slug}"
  end
end
```

`app/models/spec_dependency.rb`:

```ruby
class SpecDependency < ApplicationRecord
  belongs_to :spec
  belongs_to :depends_on_spec, class_name: "Spec"

  validates :depends_on_spec_id, uniqueness: { scope: :spec_id }
  validate :same_project

  private

  def same_project
    return if spec.nil? || depends_on_spec.nil?
    errors.add(:depends_on_spec, "must be in the same project") if spec.project_id != depends_on_spec.project_id
  end
end
```

`app/models/spec_shaper.rb`:

```ruby
class SpecShaper < ApplicationRecord
  belongs_to :spec
  belongs_to :user
  validates :user_id, uniqueness: { scope: :spec_id }
end
```

`app/models/run.rb`:

```ruby
class Run < ApplicationRecord
  STATUSES = %w[active paused shipped failed handed_over closed].freeze
  LIVE = %w[active paused].freeze

  belongs_to :project
  belongs_to :spec
  has_many :events, class_name: "RunEvent", dependent: :destroy
  has_many :checkpoints, dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :runner_id, presence: true
  before_validation { self.started_at ||= Time.current }

  scope :live, -> { where(status: LIVE) }
  scope :attention, -> { where(status: "failed") }
  scope :newest_first, -> { order(started_at: :desc) }

  def live? = LIVE.include?(status)
end
```

`app/models/run_event.rb`:

```ruby
class RunEvent < ApplicationRecord
  EVENTS = %w[started claimed shipped paused failed idle deployed closed].freeze
  TERMINAL = %w[shipped failed deployed closed].freeze

  belongs_to :run
  enum :event, EVENTS.index_by(&:itself), validate: true
  before_validation { self.at ||= Time.current }

  scope :chronological, -> { order(:at, :id) }
end
```

`app/models/checkpoint.rb`:

```ruby
class Checkpoint < ApplicationRecord
  REASONS = %w[plan_review build_blocked build_checkpoint gate_failure verify_checkpoint ship_approval question].freeze
  ASKED_BY = %w[plan build builder reviewer verify ship].freeze
  STATUSES = %w[open answered].freeze
  PRIORITIES = %w[needs_human routine unclear].freeze

  belongs_to :run
  belongs_to :spec
  belongs_to :answered_by, class_name: "User", optional: true

  enum :reason, REASONS.index_by(&:itself), validate: true
  enum :status, STATUSES.index_by(&:itself), validate: true
  enum :priority, PRIORITIES.index_by(&:itself), validate: { allow_nil: true }

  validates :seq, presence: true, uniqueness: { scope: :spec_id }
  validates :asked_by, inclusion: { in: ASKED_BY }
  before_validation { self.asked_at ||= Time.current }

  scope :oldest_first, -> { order(:seq) }
  scope :attention_order, -> { order(Arel.sql("CASE priority WHEN 'needs_human' THEN 0 WHEN 'unclear' THEN 1 ELSE 2 END, asked_at ASC")) }

  def ref
    format("%s #%03d %s", spec.slug, seq, reason)
  end
end
```

`app/models/judgment.rb`:

```ruby
class Judgment < ApplicationRecord
  belongs_to :subject, polymorphic: true, optional: true
  validates :purpose, presence: true
  scope :newest_first, -> { order(created_at: :desc) }
end
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/models`
Expected: PASS (all)

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "models: every Agentile table, enums, associations and fixtures"
```

---

### Task 3: Spec markdown round-trip

**Files:**
- Create: `app/models/spec/markdown.rb` (concern), `app/models/outcome/markdown.rb`
- Modify: `app/models/spec.rb`, `app/models/outcome.rb`
- Test: `test/models/spec_markdown_test.rb`

**Interfaces:**
- Produces: `Spec#to_markdown -> String` (canonical: frontmatter + `# title` + `## ` sections exactly as `bin/ag-store-adapters/airtable/schema.rb#render_spec_markdown`), `Spec.attributes_from_markdown(md) -> { attributes: Hash, depends_on: [slug], serves: slug|nil, tags: [String] }`, `Spec#apply_markdown!(md)`; `Outcome#to_markdown`, `Outcome.attributes_from_markdown(md)`.

- [ ] **Step 1: Write the failing test**

`test/models/spec_markdown_test.rb`:

```ruby
require "test_helper"

class SpecMarkdownTest < ActiveSupport::TestCase
  MD = <<~MD
    ---
    title: Rate-limit the login endpoint
    slug: rate-limit-login
    status: ready
    depends_on: [ready-a, ready-b]
    type: feature
    route: foreground
    business_value: high
    technical_certainty: medium
    serves: faster-onboarding
    tags: [auth, security]
    outcome: Fewer brute-force attempts
    ---

    # Rate-limit the login endpoint

    ## Problem / why now

    Bots hammer the login form.

    ## Acceptance criteria

    - 429 after 10 attempts per minute

    ## Scope boundary

    **In scope:** the login endpoint

    **Out of scope:** password reset

    ## Edge cases and failure paths

    Shared office IP.

    ## Affected areas

    SessionsController

    ## Open questions

    None

    ## Verification

    Request spec for 429.
  MD

  test "parses every frontmatter key and section" do
    parsed = Spec.attributes_from_markdown(MD)
    a = parsed[:attributes]
    assert_equal "rate-limit-login", a[:slug]
    assert_equal "Rate-limit the login endpoint", a[:title]
    assert_equal "feature", a[:kind]
    assert_equal "foreground", a[:route]
    assert_equal "high", a[:business_value]
    assert_equal "medium", a[:technical_certainty]
    assert_equal "Fewer brute-force attempts", a[:outcome]
    assert_equal "Bots hammer the login form.", a[:problem_why_now]
    assert_equal "- 429 after 10 attempts per minute", a[:acceptance_criteria]
    assert_equal "the login endpoint", a[:scope_in]
    assert_equal "password reset", a[:scope_out]
    assert_equal "Shared office IP.", a[:edge_cases]
    assert_equal "SessionsController", a[:affected_areas]
    assert_equal "None", a[:open_questions]
    assert_equal "Request spec for 429.", a[:verification]
    assert_equal %w[ready-a ready-b], parsed[:depends_on]
    assert_equal "faster-onboarding", parsed[:serves]
    assert_equal %w[auth security], parsed[:tags]
  end

  test "round-trips through a saved spec" do
    spec = projects(:tekmore).specs.new
    spec.apply_markdown!(MD)
    spec.reload
    reparsed = Spec.attributes_from_markdown(spec.to_markdown)
    assert_equal Spec.attributes_from_markdown(MD)[:attributes].except(:status), reparsed[:attributes].except(:status)
    assert_equal %w[ready-a ready-b], reparsed[:depends_on]
    assert_equal "faster-onboarding", reparsed[:serves]
    assert_equal %w[auth security], reparsed[:tags]
    assert_match(/^created_at: \d{4}-\d{2}-\d{2}T/, spec.to_markdown)
  end

  test "rendered markdown carries rank, claim and attribution keys" do
    md = specs(:tek_in_progress).to_markdown
    assert_match(/^rank: 0$/, md)
    assert_match(/^claimed_by: sess-1$/, md)
    assert_match(/^claimed_by_member: danny@example.com$/, md)
    assert_match(/^status: in_progress$/, md)
  end

  test "unknown dependency slug is an error" do
    spec = projects(:tekmore).specs.new
    assert_raises(ActiveRecord::RecordNotFound) { spec.apply_markdown!(MD.sub("ready-b", "nope")) }
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bin/rails test test/models/spec_markdown_test.rb`
Expected: FAIL with `undefined method 'attributes_from_markdown'`

- [ ] **Step 3: Implement the concern**

`app/models/spec/markdown.rb`:

```ruby
# The canonical spec markdown the plugin reads and writes (ported from the
# Airtable adapter's render/parse so `ag-store spec_read`/`spec_create` see no change).
module Spec::Markdown
  extend ActiveSupport::Concern

  FRONTMATTER_KEYS = %i[
    title slug status depends_on type route business_value technical_certainty
    rank created_at serves tags outcome claimed_by label claimed_at claimed_by_member
    abandoned_reason abandoned_at shipped_at captured_by shaped_by source_inbox
  ].freeze

  SECTION_HEADINGS = {
    problem_why_now: "Problem / why now",
    acceptance_criteria: "Acceptance criteria",
    edge_cases: "Edge cases and failure paths",
    affected_areas: "Affected areas",
    open_questions: "Open questions",
    verification: "Verification"
  }.freeze

  class_methods do
    def attributes_from_markdown(markdown)
      fm_text = markdown[/\A---\n(.*?)\n---/m, 1] || ""
      body = markdown.sub(/\A---\n.*?\n---/m, "").strip
      fm = {}
      fm_text.each_line do |line|
        next unless (m = line.chomp.match(/\A([A-Za-z_]+):\s*(.*)\z/))
        val = m[2].strip
        val = val[1..-2].split(",").map(&:strip).reject(&:empty?) if val.start_with?("[") && val.end_with?("]")
        fm[m[1].to_sym] = val
      end
      sections = body.split(/^## /).drop(1).to_h do |chunk|
        heading, rest = chunk.split("\n", 2)
        [ heading.strip, rest.to_s.strip ]
      end
      scope = sections["Scope boundary"].to_s
      attributes = {
        slug: fm[:slug].presence,
        title: fm[:title].presence || body[/\A#\s+(.+)$/, 1].to_s.strip,
        status: fm[:status].presence || "ready",
        kind: fm[:type].presence || "feature",
        route: fm[:route].presence,
        business_value: fm[:business_value].presence,
        technical_certainty: fm[:technical_certainty].presence,
        outcome: fm[:outcome].presence,
        label: fm[:label].presence,
        problem_why_now: sections[SECTION_HEADINGS[:problem_why_now]].to_s,
        acceptance_criteria: sections[SECTION_HEADINGS[:acceptance_criteria]].to_s,
        scope_in: scope[/\*\*In scope:\*\*\s*(.*?)(?=\n\n\*\*Out of scope|\z)/m, 1].to_s.strip,
        scope_out: scope[/\*\*Out of scope:\*\*\s*(.*)\z/m, 1].to_s.strip,
        edge_cases: sections[SECTION_HEADINGS[:edge_cases]].to_s,
        affected_areas: sections[SECTION_HEADINGS[:affected_areas]].to_s,
        open_questions: sections[SECTION_HEADINGS[:open_questions]].to_s,
        verification: sections[SECTION_HEADINGS[:verification]].to_s
      }.compact
      {
        attributes: attributes,
        depends_on: Array(fm[:depends_on]).map(&:to_s),
        serves: fm[:serves].presence,
        tags: Array(fm[:tags]).map(&:to_s)
      }
    end
  end

  # Applies parsed markdown to this (new or existing) spec inside a transaction:
  # scalar attributes, dependencies by slug (must exist in the project), the
  # served outcome by slug, and tags. Raises RecordNotFound for unknown slugs.
  def apply_markdown!(markdown)
    parsed = self.class.attributes_from_markdown(markdown)
    transaction do
      assign_attributes(parsed[:attributes])
      self.tags = parsed[:tags]
      self.serves_outcome = parsed[:serves] ? project.outcomes.find_by!(slug: parsed[:serves]) : nil
      save!
      deps = parsed[:depends_on].map { |s| project.specs.find_by!(slug: s) }
      self.dependencies = deps
    end
    self
  end

  def to_markdown
    v = {
      title: title, slug: slug, status: status,
      depends_on: dependencies.map(&:slug), type: kind, route: route,
      business_value: business_value, technical_certainty: technical_certainty,
      rank: rank, created_at: AgTime.iso(created_at), serves: serves_outcome&.slug,
      tags: tags, outcome: outcome, claimed_by: claimed_by_session, label: label,
      claimed_at: AgTime.iso(claimed_at), claimed_by_member: claimed_by_user&.email,
      abandoned_reason: abandoned_reason, abandoned_at: AgTime.iso(abandoned_at),
      shipped_at: AgTime.iso(shipped_at), captured_by: captured_by&.email,
      shaped_by: shapers.map(&:email), source_inbox: source_inbox_item&.title
    }
    fm = FRONTMATTER_KEYS.filter_map do |k|
      val = v[k]
      next if val.nil? || val == "" || (val.is_a?(Array) && val.empty?)
      "#{k}: #{val.is_a?(Array) ? "[#{val.join(', ')}]" : val}"
    end.join("\n")
    body = +"# #{title}\n\n"
    body << "## #{SECTION_HEADINGS[:problem_why_now]}\n\n#{problem_why_now}\n\n"
    body << "## #{SECTION_HEADINGS[:acceptance_criteria]}\n\n#{acceptance_criteria}\n\n"
    body << "## Scope boundary\n\n**In scope:** #{scope_in}\n\n**Out of scope:** #{scope_out}\n\n"
    body << "## #{SECTION_HEADINGS[:edge_cases]}\n\n#{edge_cases}\n\n"
    body << "## #{SECTION_HEADINGS[:affected_areas]}\n\n#{affected_areas}\n\n"
    body << "## #{SECTION_HEADINGS[:open_questions]}\n\n#{open_questions}\n\n"
    body << "## #{SECTION_HEADINGS[:verification]}\n\n#{verification}\n"
    "---\n#{fm}\n---\n\n#{body}"
  end
end
```

Add `include Spec::Markdown` at the top of `class Spec`.

`app/models/outcome/markdown.rb`:

```ruby
module Outcome::Markdown
  extend ActiveSupport::Concern

  KEYS = %i[title slug status rank created achieved_at abandoned_at abandoned_reason created_by].freeze
  SECTIONS = { claim: "Claim", measure: "Measure", stop_rule: "Stop rule", notes: "Notes" }.freeze

  class_methods do
    def attributes_from_markdown(markdown)
      fm_text = markdown[/\A---\n(.*?)\n---/m, 1] || ""
      body = markdown.sub(/\A---\n.*?\n---/m, "").strip
      fm = {}
      fm_text.each_line do |line|
        next unless (m = line.chomp.match(/\A([A-Za-z_]+):\s*(.*)\z/))
        fm[m[1].to_sym] = m[2].strip
      end
      sections = body.split(/^## /).drop(1).to_h do |chunk|
        heading, rest = chunk.split("\n", 2)
        [ heading.strip, rest.to_s.strip ]
      end
      {
        slug: fm[:slug].presence,
        title: fm[:title].presence || body[/\A#\s+(.+)$/, 1].to_s.strip,
        status: fm[:status].presence || "open",
        rank: fm[:rank].presence&.to_i,
        claim: sections["Claim"].to_s, measure: sections["Measure"].to_s,
        stop_rule: sections["Stop rule"].to_s, notes: sections["Notes"].to_s
      }.compact
    end
  end

  def to_markdown
    v = { title: title, slug: slug, status: status, rank: rank, created: AgTime.iso(created_at),
          achieved_at: AgTime.iso(achieved_at), abandoned_at: AgTime.iso(abandoned_at),
          abandoned_reason: abandoned_reason, created_by: created_by&.email }
    fm = KEYS.filter_map { |k| v[k].nil? || v[k] == "" ? nil : "#{k}: #{v[k]}" }.join("\n")
    body = +"# #{title}\n\n"
    SECTIONS.each { |key, heading| body << "## #{heading}\n\n#{send(key)}\n\n" }
    "---\n#{fm}\n---\n\n#{body.rstrip}\n"
  end
end
```

Add `include Outcome::Markdown` to `Outcome`.

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/models/spec_markdown_test.rb`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "models: canonical spec and outcome markdown round-trip"
```

---

### Task 4: Pundit policies and project-scoped DataPages

**Files:**
- Create: `app/policies/{application_policy,project_policy,membership_policy,inbox_item_policy,spec_policy,outcome_policy,checkpoint_policy,run_policy,api_token_policy,user_policy}.rb`
- Modify: `app/controllers/application_controller.rb`, `app/controllers/concerns/data_pages.rb`, `app/controllers/admin/users_controller.rb`
- Test: `test/policies/{project_policy_test,spec_policy_test,api_token_policy_test}.rb`

**Interfaces:**
- Produces: `ApplicationPolicy` with `user`, `record`, `role` (membership role for `record.project` or `record` when it is a Project); `ProjectPolicy#show? update? manage_members? archive? create?`; resource policies `index? show? create? update? destroy?` + transition methods (`SpecPolicy#claim? rank? ship? abandon? release?`, `CheckpointPolicy#answer?`, `InboxItemPolicy#drop? shape? assist?`, `OutcomePolicy#rank? achieve? abandon?`, `RunPolicy#create? event? close?`); every `Scope#resolve` restricts to projects the user belongs to. `DataPages` concern: `scoped_collection` = `policy_scope(model)` further scoped to `current_project` when the controller defines it; `find_object` authorizes `:show?`/`:update?`.

- [ ] **Step 1: Write the failing policy tests**

`test/policies/project_policy_test.rb`:

```ruby
require "test_helper"

class ProjectPolicyTest < ActiveSupport::TestCase
  def policy(user, project) = ProjectPolicy.new(user, project)

  test "owner can manage members and archive" do
    p = policy(users(:keith), projects(:tekmore))
    assert p.show? && p.update? && p.manage_members? && p.archive?
  end

  test "member can view but not manage" do
    p = policy(users(:danny), projects(:tekmore))
    assert p.show?
    assert_not p.update?
    assert_not p.manage_members?
  end

  test "viewer can only view" do
    p = policy(users(:viewer), projects(:tekmore))
    assert p.show?
    assert_not p.update?
  end

  test "outsider sees nothing" do
    p = policy(users(:outsider), projects(:tekmore))
    assert_not p.show?
  end

  test "scope lists only the user's projects" do
    assert_equal [ projects(:tekmore) ], ProjectPolicy::Scope.new(users(:danny), Project).resolve.to_a
    assert_equal [], ProjectPolicy::Scope.new(users(:outsider), Project).resolve.to_a
  end
end
```

`test/policies/spec_policy_test.rb`:

```ruby
require "test_helper"

class SpecPolicyTest < ActiveSupport::TestCase
  def policy(user, spec) = SpecPolicy.new(user, spec)

  test "member can claim, rank and ship" do
    p = policy(users(:danny), specs(:tek_ready_a))
    assert p.show? && p.create? && p.update? && p.claim? && p.rank? && p.ship? && p.abandon?
  end

  test "viewer is read-only" do
    p = policy(users(:viewer), specs(:tek_ready_a))
    assert p.show?
    assert_not p.claim?
    assert_not p.update?
  end

  test "outsider cannot see the spec" do
    assert_not policy(users(:outsider), specs(:tek_ready_a)).show?
  end

  test "scope is project-bound" do
    resolved = SpecPolicy::Scope.new(users(:danny), Spec).resolve
    assert_includes resolved, specs(:tek_ready_a)
    assert_not_includes resolved, specs(:other_ready)
  end
end
```

`test/policies/api_token_policy_test.rb`:

```ruby
require "test_helper"

class ApiTokenPolicyTest < ActiveSupport::TestCase
  test "only the owner may revoke" do
    assert ApiTokenPolicy.new(users(:keith), api_tokens(:keith)).destroy?
    assert_not ApiTokenPolicy.new(users(:danny), api_tokens(:keith)).destroy?
  end
end
```

- [ ] **Step 2: Run to see them fail**

Run: `bin/rails test test/policies`
Expected: FAIL with `uninitialized constant ProjectPolicy`

- [ ] **Step 3: Write the policies**

`app/policies/application_policy.rb`:

```ruby
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  # The user's membership role in the record's project (or in the record when
  # it is a Project). nil when not a member.
  def role
    project = record.is_a?(Project) ? record : record.try(:project)
    project && user && project.role_for(user)
  end

  def member? = role.present?
  def writer? = %w[owner member].include?(role)
  def owner? = role == "owner"

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.where(project_id: user.memberships.select(:project_id))
    end
  end
end
```

`app/policies/project_policy.rb`:

```ruby
class ProjectPolicy < ApplicationPolicy
  def index? = true
  def show? = member?
  def create? = user.admin?
  def update? = owner?
  def manage_members? = owner?
  def archive? = owner?
  def destroy? = owner?

  class Scope < Scope
    def resolve
      scope.where(id: user.memberships.select(:project_id))
    end
  end
end
```

`app/policies/membership_policy.rb`:

```ruby
class MembershipPolicy < ApplicationPolicy
  def index? = member?
  def show? = member?
  def create? = owner?
  def update? = owner?
  def destroy? = owner? && record.user_id != user.id
end
```

A shared writer policy for backlog records — `app/policies/backlog_policy.rb`:

```ruby
class BacklogPolicy < ApplicationPolicy
  def index? = member?
  def show? = member?
  def create? = writer?
  def update? = writer?
  def destroy? = writer?
end
```

Then:

```ruby
# app/policies/inbox_item_policy.rb
class InboxItemPolicy < BacklogPolicy
  def drop? = writer?
  def shape? = writer?
  def assist? = writer?
end

# app/policies/spec_policy.rb
class SpecPolicy < BacklogPolicy
  def claim? = writer?
  def release? = writer?
  def rank? = writer?
  def ship? = writer?
  def abandon? = writer?
end

# app/policies/outcome_policy.rb
class OutcomePolicy < BacklogPolicy
  def rank? = writer?
  def achieve? = writer?
  def abandon? = writer?
end

# app/policies/checkpoint_policy.rb
class CheckpointPolicy < BacklogPolicy
  def answer? = writer?
end

# app/policies/run_policy.rb
class RunPolicy < BacklogPolicy
  def event? = writer?
  def close? = writer?
end
```

`app/policies/api_token_policy.rb`:

```ruby
class ApiTokenPolicy < ApplicationPolicy
  def index? = true
  def create? = true
  def destroy? = record.user_id == user.id

  class Scope < Scope
    def resolve = scope.where(user: user)
  end
end
```

`app/policies/user_policy.rb`:

```ruby
class UserPolicy < ApplicationPolicy
  def index? = user.admin?
  def show? = user.admin?
  def create? = user.admin?
  def update? = user.admin?
  def destroy? = user.admin? && record != user

  class Scope < Scope
    def resolve = user.admin? ? scope.all : scope.none
  end
end
```

- [ ] **Step 4: Wire Pundit into the controllers**

`app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  include Matestack::Ui::Core::Helper
  include Pundit::Authorization

  allow_browser versions: :modern

  before_action :authenticate_user!, unless: :devise_controller?
  after_action :verify_authorized, unless: :devise_controller?

  matestack_layout Web::Layout

  rescue_from Pundit::NotAuthorizedError do
    redirect_to root_path, alert: "You are not allowed to do that."
  end

  def after_sign_in_path_for(_resource) = root_path
  def after_sign_out_path_for(_resource_or_scope) = new_user_session_path

  helper_method :current_project

  # Project-scoped controllers set params[:project_slug] via routes (Task 11).
  def current_project
    return @current_project if defined?(@current_project)
    @current_project = params[:project_slug] && policy_scope(Project).find_by!(slug: params[:project_slug])
  end
end
```

`app/controllers/concerns/data_pages.rb`:

```ruby
module DataPages
  extend ActiveSupport::Concern

  included do
    include DaisyStack::Ui::DataPage::Controllers::CrudController
    before_action :authorize_data_page
  end

  class_methods do
    def data_pages(resource)
      data_page_resource resource
    end
  end

  private

  # index/new: authorize the class; member actions authorize the record in find_object.
  def authorize_data_page
    case action_name
    when "index" then authorize(model_class, :index?)
    when "new", "create" then authorize(scoped_collection.new, :create?)
    end
  end

  def scoped_collection
    base = policy_scope(model_class)
    base = base.where(project: current_project) if current_project && model_class.column_names.include?("project_id")
    base
  end

  def find_object
    scoped_collection.find(params[:id]).tap { |o| authorize(o, action_name == "edit" ? :show? : :update?) }
  end
end
```

`app/controllers/admin/users_controller.rb`: replace `before_action :require_admin!` with `before_action { authorize User }` and keep the rest.

Page classes read `params[:id]` through `scope.find` — `DaisyStack::Ui::DataPage::Base#scope` uses `resource.model_class.all`; override per resource-page in Task 12 by defining `index_page`/`detail_page` subclasses whose `scope` is `Matestack::Ui::Core::Context.controller.send(:scoped_collection)`. Add that once, in `app/matestack/web/data_page_base.rb`:

```ruby
# Project-scoped variants of the gem's generic CRUD pages: the dataset is the
# controller's policy-scoped collection, never Model.all.
module Web::DataPageScope
  def scope
    base = Matestack::Ui::Core::Context.controller.send(:scoped_collection)
    order = resource.grid.order
    order && base.respond_to?(:order) ? base.order(order) : base
  end
end

class Web::ScopedIndex < DaisyStack::Ui::DataPage::Index
  include Web::DataPageScope
end

class Web::ScopedDetail < DaisyStack::Ui::DataPage::Detail
  include Web::DataPageScope
end

class Web::ScopedNew < DaisyStack::Ui::DataPage::New
  include Web::DataPageScope
end
```

Every resource in Task 12 declares `index_page Web::ScopedIndex`, `detail_page Web::ScopedDetail`, `new_page Web::ScopedNew`.

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/policies`
Expected: PASS. Also `bin/rails test` stays green (the admin users page still renders for `users(:keith)`).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "auth: Pundit policies for projects, backlog records and tokens; scoped DataPages"
```

---

### Task 5: API base controller, bearer auth, `/me` and `/doctor`

**Files:**
- Create: `app/controllers/api/v1/base_controller.rb`, `app/controllers/api/v1/me_controller.rb`, `app/controllers/api/v1/projects_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/integration/api/auth_test.rb`

**Interfaces:**
- Produces: `Api::V1::BaseController` (`ActionController::API`, `include Pundit::Authorization`, `current_user` from `Authorization: Bearer`, `current_project` from `params[:project_slug]` restricted by `policy_scope(Project)`, `render_error(status, error, detail)`; rescues `Pundit::NotAuthorizedError` → 403, `ActiveRecord::RecordNotFound` → 404, `ActiveRecord::RecordInvalid` → 422, `ApiError::Conflict` → 409). `GET /api/v1/me`, `GET /api/v1/projects/:project_slug/doctor`. Routes block `namespace :api { namespace :v1 { ... } }` with `scope "projects/:project_slug", as: :project do ... end` for later tasks.

- [ ] **Step 1: Write the failing test**

`test/integration/api/auth_test.rb`:

```ruby
require "test_helper"

class Api::AuthTest < ActionDispatch::IntegrationTest
  def auth(token) = { "Authorization" => "Bearer #{token}" }

  test "no token is 401" do
    get "/api/v1/me"
    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["error"]
  end

  test "revoked token is 401" do
    get "/api/v1/me", headers: auth("revoked-token")
    assert_response :unauthorized
  end

  test "me lists the user's projects and roles" do
    get "/api/v1/me", headers: auth("danny-token")
    assert_response :success
    body = response.parsed_body
    assert_equal users(:danny).id, body["user_id"]
    assert_equal [ { "slug" => "tekmore", "role" => "member" } ], body["projects"]
  end

  test "doctor on a project the user is not in is 404" do
    get "/api/v1/projects/tekmore/doctor", headers: auth("outsider-token")
    assert_response :not_found
  end

  test "doctor reports project and role" do
    get "/api/v1/projects/tekmore/doctor", headers: auth("viewer-token")
    assert_response :success
    assert_equal({ "project" => "tekmore", "role" => "viewer", "reachable" => true }, response.parsed_body)
  end

  test "token use stamps last_used_at" do
    get "/api/v1/me", headers: auth("keith-token")
    assert_not_nil api_tokens(:keith).reload.last_used_at
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bin/rails test test/integration/api/auth_test.rb`
Expected: FAIL (404 routing errors)

- [ ] **Step 3: Write the base controller and endpoints**

`app/controllers/api/v1/base_controller.rb`:

```ruby
module ApiError
  class Conflict < StandardError; end
end

class Api::V1::BaseController < ActionController::API
  include Pundit::Authorization

  before_action :authenticate_token!
  after_action :verify_authorized

  rescue_from Pundit::NotAuthorizedError do |e|
    render_error :forbidden, "forbidden", e.message
  end
  rescue_from ActiveRecord::RecordNotFound do |e|
    render_error :not_found, "not_found", e.message
  end
  rescue_from ActiveRecord::RecordInvalid do |e|
    render_error :unprocessable_entity, "invalid", e.record.errors.full_messages.join("; ")
  end
  rescue_from ApiError::Conflict do |e|
    render_error :conflict, "conflict", e.message
  end
  rescue_from ActionController::ParameterMissing do |e|
    render_error :unprocessable_entity, "invalid", e.message
  end

  attr_reader :current_user, :current_token

  private

  def authenticate_token!
    raw = request.authorization.to_s[/\ABearer\s+(.+)\z/, 1]
    @current_token = ApiToken.authenticate(raw)
    @current_user = @current_token&.user
    render_error(:unauthorized, "unauthorized", "missing or invalid bearer token") unless @current_user
  end

  def current_project
    @current_project ||= policy_scope(Project).live.find_by!(slug: params[:project_slug])
  end

  def render_error(status, error, detail)
    render json: { error: error, detail: detail }, status: status
  end

  def markdown_body
    request.body.rewind
    request.body.read.to_s
  end

  def body_params
    params.permit!.to_h.except("controller", "action", "project_slug", "format")
  end
end
```

`app/controllers/api/v1/me_controller.rb`:

```ruby
class Api::V1::MeController < Api::V1::BaseController
  def show
    skip_authorization
    render json: {
      user_id: current_user.id, name: current_user.display_name, email: current_user.email,
      projects: current_user.memberships.includes(:project).order("projects.slug")
                            .map { |m| { slug: m.project.slug, role: m.role } }
    }
  end
end
```

`app/controllers/api/v1/projects_controller.rb`:

```ruby
class Api::V1::ProjectsController < Api::V1::BaseController
  def doctor
    authorize current_project, :show?
    render json: { project: current_project.slug, role: current_project.role_for(current_user), reachable: true }
  end

  def brief
    authorize current_project, :show?
    render plain: Projects::BriefMarkdown.new(current_project).render, content_type: "text/markdown"
  end
end
```

(`brief` depends on Task 6's `Projects::BriefMarkdown`; leave the route out until Task 8.)

Add to `config/routes.rb` before `get "up"`:

```ruby
  namespace :api do
    namespace :v1 do
      get "me", to: "me#show"
      scope "projects/:project_slug", as: :project do
        get "doctor", to: "projects#doctor"
      end
    end
  end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/integration/api/auth_test.rb`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "api: bearer-token base controller, /me and /doctor"
```

---

### Task 6: Domain services — claim, rank, dependencies, flow, map, brief

**Files:**
- Create: `app/services/specs/claim.rb`, `app/services/specs/rank.rb`, `app/services/specs/dependencies.rb`, `app/services/specs/transitions.rb`, `app/services/projects/flow.rb`, `app/services/projects/map.rb`, `app/services/projects/brief_markdown.rb`
- Test: `test/services/specs/claim_test.rb`, `test/services/specs/rank_test.rb`, `test/services/specs/dependencies_test.rb`, `test/services/projects/flow_test.rb`, `test/services/projects/map_test.rb`, `test/services/projects/brief_markdown_test.rb`

**Interfaces:**
- Produces:
  - `Specs::Claim.new(project:, identity:, user:, label: nil, wip: 0, slug: nil).call -> Specs::Claim::Result` with `#result` (slug String or one of `WIP_FULL BLOCKED UNPRIORITISED NONE NOT_FOUND TAKEN`), `#spec`, `#run` (a `Run` created on success), `#claimed?`.
  - `Specs::Rank.new(project:, slugs:).call -> [Spec]` (raises `ApiError::Conflict` on a non-ready slug, `ActiveRecord::RecordNotFound` on unknown).
  - `Specs::Dependencies.deps(spec) -> [slug]`, `.dependents(spec) -> [slug]` (transitive, active only, BFS).
  - `Specs::Transitions.release!(spec)`, `.ship!(spec, run: nil)`, `.abandon!(spec, reason:, cascade: [])` (cascade: slugs of active dependents to abandon with the same reason).
  - `Projects::Flow.new(project).all -> [Hash]`, `.for(spec) -> Hash` with keys exactly `slug status in_progress created_at claimed_at shipped_at queue_wait_seconds cycle_seconds human_wait_seconds agent_seconds lead_seconds checkpoint_count open_checkpoint_count checkpoints[]`.
  - `Projects::Map.new(project).call -> { outcomes: [...], unlinked: {...}, orphaned: {...}, tags: {...} }` matching `bin/ag-store-adapters/local.rb#build_map`.
  - `Projects::BriefMarkdown.new(project).render -> String` (project brief with `## Prioritised outcomes` regenerated from open outcomes by rank).

- [ ] **Step 1: Write the failing claim tests**

`test/services/specs/claim_test.rb`:

```ruby
require "test_helper"

class Specs::ClaimTest < ActiveSupport::TestCase
  def claim(**opts)
    Specs::Claim.new(project: projects(:tekmore), identity: "sess-9", user: users(:danny), **opts).call
  end

  test "claims the lowest-rank eligible ready spec and opens a run" do
    r = claim(wip: 5)
    assert_equal "ready-a", r.result
    spec = specs(:tek_ready_a).reload
    assert spec.in_progress?
    assert_equal "sess-9", spec.claimed_by_session
    assert_equal users(:danny), spec.claimed_by_user
    assert_not_nil spec.claimed_at
    assert_equal spec, r.run.spec
    assert_equal "sess-9", r.run.runner_id
    assert r.run.active?
    assert_equal %w[started claimed], r.run.events.chronological.map(&:event)
  end

  test "WIP_FULL when in-progress count reaches the limit" do
    assert_equal "WIP_FULL", claim(wip: 1).result
  end

  test "wip 0 means unlimited" do
    assert_equal "ready-a", claim(wip: 0).result
  end

  test "targeted claim by slug ignores rank but respects deps" do
    assert_equal "ready-b", claim(wip: 5, slug: "ready-b").result
    assert_equal "BLOCKED", claim(wip: 5, slug: "blocked").result
    assert_equal "NOT_FOUND", claim(wip: 5, slug: "nope").result
    assert_equal "NOT_FOUND", claim(wip: 5, slug: "shipped-one").result
    assert_equal "TAKEN", claim(wip: 5, slug: "in-progress-spec").result
  end

  test "UNPRIORITISED when only unranked ready specs remain" do
    Spec.where(project: projects(:tekmore), status: "ready").where.not(rank: nil).update_all(rank: nil)
    assert_equal "UNPRIORITISED", claim(wip: 5).result
  end

  test "NONE when nothing is ready" do
    Spec.where(project: projects(:tekmore), status: "ready").update_all(status: "abandoned")
    assert_equal "NONE", claim(wip: 5).result
  end

  test "BLOCKED when every ranked spec has unshipped deps" do
    specs(:tek_ready_a).update!(status: "abandoned")
    specs(:tek_ready_b).update!(status: "abandoned")
    assert_equal "BLOCKED", claim(wip: 5).result
  end

  test "two concurrent claims get different specs" do
    results = []
    threads = 2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          results << Specs::Claim.new(project: projects(:tekmore), identity: "t#{i}", user: users(:danny), wip: 0).call.result
        end
      end
    end
    threads.each(&:join)
    assert_equal %w[ready-a ready-b], results.sort
  end
end
```

Note: the concurrency test needs the test DB shared across threads; `test_helper.rb` keeps `parallelize(workers: :number_of_processors)` (process-based) which is fine, but this one test must run without transactional fixtures — add `self.use_transactional_tests = false` at the top of the class and `teardown { Spec.where(claimed_by_session: %w[t0 t1]).update_all(status: "ready", claimed_by_session: nil, claimed_at: nil, claimed_by_user_id: nil); Run.where(runner_id: %w[t0 t1]).destroy_all }`.

- [ ] **Step 2: Run to see them fail**

Run: `bin/rails test test/services/specs/claim_test.rb`
Expected: FAIL with `uninitialized constant Specs::Claim`

- [ ] **Step 3: Implement `Specs::Claim`**

`app/services/specs/claim.rb`:

```ruby
# One transaction, one winner. SQLite serialises writers, so a BEGIN IMMEDIATE
# transaction plus a conditional UPDATE (WHERE status='ready' AND claimed_by
# IS NULL) is race-safe without .pull.lock. Return codes match ag-store.
class Specs::Claim
  Result = Struct.new(:result, :spec, :run, keyword_init: true) do
    def claimed? = spec.present?
  end

  def initialize(project:, identity:, user:, label: nil, wip: 0, slug: nil)
    @project, @identity, @user, @label = project, identity, user, label.presence
    @wip = wip.to_i
    @slug = slug.presence&.sub(/\A\d+-/, "")
  end

  def call
    2.times do
      outcome = attempt
      return outcome unless outcome.result == "RETRY"
    end
    Result.new(result: "NONE")
  end

  private

  def attempt
    Spec.transaction(isolation: nil) do
      Spec.connection.execute("BEGIN IMMEDIATE") if Spec.connection.adapter_name == "SQLite" && Spec.connection.open_transactions == 1 && !Spec.connection.transaction_open?
      in_progress = @project.specs.where(status: "in_progress").count
      return Result.new(result: "WIP_FULL") if @wip.positive? && in_progress >= @wip

      chosen = @slug ? targeted : from_queue
      return chosen if chosen.is_a?(Result)

      now = Time.current
      updated = Spec.where(id: chosen.id, status: "ready", claimed_by_session: [ nil, "" ])
                    .update_all(status: "in_progress", claimed_by_session: @identity, claimed_by_user_id: @user&.id,
                                claimed_at: now, label: @label, updated_at: now)
      return Result.new(result: "RETRY") if updated.zero?

      chosen.reload
      run = Runs::Start.call(project: @project, spec: chosen, runner_id: @identity, session_id: @identity, at: now)
      Result.new(result: chosen.slug, spec: chosen, run: run)
    end
  end

  def pool
    @project.specs.includes(:dependencies)
  end

  def targeted
    spec = pool.find_by(slug: @slug)
    return Result.new(result: "NOT_FOUND") if spec.nil? || spec.shipped? || spec.abandoned?
    return Result.new(result: "TAKEN") unless spec.ready? && spec.claimed_by_session.blank?
    return Result.new(result: "BLOCKED") unless spec.deps_shipped?
    spec
  end

  def from_queue
    ready = pool.where(status: "ready").unclaimed.to_a
    return Result.new(result: "NONE") if ready.empty?
    ranked = ready.select { |s| s.rank.present? }
    return Result.new(result: "UNPRIORITISED") if ranked.empty?
    eligible = ranked.select(&:deps_shipped?)
    return Result.new(result: "BLOCKED") if eligible.empty?
    eligible.min_by { |s| [ s.rank, s.slug ] }
  end
end
```

Simplify the `BEGIN IMMEDIATE` line: Rails 8.1's SQLite adapter takes `Spec.transaction(isolation: :read_uncommitted)`? No — use the adapter's supported form instead. Replace the first two lines of `attempt` with:

```ruby
    Spec.connection.transaction(joinable: false) do
      Spec.connection.execute("PRAGMA busy_timeout = 5000")
```

and rely on the conditional `update_all` (zero rows → RETRY) as the correctness guarantee; the two-thread test proves it. Keep `attempt` otherwise as written, closing the block with `end`.

`app/services/runs/start.rb` (needed by claim; the rest of `Runs` comes in Task 7):

```ruby
class Runs::Start
  def self.call(project:, spec:, runner_id:, session_id: nil, at: Time.current)
    run = project.runs.create!(spec: spec, runner_id: runner_id, session_id: session_id, status: "active",
                               started_at: at, last_event_at: at)
    run.events.create!(event: "started", at: at)
    run.events.create!(event: "claimed", at: at)
    run
  end
end
```

- [ ] **Step 4: Run the claim tests**

Run: `bin/rails test test/services/specs/claim_test.rb`
Expected: PASS (8 tests). If the two-thread test deadlocks, confirm `config/database.yml` has `timeout: 5000` (it does in the copied file).

- [ ] **Step 5: Write the failing rank, dependency and transition tests**

`test/services/specs/rank_test.rb`:

```ruby
require "test_helper"

class Specs::RankTest < ActiveSupport::TestCase
  test "writes dense ranks in the given order and pushes unlisted ready specs after" do
    Specs::Rank.new(project: projects(:tekmore), slugs: %w[blocked ready-b]).call
    assert_equal 1, specs(:tek_blocked).reload.rank
    assert_equal 2, specs(:tek_ready_b).reload.rank
    assert_equal 3, specs(:tek_ready_a).reload.rank
    assert_equal 4, specs(:tek_dependent).reload.rank
    assert_nil specs(:tek_unranked).reload.rank
  end

  test "refuses a non-ready slug" do
    assert_raises(ApiError::Conflict) { Specs::Rank.new(project: projects(:tekmore), slugs: %w[in-progress-spec]).call }
  end

  test "unknown slug is not found" do
    assert_raises(ActiveRecord::RecordNotFound) { Specs::Rank.new(project: projects(:tekmore), slugs: %w[zzz]).call }
  end
end
```

`test/services/specs/dependencies_test.rb`:

```ruby
require "test_helper"

class Specs::DependenciesTest < ActiveSupport::TestCase
  test "deps and transitive active dependents" do
    assert_equal %w[ready-a], Specs::Dependencies.deps(specs(:tek_dependent))
    grand = projects(:tekmore).specs.create!(slug: "grand", title: "Grand", status: "ready")
    grand.dependencies << specs(:tek_dependent)
    assert_equal %w[dependent grand], Specs::Dependencies.dependents(specs(:tek_ready_a)).sort
    grand.update!(status: "abandoned")
    assert_equal %w[dependent], Specs::Dependencies.dependents(specs(:tek_ready_a))
  end
end
```

`test/services/specs/transitions_test.rb`:

```ruby
require "test_helper"

class Specs::TransitionsTest < ActiveSupport::TestCase
  test "release returns an in-progress spec to ready and closes its run" do
    Specs::Transitions.release!(specs(:tek_in_progress))
    s = specs(:tek_in_progress).reload
    assert s.ready?
    assert_nil s.claimed_by_session
    assert runs(:active_run).reload.closed?
  end

  test "ship stamps shipped_at and marks the run shipped" do
    Specs::Transitions.ship!(specs(:tek_in_progress))
    s = specs(:tek_in_progress).reload
    assert s.shipped?
    assert_not_nil s.shipped_at
    assert runs(:active_run).reload.shipped?
    assert_equal "shipped", runs(:active_run).events.chronological.last.event
  end

  test "abandon records the reason and cascades" do
    Specs::Transitions.abandon!(specs(:tek_ready_a), reason: "no longer needed", cascade: %w[dependent])
    assert specs(:tek_ready_a).reload.abandoned?
    assert_equal "no longer needed", specs(:tek_ready_a).abandoned_reason
    assert specs(:tek_dependent).reload.abandoned?
  end
end
```

- [ ] **Step 6: Run to see them fail**

Run: `bin/rails test test/services/specs`
Expected: the three new files FAIL with uninitialized constants

- [ ] **Step 7: Implement rank, dependencies, transitions**

`app/services/specs/rank.rb`:

```ruby
class Specs::Rank
  def initialize(project:, slugs:)
    @project, @slugs = project, Array(slugs).map(&:to_s)
  end

  def call
    Spec.transaction do
      listed = @slugs.map { |s| @project.specs.find_by!(slug: s) }
      bad = listed.reject(&:ready?)
      raise ApiError::Conflict, "not ready: #{bad.map(&:slug).join(', ')}" if bad.any?
      rest = @project.specs.where(status: "ready").where.not(id: listed.map(&:id)).where.not(rank: nil).ranked.to_a
      (listed + rest).each_with_index { |spec, i| spec.update_columns(rank: i + 1, updated_at: Time.current) }
      listed
    end
  end
end
```

`app/services/specs/dependencies.rb`:

```ruby
module Specs::Dependencies
  module_function

  def deps(spec)
    spec.dependencies.order(:slug).pluck(:slug)
  end

  # Transitive dependents that are still active (ready/in_progress), BFS.
  def dependents(spec)
    seen = {}
    queue = [ spec ]
    until queue.empty?
      current = queue.shift
      current.dependents.active.each do |d|
        next if seen[d.slug]
        seen[d.slug] = true
        queue << d
      end
    end
    seen.keys.sort
  end
end
```

`app/services/specs/transitions.rb`:

```ruby
module Specs::Transitions
  module_function

  def release!(spec)
    Spec.transaction do
      spec.update!(status: "ready", claimed_by_session: nil, claimed_by_user: nil, claimed_at: nil, label: nil)
      spec.runs.live.each { |run| Runs::Close.call(run, status: "closed", detail: "released") }
    end
    spec
  end

  def ship!(spec, run: nil)
    Spec.transaction do
      now = Time.current
      spec.update!(status: "shipped", shipped_at: now)
      (run ? [ run ] : spec.runs.live).each { |r| Runs::Close.call(r, status: "shipped", at: now) }
    end
    spec
  end

  def abandon!(spec, reason:, cascade: [])
    Spec.transaction do
      now = Time.current
      spec.update!(status: "abandoned", abandoned_reason: reason, abandoned_at: now,
                   claimed_by_session: nil, claimed_by_user: nil)
      spec.runs.live.each { |r| Runs::Close.call(r, status: "closed", at: now, detail: "abandoned") }
      Array(cascade).each do |slug|
        dep = spec.project.specs.active.find_by(slug: slug) or next
        abandon!(dep, reason: "cascade: #{spec.slug} abandoned (#{reason})")
      end
    end
    spec
  end
end
```

`app/services/runs/close.rb` (final form; Task 7 tests it):

```ruby
class Runs::Close
  def self.call(run, status: "closed", at: Time.current, detail: nil)
    Run.transaction do
      run.events.create!(event: (status == "closed" ? "closed" : status), at: at, detail: detail)
      run.update!(status: status, ended_at: at, last_event_at: at, detail: detail || run.detail)
    end
    run
  end
end
```

- [ ] **Step 8: Run the spec service tests**

Run: `bin/rails test test/services/specs`
Expected: PASS

- [ ] **Step 9: Write the failing flow, map and brief tests**

`test/services/projects/flow_test.rb`:

```ruby
require "test_helper"

class Projects::FlowTest < ActiveSupport::TestCase
  test "shipped spec has lead time and cycle time" do
    f = Projects::Flow.new(projects(:tekmore)).for(specs(:tek_shipped))
    assert_equal "shipped-one", f[:slug]
    assert_equal false, f[:in_progress]
    assert_in_delta 5.days.to_i, f[:lead_seconds], 5
    assert_in_delta 1.day.to_i, f[:cycle_seconds], 5
    assert_in_delta 4.days.to_i, f[:queue_wait_seconds], 5
    assert_equal 1, f[:checkpoint_count]
    assert_equal 0, f[:open_checkpoint_count]
  end

  test "in-progress spec measures cycle to now and counts open checkpoint wait" do
    f = Projects::Flow.new(projects(:tekmore)).for(specs(:tek_in_progress))
    assert_equal true, f[:in_progress]
    assert_in_delta 2.hours.to_i, f[:human_wait_seconds], 5
    assert_in_delta 22.hours.to_i, f[:agent_seconds], 5
    assert_nil f[:lead_seconds]
    assert_equal "ship_approval", f[:checkpoints].first[:reason]
  end

  test "all returns every spec sorted by slug" do
    slugs = Projects::Flow.new(projects(:tekmore)).all.map { |f| f[:slug] }
    assert_equal slugs.sort, slugs
    assert_includes slugs, "abandoned-one"
  end
end
```

`test/services/projects/map_test.rb`:

```ruby
require "test_helper"

class Projects::MapTest < ActiveSupport::TestCase
  test "groups specs by outcome and status, flags blocked, indexes tags" do
    m = Projects::Map.new(projects(:tekmore)).call
    onboarding = m[:outcomes].find { |o| o[:slug] == "faster-onboarding" }
    assert_equal %w[ready-a], onboarding[:specs]["ready"]
    assert_equal %w[shipped-one], onboarding[:specs]["shipped"]
    assert_includes m[:unlinked]["ready"], "blocked"
    assert_includes m[:unlinked][:blocked], "blocked"
    assert_equal %w[ready-a], m[:tags]["api"]
  end
end
```

`test/services/projects/brief_markdown_test.rb`:

```ruby
require "test_helper"

class Projects::BriefMarkdownTest < ActiveSupport::TestCase
  test "regenerates the prioritised outcomes section from open outcomes by rank" do
    md = Projects::BriefMarkdown.new(projects(:tekmore)).render
    assert_includes md, "## Prioritised outcomes\n\n1. **Faster onboarding** — New users reach first value in under a day\n2. **Fewer support tickets** — Tickets fall by a third\n"
    assert_not_includes md, "- old"
    assert_includes md, "## Constraints\n\nnone"
  end

  test "appends the section when the brief lacks it" do
    projects(:other).update!(brief: "# Other\n\nHello\n")
    md = Projects::BriefMarkdown.new(projects(:other)).render
    assert_includes md, "## Prioritised outcomes\n\n_No open outcomes yet._"
  end
end
```

- [ ] **Step 10: Implement flow, map, brief**

`app/services/projects/flow.rb`:

```ruby
# Flow metrics, ported from bin/ag-store-adapters/local.rb#compute_flow.
class Projects::Flow
  def initialize(project, now: Time.current)
    @project, @now = project, now.utc
  end

  def all
    @project.specs.includes(checkpoints: []).order(:slug).map { |s| self.for(s) }
  end

  def for(spec)
    created, claimed, shipped = spec.created_at&.utc, spec.claimed_at&.utc, spec.shipped_at&.utc
    in_progress = shipped.nil? && !claimed.nil?
    cycle_end = shipped || (in_progress ? @now : nil)
    cps = spec.checkpoints.oldest_first.map do |c|
      ended = c.answered_at&.utc || cycle_end || @now
      { reason: c.reason, asked_by: c.asked_by, status: c.status,
        asked_at: AgTime.iso(c.asked_at), answered_at: AgTime.iso(c.answered_at),
        wait_seconds: secs(c.asked_at.utc, ended) }
    end
    human = cps.sum { |c| c[:wait_seconds].to_i }
    cycle = secs(claimed, cycle_end)
    {
      slug: spec.slug, status: spec.status, in_progress: in_progress,
      created_at: AgTime.iso(created), claimed_at: AgTime.iso(claimed), shipped_at: AgTime.iso(shipped),
      queue_wait_seconds: secs(created, claimed),
      cycle_seconds: cycle,
      human_wait_seconds: (cycle.nil? ? nil : human),
      agent_seconds: (cycle.nil? ? nil : [ cycle - human, 0 ].max),
      lead_seconds: secs(created, shipped),
      checkpoint_count: cps.length,
      open_checkpoint_count: cps.count { |c| c[:status] != "answered" },
      checkpoints: cps
    }
  end

  private

  def secs(from, to)
    return nil if from.nil? || to.nil?
    (to - from).to_i
  end
end
```

`app/services/projects/map.rb`:

```ruby
class Projects::Map
  STATES = %w[ready in_progress shipped abandoned].freeze

  def initialize(project)
    @project = project
  end

  def call
    outcomes = @project.outcomes.ranked.map do |o|
      { slug: o.slug, title: o.title, status: o.status, rank: o.rank, created: AgTime.iso(o.created_at),
        achieved_at: AgTime.iso(o.achieved_at), abandoned_at: AgTime.iso(o.abandoned_at) }
    end
    known = outcomes.map { |o| o[:slug] }
    by_outcome = Hash.new { |h, k| h[k] = STATES.index_with { [] } }
    unlinked = STATES.index_with { [] }
    blocked = Hash.new { |h, k| h[k] = [] }
    orphaned = Hash.new { |h, k| h[k] = [] }
    tags = Hash.new { |h, k| h[k] = [] }

    @project.specs.includes(:serves_outcome, :dependencies).order(:slug).each do |s|
      serves = s.serves_outcome&.slug.to_s
      if serves.empty? then unlinked[s.status] << s.slug
      elsif known.include?(serves) then by_outcome[serves][s.status] << s.slug
      else orphaned[serves] << s.slug
      end
      blocked[serves] << s.slug if s.blocked?
      Array(s.tags).each { |t| tags[t.to_s] << s.slug }
    end

    {
      outcomes: outcomes.map { |o| o.merge(specs: by_outcome[o[:slug]], blocked: blocked[o[:slug]]) },
      unlinked: unlinked.merge(blocked: blocked[""]),
      orphaned: orphaned.sort.to_h,
      tags: tags.sort.to_h
    }
  end
end
```

`app/services/projects/brief_markdown.rb`:

```ruby
class Projects::BriefMarkdown
  HEADING = "## Prioritised outcomes".freeze

  def initialize(project)
    @project = project
  end

  def render
    brief = @project.brief.to_s
    brief = "# #{@project.name}\n" if brief.strip.empty?
    section = "#{HEADING}\n\n#{outcomes_list}\n"
    if brief.include?(HEADING)
      brief.sub(/#{Regexp.escape(HEADING)}\n.*?(?=\n## |\z)/m, section.rstrip + "\n")
    else
      "#{brief.rstrip}\n\n#{section}"
    end
  end

  private

  def outcomes_list
    open = @project.outcomes.where(status: "open").ranked
    return "_No open outcomes yet._" if open.empty?
    open.each_with_index.map { |o, i| "#{i + 1}. **#{o.title}** — #{o.claim.to_s.strip}" }.join("\n")
  end
end
```

- [ ] **Step 11: Run all service tests**

Run: `bin/rails test test/services`
Expected: PASS

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "services: transactional claim, rank, dependencies, transitions, flow, map, brief"
```

---

### Task 7: Checkpoint and run services

**Files:**
- Create: `app/services/checkpoints/open.rb`, `app/services/checkpoints/answer.rb`, `app/services/runs/event.rb`
- Test: `test/services/checkpoints_test.rb`, `test/services/runs_test.rb`

**Interfaces:**
- Produces: `Checkpoints::Open.call(run:, reason:, asked_by:, ask:, session_id: nil) -> Checkpoint` (seq assigned under the spec row lock, run → `paused`, run event `paused`); `Checkpoints::Answer.call(checkpoint, answer:, by: User|String) -> Checkpoint` (status answered, run back to `active` when no open checkpoint remains, run event `idle` with detail "checkpoint answered"); `Runs::Event.call(run, event:, detail: nil, at:) -> RunEvent` (updates `run.status`: `paused`→paused, `shipped`→shipped, `failed`→failed, `deployed`/`closed`→closed, `idle`/`started`/`claimed`→active, and `ended_at` for terminal events).

- [ ] **Step 1: Write the failing tests**

`test/services/checkpoints_test.rb`:

```ruby
require "test_helper"

class CheckpointsTest < ActiveSupport::TestCase
  test "open assigns the next seq, pauses the run and logs an event" do
    run = runs(:active_run)
    cp = Checkpoints::Open.call(run: run, reason: "question", asked_by: "builder", ask: "Which DB?", session_id: "sess-1")
    assert_equal 2, cp.seq
    assert cp.open?
    assert run.reload.paused?
    assert_equal "paused", run.events.chronological.last.event
    assert_equal "in-progress-spec #002 question", cp.ref
  end

  test "open rejects an unknown reason" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Checkpoints::Open.call(run: runs(:active_run), reason: "nope", asked_by: "build", ask: "?")
    end
  end

  test "answer resumes the run when nothing else is open" do
    cp = Checkpoints::Answer.call(checkpoints(:open_ship), answer: "approved", by: users(:keith))
    assert cp.answered?
    assert_equal users(:keith), cp.answered_by
    assert_not_nil cp.answered_at
    assert runs(:active_run).reload.active?
  end

  test "answer keeps the run paused while another checkpoint is open" do
    Checkpoints::Open.call(run: runs(:active_run), reason: "question", asked_by: "builder", ask: "?")
    Checkpoints::Answer.call(checkpoints(:open_ship), answer: "yes", by: "keith")
    assert runs(:active_run).reload.paused?
  end

  test "answering twice is a conflict" do
    assert_raises(ApiError::Conflict) { Checkpoints::Answer.call(checkpoints(:answered_plan), answer: "again", by: "x") }
  end
end
```

`test/services/runs_test.rb`:

```ruby
require "test_helper"

class RunsTest < ActiveSupport::TestCase
  test "event updates run status and timestamps" do
    run = runs(:active_run)
    Runs::Event.call(run, event: "idle")
    assert run.reload.active?
    Runs::Event.call(run, event: "failed", detail: "gate red")
    assert run.reload.failed?
    assert_not_nil run.ended_at
    assert_equal "gate red", run.detail
  end

  test "close appends a closed event" do
    run = runs(:active_run)
    Runs::Close.call(run)
    assert run.reload.closed?
    assert_equal "closed", run.events.chronological.last.event
  end
end
```

- [ ] **Step 2: Run to see them fail**

Run: `bin/rails test test/services/checkpoints_test.rb test/services/runs_test.rb`
Expected: FAIL with uninitialized constants

- [ ] **Step 3: Implement**

`app/services/checkpoints/open.rb`:

```ruby
class Checkpoints::Open
  def self.call(run:, reason:, asked_by:, ask:, session_id: nil, at: Time.current)
    Checkpoint.transaction do
      spec = run.spec.lock!
      seq = spec.checkpoints.maximum(:seq).to_i + 1
      cp = spec.checkpoints.create!(run: run, seq: seq, reason: reason, asked_by: asked_by, ask: ask,
                                    session_id: session_id || run.session_id, asked_at: at, status: "open")
      Runs::Event.call(run, event: "paused", detail: reason, at: at)
      cp
    end
  end
end
```

`app/services/checkpoints/answer.rb`:

```ruby
class Checkpoints::Answer
  def self.call(checkpoint, answer:, by:, at: Time.current)
    raise ApiError::Conflict, "checkpoint #{checkpoint.ref} is already answered" if checkpoint.answered?
    Checkpoint.transaction do
      user = by.is_a?(User) ? by : User.find_by(email: by.to_s)
      checkpoint.update!(status: "answered", answer: answer, answered_at: at, answered_by: user)
      run = checkpoint.run
      unless run.checkpoints.where(status: "open").exists?
        Runs::Event.call(run, event: "idle", detail: "checkpoint #{checkpoint.seq} answered", at: at)
      end
      checkpoint
    end
  end
end
```

`app/services/runs/event.rb`:

```ruby
class Runs::Event
  STATUS_FOR = { "paused" => "paused", "shipped" => "shipped", "failed" => "failed",
                 "deployed" => "closed", "closed" => "closed" }.freeze

  def self.call(run, event:, detail: nil, at: Time.current)
    Run.transaction do
      ev = run.events.create!(event: event, detail: detail, at: at)
      status = STATUS_FOR.fetch(event, "active")
      attrs = { status: status, last_event_at: at }
      attrs[:ended_at] = at if RunEvent::TERMINAL.include?(event)
      attrs[:detail] = detail if detail.present?
      run.update!(attrs)
      ev
    end
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/services`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "services: checkpoints open/answer with server-side seq, run events and status"
```

---

### Task 8: API controllers for every §5 endpoint

**Files:**
- Create: `app/controllers/api/v1/{inbox,specs,outcomes,checkpoints,runs}_controller.rb`, `app/serializers/{spec_summary,inbox_item_json,outcome_json,checkpoint_json,run_json}.rb`
- Modify: `config/routes.rb`, `app/controllers/api/v1/projects_controller.rb`
- Test: `test/integration/api/{inbox,specs,outcomes,checkpoints,runs,brief_map_flow}_test.rb`

**Interfaces:**
- Consumes: Tasks 5–7 services and `Spec::Markdown`.
- Produces: the endpoints in spec §5 with these JSON shapes:
  - `SpecSummary.call(spec) -> { slug, prefix, path, status, title, created_at, business_value, technical_certainty, route, depends_on[], claimed_by, claimed_at, label, shipped_at, serves, tags[] }` (`prefix` = rank, `path` = `docs/agentile/specs/<slug>`).
  - `InboxItemJson.call(item) -> { id, title, text, type, captured_at, captured_by, captured_by_id, serves, status, suggested_kind, suggested_outcome, duplicate_of, duplicate_probability }`.
  - `OutcomeJson.call(o) -> { slug, title, status, rank, created, achieved_at, abandoned_at }`.
  - `CheckpointJson.call(c) -> { id, seq, ref, reason, asked_by, asked_at, session_id, status, answered_at, answered_by, ask, answer, priority, run_id, spec }`.
  - `RunJson.call(run) -> { id, spec, runner_id, session_id, status, started_at, ended_at, last_event_at, detail, events: [{event, at, detail}] }` — `runner_id` (not `runner`) because the plugin client matches its own active run on that key.
  - `Inbox::Assist` (Task 10) is called by `POST /inbox/assist`; until Task 10 lands, the controller calls `Inbox::Assist.call(project:, text:)` which this task stubs as returning `{ title:, text:, kind: "feature", serves_outcome_slug: nil, duplicate_of: nil, duplicate_probability: nil, judgment_id: nil }` from a plain first-line/rest split — Task 10 replaces the body, not the signature.

- [ ] **Step 1: Write the failing inbox API test**

`test/integration/api/inbox_test.rb`:

```ruby
require "test_helper"

class Api::InboxTest < ActionDispatch::IntegrationTest
  def auth(token = "danny-token") = { "Authorization" => "Bearer #{token}" }
  BASE = "/api/v1/projects/tekmore".freeze

  test "list returns open stubs newest first with the ag-store keys" do
    get "#{BASE}/inbox", headers: auth
    assert_response :success
    rows = response.parsed_body
    assert_equal %w[Login\ page\ slow Add\ CSV\ export], rows.map { |r| r["title"] }
    assert_equal %w[id title text type captured_at captured_by captured_by_id serves status suggested_kind suggested_outcome duplicate_of duplicate_probability].sort, rows.first.keys.sort
    assert_equal "Keith", rows.last["captured_by"]
  end

  test "add creates an open stub attributed to the token user" do
    assert_difference "InboxItem.count", 1 do
      post "#{BASE}/inbox", params: { text: "Export as PDF", title: "PDF export", type: "feature", serves: "faster-onboarding" }, as: :json, headers: auth
    end
    assert_response :created
    item = InboxItem.last
    assert_equal users(:danny), item.captured_by
    assert_equal outcomes(:faster_onboarding), item.serves_outcome
    assert_equal true, response.parsed_body["ok"]
  end

  test "add derives a title from the text when none is given" do
    post "#{BASE}/inbox", params: { text: "Make the login faster on mobile. It is slow." }, as: :json, headers: auth
    assert_equal "Make the login faster on mobile", InboxItem.last.title
  end

  test "viewer cannot add" do
    post "#{BASE}/inbox", params: { text: "x" }, as: :json, headers: auth("viewer-token")
    assert_response :forbidden
  end

  test "drop marks the stub dropped" do
    post "#{BASE}/inbox/#{inbox_items(:open_one).id}/drop", headers: auth
    assert_response :success
    assert inbox_items(:open_one).reload.dropped?
  end

  test "assist returns suggestions without saving" do
    assert_no_difference "InboxItem.count" do
      post "#{BASE}/inbox/assist", params: { text: "Add dark mode\nusers keep asking" }, as: :json, headers: auth
    end
    assert_response :success
    assert_equal "Add dark mode", response.parsed_body["title"]
    assert_includes response.parsed_body.keys, "kind"
  end

  test "shape creates the spec from markdown and marks the stub shaped" do
    md = "---\nslug: csv-export\nstatus: ready\ntype: feature\n---\n\n# CSV export\n\n## Acceptance criteria\n\n- exports\n"
    post "#{BASE}/inbox/#{inbox_items(:open_one).id}/shape", params: md, headers: auth.merge("Content-Type" => "text/markdown")
    assert_response :created
    spec = projects(:tekmore).specs.find_by!(slug: "csv-export")
    assert_equal inbox_items(:open_one), spec.source_inbox_item
    assert_equal users(:keith), spec.captured_by
    assert_includes spec.shapers, users(:danny)
    assert inbox_items(:open_one).reload.shaped?
    assert_equal "csv-export", response.parsed_body["slug"]
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bin/rails test test/integration/api/inbox_test.rb`
Expected: FAIL (routing errors)

- [ ] **Step 3: Serializers**

`app/serializers/spec_summary.rb`:

```ruby
module SpecSummary
  module_function

  def call(spec)
    {
      slug: spec.slug, prefix: spec.rank, path: spec.plan_path, status: spec.status, title: spec.title,
      created_at: AgTime.iso(spec.created_at), business_value: spec.business_value,
      technical_certainty: spec.technical_certainty, route: spec.route,
      depends_on: spec.dependencies.map(&:slug).sort, claimed_by: spec.claimed_by_session,
      claimed_at: AgTime.iso(spec.claimed_at), label: spec.label, shipped_at: AgTime.iso(spec.shipped_at),
      serves: spec.serves_outcome&.slug, tags: Array(spec.tags),
      needs_review: spec.needs_review, kind: spec.kind
    }
  end
end
```

`app/serializers/inbox_item_json.rb`:

```ruby
module InboxItemJson
  module_function

  def call(item)
    {
      id: item.id, title: item.title, text: item.text, type: item.kind,
      captured_at: AgTime.iso(item.captured_at), captured_by: item.captured_by&.display_name,
      captured_by_id: item.captured_by_id, serves: item.serves_outcome&.slug, status: item.status,
      suggested_kind: item.suggested_kind, suggested_outcome: item.suggested_outcome&.slug,
      duplicate_of: item.duplicate_of_id, duplicate_probability: item.duplicate_probability
    }
  end
end
```

`app/serializers/outcome_json.rb`:

```ruby
module OutcomeJson
  module_function

  def call(o)
    { slug: o.slug, title: o.title, status: o.status, rank: o.rank, created: AgTime.iso(o.created_at),
      achieved_at: AgTime.iso(o.achieved_at), abandoned_at: AgTime.iso(o.abandoned_at) }
  end
end
```

`app/serializers/checkpoint_json.rb`:

```ruby
module CheckpointJson
  module_function

  def call(c)
    { id: c.id, seq: c.seq, ref: c.ref, reason: c.reason, asked_by: c.asked_by, asked_at: AgTime.iso(c.asked_at),
      session_id: c.session_id, status: c.status, answered_at: AgTime.iso(c.answered_at),
      answered_by: c.answered_by&.display_name.to_s, ask: c.ask.to_s, answer: c.answer.to_s,
      priority: c.priority, run_id: c.run_id, spec: c.spec.slug }
  end
end
```

`app/serializers/run_json.rb`:

```ruby
module RunJson
  module_function

  def call(run, events: true)
    h = { id: run.id, spec: run.spec.slug, runner_id: run.runner_id, session_id: run.session_id, status: run.status,
          started_at: AgTime.iso(run.started_at), ended_at: AgTime.iso(run.ended_at),
          last_event_at: AgTime.iso(run.last_event_at), detail: run.detail.to_s }
    h[:events] = run.events.chronological.map { |e| { event: e.event, at: AgTime.iso(e.at), detail: e.detail.to_s } } if events
    h
  end
end
```

- [ ] **Step 4: Inbox controller and routes**

`app/controllers/api/v1/inbox_controller.rb`:

```ruby
class Api::V1::InboxController < Api::V1::BaseController
  def index
    authorize InboxItem, :index?
    scope = current_project.inbox_items.includes(:captured_by, :serves_outcome, :suggested_outcome).recent_first
    scope = scope.where(status: params[:status].presence || "open")
    render json: scope.map { |i| InboxItemJson.call(i) }
  end

  def create
    item = current_project.inbox_items.new(
      text: params[:text].to_s, title: params[:title].presence || derive_title(params[:text]),
      kind: params[:kind].presence || params[:type].presence || "feature", captured_by: current_user,
      serves_outcome: find_outcome(params[:serves]),
      suggested_kind: params[:suggested_kind].presence, duplicate_of_id: params[:duplicate_of].presence,
      duplicate_probability: params[:duplicate_probability].presence
    )
    authorize item, :create?
    item.save!
    render json: { ok: true, id: item.id }, status: :created
  end

  def drop
    item = find_item
    authorize item, :drop?
    item.update!(status: "dropped")
    render json: { ok: true }
  end

  def assist
    authorize InboxItem, :assist?
    render json: Inbox::Assist.call(project: current_project, text: params.require(:text).to_s)
  end

  def shape
    item = find_item
    authorize item, :shape?
    spec = current_project.specs.new(source_inbox_item: item, captured_by: item.captured_by)
    Spec.transaction do
      spec.apply_markdown!(markdown_body)
      spec.shapers << current_user unless spec.shapers.include?(current_user)
      item.update!(status: "shaped")
    end
    render json: SpecSummary.call(spec), status: :created
  end

  private

  def find_item = current_project.inbox_items.find(params[:id])

  def find_outcome(slug)
    slug.present? ? current_project.outcomes.find_by!(slug: slug) : nil
  end

  def derive_title(text)
    text.to_s.lines.first.to_s.strip.split(/(?<=[.!?])\s/).first.to_s.sub(/[.!?]\z/, "").truncate(80)
  end
end
```

Temporary `app/services/inbox/assist.rb` (replaced in Task 10):

```ruby
class Inbox::Assist
  def self.call(project:, text:)
    first, rest = text.to_s.strip.split("\n", 2)
    { title: first.to_s.strip.truncate(80), text: (rest.presence || first).to_s.strip, kind: "feature",
      serves_outcome_slug: nil, duplicate_of: nil, duplicate_probability: nil, judgment_id: nil }
  end
end
```

Routes — replace the `scope "projects/:project_slug"` block with:

```ruby
      scope "projects/:project_slug", as: :project do
        get "doctor", to: "projects#doctor"
        get "brief", to: "projects#brief"
        get "map", to: "projects#map"
        get "flow", to: "projects#flow"
        get "flow/:slug", to: "projects#flow"

        resources :inbox, only: [ :index, :create ], controller: :inbox do
          collection { post :assist }
          member { post :drop; post :shape }
        end

        put "specs/rank", to: "specs#rank"
        post "specs/claim", to: "specs#claim"
        resources :specs, only: [ :index, :show, :create, :update ], param: :slug, constraints: { slug: /[^\/]+/ } do
          member do
            post :release; post :ship; post :abandon
            get :deps; get :dependents; get :checkpoints
          end
        end

        put "outcomes/rank", to: "outcomes#rank"
        resources :outcomes, only: [ :index, :show, :create, :update ], param: :slug do
          member { post :achieve; post :abandon }
        end

        resources :runs, only: [ :index, :create ] do
          member { post :events; post :close }
          resources :checkpoints, only: [ :create ]
        end
        post "checkpoints/:id/answer", to: "checkpoints#answer"
      end
```

`GET /specs/:slug.md` works through `param: :slug` with `format: :md` — the constraint above stops Rails eating the dot; the controller checks `request.format`.

- [ ] **Step 5: Run the inbox test**

Run: `bin/rails test test/integration/api/inbox_test.rb`
Expected: PASS (7 tests)

- [ ] **Step 6: Write the failing specs API test**

`test/integration/api/specs_test.rb`:

```ruby
require "test_helper"

class Api::SpecsTest < ActionDispatch::IntegrationTest
  def auth(token = "danny-token") = { "Authorization" => "Bearer #{token}" }
  BASE = "/api/v1/projects/tekmore".freeze

  test "list active specs with ag-store keys, filter by status and pool" do
    get "#{BASE}/specs", headers: auth
    assert_response :success
    rows = response.parsed_body
    assert_equal %w[ready in_progress].to_set, rows.map { |r| r["status"] }.to_set
    assert_equal %w[slug prefix path status title created_at business_value technical_certainty route depends_on claimed_by claimed_at label shipped_at serves tags needs_review kind].sort, rows.first.keys.sort
    assert_equal "docs/agentile/specs/ready-a", rows.find { |r| r["slug"] == "ready-a" }["path"]

    get "#{BASE}/specs?pool=done", headers: auth
    assert_equal %w[shipped-one], response.parsed_body.map { |r| r["slug"] }
    get "#{BASE}/specs?status=in_progress", headers: auth
    assert_equal %w[in-progress-spec], response.parsed_body.map { |r| r["slug"] }
  end

  test "show as json and as markdown" do
    get "#{BASE}/specs/ready-a", headers: auth
    assert_response :success
    assert_equal "Ready A", response.parsed_body["title"]
    assert_equal "Why A", response.parsed_body["problem_why_now"]
    get "#{BASE}/specs/ready-a.md", headers: auth
    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_match(/^slug: ready-a$/, response.body)
  end

  test "create from markdown" do
    md = "---\nslug: new-one\ntype: chore\n---\n\n# New one\n\n## Acceptance criteria\n\n- x\n"
    post "#{BASE}/specs", params: md, headers: auth.merge("Content-Type" => "text/markdown")
    assert_response :created
    assert_equal "new-one", response.parsed_body["slug"]
    assert projects(:tekmore).specs.find_by(slug: "new-one").ready?
  end

  test "duplicate slug is 422" do
    post "#{BASE}/specs", params: "---\nslug: ready-a\n---\n\n# dup\n", headers: auth.merge("Content-Type" => "text/markdown")
    assert_response :unprocessable_entity
  end

  test "update fields incl. list values" do
    patch "#{BASE}/specs/ready-a", params: { route: "spike", tags: [ "a", "b" ], depends_on: [ "ready-b" ] }, as: :json, headers: auth
    assert_response :success
    s = specs(:tek_ready_a).reload
    assert_equal "spike", s.route
    assert_equal %w[a b], s.tags
    assert_equal %w[ready-b], s.dependencies.map(&:slug)
  end

  test "rank" do
    put "#{BASE}/specs/rank", params: { slugs: %w[ready-b ready-a] }, as: :json, headers: auth
    assert_response :success
    assert_equal %w[ready-b ready-a], response.parsed_body["ranked"].first(2)
    assert_equal 1, specs(:tek_ready_b).reload.rank
  end

  test "rank of a non-ready spec is 409" do
    put "#{BASE}/specs/rank", params: { slugs: %w[in-progress-spec] }, as: :json, headers: auth
    assert_response :conflict
  end

  test "claim returns the slug and a run id, then WIP_FULL" do
    post "#{BASE}/specs/claim", params: { identity: "sess-x", label: "lbl", wip: 2 }, as: :json, headers: auth
    assert_response :success
    assert_equal "ready-a", response.parsed_body["result"]
    assert Run.exists?(response.parsed_body["run_id"])
    post "#{BASE}/specs/claim", params: { identity: "sess-y", wip: 2 }, as: :json, headers: auth
    assert_equal "WIP_FULL", response.parsed_body["result"]
    assert_nil response.parsed_body["run_id"]
  end

  test "release, ship, abandon" do
    post "#{BASE}/specs/in-progress-spec/release", headers: auth
    assert_response :success
    assert specs(:tek_in_progress).reload.ready?

    post "#{BASE}/specs/claim", params: { identity: "s", slug: "ready-a" }, as: :json, headers: auth
    post "#{BASE}/specs/ready-a/ship", headers: auth
    assert_response :success
    assert specs(:tek_ready_a).reload.shipped?

    post "#{BASE}/specs/ready-b/abandon", params: { reason: "meh" }, as: :json, headers: auth
    assert_response :success
    assert_equal "meh", specs(:tek_ready_b).reload.abandoned_reason
  end

  test "deps, dependents and checkpoints" do
    get "#{BASE}/specs/dependent/deps", headers: auth
    assert_equal %w[ready-a], response.parsed_body
    get "#{BASE}/specs/ready-a/dependents", headers: auth
    assert_equal %w[dependent], response.parsed_body
    get "#{BASE}/specs/in-progress-spec/checkpoints", headers: auth
    assert_equal [ "Diff is green. Ship it?" ], response.parsed_body.map { |c| c["ask"] }
  end

  test "viewer cannot claim" do
    post "#{BASE}/specs/claim", params: { identity: "v" }, as: :json, headers: auth("viewer-token")
    assert_response :forbidden
  end
end
```

- [ ] **Step 7: Specs controller**

`app/controllers/api/v1/specs_controller.rb`:

```ruby
class Api::V1::SpecsController < Api::V1::BaseController
  POOLS = { "active" => %w[ready in_progress], "done" => %w[shipped], "abandoned" => %w[abandoned] }.freeze
  LIST_FIELDS = %w[depends_on tags shaped_by].freeze
  WRITABLE = %w[title status kind type route business_value technical_certainty rank label outcome problem_why_now
                acceptance_criteria scope_in scope_out edge_cases affected_areas open_questions verification
                abandoned_reason serves needs_review].freeze

  def index
    authorize Spec, :index?
    statuses = POOLS.fetch(params[:pool].presence || "active") { raise ActionController::BadRequest, "unknown pool" }
    scope = current_project.specs.includes(:dependencies, :serves_outcome).where(status: statuses)
    scope = scope.where(status: params[:status]) if params[:status].present?
    render json: scope.ranked.map { |s| SpecSummary.call(s) }
  end

  def show
    spec = find_spec
    authorize spec, :show?
    if request.format.symbol == :md || params[:format] == "md"
      render plain: spec.to_markdown, content_type: "text/markdown"
    else
      render json: SpecSummary.call(spec).merge(spec.slice(*Spec::SECTIONS.map(&:to_s), "abandoned_reason", "needs_review_reason"))
                                        .merge(shaped_by: spec.shapers.map(&:email), captured_by: spec.captured_by&.email)
    end
  end

  def create
    spec = current_project.specs.new(captured_by: current_user)
    authorize spec, :create?
    spec.apply_markdown!(markdown_body)
    render json: SpecSummary.call(spec), status: :created
  end

  def update
    spec = find_spec
    authorize spec, :update?
    attrs = body_params.slice(*WRITABLE)
    attrs["kind"] = attrs.delete("type") if attrs.key?("type")
    serves = attrs.delete("serves")
    Spec.transaction do
      spec.assign_attributes(attrs)
      spec.serves_outcome = serves.present? ? current_project.outcomes.find_by!(slug: serves) : nil if body_params.key?("serves")
      spec.tags = list(body_params["tags"]) if body_params.key?("tags")
      spec.save!
      spec.dependencies = list(body_params["depends_on"]).map { |s| current_project.specs.find_by!(slug: s) } if body_params.key?("depends_on")
      spec.shapers = list(body_params["shaped_by"]).map { |e| User.find_by!(email: e) } if body_params.key?("shaped_by")
    end
    render json: SpecSummary.call(spec.reload)
  end

  def rank
    authorize Spec, :rank?
    Specs::Rank.new(project: current_project, slugs: params.require(:slugs)).call
    render json: { ranked: current_project.specs.where(status: "ready").where.not(rank: nil).ranked.pluck(:slug) }
  end

  def claim
    authorize Spec, :claim?
    r = Specs::Claim.new(project: current_project, identity: params.require(:identity), user: current_user,
                         label: params[:label], wip: params[:wip].to_i, slug: params[:slug]).call
    render json: { result: r.result, run_id: r.run&.id }
  end

  def release
    spec = find_spec
    authorize spec, :release?
    render json: SpecSummary.call(Specs::Transitions.release!(spec))
  end

  def ship
    spec = find_spec
    authorize spec, :ship?
    run = params[:run_id].present? ? current_project.runs.find(params[:run_id]) : nil
    render json: SpecSummary.call(Specs::Transitions.ship!(spec, run: run))
  end

  def abandon
    spec = find_spec
    authorize spec, :abandon?
    render json: SpecSummary.call(Specs::Transitions.abandon!(spec, reason: params.require(:reason), cascade: params[:cascade]))
  end

  def deps
    spec = find_spec
    authorize spec, :show?
    render json: Specs::Dependencies.deps(spec)
  end

  def dependents
    spec = find_spec
    authorize spec, :show?
    render json: Specs::Dependencies.dependents(spec)
  end

  def checkpoints
    spec = find_spec
    authorize spec, :show?
    render json: spec.checkpoints.includes(:answered_by, :spec).oldest_first.map { |c| CheckpointJson.call(c) }
  end

  private

  def find_spec
    current_project.specs.find_by!(slug: params[:slug].to_s.sub(/\.md\z/, ""))
  end

  # ag-store may send "[a, b]" strings as well as arrays
  def list(val)
    return [] if val.nil?
    return val.map(&:to_s) if val.is_a?(Array)
    s = val.to_s.strip
    s = s[1..-2] if s.start_with?("[") && s.end_with?("]")
    s.split(",").map(&:strip).reject(&:empty?)
  end
end
```

- [ ] **Step 8: Run the specs test**

Run: `bin/rails test test/integration/api/specs_test.rb`
Expected: PASS (11 tests)

- [ ] **Step 9: Write the failing outcomes, checkpoints/runs and brief/map/flow tests**

`test/integration/api/outcomes_test.rb`:

```ruby
require "test_helper"

class Api::OutcomesTest < ActionDispatch::IntegrationTest
  def auth = { "Authorization" => "Bearer danny-token" }
  BASE = "/api/v1/projects/tekmore".freeze

  test "list, filter, show json and markdown" do
    get "#{BASE}/outcomes", headers: auth
    assert_equal %w[faster-onboarding fewer-tickets done-thing], response.parsed_body.map { |o| o["slug"] }
    get "#{BASE}/outcomes?status=open", headers: auth
    assert_equal 2, response.parsed_body.size
    get "#{BASE}/outcomes/faster-onboarding", headers: auth
    assert_equal "Median time-to-first-value", response.parsed_body["measure"]
    get "#{BASE}/outcomes/faster-onboarding.md", headers: auth
    assert_match(/^## Claim\n\nNew users/, response.body)
  end

  test "create from markdown, update, rank, achieve, abandon" do
    md = "---\nslug: new-out\nstatus: open\n---\n\n# New outcome\n\n## Claim\n\nc\n\n## Measure\n\nm\n\n## Stop rule\n\ns\n"
    post "#{BASE}/outcomes", params: md, headers: auth.merge("Content-Type" => "text/markdown")
    assert_response :created
    o = projects(:tekmore).outcomes.find_by!(slug: "new-out")
    assert_equal users(:danny), o.created_by

    patch "#{BASE}/outcomes/new-out", params: { notes: "n" }, as: :json, headers: auth
    assert_equal "n", o.reload.notes

    put "#{BASE}/outcomes/rank", params: { slugs: %w[new-out faster-onboarding] }, as: :json, headers: auth
    assert_equal 1, o.reload.rank
    assert_equal 2, outcomes(:faster_onboarding).reload.rank

    post "#{BASE}/outcomes/new-out/achieve", headers: auth
    assert o.reload.achieved?
    post "#{BASE}/outcomes/fewer-tickets/abandon", params: { reason: "r" }, as: :json, headers: auth
    assert_equal "r", outcomes(:second_outcome).reload.abandoned_reason
  end
end
```

`test/integration/api/checkpoints_test.rb`:

```ruby
require "test_helper"

class Api::CheckpointsTest < ActionDispatch::IntegrationTest
  def auth(t = "danny-token") = { "Authorization" => "Bearer #{t}" }
  BASE = "/api/v1/projects/tekmore".freeze

  test "open a checkpoint on a run, list it, answer it" do
    run = runs(:active_run)
    post "#{BASE}/runs/#{run.id}/checkpoints", params: { reason: "question", asked_by: "builder", session_id: "sess-1", ask: "Which DB?" }, as: :json, headers: auth
    assert_response :created
    id = response.parsed_body["id"]
    assert_equal 2, response.parsed_body["seq"]
    assert_equal "in-progress-spec #002 question", response.parsed_body["ref"]

    get "#{BASE}/specs/in-progress-spec/checkpoints", headers: auth
    assert_equal [ 1, 2 ], response.parsed_body.map { |c| c["seq"] }

    post "#{BASE}/checkpoints/#{id}/answer", params: { answer: "Postgres", by: "keith@example.com" }, as: :json, headers: auth("keith-token")
    assert_response :success
    cp = Checkpoint.find(id)
    assert cp.answered?
    assert_equal users(:keith), cp.answered_by
  end

  test "answering twice is 409" do
    post "#{BASE}/checkpoints/#{checkpoints(:answered_plan).id}/answer", params: { answer: "x", by: "k" }, as: :json, headers: auth
    assert_response :conflict
  end

  test "checkpoint on another project's run is 404" do
    post "/api/v1/projects/other/runs/#{runs(:active_run).id}/checkpoints", params: { reason: "question", asked_by: "build", ask: "?" }, as: :json, headers: auth("keith-token")
    assert_response :not_found
  end
end
```

`test/integration/api/runs_test.rb`:

```ruby
require "test_helper"

class Api::RunsTest < ActionDispatch::IntegrationTest
  def auth = { "Authorization" => "Bearer danny-token" }
  BASE = "/api/v1/projects/tekmore".freeze

  test "start a run, post events, list by status, close" do
    post "#{BASE}/runs", params: { spec: "ready-a", runner_id: "ag-run@box/7", session_id: "s7" }, as: :json, headers: auth
    assert_response :created
    id = response.parsed_body["id"]
    assert_equal "active", response.parsed_body["status"]

    post "#{BASE}/runs/#{id}/events", params: { event: "failed", detail: "tests red" }, as: :json, headers: auth
    assert_response :success
    assert Run.find(id).failed?

    get "#{BASE}/runs?status=active", headers: auth
    assert_equal [ runs(:active_run).id ], response.parsed_body.map { |r| r["id"] }
    get "#{BASE}/runs?spec=ready-a", headers: auth
    assert_equal [ id ], response.parsed_body.map { |r| r["id"] }
    assert_equal %w[started failed], response.parsed_body.first["events"].map { |e| e["event"] }

    post "#{BASE}/runs/#{id}/close", headers: auth
    assert Run.find(id).closed?
  end

  test "unknown event is 422" do
    post "#{BASE}/runs/#{runs(:active_run).id}/events", params: { event: "bogus" }, as: :json, headers: auth
    assert_response :unprocessable_entity
  end
end
```

`test/integration/api/brief_map_flow_test.rb`:

```ruby
require "test_helper"

class Api::BriefMapFlowTest < ActionDispatch::IntegrationTest
  def auth = { "Authorization" => "Bearer viewer-token" }
  BASE = "/api/v1/projects/tekmore".freeze

  test "brief is markdown with regenerated outcomes" do
    get "#{BASE}/brief", headers: auth
    assert_equal "text/markdown", response.media_type
    assert_includes response.body, "1. **Faster onboarding**"
  end

  test "map and flow" do
    get "#{BASE}/map", headers: auth
    assert_equal %w[outcomes unlinked orphaned tags], response.parsed_body.keys
    get "#{BASE}/flow", headers: auth
    assert_equal response.parsed_body.map { |f| f["slug"] }.sort, response.parsed_body.map { |f| f["slug"] }
    get "#{BASE}/flow/shipped-one", headers: auth
    assert_equal "shipped-one", response.parsed_body["slug"]
    assert response.parsed_body.key?("lead_seconds")
  end
end
```

- [ ] **Step 10: Outcomes, checkpoints, runs, projects controllers**

`app/controllers/api/v1/outcomes_controller.rb`:

```ruby
class Api::V1::OutcomesController < Api::V1::BaseController
  WRITABLE = %w[title status rank claim measure stop_rule notes abandoned_reason].freeze

  def index
    authorize Outcome, :index?
    scope = current_project.outcomes.ranked
    scope = scope.where(status: params[:status]) if params[:status].present?
    render json: scope.map { |o| OutcomeJson.call(o) }
  end

  def show
    o = find_outcome
    authorize o, :show?
    if request.format.symbol == :md || params[:format] == "md"
      render plain: o.to_markdown, content_type: "text/markdown"
    else
      render json: OutcomeJson.call(o).merge(o.slice("claim", "measure", "stop_rule", "notes", "abandoned_reason"))
                                       .merge(created_by: o.created_by&.email)
    end
  end

  def create
    o = current_project.outcomes.new(created_by: current_user)
    authorize o, :create?
    o.update!(Outcome.attributes_from_markdown(markdown_body))
    render json: OutcomeJson.call(o), status: :created
  end

  def update
    o = find_outcome
    authorize o, :update?
    o.update!(body_params.slice(*WRITABLE))
    render json: OutcomeJson.call(o)
  end

  def rank
    authorize Outcome, :rank?
    Outcome.transaction do
      listed = params.require(:slugs).map { |s| current_project.outcomes.find_by!(slug: s) }
      rest = current_project.outcomes.where(status: "open").where.not(id: listed.map(&:id)).where.not(rank: nil).ranked
      (listed + rest.to_a).each_with_index { |o, i| o.update_columns(rank: i + 1, updated_at: Time.current) }
    end
    render json: { ranked: current_project.outcomes.where.not(rank: nil).ranked.pluck(:slug) }
  end

  def achieve
    o = find_outcome
    authorize o, :achieve?
    o.update!(status: "achieved", achieved_at: Time.current)
    render json: OutcomeJson.call(o)
  end

  def abandon
    o = find_outcome
    authorize o, :abandon?
    o.update!(status: "abandoned", abandoned_at: Time.current, abandoned_reason: params.require(:reason))
    render json: OutcomeJson.call(o)
  end

  private

  def find_outcome = current_project.outcomes.find_by!(slug: params[:slug].to_s.sub(/\.md\z/, ""))
end
```

`app/controllers/api/v1/checkpoints_controller.rb`:

```ruby
class Api::V1::CheckpointsController < Api::V1::BaseController
  def create
    run = current_project.runs.find(params[:run_id])
    authorize Checkpoint.new(run: run, spec: run.spec), :create?
    cp = Checkpoints::Open.call(run: run, reason: params.require(:reason), asked_by: params.require(:asked_by),
                                ask: params[:ask].to_s, session_id: params[:session_id])
    Checkpoints::TriageJob.perform_later(cp.id) if defined?(Checkpoints::TriageJob)
    render json: CheckpointJson.call(cp), status: :created
  end

  def answer
    cp = Checkpoint.joins(:run).where(runs: { project_id: current_project.id }).find(params[:id])
    authorize cp, :answer?
    by = params[:by].presence
    by_user = by && User.find_by(email: by) || current_user
    render json: CheckpointJson.call(Checkpoints::Answer.call(cp, answer: params.require(:answer).to_s, by: by_user))
  end
end
```

`app/controllers/api/v1/runs_controller.rb`:

```ruby
class Api::V1::RunsController < Api::V1::BaseController
  def index
    authorize Run, :index?
    scope = current_project.runs.includes(:spec, :events).newest_first
    scope = scope.joins(:spec).where(specs: { slug: params[:spec] }) if params[:spec].present?
    case params[:status].presence
    when nil then nil
    when "active" then scope = scope.live
    when "closed" then scope = scope.where.not(status: Run::LIVE)
    else scope = scope.where(status: params[:status])
    end
    render json: scope.map { |r| RunJson.call(r) }
  end

  def create
    spec = current_project.specs.find_by!(slug: params.require(:spec))
    run = Run.new(project: current_project, spec: spec)
    authorize run, :create?
    run = current_project.runs.create!(spec: spec, runner_id: params.require(:runner_id), session_id: params[:session_id],
                                       status: "active", started_at: Time.current, last_event_at: Time.current)
    run.events.create!(event: "started", detail: params[:detail])
    render json: RunJson.call(run), status: :created
  end

  def events
    run = current_project.runs.find(params[:id])
    authorize run, :event?
    Runs::Event.call(run, event: params.require(:event), detail: params[:detail])
    render json: RunJson.call(run.reload)
  end

  def close
    run = current_project.runs.find(params[:id])
    authorize run, :close?
    render json: RunJson.call(Runs::Close.call(run, detail: params[:detail]))
  end
end
```

Add to `app/controllers/api/v1/projects_controller.rb`:

```ruby
  def map
    authorize current_project, :show?
    render json: Projects::Map.new(current_project).call
  end

  def flow
    authorize current_project, :show?
    flow = Projects::Flow.new(current_project)
    if params[:slug].present?
      render json: flow.for(current_project.specs.find_by!(slug: params[:slug]))
    else
      render json: flow.all
    end
  end
```

- [ ] **Step 11: Run every API test**

Run: `bin/rails test test/integration/api`
Expected: PASS

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "api: inbox, specs, outcomes, checkpoints, runs, brief, map, flow endpoints"
```

---

### Task 9: Realtime push — emit on every write, authorised channel

**Files:**
- Create: `app/services/realtime.rb`, `app/channels/project_push_channel.rb`, `app/channels/application_cable/connection.rb`
- Modify: `app/controllers/api/v1/base_controller.rb`, `app/controllers/application_controller.rb`, `app/javascript/application.js`
- Test: `test/services/realtime_test.rb`, `test/channels/project_push_channel_test.rb`

**Interfaces:**
- Produces: `Realtime.project_changed(project, event)` and `Realtime.user_notify(user, event, payload = {})`, buffered per request via `Realtime.buffer { ... }` (coalesces duplicate events, flushes after the block); events `inbox_changed specs_changed outcomes_changed runs_changed checkpoint_opened checkpoint_answered members_changed project_changed`. `ProjectPushChannel < DaisyStack::Push::Channel` rejects `project:<slug>` unless the connection's user is a member and `user:<id>` unless it is their own id. Pages call `ds_push stream: "project:#{slug}", channel: "ProjectPushChannel"`.

- [ ] **Step 1: Write the failing tests**

`test/services/realtime_test.rb`:

```ruby
require "test_helper"

class RealtimeTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  test "project_changed broadcasts to the project stream and every member's user stream" do
    assert_broadcast_on("daisy_stack_push:project:tekmore", { event: "specs_changed", payload: {} }) do
      assert_broadcast_on("daisy_stack_push:user:#{users(:danny).id}", { event: "specs_changed", payload: { project: "tekmore" } }) do
        Realtime.project_changed(projects(:tekmore), :specs_changed)
      end
    end
  end

  test "buffer coalesces duplicate events" do
    assert_broadcasts("daisy_stack_push:project:tekmore", 1) do
      Realtime.buffer do
        Realtime.project_changed(projects(:tekmore), :inbox_changed)
        Realtime.project_changed(projects(:tekmore), :inbox_changed)
      end
    end
  end
end
```

`test/channels/project_push_channel_test.rb`:

```ruby
require "test_helper"

class ProjectPushChannelTest < ActionCable::Channel::TestCase
  tests ProjectPushChannel

  test "member subscribes to the project stream" do
    stub_connection current_user: users(:danny)
    subscribe stream: "project:tekmore"
    assert subscription.confirmed?
    assert_has_stream "daisy_stack_push:project:tekmore"
  end

  test "outsider is rejected" do
    stub_connection current_user: users(:outsider)
    subscribe stream: "project:tekmore"
    assert subscription.rejected?
  end

  test "user stream must be your own" do
    stub_connection current_user: users(:danny)
    subscribe stream: "user:#{users(:keith).id}"
    assert subscription.rejected?
    subscribe stream: "user:#{users(:danny).id}"
    assert subscription.confirmed?
  end
end
```

- [ ] **Step 2: Run to see them fail**

Run: `bin/rails test test/services/realtime_test.rb test/channels`
Expected: FAIL with uninitialized constants

- [ ] **Step 3: Implement**

`app/services/realtime.rb`:

```ruby
# Payload-free push: pages re-read the DB on rerender_on:. Buffered per
# request so a write that touches three tables emits each event once.
module Realtime
  EVENTS = %w[inbox_changed specs_changed outcomes_changed runs_changed checkpoint_opened
              checkpoint_answered members_changed project_changed].freeze

  module_function

  def project_changed(project, event, payload = {})
    raise ArgumentError, "unknown event #{event}" unless EVENTS.include?(event.to_s)
    enqueue([ :project, project.slug, event.to_s, payload ])
    project.memberships.pluck(:user_id).each { |uid| enqueue([ :user, uid, event.to_s, payload.merge(project: project.slug) ]) }
  end

  def user_notify(user, event, payload = {})
    enqueue([ :user, user.id, event.to_s, payload ])
  end

  def buffer
    previous = Thread.current[:realtime_buffer]
    Thread.current[:realtime_buffer] = {}
    yield
  ensure
    pending = Thread.current[:realtime_buffer]
    Thread.current[:realtime_buffer] = previous
    pending&.each_value { |msg| deliver(msg) }
  end

  def enqueue(msg)
    buf = Thread.current[:realtime_buffer]
    if buf
      buf[msg.first(3)] = msg
    else
      deliver(msg)
    end
  end

  def deliver((kind, key, event, payload))
    DaisyStack::Push.emit(event, payload, to: "#{kind}:#{key}")
  end
end
```

`app/channels/application_cable/connection.rb`:

```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = env["warden"].user || reject_unauthorized_connection
    end
  end
end
```

`app/channels/project_push_channel.rb`:

```ruby
class ProjectPushChannel < DaisyStack::Push::Channel
  def subscribed
    stream = params[:stream].to_s
    kind, key = stream.split(":", 2)
    allowed =
      case kind
      when "project" then current_user.memberships.joins(:project).exists?(projects: { slug: key })
      when "user" then key.to_i == current_user.id
      when "all", "" then true
      else false
      end
    return reject unless allowed
    stream_from DaisyStack::Push.stream_name(stream.presence || :all)
  end
end
```

Wrap every API and web write in the buffer — in `Api::V1::BaseController` add `around_action :buffer_realtime` with:

```ruby
  def buffer_realtime(&block) = Realtime.buffer(&block)
```

and the same `around_action` in `ApplicationController`. Then add the emits to the services/controllers written so far (one line each, at the end of the successful path):

- `Api::V1::InboxController#create/#drop/#shape` → `Realtime.project_changed(current_project, :inbox_changed)` (`shape` also `:specs_changed`).
- `Api::V1::SpecsController#create/#update/#rank/#claim(when claimed)/#release/#ship/#abandon` → `:specs_changed`; `claim`/`release`/`ship`/`abandon` also `:runs_changed`.
- `Api::V1::OutcomesController` writes → `:outcomes_changed`.
- `Api::V1::CheckpointsController#create` → `Realtime.project_changed(current_project, :checkpoint_opened, checkpoint_id: cp.id, spec: cp.spec.slug, reason: cp.reason)`; `#answer` → `:checkpoint_answered`; both also `:runs_changed`.
- `Api::V1::RunsController#create/#events/#close` → `:runs_changed`.

In `app/javascript/application.js` nothing changes — `ds_push` takes `channel: "ProjectPushChannel"` from the page.

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/services/realtime_test.rb test/channels test/integration/api`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "realtime: buffered project/user push events and an authorised push channel"
```

---

### Task 10: Jev and RubyLLM — capture assist, checkpoint triage, claim sanity

**Files:**
- Create: `app/services/jev.rb` (from Jev Lab, plus `Judgment` recording), `app/services/llm.rb`, `app/services/inbox/assist.rb` (replace), `app/jobs/checkpoints/triage_job.rb`, `app/jobs/specs/sanity_job.rb`, `config/initializers/ruby_llm.rb`
- Delete: `app/services/jev_client.rb`
- Modify: `test/test_helper.rb`, `app/services/specs/claim.rb` (enqueue sanity job)
- Test: `test/services/jev_test.rb`, `test/services/inbox_assist_test.rb`, `test/jobs/checkpoints_triage_job_test.rb`, `test/jobs/specs_sanity_job_test.rb`

**Interfaces:**
- Produces: `Jev.ask(state:, questions:, purpose:, subject: nil) -> RubyDecisionModel::Response` (records a `Judgment`), `Jev::Q` (= `RubyDecisionModel::Questions`), `Jev.transport=`, `Jev::FakeTransport` (verbatim from Jev Lab), `Jev.raw_client`; `Llm.chat(system:, user:) -> String`, `Llm.client=` with `Llm::Fake` returning a canned string; `Inbox::Assist.call(project:, text:) -> Hash` (keys from Task 8); `Checkpoints::TriageJob.perform(checkpoint_id)` sets `priority`; `Specs::SanityJob.perform(spec_id)` sets `needs_review`/`needs_review_reason`.

- [ ] **Step 1: Write the failing tests**

`test/services/jev_test.rb`:

```ruby
require "test_helper"

class JevTest < ActiveSupport::TestCase
  test "ask records a judgment with request, response and purpose" do
    Jev.transport = Jev::FakeTransport.new("kind" => "bug")
    assert_difference "Judgment.count", 1 do
      r = Jev.ask(state: { text: "login is broken" },
                  questions: { "kind" => Jev::Q.choice("What kind?", criteria: { "feature" => "new", "bug" => "broken" }) },
                  purpose: "test", subject: inbox_items(:open_one))
      assert_equal "bug", r.answers["kind"].choice
    end
    j = Judgment.last
    assert_equal "test", j.purpose
    assert_equal inbox_items(:open_one), j.subject
    assert_equal "fake", j.transport
    assert j.request["questions"].key?("kind")
  end

  test "a transport failure raises Jev::Error and still records" do
    Jev.transport = Jev::FakeTransport.new(fail_with: 500)
    assert_raises(Jev::Error) { Jev.ask(state: {}, questions: { "q" => Jev::Q.noul("?") }, purpose: "x") }
  end
end
```

`test/services/inbox_assist_test.rb`:

```ruby
require "test_helper"

class InboxAssistTest < ActiveSupport::TestCase
  test "tidies with the LLM and classifies with Jev" do
    Llm.client = Llm::Fake.new("Add CSV export\n\nUsers want the report as a CSV download.")
    Jev.transport = Jev::FakeTransport.new("kind" => "feature", "serves_outcome" => "faster-onboarding", "duplicate" => 0.8)
    r = Inbox::Assist.call(project: projects(:tekmore), text: "csv export pls, ppl keep asking")
    assert_equal "Add CSV export", r[:title]
    assert_equal "Users want the report as a CSV download.", r[:text]
    assert_equal "feature", r[:kind]
    assert_equal "faster-onboarding", r[:serves_outcome_slug]
    assert_equal inbox_items(:open_one).id, r[:duplicate_of]
    assert_in_delta 0.8, r[:duplicate_probability], 0.01
    assert Judgment.exists?(r[:judgment_id])
  end

  test "low-confidence kind and outcome are not applied" do
    Llm.client = Llm::Fake.new("Thing\n\nText.")
    Jev.transport = Jev::FakeTransport.new { |id, q| { type: "choice", choice: q["criteria"].keys.first, confidence: 0.3, probabilities: {} } if q["type"] == "choice" }
    r = Inbox::Assist.call(project: projects(:tekmore), text: "thing")
    assert_nil r[:kind]
    assert_nil r[:serves_outcome_slug]
  end

  test "an LLM failure still returns the raw text and the Jev classification" do
    Llm.client = Llm::Fake.new(raise: Llm::Error.new("down"))
    Jev.transport = Jev::FakeTransport.new("kind" => "bug")
    r = Inbox::Assist.call(project: projects(:tekmore), text: "login broken")
    assert_equal "login broken", r[:title]
    assert_equal "bug", r[:kind]
  end
end
```

`test/jobs/checkpoints_triage_job_test.rb`:

```ruby
require "test_helper"

class CheckpointsTriageJobTest < ActiveJob::TestCase
  test "sets priority from Jev" do
    Jev.transport = Jev::FakeTransport.new("priority" => "routine")
    Checkpoints::TriageJob.perform_now(checkpoints(:open_ship).id)
    assert_equal "routine", checkpoints(:open_ship).reload.priority
  end

  test "an outage yields unclear" do
    Jev.transport = Jev::FakeTransport.new(fail_with: 503)
    Checkpoints::TriageJob.perform_now(checkpoints(:open_ship).id)
    assert_equal "unclear", checkpoints(:open_ship).reload.priority
  end
end
```

`test/jobs/specs_sanity_job_test.rb`:

```ruby
require "test_helper"

class SpecsSanityJobTest < ActiveJob::TestCase
  test "flags a spec whose acceptance criteria are not verifiable" do
    Jev.transport = Jev::FakeTransport.new("verifiable" => 0.2)
    Specs::SanityJob.perform_now(specs(:tek_ready_b).id)
    s = specs(:tek_ready_b).reload
    assert s.needs_review
    assert_match(/acceptance criteria/i, s.needs_review_reason)
  end

  test "an outage fails closed: flagged for review" do
    Jev.transport = Jev::FakeTransport.new(fail_with: 503)
    Specs::SanityJob.perform_now(specs(:tek_ready_a).id)
    assert specs(:tek_ready_a).reload.needs_review
  end

  test "a good spec is not flagged" do
    Jev.transport = Jev::FakeTransport.new("verifiable" => 0.9)
    Specs::SanityJob.perform_now(specs(:tek_ready_a).id)
    assert_not specs(:tek_ready_a).reload.needs_review
  end
end
```

- [ ] **Step 2: Run to see them fail**

Run: `bin/rails test test/services/jev_test.rb test/services/inbox_assist_test.rb test/jobs`
Expected: FAIL with `uninitialized constant Jev` / `Llm`

- [ ] **Step 3: `app/services/jev.rb`**

Copy `~/lab/jev/app/services/jev.rb` verbatim, then make these three changes:

1. Change the `ask` signature and body to record a `Judgment`:

```ruby
    def ask(state:, questions:, purpose:, subject: nil)
      body_seen = nil
      response_seen = nil
      recording = lambda do |url:, headers:, body:|
        body_seen = body
        status, response_body, response_headers = transport_for_call.call(url: url, headers: headers, body: body)
        response_seen = response_body
        [ status, response_body, response_headers ]
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = client(recording).ask(state: state, questions: questions)
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      record_judgment(purpose, subject, parse(body_seen), parse(response_seen), duration,
                      response.usage&.input_tokens.to_i + response.usage&.output_tokens.to_i)
      response
    rescue RubyDecisionModel::ConfigurationError => e
      raise NotConfigured, "Jev is not configured: set TYPESAFE_API_KEY (#{e.message})"
    rescue RubyDecisionModel::Error => e
      record_judgment(purpose, subject, parse(body_seen), { "error" => e.message }, 0, 0)
      raise Error, "Jev request failed: #{e.message}"
    end
```

2. Add, under `private`:

```ruby
    def record_judgment(purpose, subject, request, response, latency_ms, tokens)
      Judgment.create!(purpose: purpose, subject: subject, request: request, response: response,
                       latency_ms: latency_ms, tokens: tokens, transport: (transport ? "fake" : "typesafe"))
    rescue StandardError => e
      Rails.logger.warn("[Jev] judgment not recorded: #{e.message}")
    end
```

3. Delete the `record`/`push_call`/`Call` machinery (Thread-local call capture) — `Judgment` replaces it; keep `raw_client` but have `recorded_transport_call` just delegate to `transport_for_call`. Keep `FakeTransport` unchanged. Delete `app/services/jev_client.rb`.

- [ ] **Step 4: `app/services/llm.rb` and the initializer**

`config/initializers/ruby_llm.rb`:

```ruby
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_model = ENV.fetch("AGENTILE_LLM_MODEL", "claude-sonnet-5")
end
```

`app/services/llm.rb` (pin `ruby_llm ~> 2.0`; the chat API is `RubyLLM.chat(model:).with_instructions(system).ask(user).content` per its README):

```ruby
module Llm
  class Error < StandardError; end

  class Real
    def chat(system:, user:)
      RubyLLM.chat.with_instructions(system).ask(user).content.to_s
    rescue StandardError => e
      raise Error, e.message
    end
  end

  # Test double: returns a canned reply, or raises.
  class Fake
    attr_reader :calls

    def initialize(reply = "", raise: nil)
      @reply, @raise, @calls = reply, binding.local_variable_get(:raise), []
    end

    def chat(system:, user:)
      @calls << { system: system, user: user }
      raise @raise if @raise
      @reply
    end
  end

  class << self
    attr_writer :client

    def client
      @client ||= Real.new
    end

    def chat(system:, user:)
      client.chat(system: system, user: user)
    end
  end
end
```

Add to `test/test_helper.rb` inside `class TestCase`:

```ruby
    setup do
      Jev.transport = Jev::FakeTransport.new
      Llm.client = Llm::Fake.new("Title\n\nBody.")
    end
    teardown do
      Jev.transport = nil
      Llm.client = nil
    end
```

and `ENV["TYPESAFE_API_KEY"] = "test-key"` after the WebMock line.

- [ ] **Step 5: `Inbox::Assist`**

Replace `app/services/inbox/assist.rb`:

```ruby
# Capture assist: RubyLLM tidies the line into title + text, one Jev request
# classifies it. Thresholds live here, not in Jev (spec §9).
class Inbox::Assist
  KIND_FLOOR = 0.6
  OUTCOME_FLOOR = 0.6
  DUPLICATE_FLOOR = 0.5
  RECENT = 10

  TIDY_SYSTEM = <<~TXT.freeze
    You tidy one rough idea into an inbox stub for a software backlog. Reply with the title on the
    first line (under 80 characters, imperative, no trailing period), a blank line, then one short
    paragraph restating the idea in plain words. Do not add requirements, guesses or questions
    that are not in the input.
  TXT

  def self.call(project:, text:)
    new(project, text).call
  end

  def initialize(project, text)
    @project, @text = project, text.to_s.strip
  end

  def call
    title, body = tidy
    outcomes = @project.outcomes.where(status: "open").ranked.to_a
    recent = @project.inbox_items.where(status: "open").recent_first.limit(RECENT).to_a
    questions = {
      "kind" => Jev::Q.choice("What kind of backlog item is `text`?", criteria: {
        "feature" => "New or changed behaviour a user would notice",
        "bug" => "Something that is broken or behaves wrongly",
        "chore" => "Housekeeping: upgrades, refactors, tooling, docs",
        "spike" => "A timeboxed investigation whose output is an answer, not shipped code",
        "unclear" => "Cannot tell from the text"
      })
    }
    if outcomes.any?
      criteria = outcomes.to_h { |o| [ o.slug, "#{o.title}: #{o.claim.to_s.strip}" ] }.merge("none" => "Serves none of these outcomes")
      questions["serves_outcome"] = Jev::Q.choice("Which outcome does `text` serve?", criteria: criteria)
    end
    if recent.any?
      questions["duplicate"] = Jev::Q.noul("Does `text` describe the same work as any entry in `recent`?",
                                          criteria: { "true" => "Same change, even if worded differently", "false" => "Different work" })
      questions["duplicate_of"] = Jev::Q.choice("Which entry in `recent` is `text` a duplicate of?",
                                                criteria: recent.to_h { |i| [ i.id.to_s, i.title ] }.merge("none" => "None of them"))
    end
    response = Jev.ask(state: { text: body, recent: recent.map { |i| { id: i.id, title: i.title } } },
                       questions: questions, purpose: "inbox.assist")
    a = response.answers
    kind = a["kind"]
    outcome = a["serves_outcome"]
    dup = a["duplicate"]
    dup_of = a["duplicate_of"]
    duplicate_id = dup && dup.noul >= DUPLICATE_FLOOR && dup_of && dup_of.choice != "none" ? dup_of.choice.to_i : nil
    {
      title: title, text: body,
      kind: (kind.confidence >= KIND_FLOOR && kind.choice != "unclear" ? kind.choice : nil),
      serves_outcome_slug: (outcome && outcome.confidence >= OUTCOME_FLOOR && outcome.choice != "none" ? outcome.choice : nil),
      duplicate_of: duplicate_id,
      duplicate_probability: dup&.noul&.round(3),
      judgment_id: Judgment.where(purpose: "inbox.assist").order(:id).last&.id
    }
  end

  private

  def tidy
    reply = Llm.chat(system: TIDY_SYSTEM, user: @text)
    first, rest = reply.to_s.strip.split(/\n\s*\n/, 2)
    [ first.to_s.strip.truncate(80), (rest.presence || first).to_s.strip ]
  rescue Llm::Error => e
    Rails.logger.warn("[Inbox::Assist] tidy failed: #{e.message}")
    [ @text.lines.first.to_s.strip.truncate(80), @text ]
  end
end
```

- [ ] **Step 6: The two jobs**

`app/jobs/checkpoints/triage_job.rb`:

```ruby
class Checkpoints::TriageJob < ApplicationJob
  queue_as :default

  def perform(checkpoint_id)
    cp = Checkpoint.find_by(id: checkpoint_id) or return
    priority =
      begin
        r = Jev.ask(state: { reason: cp.reason, asked_by: cp.asked_by, ask: cp.ask.to_s },
                    questions: { "priority" => Jev::Q.choice("Does this pause need a person's judgment?", criteria: {
                      "needs_human" => "A decision, approval, or missing information only a person can supply",
                      "routine" => "A formality a person will wave through: a green plan, a routine checkpoint",
                      "unclear" => "Cannot tell from the ask"
                    }) }, purpose: "checkpoint.triage", subject: cp)
        r.answers["priority"].choice
      rescue Jev::Error, Jev::NotConfigured
        "unclear"
      end
    cp.update!(priority: priority)
    Realtime.project_changed(cp.run.project, :runs_changed)
  end
end
```

`app/jobs/specs/sanity_job.rb`:

```ruby
require "decide/askers/decision_model"

# Fail-closed: if Jev cannot answer, the spec is flagged for a human read.
class Specs::SanityJob < ApplicationJob
  queue_as :default
  FLOOR = 0.6

  def perform(spec_id)
    spec = Spec.find_by(id: spec_id) or return
    decision = Decide::Decision.new(name: "spec_acceptance_verifiable", asker: Decide::Askers::DecisionModel.new(Jev.raw_client),
                                    floor: FLOOR, fail_mode: :closed) do
      noul :verifiable, "Are the `acceptance_criteria` concrete enough that a test or a reviewer could check each one?",
           criteria: { true: "Each criterion names an observable result", false: "Vague, empty, or aspirational" }
      rule { |a| a[:verifiable].noul >= FLOOR }
    end
    verdict = decision.decide({ "title" => spec.title, "acceptance_criteria" => spec.acceptance_criteria.to_s })
    Judgment.create!(purpose: "spec.sanity", subject: spec, request: { "acceptance_criteria" => spec.acceptance_criteria.to_s },
                     response: JSON.parse(verdict.to_h.to_json), transport: (Jev.transport ? "fake" : "typesafe"))
    if verdict.matched?
      spec.update!(needs_review: false, needs_review_reason: nil)
    else
      reason = verdict.failed? ? "Jev unavailable; acceptance criteria not checked" : "Acceptance criteria look hard to verify (P=#{verdict.probability.to_f.round(2)})"
      spec.update!(needs_review: true, needs_review_reason: reason)
    end
    Realtime.project_changed(spec.project, :specs_changed)
  end
end
```

Enqueue it from `Specs::Claim#attempt` after the run is created: `Specs::SanityJob.perform_later(chosen.id)`. Set `config.active_job.queue_adapter = :test` in `config/environments/test.rb` (ActiveJob::TestCase then runs jobs with `perform_now` as written).

- [ ] **Step 7: Run the tests**

Run: `bin/rails test`
Expected: PASS — including the earlier API tests, now with `Llm::Fake` and `FakeTransport` installed by the helper.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "jev: one door with judgments; capture assist, checkpoint triage, claim-time sanity"
```

---

### Task 11: Web shell, home dashboard and project dashboard

**Files:**
- Create: `app/controllers/projects_controller.rb`, `app/controllers/projects/dashboard_controller.rb`, `app/controllers/projects/checkpoints_controller.rb`, `app/matestack/web/pages/dashboard.rb` (rewrite), `app/matestack/web/pages/projects/dashboard.rb`, `app/matestack/web/components/{attention_list,stat_tile,list_card,pill}.rb`, `app/services/projects/dashboard_metrics.rb`, `app/services/home_metrics.rb`
- Modify: `config/routes.rb`, `app/matestack/web/layout.rb`, `app/controllers/application_controller.rb`
- Test: `test/services/projects/dashboard_metrics_test.rb`, `test/integration/pages_test.rb`

**Interfaces:**
- Consumes: `Web::Colors`, `Realtime`, `Projects::Flow`, policies.
- Produces: routes `GET /` (home), `GET /p/:project_slug` (project dashboard), `POST /p/:project_slug/checkpoints/:id/answer` (web answer form, JSON reply for `matestack_form`); components `pill(concept, value)`, `stat_tile(title, value, description, icon, color: nil)`, `list_card(title, path)`, `attention_list(project)`; `HomeMetrics.new(user).projects -> [{ project:, role:, open_inbox:, ready:, in_progress:, shipped_7d:, attention:, next_up: }]`; `Projects::DashboardMetrics.new(project)` with `queue_depth wip wip_limit shipped_7d shipped_30d median_lead_seconds open_checkpoints failed_runs in_progress up_next recent_events`.

- [ ] **Step 1: Write the failing metrics test**

`test/services/projects/dashboard_metrics_test.rb`:

```ruby
require "test_helper"

class Projects::DashboardMetricsTest < ActiveSupport::TestCase
  test "counts and lists" do
    m = Projects::DashboardMetrics.new(projects(:tekmore))
    assert_equal 5, m.queue_depth
    assert_equal 1, m.wip
    assert_equal 2, m.wip_limit
    assert_equal 1, m.shipped_7d
    assert_equal 1, m.open_checkpoints.size
    assert_equal [ specs(:tek_in_progress) ], m.in_progress.map(&:spec)
    assert_equal %w[ready-a ready-b], m.up_next.map(&:slug).first(2)
    assert_in_delta 5.days.to_i, m.median_lead_seconds, 5
  end

  test "home metrics roll up per project with attention count" do
    rows = HomeMetrics.new(users(:danny)).projects
    assert_equal 1, rows.size
    row = rows.first
    assert_equal "member", row[:role]
    assert_equal 2, row[:open_inbox]
    assert_equal 1, row[:attention]
    assert_equal "ready-a", row[:next_up]&.slug
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bin/rails test test/services/projects/dashboard_metrics_test.rb`
Expected: FAIL with uninitialized constant

- [ ] **Step 3: Metrics services**

`app/services/projects/dashboard_metrics.rb`:

```ruby
class Projects::DashboardMetrics
  def initialize(project, now: Time.current)
    @project, @now = project, now
  end

  def queue_depth = @project.specs.where(status: "ready").count
  def wip = @project.specs.where(status: "in_progress").count
  def wip_limit = @project.wip_limit
  def shipped_7d = @project.specs.where(shipped_at: (@now - 7.days)..).count
  def shipped_30d = @project.specs.where(shipped_at: (@now - 30.days)..).count

  def median_lead_seconds
    leads = @project.specs.where.not(shipped_at: nil).pluck(:created_at, :shipped_at).map { |c, s| (s - c).to_i }.sort
    return nil if leads.empty?
    mid = leads.size / 2
    leads.size.odd? ? leads[mid] : (leads[mid - 1] + leads[mid]) / 2
  end

  def open_checkpoints
    Checkpoint.joins(:run).where(runs: { project_id: @project.id }, status: "open").includes(:spec, :run).attention_order
  end

  def failed_runs = @project.runs.attention.includes(:spec).newest_first
  def in_progress = @project.runs.live.includes(:spec).newest_first
  def up_next = @project.specs.where(status: "ready").where.not(rank: nil).includes(:dependencies).ranked.limit(8)

  def recent_events(limit = 12)
    RunEvent.joins(:run).where(runs: { project_id: @project.id }).includes(run: :spec).order(at: :desc).limit(limit)
  end

  def attention_count = open_checkpoints.count + failed_runs.count
end
```

`app/services/home_metrics.rb`:

```ruby
class HomeMetrics
  def initialize(user)
    @user = user
  end

  def projects
    @user.memberships.includes(:project).joins(:project).merge(Project.live).order("projects.name").map do |m|
      p = m.project
      dm = Projects::DashboardMetrics.new(p)
      { project: p, role: m.role, open_inbox: p.inbox_items.where(status: "open").count,
        ready: dm.queue_depth, in_progress: dm.wip, shipped_7d: dm.shipped_7d,
        attention: dm.attention_count, next_up: dm.up_next.find(&:claimable?) }
    end
  end
end
```

- [ ] **Step 4: Run the metrics test**

Run: `bin/rails test test/services/projects/dashboard_metrics_test.rb`
Expected: PASS

- [ ] **Step 5: Routes, controllers and layout**

Routes — add after `root`:

```ruby
  resources :projects, only: [ :index, :new, :create ]
  scope "p/:project_slug", as: :project, module: :projects do
    get "/", to: "dashboard#show", as: :dashboard
    post "checkpoints/:id/answer", to: "checkpoints#answer", as: :answer_checkpoint
  end
```

`app/controllers/projects/dashboard_controller.rb`:

```ruby
class Projects::DashboardController < ApplicationController
  def show
    authorize current_project, :show?
    render Web::Pages::Projects::Dashboard
  end
end
```

`app/controllers/projects/checkpoints_controller.rb`:

```ruby
class Projects::CheckpointsController < ApplicationController
  def answer
    cp = Checkpoint.joins(:run).where(runs: { project_id: current_project.id }).find(params[:id])
    authorize cp, :answer?
    Checkpoints::Answer.call(cp, answer: params.require(:checkpoint).require(:answer), by: current_user)
    Realtime.project_changed(current_project, :checkpoint_answered)
    Realtime.project_changed(current_project, :runs_changed)
    render json: {}, status: :ok
  rescue ApiError::Conflict => e
    render json: { message: e.message, errors: {} }, status: :unprocessable_entity
  end
end
```

`app/controllers/projects_controller.rb` (index redirects home; new/create are owner-less admin actions):

```ruby
class ProjectsController < ApplicationController
  def index
    skip_authorization
    redirect_to root_path
  end

  def new
    authorize Project, :create?
    render Web::Pages::Projects::New
  end

  def create
    authorize Project, :create?
    project = Project.new(params.require(:project).permit(:name, :slug, :trunk, :wip_limit, :brief))
    Project.transaction do
      project.save!
      project.memberships.create!(user: current_user, role: "owner")
    end
    render json: { redirect: project_dashboard_path(project.slug) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { message: "Missing or invalid params", errors: e.record.errors }, status: :unprocessable_entity
  end
end
```

`app/matestack/web/pages/projects/new.rb`:

```ruby
class Web::Pages::Projects::New < DaisyStack::Ui::Page
  def response
    ds_page_header title: "New project", icon: "plus"
    ds_card bordered: true do
      matestack_form for: :project, method: :post, path: projects_path, delay: 0,
                     success: { redirect: { follow_response: true } }, failure: { emit: "project_failed" } do
        ds_form_input key: :name, label: "Name", required: true
        ds_form_input key: :slug, label: "Slug", required: true, hint: "lowercase-with-dashes; used in URLs and store.md"
        ds_form_input key: :trunk, label: "Trunk branch", init: "main"
        ds_form_input key: :wip_limit, label: "WIP limit", type: :number, init: 1
        ds_form_textarea key: :brief, label: "Brief (markdown)", rows: 8
        div(class: "mt-4") { ds_form_submit text: "Create project" }
      end
      toggle show_on: "project_failed", hide_after: 5000 do
        ds_alert "Check the name and slug.", status: :error, variant: :soft, classes: "mt-3 text-sm"
      end
    end
  end
end
```

`app/matestack/web/layout.rb` menu — replace the placeholder menu with:

```ruby
  menu "Projects" do
    item "Home", path: "/", icon: "squares-2x2", match: :exact
  end

  # One group per project the user belongs to; built at render time.
  def sidebar_menus
    base = super
    return base unless signed_in?
    current_user.projects.live.order(:name).each do |p|
      base << menu_group(p.name) do
        item "Dashboard", path: "/p/#{p.slug}", icon: "chart-bar", match: :exact
        item "Inbox", path: "/p/#{p.slug}/inbox", icon: "inbox"
        item "Specs", path: "/p/#{p.slug}/specs", icon: "document-text"
        item "Outcomes", path: "/p/#{p.slug}/outcomes", icon: "flag"
        item "Runs", path: "/p/#{p.slug}/runs", icon: "play"
        item "Checkpoints", path: "/p/#{p.slug}/checkpoints", icon: "hand-raised"
        item "Members", path: "/p/#{p.slug}/members", icon: "users"
        item "Settings", path: "/p/#{p.slug}/settings", icon: "cog-6-tooth"
      end
    end
    base
  end
```

`DaisyStack::Ui::Layout::Shell` exposes the declared menus via a class-level list; if `sidebar_menus`/`menu_group` are not the hook names in the installed gem, open `vendor/daisy_stack/lib/ui/layout/shell.rb`, find the method that iterates `self.class.menus` inside `sidebar`, and override *that* method to append the per-project groups using the same struct the `menu` DSL builds. Keep the admin menu and `user_menu` as they are; add `item "API tokens", path: "/account/api_tokens", icon: "key"` to `user_menu`.

- [ ] **Step 6: Shared components**

`app/matestack/web/components/pill.rb`:

```ruby
class Web::Components::Pill < DaisyStack::Ui::Components::BaseUi
  # Tailwind safelist: badge badge-sm badge-soft
  optional :concept
  optional :value
  register_as :pill

  def response
    ds_badge text: context.value.to_s.titleize, size: :sm, style: :soft,
             brand_color: Web::Colors.for(context.concept, context.value), classes: context.classes
  end
end
```

`app/matestack/web/components/stat_tile.rb`:

```ruby
class Web::Components::StatTile < DaisyStack::Ui::Components::BaseUi
  # Tailwind safelist: card card-border border-base-300 card-sm bg-base-100 card-body gap-1 py-3
  # text-xs uppercase tracking-wide opacity-60 text-2xl font-semibold tabular text-error text-warning text-success
  optional :title, :value, :description, :icon, :brand_color
  register_as :stat_tile

  def response
    root class: "card card-border border-base-300 card-sm bg-base-100" do
      div class: "card-body gap-1 py-3" do
        div class: "flex items-center justify-between text-xs uppercase tracking-wide opacity-60" do
          span text: context.title
          ds_icon name: context.icon, size: 16 if context.icon
        end
        div class: "text-2xl font-semibold tabular #{context.brand_color ? "text-#{context.brand_color}" : ''}", text: context.value.to_s
        div class: "text-xs opacity-60", text: context.description.to_s if context.description
      end
    end
  end
end
```

`app/matestack/web/components/list_card.rb`:

```ruby
class Web::Components::ListCard < DaisyStack::Ui::Components::BaseUi
  # Tailwind safelist: card card-border border-base-300 card-sm bg-base-100 overflow-hidden border-b px-4 py-2
  # flex items-center justify-between text-sm font-semibold link link-hover text-xs opacity-60 card-body p-0
  optional :title, :path, :count
  register_as :list_card

  def response
    root class: "card card-border border-base-300 card-sm bg-base-100 overflow-hidden" do
      div class: "border-b border-base-300 px-4 py-2 flex items-center justify-between" do
        div class: "text-sm font-semibold flex items-center gap-2" do
          plain context.title
          ds_badge text: context.count.to_s, size: :sm, brand_color: :neutral if context.count
        end
        if context.path
          transition(path: context.path, delay: 0, class: "link link-hover text-xs opacity-60") { plain "View all" }
        end
      end
      div class: "card-body p-0" do
        yield if block_given?
      end
    end
  end
end
```

`app/matestack/web/components/attention_list.rb` — open checkpoints with an inline answer form, and failed runs:

```ruby
class Web::Components::AttentionList < DaisyStack::Ui::Components::BaseUi
  # Tailwind safelist: divide-y divide-base-300 p-4 flex flex-col gap-2 text-sm font-mono opacity-70 whitespace-pre-wrap
  optional :project, :checkpoints, :failed_runs
  register_as :attention_list

  def response
    root class: "divide-y divide-base-300" do
      if context.checkpoints.empty? && context.failed_runs.empty?
        ds_empty_state text: "Nothing needs you right now.", icon: "check-circle"
      end
      context.checkpoints.each { |cp| checkpoint_row(cp) }
      context.failed_runs.each { |run| failed_row(run) }
    end
  end

  private

  def checkpoint_row(cp)
    div class: "p-4 flex flex-col gap-2" do
      div class: "flex items-center gap-2 text-sm" do
        pill concept: :checkpoint_reason, value: cp.reason
        pill concept: :checkpoint_priority, value: cp.priority if cp.priority
        span class: "font-mono", text: cp.spec.slug
        span class: "opacity-70 text-xs", text: "asked by #{cp.asked_by} · #{DaisyStack::Format.datetime(cp.asked_at)}"
      end
      div class: "text-sm whitespace-pre-wrap", text: cp.ask.to_s
      matestack_form for: :checkpoint, method: :post, path: "/p/#{context.project.slug}/checkpoints/#{cp.id}/answer", delay: 0,
                     success: { emit: "attention_changed", reset: true }, failure: { emit: "answer_failed" } do
        div class: "flex items-end gap-2" do
          div(class: "grow") { ds_form_textarea key: :answer, rows: 2, placeholder: "Your answer (e.g. approved)", required: true }
          ds_form_submit text: "Answer", size: :sm
        end
      end
    end
  end

  def failed_row(run)
    div class: "p-4 flex items-center gap-2 text-sm" do
      pill concept: :run_status, value: run.status
      span class: "font-mono", text: run.spec.slug
      span class: "opacity-70 text-xs", text: "#{run.runner_id} · #{run.detail}"
    end
  end
end
```

- [ ] **Step 7: The two dashboard pages**

`app/matestack/web/pages/dashboard.rb` (home):

```ruby
class Web::Pages::Dashboard < DaisyStack::Ui::Page
  # Tailwind safelist: grid gap-4 md:grid-cols-2 xl:grid-cols-3 indicator indicator-item
  def prepare
    @rows = HomeMetrics.new(current_user).projects
  end

  def response
    ds_push stream: "user:#{current_user.id}", channel: "ProjectPushChannel"
    ds_page_header title: "Your projects", icon: "squares-2x2", subtitle: Date.current.strftime("%A %-d %B %Y")
    async id: "home-cards", rerender_on: "specs_changed, runs_changed, inbox_changed, checkpoint_opened, checkpoint_answered" do
      if @rows.empty?
        ds_empty_state title: "No projects yet", text: "Ask a project owner to add you, or create one from the admin menu.", icon: "rectangle-stack"
      else
        div class: "grid gap-4 md:grid-cols-2 xl:grid-cols-3" do
          @rows.each { |row| project_card(row) }
        end
      end
    end
  end

  private

  def project_card(row)
    p = row[:project]
    div class: "card card-border border-base-300 card-sm bg-base-100" do
      div class: "card-body gap-2" do
        div class: "flex items-center justify-between" do
          transition(path: "/p/#{p.slug}", delay: 0, class: "text-base font-semibold link link-hover") { plain p.name }
          div class: "flex items-center gap-2" do
            pill concept: :role, value: row[:role]
            ds_badge text: "#{row[:attention]} need you", size: :sm, brand_color: :error if row[:attention].positive?
          end
        end
        div class: "grid grid-cols-4 gap-2 text-center text-xs" do
          [ [ "Inbox", row[:open_inbox] ], [ "Ready", row[:ready] ], [ "In progress", row[:in_progress] ], [ "Shipped 7d", row[:shipped_7d] ] ].each do |label, n|
            div do
              div class: "text-lg font-semibold tabular", text: n.to_s
              div class: "opacity-60", text: label
            end
          end
        end
        div class: "text-xs opacity-70" do
          if row[:next_up]
            plain "Next up: "
            span class: "font-mono", text: row[:next_up].slug
          else
            plain "Nothing claimable"
          end
        end
      end
    end
  end
end
```

`app/matestack/web/pages/projects/dashboard.rb`:

```ruby
class Web::Pages::Projects::Dashboard < DaisyStack::Ui::Page
  # Tailwind safelist: grid gap-4 grid-cols-2 lg:grid-cols-4 lg:grid-cols-2 mt-4 prose prose-sm max-w-none
  def prepare
    @project = current_project
    @m = Projects::DashboardMetrics.new(@project)
  end

  def response
    ds_push stream: "project:#{@project.slug}", channel: "ProjectPushChannel"
    ds_page_header title: @project.name, icon: "chart-bar", subtitle: "trunk #{@project.trunk} · WIP limit #{@project.wip_limit}"

    async id: "stats", rerender_on: "specs_changed, runs_changed" do
      div class: "grid gap-4 grid-cols-2 lg:grid-cols-4" do
        stat_tile title: "Queue", value: @m.queue_depth, description: "ready specs", icon: "queue-list"
        stat_tile title: "WIP", value: "#{@m.wip} / #{@m.wip_limit}", description: "in progress vs limit", icon: "play",
                  brand_color: (@m.wip > @m.wip_limit ? :warning : nil)
        stat_tile title: "Shipped", value: @m.shipped_7d, description: "#{@m.shipped_30d} in 30 days", icon: "check"
        stat_tile title: "Lead time", value: lead_time_text, description: "median, shipped specs", icon: "clock"
      end
    end

    div class: "grid gap-4 lg:grid-cols-2 mt-4" do
      list_card title: "Attention", path: "/p/#{@project.slug}/checkpoints", count: @m.attention_count do
        async id: "attention", rerender_on: "checkpoint_opened, checkpoint_answered, attention_changed, runs_changed" do
          attention_list project: @project, checkpoints: @m.open_checkpoints.to_a, failed_runs: @m.failed_runs.to_a
        end
      end
      list_card title: "In progress", path: "/p/#{@project.slug}/runs" do
        async id: "wip", rerender_on: "runs_changed, specs_changed" do
          runs = @m.in_progress.to_a
          if runs.empty?
            ds_empty_state text: "No builds running.", icon: "play"
          else
            ds_table size: :xs, hover: true, dataset: runs, columns: [
              [ :spec, { heading: "Spec", value: ->(r) { transition(path: "/p/#{@project.slug}/specs/#{r.spec.id}/edit", delay: 0, class: "link link-primary font-mono") { plain r.spec.slug }; nil } } ],
              [ :status, { heading: "Status", value: ->(r) { pill concept: :run_status, value: r.status } } ],
              [ :runner, { heading: "Runner", value: ->(r) { r.runner_id } } ],
              [ :since, { heading: "Since", value: ->(r) { DaisyStack::Format.datetime(r.started_at) } } ],
              [ :last, { heading: "Last event", value: ->(r) { DaisyStack::Format.datetime(r.last_event_at) } } ]
            ]
          end
        end
      end
    end

    div class: "grid gap-4 lg:grid-cols-2 mt-4" do
      list_card title: "Up next", path: "/p/#{@project.slug}/specs?specs[status]=ready" do
        async id: "up-next", rerender_on: "specs_changed" do
          specs = @m.up_next.to_a
          if specs.empty?
            ds_empty_state text: "Nothing ranked. Run /ag-prioritise.", icon: "queue-list"
          else
            ds_table size: :xs, hover: true, dataset: specs, columns: [
              [ :rank, { heading: "#", value: ->(s) { s.rank.to_s }, align: :right } ],
              [ :slug, { heading: "Spec", value: ->(s) { transition(path: "/p/#{@project.slug}/specs/#{s.id}/edit", delay: 0, class: "link link-primary font-mono") { plain s.slug }; nil } } ],
              [ :route, { heading: "Route", value: ->(s) { s.route ? pill(concept: :route, value: s.route) : nil } } ],
              [ :deps, { heading: "Deps", value: ->(s) { s.blocked? ? ds_badge(text: "blocked", size: :sm, brand_color: :error) : ds_badge(text: "clear", size: :sm, style: :soft, brand_color: :success) } } ]
            ]
          end
        end
      end
      list_card title: "Recent events", path: "/p/#{@project.slug}/runs" do
        async id: "events", rerender_on: "runs_changed" do
          ds_table size: :xs, dataset: @m.recent_events.to_a, columns: [
            [ :at, { heading: "When", value: ->(e) { DaisyStack::Format.datetime(e.at) } } ],
            [ :spec, { heading: "Spec", value: ->(e) { e.run.spec.slug } } ],
            [ :event, { heading: "Event", value: ->(e) { e.event } } ],
            [ :detail, { heading: "Detail", value: ->(e) { e.detail.to_s.truncate(60) } } ]
          ]
        end
      end
    end

    div class: "mt-4" do
      list_card title: "Brief", path: "/p/#{@project.slug}/settings" do
        div class: "p-4 prose prose-sm max-w-none" do
          plain raw(DaisyStack::Markdown::Renderer.new.render(Projects::BriefMarkdown.new(@project).render).html)
        end
      end
    end

    ds_toast vertical: :top, horizontal: :end do
      toggle show_on: "checkpoint_opened", hide_after: 8000 do
        ds_alert status: :warning do
          plain "A build is waiting for input: {{ vc.event.data.spec }} ({{ vc.event.data.reason }})"
        end
      end
    end
  end

  private

  def lead_time_text
    secs = @m.median_lead_seconds
    return "—" if secs.nil?
    secs >= 86_400 ? "#{(secs / 86_400.0).round(1)}d" : "#{(secs / 3600.0).round(1)}h"
  end
end
```

If `DaisyStack::Markdown::Renderer#render` has a different name in the installed gem, open `vendor/daisy_stack/lib/markdown.rb` and call the method that returns a `Result` with `#html`.

- [ ] **Step 8: Write the pages test and run it**

`test/integration/pages_test.rb`:

```ruby
require "test_helper"

class PagesTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:danny) }

  test "home renders project cards with attention badge" do
    get "/"
    assert_response :success
    assert_includes response.body, "Tekmore"
    assert_includes response.body, "1 need you"
  end

  test "project dashboard renders stats, attention and up next" do
    get "/p/tekmore"
    assert_response :success
    assert_includes response.body, "Diff is green. Ship it?"
    assert_includes response.body, "ready-a"
    assert_includes response.body, "Faster onboarding"
  end

  test "outsider gets redirected from a project" do
    sign_in users(:outsider)
    get "/p/tekmore"
    assert_response :redirect
  end

  test "answering a checkpoint from the web resumes the run" do
    post "/p/tekmore/checkpoints/#{checkpoints(:open_ship).id}/answer", params: { checkpoint: { answer: "approved" } }, as: :json
    assert_response :success
    assert checkpoints(:open_ship).reload.answered?
    assert runs(:active_run).reload.active?
  end
end
```

Run: `bin/rails test test/integration/pages_test.rb`
Expected: PASS. Also open http://localhost:3300 in a browser after `npm run build && npm run build:css`, sign in as the seeded admin, and confirm the sidebar shows a project group once a project exists.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "web: shell menus, home and project dashboards with live push and inline checkpoint answers"
```

---

### Task 12: DataPage resources — inbox, specs, outcomes, runs, checkpoints, members, settings, API tokens

**Files:**
- Create: `app/matestack/web/resources/{inbox_item,spec,outcome,run,checkpoint,membership}_resource.rb`, `app/controllers/projects/{inbox_items,specs,outcomes,runs,checkpoints,memberships,settings}_controller.rb`, `app/controllers/account/api_tokens_controller.rb`, `app/matestack/web/pages/projects/{settings,rank}.rb`, `app/matestack/web/pages/account/api_tokens.rb`, `app/matestack/web/pages/projects/inbox_new.rb`, `app/javascript/assist_panel.js`
- Modify: `config/routes.rb`, `app/javascript/application.js`, `app/matestack/web/resources/user_resource.rb`
- Test: `test/integration/resources_test.rb`

**Interfaces:**
- Consumes: `Web::Scoped*` pages (Task 4), `Web::Colors`, services.
- Produces: routes under `/p/:project_slug/` for `inbox`, `specs`, `outcomes`, `runs`, `checkpoints`, `members`, `settings`, `specs/rank`; `/account/api_tokens`; every grid/detail/pill uses `Web::Colors`.

- [ ] **Step 1: Write the failing integration test**

`test/integration/resources_test.rb`:

```ruby
require "test_helper"

class ResourcesTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:keith) }

  {
    "inbox" => "/p/tekmore/inbox", "new stub" => "/p/tekmore/inbox/new", "specs" => "/p/tekmore/specs",
    "outcomes" => "/p/tekmore/outcomes", "runs" => "/p/tekmore/runs", "checkpoints" => "/p/tekmore/checkpoints",
    "members" => "/p/tekmore/members", "settings" => "/p/tekmore/settings", "rank" => "/p/tekmore/specs/rank",
    "api tokens" => "/account/api_tokens", "admin users" => "/admin/users"
  }.each do |name, path|
    test "#{name} renders" do
      get path
      assert_response :success
    end
  end

  test "spec detail renders sections, deps and checkpoints" do
    get "/p/tekmore/specs/#{specs(:tek_in_progress).id}/edit"
    assert_response :success
    assert_includes response.body, "Diff is green"
  end

  test "grid is project scoped" do
    get "/p/other/specs"
    assert_includes response.body, "Other project"
    assert_not_includes response.body, "Ready B"
  end

  test "viewer cannot create a stub" do
    sign_in users(:viewer)
    post "/p/tekmore/inbox", params: { inbox_item: { title: "x", text: "y" } }, as: :json
    assert_response :redirect
  end

  test "capture from the web with assist fields" do
    assert_difference "InboxItem.count", 1 do
      post "/p/tekmore/inbox", params: { inbox_item: { title: "Dark mode", text: "Users ask", kind: "feature", serves_outcome_id: outcomes(:faster_onboarding).id } }, as: :json
    end
    assert_response :success
    assert_equal users(:keith), InboxItem.last.captured_by
  end

  test "assist endpoint for the web form" do
    Llm.client = Llm::Fake.new("Dark mode\n\nUsers keep asking for it.")
    post "/p/tekmore/inbox/assist", params: { text: "dark mode pls" }, as: :json
    assert_response :success
    assert_equal "Dark mode", response.parsed_body["title"]
  end

  test "owner invites a member and changes a role" do
    post "/p/tekmore/members", params: { membership: { email: "out@example.com", role: "viewer" } }, as: :json
    assert_response :success
    assert_equal "viewer", projects(:tekmore).role_for(users(:outsider))
    m = projects(:tekmore).memberships.find_by(user: users(:outsider))
    patch "/p/tekmore/members/#{m.id}", params: { membership: { role: "member" } }, as: :json
    assert_equal "member", m.reload.role
  end

  test "member cannot manage members" do
    sign_in users(:danny)
    post "/p/tekmore/members", params: { membership: { email: "out@example.com", role: "viewer" } }, as: :json
    assert_response :redirect
  end

  test "settings updates brief and wip limit" do
    patch "/p/tekmore/settings", params: { project: { brief: "# New brief", wip_limit: 3 } }, as: :json
    assert_response :success
    assert_equal 3, projects(:tekmore).reload.wip_limit
  end

  test "rank editor saves an order" do
    put "/p/tekmore/specs/rank", params: { slugs: %w[ready-b ready-a] }, as: :json
    assert_response :success
    assert_equal 1, specs(:tek_ready_b).reload.rank
  end

  test "api token create shows the raw token once and revoke works" do
    post "/account/api_tokens", params: { api_token: { name: "desk" } }, as: :json
    assert_response :success
    raw = response.parsed_body["token"]
    assert_equal 64, raw.length
    token = ApiToken.find_by(token_digest: ApiToken.digest(raw))
    delete "/account/api_tokens/#{token.id}", as: :json
    assert_response :success
    assert token.reload.revoked_at
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bin/rails test test/integration/resources_test.rb`
Expected: FAIL (routing)

- [ ] **Step 3: Routes**

Inside the `scope "p/:project_slug"` block from Task 11 add:

```ruby
    daisy_stack_pages :inbox, controller: :inbox_items do
      collection { post :assist }
      member { patch :drop }
    end
    get "specs/rank", to: "specs#rank_page", as: :rank_specs
    put "specs/rank", to: "specs#rank"
    daisy_stack_pages :specs do
      member { patch :release; patch :ship; patch :abandon }
    end
    daisy_stack_pages :outcomes do
      member { patch :achieve; patch :abandon }
    end
    daisy_stack_pages :runs, only: [ :index, :edit ] do
      member { patch :close }
    end
    daisy_stack_pages :checkpoints, only: [ :index, :edit ]
    daisy_stack_pages :members, controller: :memberships, only: [ :index, :create, :update, :destroy ]
    resource :settings, only: [ :show, :update ] do
      patch :archive
    end
```

and, in `namespace :account`, `resources :api_tokens, only: [ :index, :create, :destroy ]`.

Because these resources live under `p/:project_slug`, each resource declares `route_namespace :project` and the path helpers become `project_inbox_index_path(project_slug)` etc. — the gem's `path_names` builds `project_inbox_path`/`project_specs_path`; `DaisyStack::Ui::DataPage::Base#index_path` passes `parent_object_instance` only. Override in `Web::DataPageScope` (Task 4 file) so every path call includes the project slug:

```ruby
  def index_path = send(resource.path_names[:index], params[:project_slug])
  def new_path = send(resource.path_names[:new], params[:project_slug])
  def edit_path_for(object) = send(resource.path_names[:edit], params[:project_slug], object)
  def member_path_for(object) = send(resource.path_names[:member], params[:project_slug], object)
```

(guard each with `return super unless params[:project_slug]` so `admin/users` keeps working).

- [ ] **Step 4: Inbox resource, controller, capture page with assist**

`app/matestack/web/resources/inbox_item_resource.rb`:

```ruby
class Web::Resources::InboxItemResource < DaisyStack::Ui::DataPage::Resource
  model :inbox_item
  title "Inbox"
  icon "inbox"
  route_namespace :project
  index_page Web::ScopedIndex
  detail_page Web::ScopedDetail
  new_page Web::Pages::Projects::InboxNew

  grid do
    column :title, link: :detail
    column :kind, heading: "Type", format: :badge, colors: Web::Colors::KIND
    column :status, format: :badge, colors: Web::Colors::INBOX_STATUS
    column :serves_outcome, heading: "Serves", format: ->(i) { i.serves_outcome&.title.to_s }
    column :captured_by, format: ->(i) { i.captured_by&.display_name.to_s }
    column :captured_at, format: :datetime
    filter :title, placeholder: "Search stubs"
    filter :status, buttons: InboxItem::STATUSES
    filter :kind, options: InboxItem::KINDS
    order captured_at: :desc
    paginate 20
    empty "Inbox is empty. Capture something."
    row_action :drop, label: "Drop", path: ->(i) { "/p/#{i.project.slug}/inbox/#{i.id}/drop" }, method: :patch,
               confirm: "Drop this stub?", icon: "trash", if: ->(i) { i.open? }
  end

  form do
    section "Stub", columns: 2 do
      field :title, required: true
      field :kind, as: :select, label: "Type", options: InboxItem::KINDS
      field :serves_outcome_id, as: :select, label: "Serves outcome",
            options: -> { Matestack::Ui::Core::Context.controller.current_project.outcomes.where(status: "open").ranked.pluck(:title, :id).to_h }
      field :text, as: :textarea, span: :full
    end
  end

  detail do
    stat "Status", value: ->(i) { i.status.titleize }
    stat "Duplicate?", value: ->(i) { i.duplicate_of ? "maybe of ##{i.duplicate_of_id} (#{(i.duplicate_probability.to_f * 100).round}%)" : "no" }
  end
end
```

`app/controllers/projects/inbox_items_controller.rb`:

```ruby
class Projects::InboxItemsController < ApplicationController
  include DataPages
  data_pages Web::Resources::InboxItemResource

  def create
    item = scoped_collection.new(object_params.merge(captured_by: current_user, project: current_project))
    authorize item, :create?
    if item.save
      Realtime.project_changed(current_project, :inbox_changed)
      render json: {}, status: :ok
    else
      render_form_errors(item)
    end
  end

  def assist
    authorize InboxItem, :assist?
    render json: Inbox::Assist.call(project: current_project, text: params.require(:text).to_s)
  end

  def drop
    item = find_object
    authorize item, :drop?
    item.update!(status: "dropped")
    Realtime.project_changed(current_project, :inbox_changed)
    respond_with_result(item, true, to: project_inbox_index_path(current_project.slug))
  end

  private

  def inbox_item_params
    params.require(:inbox_item).permit(:title, :text, :kind, :serves_outcome_id, :suggested_kind, :duplicate_of_id, :duplicate_probability)
  end
end
```

`app/matestack/web/pages/projects/inbox_new.rb` — the capture form with an assist panel (a small Vue sidecar posts the raw text to `/assist` and fills the fields):

```ruby
class Web::Pages::Projects::InboxNew < DaisyStack::Ui::DataPage::New
  include Web::DataPageScope

  def inner_content
    assist_panel project_slug: params[:project_slug]
    form_partial form_config
  end
end
```

`app/matestack/web/components/assist_panel.rb`:

```ruby
class Web::Components::AssistPanel < DaisyStack::Ui::Components::BaseUiVueJs
  # Tailwind safelist: mb-4 flex gap-2 items-end grow textarea textarea-bordered w-full btn btn-sm btn-primary text-xs opacity-70
  optional :project_slug
  register_as :assist_panel
  vue_name "assist-panel"

  def response
    root class: "mb-4" do
      div class: "flex gap-2 items-end" do
        div class: "grow" do
          label(class: "text-xs opacity-70") { plain "Rough idea" }
          textarea class: "textarea textarea-bordered w-full", rows: 2, "v-model": "vc.raw", placeholder: "Type it as it comes — assist tidies and classifies it"
        end
        button class: "btn btn-sm btn-primary", "@click.prevent": "vc.assist()", ":disabled": "vc.busy" do
          plain "Assist"
        end
      end
      div class: "text-xs opacity-70 mt-1", "v-if": "vc.note" do
        plain "{{ vc.note }}"
      end
    end
  end

  def vue_props
    { assist_url: "/p/#{context.project_slug}/inbox/assist" }
  end
end
```

`app/javascript/assist_panel.js`:

```js
import MatestackUiVueJs from "matestack-ui-vuejs";
import axios from "axios";

// Posts the raw line to /inbox/assist and writes the suggestions into the
// matestack form's inputs (title, text, kind, serves_outcome_id).
const assistPanel = {
  mixins: [MatestackUiVueJs.componentMixin],
  template: MatestackUiVueJs.componentHelpers.inlineTemplate,
  data() { return { raw: "", busy: false, note: "" }; },
  methods: {
    setField(name, value) {
      const el = document.querySelector(`[name="inbox_item[${name}]"]`);
      if (!el || value == null) return;
      el.value = value;
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    },
    async assist() {
      if (!this.raw.trim()) return;
      this.busy = true;
      this.note = "";
      try {
        const token = document.querySelector('meta[name="csrf-token"]')?.content;
        const { data } = await axios.post(this.props["assist_url"], { text: this.raw }, { headers: { "X-CSRF-Token": token } });
        this.setField("title", data.title);
        this.setField("text", data.text);
        this.setField("kind", data.kind);
        this.setField("suggested_kind", data.kind);
        if (data.serves_outcome_slug) this.note = `Suggested outcome: ${data.serves_outcome_slug}. `;
        if (data.duplicate_of) {
          this.note += `Possible duplicate of stub #${data.duplicate_of} (${Math.round(data.duplicate_probability * 100)}%).`;
          this.setField("duplicate_of_id", data.duplicate_of);
          this.setField("duplicate_probability", data.duplicate_probability);
        }
      } catch (e) {
        this.note = "Assist failed; fill the fields by hand.";
      } finally {
        this.busy = false;
      }
    },
  },
};
export default assistPanel;
```

Register in `application.js`: `import assistPanel from "./assist_panel"; appInstance.component("assist-panel", assistPanel);`. Add hidden fields to the inbox form section: `field :suggested_kind, as: :hidden`, `field :duplicate_of_id, as: :hidden`, `field :duplicate_probability, as: :hidden`. The "serves outcome" suggestion is shown as a note rather than auto-selected (slug ≠ id); the user picks it.

- [ ] **Step 5: Spec resource with rank editor and transitions**

`app/matestack/web/resources/spec_resource.rb`:

```ruby
class Web::Resources::SpecResource < DaisyStack::Ui::DataPage::Resource
  model :spec
  icon "document-text"
  route_namespace :project
  index_page Web::ScopedIndex
  detail_page Web::Pages::Projects::SpecDetail
  new_page Web::ScopedNew

  grid do
    column :rank, heading: "#", align: :right, format: ->(s) { s.rank.to_s }
    column :slug, link: :detail, format: ->(s) { s.slug }
    column :title
    column :status, format: :badge, colors: Web::Colors::SPEC_STATUS
    column :kind, heading: "Type", format: :badge, colors: Web::Colors::KIND
    column :route, format: ->(s) { s.route ? pill(concept: :route, value: s.route) : nil }
    column :business_value, heading: "Value", format: :badge, colors: Web::Colors::LEVEL
    column :technical_certainty, heading: "Certainty", format: :badge, colors: Web::Colors::LEVEL
    column :claimed_by_session, heading: "Claimed by"
    column :needs_review, heading: "Review", format: :boolean
    filter :slug, placeholder: "Search specs"
    filter :status, buttons: Spec::STATUSES
    filter :route, options: Spec::ROUTES
    order Arel.sql("CASE status WHEN 'in_progress' THEN 0 WHEN 'ready' THEN 1 WHEN 'shipped' THEN 2 ELSE 3 END, rank IS NULL, rank ASC, slug ASC")
    paginate 25
    empty "No specs match."
    stat "Ready", value: ->(scope) { scope.where(status: "ready").count }, format: :number
    stat "In progress", value: ->(scope) { scope.where(status: "in_progress").count }, format: :number
    stat "Shipped", value: ->(scope) { scope.where(status: "shipped").count }, format: :number
  end

  form do
    section "Spec", columns: 2 do
      field :slug, required: true
      field :title, required: true
      field :kind, as: :select, label: "Type", options: Spec::KINDS
      field :route, as: :select, options: Spec::ROUTES
      field :business_value, as: :select, options: Spec::LEVELS
      field :technical_certainty, as: :select, options: Spec::LEVELS
      field :serves_outcome_id, as: :select, label: "Serves outcome",
            options: -> { Matestack::Ui::Core::Context.controller.current_project.outcomes.ranked.pluck(:title, :id).to_h }
      field :label
    end
    section "Sections" do
      field :outcome, as: :textarea
      field :problem_why_now, as: :textarea, label: "Problem / why now"
      field :acceptance_criteria, as: :textarea
      field :scope_in, as: :textarea
      field :scope_out, as: :textarea
      field :edge_cases, as: :textarea, label: "Edge cases and failure paths"
      field :affected_areas, as: :textarea
      field :open_questions, as: :textarea
      field :verification, as: :textarea
    end
  end

  detail do
    stat "Status", value: ->(s) { s.status.titleize }
    stat "Rank", value: ->(s) { s.rank || "—" }
    stat "Deps", value: ->(s) { s.dependencies.map(&:slug).join(", ").presence || "none" }
    stat "Claimed", value: ->(s) { s.claimed_by_session.presence || "—" }, description: ->(s) { s.claimed_at ? DaisyStack::Format.datetime(s.claimed_at) : nil }
    action "Release", path: ->(s) { "/p/#{s.project.slug}/specs/#{s.id}/release" }, icon: "arrow-uturn-left", style: :outline, if: ->(s) { s.in_progress? }
    action "Ship", path: ->(s) { "/p/#{s.project.slug}/specs/#{s.id}/ship" }, icon: "check", brand_color: :success, confirm: "Mark shipped?", if: ->(s) { s.in_progress? }
    action "Abandon", path: ->(s) { "/p/#{s.project.slug}/specs/#{s.id}/abandon" }, icon: "x-mark", brand_color: :error, confirm: "Abandon this spec?", if: ->(s) { s.ready? || s.in_progress? }
    readonly_when ->(s) { s.shipped? || s.abandoned? }, notice: "This spec is closed; its record is read-only."
  end
end
```

`app/matestack/web/pages/projects/spec_detail.rb` — the gem's detail plus checkpoints and runs below:

```ruby
class Web::Pages::Projects::SpecDetail < Web::ScopedDetail
  def response
    super
    spec = object_instance
    div class: "grid gap-4 lg:grid-cols-2 mt-6" do
      list_card title: "Checkpoints", count: spec.checkpoints.count do
        cps = spec.checkpoints.includes(:answered_by).oldest_first.to_a
        if cps.empty?
          ds_empty_state text: "No checkpoints yet.", icon: "hand-raised"
        else
          ds_table size: :xs, dataset: cps, columns: [
            [ :seq, { heading: "#", value: ->(c) { c.seq.to_s } } ],
            [ :reason, { heading: "Reason", value: ->(c) { pill concept: :checkpoint_reason, value: c.reason } } ],
            [ :status, { heading: "Status", value: ->(c) { c.status } } ],
            [ :ask, { heading: "Ask", value: ->(c) { c.ask.to_s.truncate(80) } } ],
            [ :answer, { heading: "Answer", value: ->(c) { c.answer.to_s.truncate(60) } } ]
          ]
        end
      end
      list_card title: "Runs", count: spec.runs.count do
        ds_table size: :xs, dataset: spec.runs.newest_first.to_a, columns: [
          [ :runner, { heading: "Runner", value: ->(r) { r.runner_id } } ],
          [ :status, { heading: "Status", value: ->(r) { pill concept: :run_status, value: r.status } } ],
          [ :started, { heading: "Started", value: ->(r) { DaisyStack::Format.datetime(r.started_at) } } ],
          [ :ended, { heading: "Ended", value: ->(r) { r.ended_at ? DaisyStack::Format.datetime(r.ended_at) : "—" } } ]
        ]
      end
    end
    if spec.needs_review
      ds_alert "Flagged for review: #{spec.needs_review_reason}", status: :warning, variant: :soft, classes: "mt-4 text-sm"
    end
  end
end
```

`app/controllers/projects/specs_controller.rb`:

```ruby
class Projects::SpecsController < ApplicationController
  include DataPages
  data_pages Web::Resources::SpecResource

  def create
    spec = scoped_collection.new(object_params.merge(project: current_project, captured_by: current_user))
    authorize spec, :create?
    if spec.save
      Realtime.project_changed(current_project, :specs_changed)
      render json: {}, status: :ok
    else
      render_form_errors(spec)
    end
  end

  def release
    spec = find_object
    authorize spec, :release?
    Specs::Transitions.release!(spec)
    emit_and_respond(spec)
  end

  def ship
    spec = find_object
    authorize spec, :ship?
    Specs::Transitions.ship!(spec)
    emit_and_respond(spec)
  end

  def abandon
    spec = find_object
    authorize spec, :abandon?
    Specs::Transitions.abandon!(spec, reason: params[:reason].presence || "abandoned from the web")
    emit_and_respond(spec)
  end

  def rank_page
    authorize Spec, :rank?
    render Web::Pages::Projects::Rank
  end

  def rank
    authorize Spec, :rank?
    Specs::Rank.new(project: current_project, slugs: params.require(:slugs)).call
    Realtime.project_changed(current_project, :specs_changed)
    render json: {}, status: :ok
  rescue ApiError::Conflict => e
    render json: { message: e.message, errors: {} }, status: :unprocessable_entity
  end

  private

  def emit_and_respond(spec)
    Realtime.project_changed(current_project, :specs_changed)
    Realtime.project_changed(current_project, :runs_changed)
    respond_with_result(spec, true)
  end
end
```

`app/matestack/web/pages/projects/rank.rb` — a simple ordered list with up/down buttons (no drag library), saved as one `PUT` with the slug order:

```ruby
class Web::Pages::Projects::Rank < DaisyStack::Ui::Page
  # Tailwind safelist: join join-item btn btn-xs btn-ghost font-mono list-none flex items-center gap-2 py-1
  def prepare
    @specs = current_project.specs.where(status: "ready").includes(:dependencies).ranked.to_a
  end

  def response
    ds_page_header title: "Rank the ready queue", icon: "queue-list", subtitle: "Top claims first. Unranked specs are not claimable."
    ds_card bordered: true do
      rank_editor slugs: @specs.map(&:slug), ranked: @specs.map { |s| s.rank.present? },
                  blocked: @specs.map(&:blocked?), save_url: "/p/#{current_project.slug}/specs/rank"
    end
  end
end
```

`app/matestack/web/components/rank_editor.rb`:

```ruby
class Web::Components::RankEditor < DaisyStack::Ui::Components::BaseUiVueJs
  optional :slugs, :ranked, :blocked, :save_url
  register_as :rank_editor
  vue_name "rank-editor"

  def response
    root do
      ul class: "list-none" do
        li class: "flex items-center gap-2 py-1", "v-for": "(row, i) in vc.rows", ":key": "row.slug" do
          span class: "w-6 text-right tabular opacity-60", "v-text": "i + 1"
          span class: "font-mono grow", "v-text": "row.slug"
          span class: "badge badge-sm badge-error", "v-if": "row.blocked" do
            plain "blocked"
          end
          div class: "join" do
            button(class: "btn btn-xs btn-ghost join-item", "@click.prevent": "vc.move(i, -1)") { plain "↑" }
            button(class: "btn btn-xs btn-ghost join-item", "@click.prevent": "vc.move(i, 1)") { plain "↓" }
          end
        end
      end
      div class: "mt-4 flex items-center gap-2" do
        button(class: "btn btn-sm btn-primary", "@click.prevent": "vc.save()", ":disabled": "vc.busy") { plain "Save order" }
        span class: "text-xs opacity-70", "v-text": "vc.note"
      end
    end
  end

  def vue_props
    { rows: context.slugs.each_with_index.map { |s, i| { slug: s, ranked: context.ranked[i], blocked: context.blocked[i] } },
      save_url: context.save_url }
  end
end
```

`app/javascript/rank_editor.js`:

```js
import MatestackUiVueJs from "matestack-ui-vuejs";
import axios from "axios";

const rankEditor = {
  mixins: [MatestackUiVueJs.componentMixin],
  template: MatestackUiVueJs.componentHelpers.inlineTemplate,
  data() { return { rows: [], busy: false, note: "" }; },
  mounted() { this.rows = [...this.props["rows"]]; },
  methods: {
    move(i, delta) {
      const j = i + delta;
      if (j < 0 || j >= this.rows.length) return;
      const rows = [...this.rows];
      [rows[i], rows[j]] = [rows[j], rows[i]];
      this.rows = rows;
    },
    async save() {
      this.busy = true;
      try {
        const token = document.querySelector('meta[name="csrf-token"]')?.content;
        await axios.put(this.props["save_url"], { slugs: this.rows.map((r) => r.slug) }, { headers: { "X-CSRF-Token": token } });
        this.note = "Saved.";
        MatestackUiVueJs.eventHub.$emit("specs_changed", {});
      } catch (e) {
        this.note = e.response?.data?.message || "Save failed.";
      } finally {
        this.busy = false;
      }
    },
  },
};
export default rankEditor;
```

Register `rank-editor` in `application.js`.

- [ ] **Step 6: Outcome, run, checkpoint resources**

`app/matestack/web/resources/outcome_resource.rb`:

```ruby
class Web::Resources::OutcomeResource < DaisyStack::Ui::DataPage::Resource
  model :outcome
  icon "flag"
  route_namespace :project
  index_page Web::ScopedIndex
  detail_page Web::ScopedDetail
  new_page Web::ScopedNew

  grid do
    column :rank, heading: "#", align: :right, format: ->(o) { o.rank.to_s }
    column :title, link: :detail
    column :slug, format: ->(o) { o.slug }
    column :status, format: :badge, colors: Web::Colors::OUTCOME_STATUS
    column :specs, heading: "Specs", format: ->(o) { o.specs.group(:status).count.map { |k, v| "#{v} #{k}" }.join(" · ") }
    filter :title, placeholder: "Search outcomes"
    filter :status, buttons: Outcome::STATUSES
    order Arel.sql("rank IS NULL, rank ASC, slug ASC")
    paginate 20
    empty "No outcomes yet. Create one with /ag-outcome or the Add button."
  end

  form do
    section "Outcome", columns: 2 do
      field :slug, required: true
      field :title, required: true
      field :rank, as: :number
    end
    section "The bet" do
      field :claim, as: :textarea, hint: "What will be true"
      field :measure, as: :textarea, hint: "How we'd know"
      field :stop_rule, as: :textarea, hint: "When we stop betting"
      field :notes, as: :textarea
    end
  end

  detail do
    stat "Status", value: ->(o) { o.status.titleize }
    stat "Specs", value: ->(o) { o.specs.count }, format: :number
    action "Achieved", path: ->(o) { "/p/#{o.project.slug}/outcomes/#{o.id}/achieve" }, brand_color: :success, icon: "check", if: ->(o) { o.open? }
    action "Abandon", path: ->(o) { "/p/#{o.project.slug}/outcomes/#{o.id}/abandon" }, brand_color: :error, icon: "x-mark", confirm: "Abandon this outcome?", if: ->(o) { o.open? }
    nested_grid :specs, resource: "Web::Resources::SpecResource", title: "Specs serving this outcome"
  end
end
```

`app/controllers/projects/outcomes_controller.rb`:

```ruby
class Projects::OutcomesController < ApplicationController
  include DataPages
  data_pages Web::Resources::OutcomeResource

  def create
    o = scoped_collection.new(object_params.merge(project: current_project, created_by: current_user))
    authorize o, :create?
    if o.save
      Realtime.project_changed(current_project, :outcomes_changed)
      render json: {}, status: :ok
    else
      render_form_errors(o)
    end
  end

  def achieve
    o = find_object
    authorize o, :achieve?
    o.update!(status: "achieved", achieved_at: Time.current)
    Realtime.project_changed(current_project, :outcomes_changed)
    respond_with_result(o, true)
  end

  def abandon
    o = find_object
    authorize o, :abandon?
    o.update!(status: "abandoned", abandoned_at: Time.current, abandoned_reason: params[:reason].presence || "abandoned from the web")
    Realtime.project_changed(current_project, :outcomes_changed)
    respond_with_result(o, true)
  end
end
```

`app/matestack/web/resources/run_resource.rb`:

```ruby
class Web::Resources::RunResource < DaisyStack::Ui::DataPage::Resource
  model :run
  icon "play"
  route_namespace :project
  index_page Web::ScopedIndex
  detail_page Web::ScopedDetail

  grid do
    column :spec, link: :detail, format: ->(r) { r.spec.slug }
    column :status, format: :badge, colors: Web::Colors::RUN_STATUS
    column :runner_id, heading: "Runner"
    column :session_id, heading: "Session"
    column :started_at, format: :datetime
    column :last_event_at, heading: "Last event", format: :datetime
    filter :runner_id, placeholder: "Runner"
    filter :status, buttons: Run::STATUSES
    order started_at: :desc
    paginate 25
    actions :edit
    addable false
    empty "No runs recorded."
  end

  form do
    section "Run", columns: 2 do
      field :detail, as: :textarea, span: :full
    end
  end

  detail do
    stat "Status", value: ->(r) { r.status.titleize }
    stat "Spec", value: ->(r) { r.spec.slug }
    stat "Session", value: ->(r) { r.session_id.presence || "—" }, description: "claude --resume <id>"
    action "Close", path: ->(r) { "/p/#{r.project.slug}/runs/#{r.id}/close" }, style: :outline, icon: "stop", if: ->(r) { r.live? }
    readonly_when ->(r) { !r.live? }
    nested_grid :events, resource: "Web::Resources::RunEventResource", title: "Events"
    nested_grid :checkpoints, resource: "Web::Resources::CheckpointResource", title: "Checkpoints"
  end
end

class Web::Resources::RunEventResource < DaisyStack::Ui::DataPage::Resource
  model :run_event
  parent :run, through: :events
  grid do
    column :at, format: :datetime
    column :event
    column :detail
    order :at
    actions :none
    addable false
  end
end
```

`app/controllers/projects/runs_controller.rb`:

```ruby
class Projects::RunsController < ApplicationController
  include DataPages
  data_pages Web::Resources::RunResource

  def close
    run = find_object
    authorize run, :close?
    Runs::Close.call(run, detail: "closed from the web")
    Realtime.project_changed(current_project, :runs_changed)
    respond_with_result(run, true)
  end
end
```

`app/matestack/web/resources/checkpoint_resource.rb`:

```ruby
class Web::Resources::CheckpointResource < DaisyStack::Ui::DataPage::Resource
  model :checkpoint
  icon "hand-raised"
  route_namespace :project
  index_page Web::ScopedIndex
  detail_page Web::ScopedDetail

  grid do
    column :ref, link: :detail, format: ->(c) { c.ref }
    column :priority, format: :badge, colors: Web::Colors::CHECKPOINT_PRIORITY
    column :reason, format: :badge, colors: Web::Colors::CHECKPOINT_REASON
    column :status, format: ->(c) { c.status }
    column :asked_by
    column :asked_at, format: :datetime
    column :answered_by, format: ->(c) { c.answered_by&.display_name.to_s }
    filter :status, buttons: Checkpoint::STATUSES
    filter :reason, options: Checkpoint::REASONS
    order Arel.sql("CASE status WHEN 'open' THEN 0 ELSE 1 END, CASE priority WHEN 'needs_human' THEN 0 WHEN 'unclear' THEN 1 ELSE 2 END, asked_at DESC")
    paginate 25
    actions :edit
    addable false
    empty "No checkpoints."
  end

  form do
    section "Checkpoint" do
      field :ask, as: :textarea
      field :answer, as: :textarea
    end
  end

  detail do
    stat "Status", value: ->(c) { c.status.titleize }
    stat "Run", value: ->(c) { c.run.runner_id }
    readonly_when ->(c) { c.answered? }, notice: "Answered; nothing to change."
  end
end
```

`app/controllers/projects/checkpoints_controller.rb` — extend the Task 11 controller: add `include DataPages`, `data_pages Web::Resources::CheckpointResource`, and an `update` that routes through `Checkpoints::Answer`:

```ruby
  def update
    cp = find_object
    authorize cp, :answer?
    Checkpoints::Answer.call(cp, answer: object_params[:answer].to_s, by: current_user)
    Realtime.project_changed(current_project, :checkpoint_answered)
    Realtime.project_changed(current_project, :runs_changed)
    render json: {}, status: :ok
  rescue ApiError::Conflict => e
    render json: { message: e.message, errors: {} }, status: :unprocessable_entity
  end

  private

  def scoped_collection
    Checkpoint.joins(:run).where(runs: { project_id: current_project.id }).includes(:spec, :run, :answered_by)
  end
```

- [ ] **Step 7: Members, settings, API tokens, admin users**

`app/matestack/web/resources/membership_resource.rb`:

```ruby
class Web::Resources::MembershipResource < DaisyStack::Ui::DataPage::Resource
  model :membership
  title "Members"
  icon "users"
  route_namespace :project
  index_page Web::ScopedIndex

  grid do
    column :user, heading: "Name", format: ->(m) { m.user.display_name }
    column :email, format: ->(m) { m.user.email }
    column :role, format: :badge, colors: Web::Colors::ROLE, editable: false
    column :status, format: ->(m) { m.user.status }
    order :id
    actions :delete
    empty "No members."
  end

  form do
    section "Add member", columns: 2 do
      field :email, as: :email, required: true, hint: "An existing user, or a new one to invite"
      field :role, as: :select, options: Membership::ROLES
    end
  end
end
```

`app/controllers/projects/memberships_controller.rb`:

```ruby
class Projects::MembershipsController < ApplicationController
  include DataPages
  data_pages Web::Resources::MembershipResource

  def create
    authorize current_project, :manage_members?
    email = params.require(:membership)[:email].to_s.downcase.strip
    user = User.find_by(email: email)
    if user.nil?
      return render(json: { message: "Only admins can invite new users", errors: { email: [ "unknown user" ] } }, status: :unprocessable_entity) unless current_user.admin?
      user = User.invite!({ email: email }, current_user)
    end
    m = current_project.memberships.find_or_initialize_by(user: user)
    m.role = params.require(:membership)[:role].presence || "member"
    if m.save
      Realtime.project_changed(current_project, :members_changed)
      render json: {}, status: :ok
    else
      render_form_errors(m)
    end
  end

  def update
    m = find_object
    authorize current_project, :manage_members?
    if m.update(role: params.require(:membership)[:role])
      render json: {}, status: :ok
    else
      render_form_errors(m)
    end
  end

  def destroy
    m = find_object
    authorize m, :destroy?
    m.destroy
    render json: {}, status: :ok
  end

  private

  def find_object = current_project.memberships.find(params[:id])
end
```

The membership grid's index page renders a per-row role select: add to `Web::ScopedIndex` nothing; instead the `MembershipResource` grid uses `column :role, format: ->(m) { role_select(m) }` where `role_select` is a small `matestack_form` per row (`method: :patch`, `path: "/p/#{m.project.slug}/members/#{m.id}"`, `success: { emit: "project-members-update" }`) with `ds_form_select key: :role, options: Membership::ROLES, init: m.role` and a submit — put it in `app/matestack/web/components/role_select.rb` registered as `role_select`.

`app/controllers/projects/settings_controller.rb`:

```ruby
class Projects::SettingsController < ApplicationController
  def show
    authorize current_project, :update?
    render Web::Pages::Projects::Settings
  end

  def update
    authorize current_project, :update?
    if current_project.update(params.require(:project).permit(:name, :trunk, :wip_limit, :brief))
      Realtime.project_changed(current_project, :project_changed)
      render json: {}, status: :ok
    else
      render json: { message: "Missing or invalid params", errors: current_project.errors }, status: :unprocessable_entity
    end
  end

  def archive
    authorize current_project, :archive?
    current_project.update!(archived_at: Time.current)
    redirect_to root_path, status: :see_other
  end
end
```

`app/matestack/web/pages/projects/settings.rb`:

```ruby
class Web::Pages::Projects::Settings < DaisyStack::Ui::Page
  def response
    p = current_project
    ds_page_header title: "#{p.name} · Settings", icon: "cog-6-tooth"
    ds_card bordered: true do
      matestack_form for: p, method: :patch, path: "/p/#{p.slug}/settings", delay: 0,
                     success: { emit: "settings_saved" }, failure: { emit: "settings_failed" } do
        div class: "grid gap-4 md:grid-cols-3" do
          ds_form_input key: :name, label: "Name", required: true
          ds_form_input key: :trunk, label: "Trunk branch"
          ds_form_input key: :wip_limit, label: "WIP limit", type: :number
        end
        ds_form_textarea key: :brief, label: "Brief (markdown)", rows: 18,
                         hint: "The '## Prioritised outcomes' section is regenerated from open outcomes; everything else is yours."
        div(class: "mt-4 flex gap-2") { ds_form_submit text: "Save" }
      end
      toggle show_on: "settings_saved", hide_after: 3000 do
        ds_alert "Saved.", status: :success, variant: :soft, classes: "mt-3 text-sm"
      end
    end
    ds_card title: "Connect a checkout", bordered: true, classes: "mt-4" do
      ds_code_block language: "yaml", code: "---\nurl: #{request.base_url}\nproject: #{p.slug}\n---\n"
      p(class: "text-sm opacity-70 mt-2") { plain "Put that in .agentile/store.md and export AGENTILE_PROJECTS_TOKEN from your API tokens page." }
    end
    ds_card title: "Danger zone", bordered: true, classes: "mt-4" do
      action method: :patch, path: "/p/#{p.slug}/settings/archive", confirm: { text: "Archive #{p.name}? It disappears from every dashboard." },
             success: { redirect: { follow_response: true } } do
        ds_button brand_color: :error, style: :outline, size: :sm do
          plain "Archive project"
        end
      end
    end
  end
end
```

`app/controllers/account/api_tokens_controller.rb`:

```ruby
class Account::ApiTokensController < ApplicationController
  def index
    authorize ApiToken, :index?
    render Web::Pages::Account::ApiTokens
  end

  def create
    authorize ApiToken, :create?
    token = ApiToken.generate!(user: current_user, name: params.require(:api_token)[:name].presence || "token")
    render json: { token: token.raw_token }, status: :ok
  end

  def destroy
    token = policy_scope(ApiToken).find(params[:id])
    authorize token, :destroy?
    token.revoke!
    render json: {}, status: :ok
  end
end
```

`app/matestack/web/pages/account/api_tokens.rb`:

```ruby
class Web::Pages::Account::ApiTokens < DaisyStack::Ui::Page
  # Tailwind safelist: font-mono break-all select-all
  def prepare
    @tokens = current_user.api_tokens.order(created_at: :desc).to_a
  end

  def response
    ds_page_header title: "API tokens", icon: "key", subtitle: "One per machine. Shown once; export as AGENTILE_PROJECTS_TOKEN."
    ds_card bordered: true do
      token_creator create_url: "/account/api_tokens"
    end
    ds_card bordered: true, classes: "mt-4" do
      async id: "tokens", rerender_on: "token_changed" do
        ds_table size: :sm, dataset: current_user.api_tokens.order(created_at: :desc).to_a, columns: [
          [ :name, { heading: "Name", value: ->(t) { t.name } } ],
          [ :created, { heading: "Created", value: ->(t) { DaisyStack::Format.datetime(t.created_at) } } ],
          [ :used, { heading: "Last used", value: ->(t) { t.last_used_at ? DaisyStack::Format.datetime(t.last_used_at) : "never" } } ],
          [ :status, { heading: "Status", value: ->(t) { t.revoked_at ? ds_badge(text: "revoked", size: :sm, brand_color: :neutral) : ds_badge(text: "active", size: :sm, style: :soft, brand_color: :success) } } ],
          [ :revoke, { heading: "", value: ->(t) {
            next nil if t.revoked_at
            action(method: :delete, path: "/account/api_tokens/#{t.id}", confirm: { text: "Revoke #{t.name}?" }, success: { emit: "token_changed" }) { ds_button size: :xs, style: :ghost, brand_color: :error do plain "Revoke" end }
            nil
          } } ]
        ]
      end
    end
  end
end
```

`app/matestack/web/components/token_creator.rb` + `app/javascript/token_creator.js`: a `BaseUiVueJs` component (`register_as :token_creator`, `vue_name "token-creator"`) with a name input, a "Create token" button that `axios.post`s `{ api_token: { name } }` to `create_url` with the CSRF header, shows the returned `token` in a `font-mono break-all select-all` box with a copy button, and emits `token_changed` on the event hub (`MatestackUiVueJs.eventHub.$emit("token_changed", {})`). Register `token-creator` in `application.js`.

`app/matestack/web/resources/user_resource.rb`: drop the `standard_rate` column/field and the hours stats; keep name/email/admin/status, invitation resend.

- [ ] **Step 8: Run the tests, then click through**

Run: `bin/rails test`
Expected: PASS. Then `bin/dev`, sign in, create a project (`/projects/new`), capture a stub with Assist (with `ANTHROPIC_API_KEY`/`TYPESAFE_API_KEY` set in `.env`, or `JEV_FAKE=1` to use the fake transport in development — add `Jev.transport = Jev::FakeTransport.new if ENV["JEV_FAKE"] == "1"` and `Llm.client = Llm::Fake.new("Tidy title\n\nTidy text.") if ENV["LLM_FAKE"] == "1"` to `config/initializers/jev.rb`), rank two specs, answer a checkpoint from the dashboard, create an API token.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "web: inbox with assist, specs with rank editor, outcomes, runs, checkpoints, members, settings, API tokens"
```

---

### Task 13: Airtable import task

**Files:**
- Create: `lib/agentile/airtable_client.rb`, `lib/agentile/importer.rb`, `lib/tasks/agentile.rake`
- Test: `test/lib/agentile/importer_test.rb`, `test/fixtures/files/airtable/{inbox,specs,members,outcomes,checkpoints,runs}.json`

**Interfaces:**
- Produces: `Agentile::AirtableClient.new(token:, base_id:).records(table) -> [ { "id" => , "fields" => {} } ]` (follows `offset` pagination); `Agentile::Importer.new(base_id:, project_slug:, client:).call -> { users:, outcomes:, inbox:, specs:, checkpoints:, runs: }` counts; rake `agentile:import[base_id,project_slug]`.

- [ ] **Step 1: Write the fixtures**

`test/fixtures/files/airtable/members.json`:

```json
[ { "id": "recM1", "fields": { "Name": "Keith", "Email": "keith@example.com", "Git Email": "keith@example.com" } },
  { "id": "recM2", "fields": { "Name": "Newbie", "Email": "new@example.com" } } ]
```

`test/fixtures/files/airtable/outcomes.json`:

```json
[ { "id": "recO1", "fields": { "Title": "Imported outcome", "Slug": "imported-outcome", "Status": "open", "Rank": 1,
    "Claim": "c", "Measure": "m", "Stop Rule": "s", "Created By": [ "recM1" ] } } ]
```

`test/fixtures/files/airtable/inbox.json`:

```json
[ { "id": "recI1", "fields": { "Title": "Imported stub", "Text": "text", "Type": "bug", "Captured At": "2026-09-01",
    "Status": "Open", "Captured By": [ "recM2" ], "Serves Outcome": [ "recO1" ] } } ]
```

`test/fixtures/files/airtable/specs.json`:

```json
[ { "id": "recS1", "fields": { "Slug": "imp-a", "Title": "Imported A", "Status": "shipped", "Type": "feature", "Route": "background",
    "Business Value": "high", "Technical Certainty": "high", "Tags": [ "x" ], "Acceptance Criteria": "- a",
    "Created At": "2026-08-20T10:00:00.000Z", "Claimed At": "2026-08-21T10:00:00.000Z", "Shipped At": "2026-08-22T10:00:00.000Z",
    "Claimed By (Session)": "s1", "Captured By": [ "recM1" ], "Shaped By": [ "recM1" ], "Serves Outcome": [ "recO1" ] } },
  { "id": "recS2", "fields": { "Slug": "imp-b", "Title": "Imported B", "Status": "ready", "Type": "chore", "Rank": 1,
    "Depends On": [ "recS1" ], "Created At": "2026-09-01T10:00:00.000Z", "Source Inbox Item": [ "recI1" ] } },
  { "id": "recS3", "fields": { "Slug": "imp-c", "Title": "Imported C", "Status": "abandoned", "Abandoned Reason": "r",
    "Abandoned At": "2026-09-02T10:00:00.000Z", "Created": "2026-08-01" } } ]
```

`test/fixtures/files/airtable/checkpoints.json`:

```json
[ { "id": "recC1", "fields": { "Ref": "imp-a #001 ship_approval", "Seq": 1, "Reason": "ship_approval", "Asked By": "ship",
    "Asked At": "2026-08-22T09:00:00.000Z", "Session Id": "s1", "Status": "answered", "Ask": "ship?", "Answer": "yes",
    "Answered At": "2026-08-22T09:30:00.000Z", "Answered By": [ "recM1" ], "Spec": [ "recS1" ] } } ]
```

`test/fixtures/files/airtable/runs.json`:

```json
[ { "id": "recR1", "fields": { "Ref": "imp-a s1", "Event": "started", "Status": "closed", "At": "2026-08-21T10:00:00.000Z", "Runner": "s1", "Spec": [ "recS1" ] } },
  { "id": "recR2", "fields": { "Ref": "imp-a s1", "Event": "shipped", "Status": "closed", "At": "2026-08-22T10:00:00.000Z", "Runner": "s1", "Spec": [ "recS1" ] } } ]
```

- [ ] **Step 2: Write the failing test**

`test/lib/agentile/importer_test.rb`:

```ruby
require "test_helper"

class Agentile::ImporterTest < ActiveSupport::TestCase
  class FakeClient
    def records(table)
      JSON.parse(Rails.root.join("test/fixtures/files/airtable/#{table.downcase}.json").read)
    end
  end

  def import
    Agentile::Importer.new(base_id: "appX", project_slug: "imported", client: FakeClient.new).call
  end

  test "creates the project and every record with links preserved" do
    counts = import
    project = Project.find_by!(slug: "imported")
    assert_equal({ users: 1, outcomes: 1, inbox: 1, specs: 3, checkpoints: 1, runs: 1 }, counts)

    newbie = User.find_by!(email: "new@example.com")
    assert newbie.invitation_pending?
    assert project.member?(users(:keith))

    a = project.specs.find_by!(slug: "imp-a")
    assert a.shipped?
    assert_equal users(:keith), a.captured_by
    assert_equal [ users(:keith) ], a.shapers.to_a
    assert_equal "imported-outcome", a.serves_outcome.slug
    assert_equal Time.utc(2026, 8, 20, 10), a.created_at
    assert_equal %w[x], a.tags

    b = project.specs.find_by!(slug: "imp-b")
    assert_equal [ a ], b.dependencies.to_a
    assert_equal 1, b.rank
    assert_equal "Imported stub", b.source_inbox_item.title

    c = project.specs.find_by!(slug: "imp-c")
    assert_equal Time.utc(2026, 8, 1), c.created_at

    run = a.runs.first
    assert run.shipped?
    assert_equal %w[started shipped], run.events.chronological.map(&:event)
    cp = a.checkpoints.first
    assert_equal run, cp.run
    assert cp.answered?
    assert_equal users(:keith), cp.answered_by
  end

  test "is idempotent" do
    import
    assert_no_difference [ "Spec.count", "InboxItem.count", "Checkpoint.count", "RunEvent.count", "User.count" ] { import }
  end
end
```

- [ ] **Step 3: Run to see it fail**

Run: `bin/rails test test/lib/agentile/importer_test.rb`
Expected: FAIL with `uninitialized constant Agentile::Importer`

- [ ] **Step 4: Implement**

`lib/agentile/airtable_client.rb`:

```ruby
require "net/http"
require "json"

module Agentile
  class AirtableClient
    API = "https://api.airtable.com/v0".freeze

    def initialize(token:, base_id:)
      @token, @base_id = token, base_id
    end

    def records(table)
      out = []
      offset = nil
      loop do
        uri = URI("#{API}/#{@base_id}/#{URI.encode_www_form_component(table)}")
        uri.query = URI.encode_www_form({ pageSize: 100, offset: offset }.compact)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@token}"
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        raise "Airtable #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
        body = JSON.parse(res.body)
        out.concat(body["records"])
        offset = body["offset"]
        break if offset.nil?
      end
      out
    end
  end
end
```

`lib/agentile/importer.rb`:

```ruby
module Agentile
  # Pulls one Airtable base (the 0.14–0.19 Team-store schema) into a Project.
  # Idempotent on (project, slug), checkpoint (spec, seq), run event (run, event, at).
  class Importer
    def initialize(base_id:, project_slug:, client: nil, project_name: nil)
      @client = client || AirtableClient.new(token: ENV.fetch("AGENTILE_AIRTABLE_TOKEN"), base_id: base_id)
      @slug, @name = project_slug, project_name || project_slug.titleize
      @users = {}
      @outcomes = {}
      @inbox = {}
      @specs = {}
      @counts = Hash.new(0)
    end

    def call
      Project.transaction do
        @project = Project.find_or_create_by!(slug: @slug) { |p| p.name = @name }
        import_members
        import_outcomes
        import_inbox
        import_specs
        import_runs
        import_checkpoints
      end
      @counts.slice(:users, :outcomes, :inbox, :specs, :checkpoints, :runs).to_h.transform_values(&:to_i).tap do |h|
        %i[users outcomes inbox specs checkpoints runs].each { |k| h[k] ||= 0 }
      end
    end

    private

    def f(rec, key) = rec["fields"][key]
    def t(val) = val.present? ? Time.zone.parse(val.to_s).utc : nil
    def link(rec, key) = Array(f(rec, key)).first

    def import_members
      @client.records("Members").each do |rec|
        email = (f(rec, "Email").presence || f(rec, "Git Email")).to_s.downcase.strip
        next if email.empty?
        user = User.find_by(email: email) || User.find_by(git_email: email)
        if user.nil?
          user = User.invite!({ email: email, name: f(rec, "Name") }, nil)
          @counts[:users] += 1
        end
        user.update_column(:git_email, f(rec, "Git Email")) if f(rec, "Git Email").present? && user.git_email.blank?
        @project.memberships.find_or_create_by!(user: user) { |m| m.role = "member" }
        @users[rec["id"]] = user
      end
    end

    def import_outcomes
      @client.records("Outcomes").each do |rec|
        o = @project.outcomes.find_or_initialize_by(slug: f(rec, "Slug").presence || f(rec, "Title").to_s.parameterize)
        @counts[:outcomes] += 1 if o.new_record?
        o.assign_attributes(title: f(rec, "Title"), status: f(rec, "Status").presence || "open", rank: f(rec, "Rank"),
                            claim: f(rec, "Claim"), measure: f(rec, "Measure"), stop_rule: f(rec, "Stop Rule"), notes: f(rec, "Notes"),
                            abandoned_reason: f(rec, "Abandoned Reason"), achieved_at: t(f(rec, "Achieved At")),
                            abandoned_at: t(f(rec, "Abandoned At")), created_by: @users[link(rec, "Created By")])
        o.save!
        o.update_column(:created_at, t(f(rec, "Created"))) if f(rec, "Created").present?
        @outcomes[rec["id"]] = o
      end
    end

    def import_inbox
      @client.records("Inbox").each do |rec|
        title = f(rec, "Title").presence || f(rec, "Text").to_s.lines.first.to_s.strip.truncate(80)
        captured_at = t(f(rec, "Captured At")) || Time.current
        item = @project.inbox_items.find_or_initialize_by(title: title, captured_at: captured_at)
        @counts[:inbox] += 1 if item.new_record?
        item.assign_attributes(text: f(rec, "Text"), kind: f(rec, "Type").presence || "feature",
                               status: f(rec, "Status").to_s.downcase.presence || "open",
                               captured_by: @users[link(rec, "Captured By")], serves_outcome: @outcomes[link(rec, "Serves Outcome")])
        item.save!
        @inbox[rec["id"]] = item
      end
    end

    def import_specs
      records = @client.records("Specs")
      records.each do |rec|
        s = @project.specs.find_or_initialize_by(slug: f(rec, "Slug"))
        @counts[:specs] += 1 if s.new_record?
        s.assign_attributes(
          title: f(rec, "Title"), status: f(rec, "Status").presence || "ready", kind: f(rec, "Type").presence || "feature",
          route: f(rec, "Route"), business_value: f(rec, "Business Value"), technical_certainty: f(rec, "Technical Certainty"),
          rank: f(rec, "Rank"), tags: Array(f(rec, "Tags")), outcome: f(rec, "Outcome"), problem_why_now: f(rec, "Problem / Why Now"),
          acceptance_criteria: f(rec, "Acceptance Criteria"), scope_in: f(rec, "Scope In"), scope_out: f(rec, "Scope Out"),
          edge_cases: f(rec, "Edge Cases"), affected_areas: f(rec, "Affected Areas"), open_questions: f(rec, "Open Questions"),
          verification: f(rec, "Verification"), abandoned_reason: f(rec, "Abandoned Reason"), label: f(rec, "Label"),
          claimed_by_session: f(rec, "Claimed By (Session)"), claimed_at: t(f(rec, "Claimed At")),
          shipped_at: t(f(rec, "Shipped At")), abandoned_at: t(f(rec, "Abandoned At")),
          claimed_by_user: @users[link(rec, "Claimed By (Member)")], captured_by: @users[link(rec, "Captured By")],
          serves_outcome: @outcomes[link(rec, "Serves Outcome")], source_inbox_item: @inbox[link(rec, "Source Inbox Item")]
        )
        s.save!
        created = t(f(rec, "Created At")) || t(f(rec, "Created"))
        s.update_column(:created_at, created) if created
        s.shapers = Array(f(rec, "Shaped By")).filter_map { |id| @users[id] }
        @specs[rec["id"]] = s
      end
      records.each do |rec|
        s = @specs[rec["id"]]
        s.dependencies = Array(f(rec, "Depends On")).filter_map { |id| @specs[id] }
      end
    end

    # Runs are events in Airtable; group into one Run per (spec, runner).
    def import_runs
      @runs = {}
      events = @client.records("Runs").map { |rec| rec }.sort_by { |rec| f(rec, "At").to_s }
      events.group_by { |rec| [ link(rec, "Spec"), f(rec, "Runner").to_s ] }.each do |(spec_id, runner), recs|
        spec = @specs[spec_id] or next
        first_at = t(f(recs.first, "At")) || Time.current
        run = spec.runs.find_or_initialize_by(runner_id: runner.presence || "unknown", started_at: first_at)
        if run.new_record?
          run.project = @project
          run.status = "active"
          run.save!
          @counts[:runs] += 1
        end
        recs.each do |rec|
          at = t(f(rec, "At")) || first_at
          next if run.events.exists?(event: f(rec, "Event"), at: at)
          Runs::Event.call(run, event: f(rec, "Event"), detail: f(rec, "Detail"), at: at)
        end
        @runs[[ spec_id, runner ]] = run
      end
    end

    def import_checkpoints
      @client.records("Checkpoints").each do |rec|
        spec = @specs[link(rec, "Spec")] or next
        seq = f(rec, "Seq").to_i
        next if spec.checkpoints.exists?(seq: seq)
        session = f(rec, "Session Id").to_s
        run = spec.runs.find_by(session_id: session) || spec.runs.find_by(runner_id: session) || spec.runs.order(:started_at).last ||
              Runs::Start.call(project: @project, spec: spec, runner_id: session.presence || "imported", session_id: session, at: t(f(rec, "Asked At")) || Time.current)
        spec.checkpoints.create!(run: run, seq: seq, reason: f(rec, "Reason"), asked_by: f(rec, "Asked By").presence || "build",
                                 asked_at: t(f(rec, "Asked At")) || Time.current, session_id: session.presence,
                                 status: f(rec, "Status").presence || "open", ask: f(rec, "Ask"), answer: f(rec, "Answer"),
                                 answered_at: t(f(rec, "Answered At")), answered_by: @users[link(rec, "Answered By")])
        @counts[:checkpoints] += 1
      end
    end
  end
end
```

`lib/tasks/agentile.rake`:

```ruby
namespace :agentile do
  desc "Import an Airtable Agentile base into a project: agentile:import[appXXXX,project-slug]"
  task :import, [ :base_id, :project_slug ] => :environment do |_t, args|
    require "agentile/importer"
    abort "usage: agentile:import[base_id,project_slug]" if args[:base_id].blank? || args[:project_slug].blank?
    counts = Agentile::Importer.new(base_id: args[:base_id], project_slug: args[:project_slug]).call
    puts counts.map { |k, v| "#{k}: #{v}" }.join("\n")
  end
end
```

Ensure `config.autoload_lib(ignore: %w[assets tasks])` (already set) lets `Agentile::Importer` autoload from `lib/agentile/`.

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/lib`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "import: agentile:import rake task pulls an Airtable base into a project, idempotently"
```

---

### Task 14: Production config, Kamal, Dockerfile, README

**Files:**
- Modify: `config/deploy.yml`, `.kamal/secrets`, `.env.example`, `config/environments/production.rb`, `config/initializers/jev.rb` (create), `Dockerfile`, `README.md`, `db/seeds.rb`

**Interfaces:**
- Produces: a deployable image `keithrowell/agentile-projects` served at `https://agentile-projects.agentaconsulting.com`; secrets `RAILS_MASTER_KEY KAMAL_REGISTRY_PASSWORD ADMIN_EMAIL ADMIN_PASSWORD TYPESAFE_API_KEY ANTHROPIC_API_KEY GITHUB_TOKEN`.

- [ ] **Step 1: `config/deploy.yml`**

```yaml
service: agentile-projects
image: keithrowell/agentile-projects

servers:
  web:
    - server1.agentaconsulting.com

proxy:
  ssl: true
  hosts:
    - agentile-projects.agentaconsulting.com
  app_port: 80

deploy_timeout: 300

registry:
  username: keithrowell
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  secret:
    - RAILS_MASTER_KEY
    - ADMIN_EMAIL
    - ADMIN_PASSWORD
    - TYPESAFE_API_KEY
    - ANTHROPIC_API_KEY
  clear:
    # Jobs run in-process on the async adapter; SolidQueue polling on SQLite
    # busy-loops the CPU when idle.
    SOLID_QUEUE_IN_PUMA: false
    MAILER_HOST: agentile-projects.agentaconsulting.com
    AGENTILE_LLM_MODEL: claude-sonnet-5

aliases:
  console: app exec --interactive --reuse "bin/rails console"
  shell:   app exec --interactive --reuse "bash"
  logs:    app logs -f
  dbc:     app exec --interactive --reuse "bin/rails dbconsole"
  import:  app exec --interactive --reuse "bin/rails agentile:import"

volumes:
  - "agentile-projects-storage:/rails/storage"

asset_path: /rails/public/assets

builder:
  arch: arm64
  secrets:
    - GITHUB_TOKEN
```

- [ ] **Step 2: `.kamal/secrets` and `.env.example`**

`.kamal/secrets`:

```bash
RAILS_MASTER_KEY=$(cat config/master.key)
KAMAL_REGISTRY_PASSWORD=$(sed -n 's/^KAMAL_REGISTRY_PASSWORD=//p' .env | tail -1)
ADMIN_EMAIL=$(sed -n 's/^ADMIN_EMAIL=//p' .env | tail -1)
ADMIN_PASSWORD=$(sed -n 's/^ADMIN_PASSWORD=//p' .env | tail -1)
TYPESAFE_API_KEY=$(sed -n 's/^TYPESAFE_API_KEY=//p' .env | tail -1)
ANTHROPIC_API_KEY=$(sed -n 's/^ANTHROPIC_API_KEY=//p' .env | tail -1)
GITHUB_TOKEN=$(sed -n 's/^GITHUB_TOKEN=//p' .env | tail -1)
```

`.env.example`:

```bash
KAMAL_REGISTRY_PASSWORD=
ADMIN_EMAIL=admin@agentaconsulting.com
ADMIN_PASSWORD=
TYPESAFE_API_KEY=
ANTHROPIC_API_KEY=
GITHUB_TOKEN=
# Local development only:
# JEV_FAKE=1
# LLM_FAKE=1
# AGENTILE_AIRTABLE_TOKEN=   (for bin/rails agentile:import)
```

Confirm `.env` is in `.gitignore` (it is in the copied file).

- [ ] **Step 3: Production env, Jev initializer, Dockerfile, seeds**

`config/environments/production.rb`: set `config.action_mailer.default_url_options = { host: ENV.fetch("MAILER_HOST", "agentile-projects.agentaconsulting.com"), protocol: "https" }`, keep `config.active_job.queue_adapter = :async`, `config.cache_store = :solid_cache_store`, and add `config.action_cable.allowed_request_origins = [ "https://agentile-projects.agentaconsulting.com" ]`, `config.assume_ssl = true`, `config.force_ssl = true`, `config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }`.

`config/initializers/jev.rb`:

```ruby
Rails.application.config.after_initialize do
  Jev.transport = Jev::FakeTransport.new if ENV["JEV_FAKE"] == "1"
  Llm.client = Llm::Fake.new("Tidy title\n\nTidy text.") if ENV["LLM_FAKE"] == "1"
end
```

`Dockerfile`: update the header comment and the image name; nothing else changes (Node, `bin/link-daisy-stack`, `GITHUB_TOKEN` secret all stay).

`db/seeds.rb`: keep the admin seed; in development only, also seed a sample project with two outcomes, three stubs, four specs (one in progress with an open `ship_approval` checkpoint and a paused run) so the dashboards have content — guard with `if Rails.env.development?`.

- [ ] **Step 4: README**

Replace `README.md` with: what the app is (Agentile's backlog store: projects, members, inbox, specs, outcomes, runs, checkpoints), Run it locally (`bin/setup`, admin login, `JEV_FAKE=1 LLM_FAKE=1` for keyless dev), Stack table (as the demo's, with Pundit/RubyLLM/Jev rows added), API (base URL, bearer token, one-line pointer to the plugin's `bin/ag-store` as the reference client, endpoint table copied from spec §5), Connecting a checkout (`store.md` block + `AGENTILE_PROJECTS_TOKEN`), Importing from Airtable (`AGENTILE_AIRTABLE_TOKEN=... bin/rails "agentile:import[appXXX,slug]"`), Tests, Deploy (`.env`, `kamal setup`, `kamal deploy`, `kamal import`).

- [ ] **Step 5: Verify the image builds and the suite is green**

Run: `bin/rails test && docker build -t agentile_projects --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN .` (export `GITHUB_TOKEN=$(gh auth token)` first)
Expected: tests PASS; image builds. `kamal setup` is run by Keith once DNS for `agentile-projects.agentaconsulting.com` points at server1.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "deploy: Kamal service agentile-projects on server1, secrets, production config, README"
```

---

### Task 15: Capybara system tests

**Files:**
- Create: `test/system/{invitation_test,capture_with_assist_test,checkpoint_answer_test,home_attention_test}.rb`
- Modify: `test/application_system_test_case.rb`

**Interfaces:**
- Consumes: everything above; `ApplicationSystemTestCase#sign_in_as(user)`.

- [ ] **Step 1: Update the system test base**

`test/application_system_test_case.rb`:

```ruby
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  def sign_in_as(user, password: "password123")
    visit new_user_session_path
    fill_in "email", with: user.email
    fill_in "password", with: password
    click_on "Sign in"
    assert_text "Your projects"
  end

  def shot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png").to_s)
  end
end
```

- [ ] **Step 2: Write the tests**

`test/system/invitation_test.rb`:

```ruby
require "application_system_test_case"

class InvitationTest < ApplicationSystemTestCase
  test "invited user accepts and lands on the home dashboard" do
    user = User.invite!({ email: "invitee@example.com" }, users(:keith))
    projects(:tekmore).memberships.create!(user: user, role: "member")
    visit accept_user_invitation_path(invitation_token: user.raw_invitation_token)
    fill_in "name", with: "Ivy"
    fill_in "password", with: "password123"
    fill_in "password_confirmation", with: "password123"
    click_on "Create account"
    assert_text "Your projects"
    assert_text "Tekmore"
    shot("01-home-after-invite")
  end
end
```

`test/system/capture_with_assist_test.rb`:

```ruby
require "application_system_test_case"

class CaptureWithAssistTest < ApplicationSystemTestCase
  test "assist fills the form and the stub appears in the inbox" do
    sign_in_as users(:danny)
    visit "/p/tekmore/inbox/new"
    fill_in placeholder: "Type it as it comes — assist tidies and classifies it", with: "dark mode pls"
    click_on "Assist"
    assert_field "inbox_item[title]", with: "Title"
    click_on "Save"
    visit "/p/tekmore/inbox"
    assert_text "Title"
    shot("02-inbox")
  end
end
```

(The test helper installs `Llm::Fake.new("Title\n\nBody.")`; the system test process shares it because `driven_by` runs the app in-process.)

`test/system/checkpoint_answer_test.rb`:

```ruby
require "application_system_test_case"

class CheckpointAnswerTest < ApplicationSystemTestCase
  test "answering from the project dashboard clears the attention list" do
    sign_in_as users(:keith)
    click_on "Tekmore"
    assert_text "Diff is green. Ship it?"
    shot("03-project-dashboard-attention")
    fill_in placeholder: "Your answer (e.g. approved)", with: "approved"
    click_on "Answer"
    assert_text "Nothing needs you right now."
    assert checkpoints(:open_ship).reload.answered?
    assert runs(:active_run).reload.active?
    shot("04-project-dashboard-clear")
  end
end
```

`test/system/home_attention_test.rb`:

```ruby
require "application_system_test_case"

class HomeAttentionTest < ApplicationSystemTestCase
  test "home shows the attention badge and theme toggle works" do
    sign_in_as users(:danny)
    assert_text "1 need you"
    find("label.ds-theme-toggle").click
    assert_equal "agentile-dark", page.evaluate_script("document.documentElement.dataset.theme")
    shot("05-home-dark")
  end
end
```

- [ ] **Step 3: Run them**

Run: `bin/rails test:system`
Expected: PASS (4 tests), screenshots in `tmp/screenshots/`. Look at `03-project-dashboard-attention.png` and confirm the `ship_approval` pill is warning-coloured and `needs_human` is error-coloured (spec §7).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "system tests: invitation, capture with assist, checkpoint answer, home attention"
```

---

## Self-review against the spec

- §3 app repo → Task 1, 14. §4 every table/enum/uniqueness/concurrency → Tasks 2, 6, 7. Markdown contract → Task 3. §5 every endpoint incl. `assist`, `shape`, `.md` variants, error shapes → Tasks 5, 8. §7 home + project dashboards, resources, colour table, themes → Tasks 1, 11, 12. §8 events, buffered emits, authorised channel, solid_cable → Task 9 (+ cable.yml already production `solid_cable`). §9 assist thresholds, triage, sanity with fail-closed, judgments → Task 10. §10 auth (Devise invitable kept, Pundit) → Task 4; import → Task 13; hosting → Task 14; testing → every task plus Task 15. §11 cut-over pieces that live in the app: token page, `store.md` snippet on settings, import task, live dashboards → Tasks 12, 13, 11.
- Not in this plan (by design): the plugin branch (`bin/ag-store` HTTP client, skill edits) — separate plan; project creation via API (spec §12 out of scope; web-only `ProjectsController#new/create` for admins is included so a project can exist before `/ag-init` links it).
- Names used consistently: `Specs::Claim#call → Result(result, spec, run)`, `Runs::Start.call`, `Runs::Event.call`, `Runs::Close.call`, `Checkpoints::Open.call`, `Checkpoints::Answer.call`, `Realtime.project_changed`, `Web::Colors.for`, `Web::ScopedIndex/Detail/New`, `Inbox::Assist.call(project:, text:)`, serializers `SpecSummary/InboxItemJson/OutcomeJson/CheckpointJson/RunJson`.
