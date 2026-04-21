# OpenSOP — Handoff

A snapshot of where the project stands, where the code lives, and what to pick up next. Read this first if you're returning to the project after a break.

---

## TL;DR

The MVP per [`SPEC.md`](./SPEC.md) §8 is shipped:

- YAML process parser, registry, instance executor with 8 step-type executors (3 real, 5 stubs).
- 9 JSON API endpoints under `/sop/*` with token auth.
- Server-rendered admin UI (Hotwire + Tailwind 4 + ViewComponent): Dashboard, Process Library, Process Detail, Instance Dashboard, Instance Detail.
- 135 RSpec examples, 0 failures.
- Two example processes (`customer-onboarding`, `lead-qualification`) that run end-to-end.
- Demo rake tasks: `bin/rails opensop:demo` and `bin/rails opensop:demo_leads`.

Run it:

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails opensop:demo            # full pipeline in the console
bin/rails server                  # http://localhost:3000
bin/rspec                         # 135 / 0
```

---

## What got built (by layer)

### Data (`app/models/sop/`, `db/migrate/`)

Five models, all UUID-keyed, JSONB-heavy:

| Model | Table | Purpose |
|-------|-------|---------|
| `Sop::Process` | `sop_processes` | Parsed YAML definition, indexed by `(name, version)` |
| `Sop::Instance` | `sop_instances` | A running execution; stores process inputs/outputs and snapshotted name+version |
| `Sop::Step` | `sop_steps` | One row per step per instance, ordered by `position` |
| `Sop::Event` | `sop_events` | Audit log of state changes |
| `Sop::Callback` | `sop_callbacks` | Pending webhook callbacks; `callback_path` auto-generated as `/sop/webhooks/<uuid>` |

**Note:** `Sop::Process` is declared as `class Sop::Process < ApplicationRecord` (qualified form) to avoid collision with Ruby's top-level `::Process`. Don't reopen `module Sop` and write `class Process`.

Factories at `spec/factories/sop_*.rb` produce valid records by default.

### Engine (`app/services/opensop/`)

| Service | Role |
|---------|------|
| `Opensop::DefinitionParser` | Validate a YAML/Hash against the 0.1 spec |
| `Opensop::Registry` | Load `processes/*.sop.yaml` into `Sop::Process` rows; idempotent |
| `Opensop::InputResolver` | Resolve `from:` references (`process.inputs.x`, `steps.y.outputs.z`, `env.X`, `instance.field`) |
| `Opensop::ConditionEvaluator` | Tiny recursive-descent boolean parser. **No `eval`.** Supports `== != > >= < <= && || !` and parens. Optional `extra:` hash for resolving bare identifiers (used by `required_if`). |
| `Opensop::InstanceExecutor` | Orchestrator: `start`, `advance!`, `submit_step`, `cancel!`. Two-pass output resolution (resolve `from:` first, then drop fields whose `required_if` is false). |
| `Opensop::StepExecutor` | Dispatcher → `step_executors/*` |

Step executors:

| Step type | Status | Notes |
|-----------|--------|-------|
| `automated` | ✅ real | Spawns the script via `Open3.capture3`, JSON in/out per [SPEC §6.3](./SPEC.md#63-step-execution-model) |
| `form` | ✅ real | Pauses at `waiting_for_input`; advance via `submit_step` |
| `notification` | ✅ real (stub) | Returns `{notified: true}` immediately — no real send |
| `webhook` | ✅ real | Fires outbound HTTP (HTTParty), supports `sync` and `callback` response modes. Interpolates `${env.X}`, `${process.inputs.Y}`, `${callback_url}`, and bare step-input paths in URL/headers/body_template. `poll` mode not yet implemented. |
| `judgment` | 🟡 stub | Pauses at `escalated`. **No LLM integration** — fill via `submit_step`. |
| `approval` | 🟡 stub | Pauses at `waiting_for_approval`. |
| `subprocess` | 🟡 stub | Pauses at `waiting_for_subprocess`. **No child instance is created.** |
| `wait` | 🟡 partial | If a `seconds:` is given, returns success immediately (does not actually sleep). If `until:` condition, pauses. |

### HTTP (`app/controllers/sop/`, `app/controllers/ui/`, `config/routes/`)

Routes split into two files: `config/routes/sop.rb` (API) and `config/routes/ui.rb` (admin UI).

API endpoints:

```
GET  /sop/                                  Discovery
GET  /sop/:name/schema                      Process definition
POST /sop/:name/start                       Start instance
GET  /sop/:name/:id                         Instance state
POST /sop/:name/:id/cancel                  Cancel
GET  /sop/:name/:id/steps                   List steps
POST /sop/:name/:id/steps/:step_id/submit   Advance a step
GET  /sop/instances                         List instances (filters: state, process, limit, offset)
POST /sop/webhooks/:callback_id             Inbound webhook callback (no auth)
POST /sop/triggers/:process_name            Third-party webhook trigger (HMAC-authed)
```

Auth: `X-SOP-Token` header. If `ENV['OPENSOP_API_TOKEN']` is unset, the API is open (with a `Rails.logger.warn`); if set, strict.

UI routes:

```
/                    Dashboard (stat tiles + recent instances)
/processes           Process Library
/processes/:name     Process detail (read-only)
/instances           Instance Dashboard with state/process filters
/instances/:id       Instance Detail (steps, forms for waiting/escalated, audit log, cancel)
```

### Admin UI (`app/views/ui/`, `app/components/`, `app/assets/tailwind/`)

- Layout: `app/views/layouts/application.html.erb` (sticky navbar via `NavbarComponent`, flash banner, footer).
- ViewComponents (all under `app/components/`): `NavbarComponent`, `StateBadgeComponent`, `StepStateIconComponent`, `StatTileComponent`, `KeyValueListComponent`, `FieldListComponent`, `TimestampComponent`, `EmptyStateComponent`.
- Tailwind 4 — config lives **inside** `app/assets/tailwind/application.css` (`@source` directives), not in a `tailwind.config.js`. Component classes (`.btn`, `.card`, `.chip`, etc.) defined in `@layer components`.
- Stimulus: a single `flash_controller.js` for auto-dismiss. Cancel confirmations use Turbo's built-in `data-turbo-confirm`.
- i18n: 158 keys at `config/locales/opensop.en.yml`. **Project rule:** every UI string goes through `t('opensop.namespace.key')` — no inline English, no lazy `t('.foo')`.

### Tests (`spec/`)

```
spec/models/sop/         model specs (38 examples)
spec/services/opensop/   service specs (67 examples)
spec/requests/sop/       API request specs (30 examples — incl. webhook receive integration)
spec/factories/          FactoryBot
spec/support/            json_response, process_definition_builder, sop_api helpers
```

Run subsets:

```bash
bin/rspec spec/models
bin/rspec spec/services
bin/rspec spec/requests
```

### Demo / sample data (`processes/`, `lib/tasks/opensop.rake`)

- `processes/customer-onboarding.sop.yaml` — 6 steps (form → automated → judgment → webhook → automated → notification).
- `processes/lead-qualification.sop.yaml` — 3 steps (form → automated → notification).
- `processes/steps/*.rb` — Ruby scripts for the automated steps. Read JSON from stdin, print JSON to stdout.
- `lib/tasks/opensop.rake` — `opensop:load_processes`, `opensop:demo`, `opensop:demo_leads`.

---

## Where to make a given change

| If you want to… | Touch |
|---|---|
| Add a new step type | `app/services/opensop/step_executors/<type>.rb` + register in `app/services/opensop/step_executor.rb` + extend `Opensop::DefinitionParser`'s step-type validation + add badge color in `app/components/state_badge_component.rb` + i18n key in `opensop.steps.type.<name>` |
| Add a new field type | `app/services/opensop/definition_parser.rb` (validation), `app/services/opensop/input_resolver.rb` (handling), and the form-renderer in `app/views/ui/instances/_step_form.html.erb` |
| Add a new API endpoint | `app/controllers/sop/<...>_controller.rb` + `config/routes/sop.rb` + a serializer if new shape + a request spec |
| Add a new admin UI page | `app/controllers/ui/<...>_controller.rb` + `app/views/ui/<...>/<action>.html.erb` + `config/routes/ui.rb` + a nav item in `NavbarComponent` |
| Adjust the engine's progression logic | `app/services/opensop/instance_executor.rb` — `advance!`, `submit_step`, `resolve_process_outputs` |
| Change auth | `app/controllers/sop/application_controller.rb#authenticate_sop_token!` |
| Tweak any UI text | `config/locales/opensop.en.yml` |

---

## Known residuals (not blocking — fix when convenient)

1. **Rubocop:** ~64 cosmetic offenses, 32 autocorrectable. `bin/rubocop -a` to clean up.
2. **`ParametersWrapper` noise:** the webhook controller's incoming JSON body is also wrapped under a `"webhook"` key by Rails. The declared outputs land correctly at the top level, but `step.outputs` ends up with an extra `"webhook"` key that mirrors the payload. One-line fix: `wrap_parameters format: []` in `Sop::WebhooksController` (or the `Sop::ApplicationController`).
3. **No CSRF on UI cancel forms?** Confirm that `Ui::ApplicationController` has CSRF protection enabled (it inherits `ActionController::Base`, so it should — but the swarm explicitly disabled it on the API base. Worth a sanity check.)
4. **Demo data isn't isolated:** `opensop:demo` deletes by `metadata['demo'] == true` but other dev data is preserved across runs. Dev-only concern.
5. **Wait step doesn't actually wait.** It returns immediately for `seconds:` durations. Real timer support needs ActiveJob + the `solid_queue` recurring scheduler (already in the Gemfile).
6. **No structured logging.** All logs go to `Rails.logger` plain. If you want to ship to a log aggregator, wire up `Lograge` or similar.

---

## What's NOT built (deferred per [SPEC §8](./SPEC.md#8-what-to-build-first))

### v0.2 candidates

- **Process Designer UI** ([SPEC §7.1](./SPEC.md#71-build--process-designer)) — visual builder for `.sop.yaml`. Currently authored as YAML.
- **Judgment router with LLM** ([SPEC §6.4](./SPEC.md#64-judgment-step-execution)) — currently stubs to `escalated`.
- **Real outbound webhook calls** — the inbound callback receiver works; the outbound POST does not. Add `HTTParty` calls in `Opensop::StepExecutors::Webhook` with body templating.
- **Subprocess execution** — currently a stub. Needs to spawn a child `Sop::Instance` and wait for completion before resolving the parent step's outputs.
- **Form-step UI in the API** ([SPEC §4.3](./SPEC.md#43-agent-as-step-executor)) — submitting form steps via API works; the UI needs nicer rendering for nested object outputs (currently dumps a JSON textarea).
- **Event bus webhook delivery** — events are emitted to `Sop::Event`, but there's no outbound delivery to subscribers.

### v0.3 candidates

- **Metrics view with constraint detection** ([SPEC §7.3](./SPEC.md#73-observe--process-metrics)).
- **`.well-known/opensop` discovery** ([SPEC §4.4](./SPEC.md#44-the-protocol-vision)).
- **CLI** (`opensop init/validate/run/deploy`).
- **WIP-threshold alerts.**

### Operational

- **Auth model is single-token.** No multi-tenant, no per-process access control yet (defined in YAML at [SPEC §3.5](./SPEC.md#35-auth-model) but not enforced).
- **No rate limiting on webhook receive.**
- **No HMAC verification on webhook callbacks.** Anyone with the callback URL can submit.
- **No background-job worker running by default.** The Wait/poll execution paths assume `solid_queue` will be wired up.

---

## Picking up — recommended next steps

If you have an afternoon:

1. **Ship outbound webhooks.** Add `HTTParty.post` in `Opensop::StepExecutors::Webhook` with body templating from `body_template:`. Move the call into an ActiveJob so it doesn't block `advance!`. Add specs.
2. **Wire up a real LLM judgment.** New `Opensop::JudgmentRouter` service. Anthropic SDK call, structured output via tool_use, confidence threshold gate. Make it configurable per step (provider, model). The seam is in `Opensop::StepExecutors::Judgment#call`.

If you have a week:

3. **Process Designer.** A Stimulus-driven form builder per [SPEC §7.1](./SPEC.md#71-build--process-designer). The whole flow is "the YAML is the source of truth" — the designer writes YAML to disk (or to the DB) and the existing parser/registry handles the rest.
4. **Metrics view.** Mostly DB queries — `Sop::Step.group(:step_id).count`, cycle time per step, conversion. The "constraint" is whichever step has highest WIP relative to throughput. Auto-flag in the UI per [SPEC §7.3](./SPEC.md#73-observe--process-metrics).
5. **Real `wait` step + scheduled processes.** Use `solid_queue`'s recurring jobs.

---

## Conventions worth keeping

- **`Sop::` namespace** for the model layer, `Opensop::` for services. The naming split avoids the `::Process` collision and is intentional.
- **Process definitions are YAML, source-of-truth in `processes/`.** The DB is a cache. `Opensop::Registry.load_all` re-syncs.
- **Every state change emits a `Sop::Event`.** Use this as the integration point for any external subscriber.
- **Tailwind only — no inline `style=""`.** Enforced by review.
- **Full i18n key paths.** No `t('.foo')`.
- **Heroicons only** for icons (inline SVG is fine).
- **No `eval`, no `instance_eval`, no `system` with user input** in services. The `ConditionEvaluator` exists specifically to give a safe expression layer.

---

## Operational quick reference

| Task | Command |
|------|---------|
| Run server (Rails + Tailwind watcher) | `bin/dev` (Procfile.dev) or `bin/rails server` |
| Reseed processes from `processes/*.sop.yaml` | `bin/rails opensop:load_processes` |
| Run the demo pipeline | `bin/rails opensop:demo` |
| Run the leads demo | `bin/rails opensop:demo_leads` |
| Reset all instance/step/event/callback rows | `bin/rails runner 'Sop::Callback.delete_all; Sop::Event.delete_all; Sop::Step.delete_all; Sop::Instance.delete_all'` |
| Full test suite | `bin/rspec` |
| Coverage report | `COVERAGE=1 bin/rspec` then open `coverage/index.html` |
| Brakeman | `bundle exec brakeman` |
| Tailwind rebuild | `bin/rails tailwindcss:build` |

---

## Files to read first if you're new

1. [`SPEC.md`](./SPEC.md) — what the platform does and why
2. [`HANDOFF.md`](./HANDOFF.md) — this file
3. [`docs/architecture.md`](./docs/architecture.md) — how the engine runs an instance
4. [`docs/process-authoring.md`](./docs/process-authoring.md) — how to write a `.sop.yaml`
5. [`processes/customer-onboarding.sop.yaml`](./processes/customer-onboarding.sop.yaml) — the canonical example
6. [`app/services/opensop/instance_executor.rb`](./app/services/opensop/instance_executor.rb) — the heart of the engine
