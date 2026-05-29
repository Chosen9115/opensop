# Changelog

All notable changes to OpenSOP. Format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased] — 2026-05-26

### Added — self-host

- **One-command Docker Compose install.** Two paths share the same stack:
  - **Script-driven:** `curl -fsSL .../scripts/install.sh | bash` — generates `RAILS_MASTER_KEY`, `SECRET_KEY_BASE`, `OPENSOP_API_TOKEN`, and a Postgres password; writes `.env` (mode 600); brings the stack up; polls `/up`; smoke-tests `/sop/`. (#49)
  - **Agent-driven:** Point Claude Code or Cursor at `INSTALL_FOR_AGENTS.md` — a machine-readable contract with mandatory decision-gate pauses for mode (local-dev / self-host-local / public), auth config, LLM integration, and first admin. (#49)
- **`OPENSOP_DISABLE_AUTH`** — guarded login-bypass for local-dev and trusted single-machine installs. When set, the admin UI auto-authenticates as the bootstrap admin without a passkey ceremony. Silently ignored when `OPENSOP_RP_ID` is a real domain, so public deployments always stay behind auth. A red banner in the admin UI and a loud boot-log warning surface whenever the bypass is active. (#49)
- **Makefile** — 13 targets for ongoing ops: `setup`, `up`, `down`, `logs`, `shell`, `console`, `health`, `backup`, `rotate-token`, `rotate-master-key`, `uninstall`. Includes cross-platform `sed` handling (BSD vs GNU). (#49)

### Fixed — self-host

- **Solid Cache / Queue databases weren't wired in Compose.** Only `DATABASE_URL` was forwarded to the app container; `CACHE_DATABASE_URL` and `QUEUE_DATABASE_URL` were unset, so `db:prepare` fell back to a local socket and aborted under `bash -e`, crash-looping the container. Fixed by pointing them at dedicated databases on the same `db` service. (#49)
- **`SOLID_QUEUE_IN_PUMA` was hardcoded `true` in Compose**, overriding `.env`. In `local-dev` mode (`RAILS_ENV=development`) the Solid Queue tables are never migrated, so the in-Puma supervisor crashed Puma on boot. Compose now honors the env var; `install.sh` writes `SOLID_QUEUE_IN_PUMA=false` for local-dev. (#49)

### Fixed — CI

- **GitHub Actions deploy job skipped when `FLY_API_TOKEN` is unset.** The job previously ran and failed at the auth step. Now exits early with a warning so the rest of CI isn't blocked on deploys from forks or branches without the secret. (#45)

### Maintenance

- **Process library curated for fresh installs.** A fresh `db:seed` previously registered everything under `processes/` — including internal engine smoke-test fixtures and undocumented AppSignal worker definitions that operators have no use for. Trimmed to the two README-documented examples (`customer-onboarding`, `lead-qualification`). Smoke-test fixtures moved to `spec/fixtures/processes/`; the fork convention (drop `processes/<your-org>/` and it auto-loads) is unchanged. (#50)
- **Dependabot bumps:** `pagy` 43.5.5 (#46), `bootsnap` 1.24.5 (#47).

---

## [Unreleased] — 2026-05-19

The big shift this week was the **passkey admin auth migration shipping to production** — see the section below for the full migration guide. Everything in this entry is on top of that.

### Added — admin UI

- **Users link in the sidebar Account section.** Admins can now reach `/account/users` (invite, list, remove admins) directly from the sidebar instead of typing the URL. Uses a distinct `user-circle` heroicon so it doesn't visually collide with the `users` icon already on Agents. First spec for `SidebarComponent` lands alongside (covers visibility gating, link paths, active highlighting, ordering, and the icon-collision regression). (#43)

### Fixed — auth

- **`POST /auth/magic_links` returned 500 in production.** `Resend::Emails.send(from:, to:, ...)` was being called with Ruby keyword args, but the gem's signature is `def send(params, options: {})` — under Ruby 3 those don't auto-collapse into a positional Hash, so the call fell through to `Object#send` and raised `ArgumentError`. The original spec missed it because `allow(...).to receive(:send)` bypasses the real method signature. Fix wraps the params in an explicit `{}` and adds a WebMock-backed regression spec that exercises the real SDK code path so the dispatch mismatch surfaces in CI. (#41)

### Fixed — CI / deploy

- **CI deploy job couldn't find the Fly CLI.** `superfly/flyctl-actions/setup-flyctl@master` only puts `flyctl` on PATH on the GitHub runner, but `bin/deploy` was hardcoded to call `fly` (which is what Homebrew installs locally). `bin/deploy` now detects at script start (`command -v flyctl || command -v fly`) and uses whichever is present. Works in both environments without forcing either side to install the other alias. (#42)

### Maintenance

- **Security gem bumps** (rolled in with the auth-fix PR):
  - `net-imap` 0.6.3 → 0.6.4 — closes 5 advisories including command injection (`CVE-2026-42258`, `CVE-2026-42257`), STARTTLS stripping, DoS, and quadratic-complexity response parsing.
  - `view_component` 4.8.0 → 4.11.0 — closes `CVE-2026-44836` (preview route helper dispatch) and `CVE-2026-44837` (system test path escape).
- **Dependabot bumps:** `oj` 3.17.1 (#35), `selenium-webdriver` 4.44.0 (#37), `bootsnap` 1.24.4 (#39), `pagy` 43.5.4 (#38), `thruster` 0.1.21 (#36), `actions/checkout` 6 (#32).
- Closed `oj` 3.17.0 bump (#17) — superseded by #35 (3.17.1).

### Known issues / follow-ups

- **`FLY_API_TOKEN` GitHub Actions secret not set.** Auto-deploy on push to `main` reaches the deploy step (PR #42 fixed the binary-not-found error) but fails authenticating against Fly. Until the secret is added, deploys must be done manually with `fly deploy --app opensop --remote-only`.
- **Legacy `OPENSOP_UI_USER` / `OPENSOP_UI_PASSWORD` Fly secrets** are still set on the `opensop` app. Harmless under the new code (nothing reads them) but should be removed: `fly secrets unset OPENSOP_UI_USER OPENSOP_UI_PASSWORD -a opensop`.

## [Unreleased] — 2026-05-04

### BREAKING

- **Admin UI authentication migrated from HTTP Basic to passkeys (WebAuthn).** The `OPENSOP_UI_USER` and `OPENSOP_UI_PASSWORD` environment variables are no longer used and should be removed from your deployment. Operators must set `OPENSOP_BOOTSTRAP_EMAIL`, `RESEND_API_KEY`, `OPENSOP_MAILER_FROM`, `OPENSOP_RP_ID`, and `OPENSOP_ORIGIN` before upgrading. See [README](./README.md#authentication) for the full migration guide. Closes [GAP-9](./GAPS.md).

### Added — auth

- Passkey-based sign-in via WebAuthn (`/auth/sign_in`).
- Email-based magic link sign-in and account recovery (delivered via Resend).
- Multi-admin support: invite/remove admins at `/account/users`.
- Per-passkey management at `/account/passkeys` (list, rename, revoke).
- Active session management at `/account/sessions` (revoke individual sessions, sign out everywhere else).
- `AuthEvent` audit log table — records sign-in, sign-out, passkey registration/revocation, magic-link requests, and other auth events.
- Rate limiting on auth endpoints via rack-attack (5/hour magic-link per email, 20/min passkey verify per IP, etc.).

### Removed

- HTTP Basic authentication on the admin UI (`OPENSOP_UI_USER` / `OPENSOP_UI_PASSWORD`).
- The `/dashboard` route no longer requires a username/password prompt.
- The `application_mailer.rb` Rails scaffold (auth emails are sent via a plain-Ruby Resend wrapper, not ActionMailer).

### Migration

For an existing deployment:

1. Add `RESEND_API_KEY`, `OPENSOP_MAILER_FROM`, `OPENSOP_RP_ID`, `OPENSOP_ORIGIN` to your environment.
2. Add `OPENSOP_BOOTSTRAP_EMAIL=your-admin-email@your-domain` (one-time).
3. Deploy. Watch the logs for the first-login URL or read `tmp/opensop_first_login.txt`.
4. Visit the URL and register your first passkey.
5. Remove `OPENSOP_UI_USER` and `OPENSOP_UI_PASSWORD` from your environment.

## [Unreleased]

### Added — UI

- **Copy debug prompt button on errored instances.** When an instance has an error (instance-level or per-step), a "Copy debug prompt" button now appears in the top-right of each red error block. Clicking copies a Claude-ready, XML-tagged prompt to the clipboard — including the process name + version, instance ID, full process YAML (truncated to 4KB), failed-step inputs/outputs/error trace, and instance inputs — wrapped in framing language that lets the user paste it directly into Claude and get useful debugging help on the first try. Truncation budgets: YAML 4KB, error trace 8KB, JSON payloads 2KB each, max 3 failed steps per instance-level prompt.

### Security

- **Engine fails closed in production when `OPENSOP_API_TOKEN` is unset.** Previously logged a warning and served `/sop/*` open — a deploy without the token exposed every endpoint (incl. instance inputs with PII) to the internet. Now returns `503 server_misconfigured` for every `/sop/*` request in `Rails.env.production?` when the token is blank. Dev/test unchanged (warn + open-mode). Closes [GAP-8](./GAPS.md).

### Added — engine

- **`trigger: type: webhook` — third-party webhooks can start instances directly.** Process YAML declares an HMAC-authenticated trigger endpoint; providers (Cal.com, Stripe, Typeform, HubSpot, DocuSign, GitHub) POST to `/sop/triggers/<process-name>` with the configured signature header and the engine verifies, maps the payload via `input_mapping`, and starts an instance. No host-side adapter required. Closes [GAP-7](./GAPS.md).
  - Supports HMAC-SHA256 with hex or base64 encoding, optional prefix (`sha256=...` style).
  - `input_mapping` uses the same `${...}` templating as webhook steps, plus `${payload.X.Y.Z}` with integer array-index support.
  - Values that are entirely a single `${...}` expression preserve their raw type (numbers stay numbers, objects stay objects) — critical for schema validation downstream.
  - Malformed payloads and failed input validation return 200-with-logged-reason so providers don't retry on a shape mismatch. Log tags: `MAPPING_REJECTED`, `INSTANCE_REJECTED`.
  - Replay protection deferred (documented); dedupe downstream by provider-specific ID.

### Added — previously

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
