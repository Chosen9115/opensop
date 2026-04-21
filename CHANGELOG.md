# Changelog

All notable changes to OpenSOP. Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added — engine

- **Webhook step — real outbound HTTP.** Fires the declared `method` + `url` via HTTParty when the step executes. Supports two response modes:
  - `response_mode: sync` — uses the JSON response body as the step's outputs directly.
  - `response_mode: callback` — fires outbound, then pauses at `waiting_for_callback` until the provider POSTs back to the auto-generated callback URL. On outbound failure, the callback row is destroyed so no orphans are left behind.
- **`Opensop::Templating`** — `${expr}` interpolation for webhook URLs, headers, and body templates. Supports `${env.X}`, `${process.inputs.Y}`, `${callback_url}`, and bare step-input paths (`${business_record.legal_name}`). Missing variables raise loudly.
- **`OPENSOP_BASE_URL`** — configures the public base URL used when constructing `${callback_url}` for outbound webhooks. Defaults to `http://localhost:3000`.

### Added — tests

- 12 new specs for `Opensop::Templating`.
- 15 new specs for `Opensop::StepExecutors::Webhook` covering sync + callback + validation + interpolation paths, all WebMock-stubbed.

### Added — project

- `LICENSE` — Apache 2.0 (SPEC §8 already declared it).

## [0.1.0] — 2026-04-18

First MVP release per [`SPEC.md`](./SPEC.md) §8. Defines, executes, and exposes business processes as APIs.

### Added — engine

- **Process definition parser** — validates `.sop.yaml` against the OpenSOP 0.1 spec.
- **Definition registry** — loads `processes/*.sop.yaml`, upserts to `Sop::Process` rows, idempotent.
- **Instance executor** — `start`, `advance!`, `submit_step`, `cancel!`. Single-transaction state changes. Two-pass output resolution honoring `required_if:`.
- **Input resolver** — handles `process.inputs.<x>`, `steps.<id>.outputs.<x>`, `env.<X>`, `instance.<field>` references.
- **Condition evaluator** — recursive-descent parser for `condition:` and `required_if:` expressions. No `eval`. Supports `== != > >= < <= && || !` and parens.
- **Step executors** — `automated` (real, runs scripts via stdin/stdout JSON per [SPEC §6.3](./SPEC.md#63-step-execution-model)), `form` (real), `notification` (stub returning immediately), `webhook` (creates inbound callback, no outbound yet), `judgment` / `approval` / `subprocess` / `wait` (pause-and-wait stubs).
- **Five-table store** — `sop_processes`, `sop_instances`, `sop_steps`, `sop_events`, `sop_callbacks`. UUID PKs, JSONB columns, GIN index on tags.

### Added — API

- `GET /sop/` — discovery endpoint.
- `GET /sop/:name/schema` — process definition.
- `POST /sop/:name/start` — start an instance.
- `GET /sop/:name/:id` — instance state.
- `GET /sop/:name/:id/steps` — step states.
- `POST /sop/:name/:id/steps/:step_id/submit` — advance a step.
- `POST /sop/:name/:id/cancel` — cancel an instance.
- `GET /sop/instances` — list instances with `state`/`process`/`limit`/`offset` filters.
- `POST /sop/webhooks/:callback_id` — inbound webhook callback receiver. Top-level Hash payloads merge into step outputs; non-Hash payloads wrap under `webhook_response`. Persists raw payload to `Sop::Callback.response` even on validation failure (no data loss).
- `X-SOP-Token` auth — strict when `OPENSOP_API_TOKEN` is set, open with a warning when unset.

### Added — admin UI

- **Dashboard** (`/`) — stat tiles (running/waiting/completed/failed) + recent instances.
- **Process Library** (`/processes`) — catalog of defined processes with in-flight counts.
- **Process Detail** (`/processes/:name`) — read-only view of inputs/outputs/steps/raw YAML.
- **Instance Dashboard** (`/instances`) — list with state and process filters.
- **Instance Detail** (`/instances/:id`) — header, summary, inputs, per-step cards with submit forms for `waiting_for_input` / `waiting_for_approval` / `escalated`, outputs panel, audit log, cancel button with Turbo confirm.
- **Tailwind 4** — config inside `app/assets/tailwind/application.css`. Component classes (`.btn`, `.card`, `.chip`).
- **Hotwire** — Turbo + one Stimulus controller (`flash_controller.js`).
- **8 ViewComponents** — `NavbarComponent`, `StateBadgeComponent`, `StepStateIconComponent`, `StatTileComponent`, `KeyValueListComponent`, `FieldListComponent`, `TimestampComponent`, `EmptyStateComponent`.
- **i18n** — 158 keys at `config/locales/opensop.en.yml`. All UI strings go through `t('opensop.*')`.

### Added — sample data

- `processes/customer-onboarding.sop.yaml` — six-step process covering form → automated → judgment → webhook → automated → notification.
- `processes/lead-qualification.sop.yaml` — three-step lead-qualification process.
- `processes/steps/*.rb` — Ruby scripts for the automated steps.
- `lib/tasks/opensop.rake` — `opensop:load_processes`, `opensop:demo`, `opensop:demo_leads`.

### Added — tests

- 135 RSpec examples, 0 failures. Coverage of models (38), services (67), and request specs (30).
- FactoryBot factories for all five models.
- WebMock disabling external HTTP by default.
- SimpleCov gated on `COVERAGE=1`.

### Added — documentation

- [`HANDOFF.md`](./HANDOFF.md) — where everything lives, what's next.
- [`docs/architecture.md`](./docs/architecture.md) — how the engine runs an instance.
- [`docs/process-authoring.md`](./docs/process-authoring.md) — how to write a `.sop.yaml`.
- [`README.md`](./README.md) — quick-start.

### Not yet built (deferred to v0.2 / v0.3 per [SPEC §8](./SPEC.md#8-what-to-build-first))

- Process Designer UI
- LLM-backed judgment router
- Outbound webhook HTTP calls (only inbound callbacks work today)
- Subprocess execution
- Real `wait` step timer support
- Metrics view with constraint detection
- `.well-known/opensop` discovery convention
- CLI (`opensop init/validate/run`)
- WIP-threshold alerts
- HMAC verification on webhook callbacks
- Per-process access control
