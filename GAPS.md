# Engine Gaps

Tracked gaps between what teams want to express in OpenSOP and what the current engine supports. Each entry is a candidate for public upstream work.

Format: `#GAP-N | severity | description | discovered while | fix scope`

---

## Open

### GAP-1 | 🟡 medium | `notification` step is a stub

**Symptom:** `notification` steps return `{ notified: true }` immediately without actually sending anything.

**Discovered while:** planning `lead-capture` (needs to send magic-link email on onboarding intent).

**Fix scope:** wire up real delivery in `app/services/opensop/step_executors/notification.rb`. Support `channel: email` (via an email provider like Postmark/SendGrid — gem TBD), `channel: slack`, `channel: sms`. Per-channel config via `ENV`. ~1 day.

---

### GAP-2 | 🟡 medium | `subprocess` step is a stub

**Symptom:** `subprocess` steps pause at `waiting_for_subprocess` but never actually spawn a child instance.

**Discovered while:** planning how `lead-capture` hands off to `customer-onboarding` when intent is "start onboarding."

**Fix scope:** implement child instance creation in `app/services/opensop/step_executors/subprocess.rb`. Start child, store its ID on the parent step's outputs, subscribe to child's `completed` event, resolve parent when child resolves. Needs thought on: failure propagation (child fails → parent fails?), cancel propagation (parent cancelled → child cancelled?), input mapping. ~2 days.

---

### GAP-3 | 🟢 low | `trigger: type: schedule` is in spec but not implemented

**Symptom:** processes can only be started via `POST /sop/:name/start`. The spec defines `trigger: type: schedule` with a cron expression, but nothing runs them.

**Discovered while:** planning `funnel-snapshot` (wants to run weekly).

**Fix scope:** tap Rails' built-in `solid_queue` (already in Gemfile, already configured). Read `trigger.schedule` from process definitions; when set, register a recurring job that calls `InstanceExecutor.start` on the cron schedule. Surface scheduled instances in the admin UI with a "next run" column. ~1 day.

---

### GAP-4 | 🟢 low | No built-in "find instance by metadata" primitive

**Symptom:** processes that need to dedupe (e.g., "is there already a running `lead-capture` for this email?") must write an `automated` step that queries `Sop::Instance` via the Rails runner. Works but feels under-engineered.

**Discovered while:** discussing dedup for `lead-capture`.

**Fix scope:** add a helper API — probably `InstanceExecutor.find_by_metadata(process_name:, metadata: {...})` — and expose it as a template variable or a script helper. Optional: a dedup primitive in the YAML itself (`dedupe_on: process.inputs.email` at the process level). ~0.5 day.

---

### GAP-5 | 🟢 low | Cross-process queries are ad-hoc

**Symptom:** reporting processes like `funnel-snapshot` need to count instances of other processes. Currently done by writing scripts that query `Sop::Instance` directly. Works but requires DB knowledge, not process-model knowledge.

**Discovered while:** planning `funnel-snapshot`.

**Fix scope:** add a `/sop/metrics` endpoint (already in SPEC §7.3) that exposes counts, conversions, and cycle times per process with date/state filters. Then scripts can hit HTTP instead of the DB. ~0.5-1 day.

---

### GAP-6 | 🟢 low | `wait` step with `seconds:` doesn't actually wait

**Symptom:** `wait` steps with a `seconds:` duration return immediately instead of pausing. `wait` with `until:` pauses forever (no polling).

**Discovered while:** discussing "follow up if abandoned after 24h" scenarios.

**Fix scope:** same `solid_queue` infrastructure as GAP-3. Enqueue a delayed job that advances the step when the timer fires. ~1 day, paired with GAP-3.

---

## Closed

### GAP-8 | 🟡 medium | Engine now fails closed in production when `OPENSOP_API_TOKEN` is unset — **closed 2026-04-29**

`Sop::ApplicationController#authenticate_sop_token!` returns `503 server_misconfigured` for every `/sop/*` request in `Rails.env.production?` when the token env var is blank. Dev/test keeps the warn + open-mode behavior so local work stays frictionless. 3 new specs cover the prod path. Discovered in a Coba deploy where the Fly secret wasn't set — the API was briefly open to the internet; this fix makes that class of incident impossible.

### GAP-7 | 🟡 medium | `trigger: type: webhook` — **closed 2026-04-21** (commit `25aad1b`)

Third-party SaaS webhooks can now start process instances directly via `POST /sop/triggers/<process-name>` with HMAC signature verification. Documented in [SPEC §2.2](./SPEC.md), [docs/API.md](./docs/API.md), and Playbook D in [docs/AGENT_GUIDE.md](./docs/AGENT_GUIDE.md). Closed GAP-4 use case partially — still no built-in dedup by payload key, but providers that retry will create duplicate instances carrying the provider ID in metadata, so `automated` steps can dedupe downstream.

### GAP-9 | 🟡 medium | Admin UI had no authentication — **closed 2026-05-04** (branch `worktree-auth-passkeys`)

Phase 4 hard cutover: the admin UI is now gated by session-based passkey authentication (with magic-link as the bootstrap path). `Ui::ApplicationController` runs `before_action :require_authentication` from the `Authenticatable` concern; unauthenticated requests are redirected to `/auth/sign_in?return_to=…`. The previous HTTP Basic gate (`OPENSOP_UI_USER` / `OPENSOP_UI_PASSWORD`) and its boot-time guard initializer have been removed entirely. `/sop/*` API endpoints are unaffected — they still use `X-SOP-Token`. `/api-docs/*` remains intentionally public.

---

## How to fix a gap

1. Open an issue on `Chosen9115/opensop` referencing the gap number.
2. Branch from `main`, implement + test.
3. Push to `public`, open PR.
4. After merge, pull into local `main`, push to `origin` (Coba fork).
5. Update this file: move the entry to the Closed section with the PR link and date.
