# OpenSOP REST API Reference

This is the complete reference for the `/sop/*` JSON API. Every endpoint is documented with its request shape, response shape, possible errors, and a copy-pasteable `curl` example. Use this alongside [`AGENT_GUIDE.md`](./AGENT_GUIDE.md) if you're authoring or integrating processes.

Spec and format: see [`SPEC.md`](../SPEC.md).
Interactive collection: import [`opensop.postman.json`](./opensop.postman.json) into Yaak, Postman, Insomnia, or Bruno.

---

## Base URL and conventions

| | |
|---|---|
| **Base URL (local)** | `http://localhost:3000` |
| **Base URL (prod)** | your deployment's origin |
| **Content-Type** | `application/json` for all request bodies |
| **Response format** | JSON, UTF-8 |
| **Timestamps** | ISO 8601 with `Z` suffix (UTC) |
| **IDs** | UUIDs (v4) |
| **Pagination** | `limit` + `offset` query params where supported |

All endpoints are rooted under `/sop/`. Process-scoped routes use `/sop/:name/...` where `:name` matches `[a-z0-9][a-z0-9_-]*`.

---

## Authentication

OpenSOP uses a single header: **`X-SOP-Token`**.

The server reads the expected token from the `OPENSOP_API_TOKEN` environment variable. Two modes:

### Dev mode (token unset)

If `OPENSOP_API_TOKEN` is blank or unset **in development or test**, authentication is skipped and every request is allowed. The server logs a warning on first request (`OPENSOP_API_TOKEN not set — API is open (dev/test mode)`). Useful for local development and tests.

```bash
curl http://localhost:3000/sop/
```

**In production**, the engine refuses to serve `/sop/*` entirely when the token is unset — every request returns:

```json
{ "error": "server_misconfigured",
  "message": "OPENSOP_API_TOKEN is not set. Set it via your deployment's secret management before serving traffic." }
```

with HTTP 503. This is a deliberate fail-closed: a production deploy without a token would otherwise expose every endpoint (including PII from instance inputs) to the open internet. Set the token via your platform's secret manager (e.g. `fly secrets set OPENSOP_API_TOKEN=$(openssl rand -hex 32)`) before directing traffic at the deploy.

### Strict mode (token set)

If `OPENSOP_API_TOKEN` is set, every non-webhook request must send `X-SOP-Token` with a matching value. Mismatch returns `401`.

```bash
export OPENSOP_API_TOKEN="sk_live_..."        # server-side
curl http://localhost:3000/sop/ \
  -H "X-SOP-Token: sk_live_..."               # client-side
```

The `actor` field on events and step submissions derives from this: `"agent"` when a valid token was presented, `"system"` when anonymous (dev mode).

**Exception:** `POST /sop/webhooks/:callback_id` never requires auth — third parties call it and wouldn't know your token.

---

## Endpoints at a glance

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/sop/` | List all active processes (discovery) |
| `GET` | `/sop/:name/schema` | Fetch a process's full YAML-derived definition |
| `POST` | `/sop/:name/start` | Start a new instance |
| `GET` | `/sop/:name/:id` | Get an instance's full state (includes steps) |
| `GET` | `/sop/:name/:id/steps` | List an instance's steps |
| `POST` | `/sop/:name/:id/steps/:step_id/submit` | Submit outputs for an active step → advance the instance |
| `POST` | `/sop/:name/:id/cancel` | Cancel an instance |
| `GET` | `/sop/instances` | List all instances (admin) |
| `POST` | `/sop/webhooks/:callback_id` | Inbound webhook callback (unauthenticated) |
| `POST` | `/sop/triggers/:process_name` | Third-party webhook triggers (HMAC-authenticated) |

---

## Discovery

### `GET /sop/`

Returns every active process, one row per `name` (latest version). Use this to let an agent discover what processes exist before reading any schemas.

**Request**

```bash
curl http://localhost:3000/sop/
```

**Response** — `200 OK`

```json
{
  "processes": [
    {
      "name": "customer-onboarding",
      "version": "1.0",
      "description": "Onboard a new business customer for cross-border banking",
      "tags": ["banking", "onboarding", "compliance", "kyb"],
      "inputs_summary":  "company_name (string, required), contact_email (string, required), country (enum: US|MX, required), source_channel (enum: website|linkedin|email|referral|cold-outbound), deal_id (string)",
      "outputs_summary": "account_id (string), member_id (string), status (enum: approved|rejected), rejection_reason (string)",
      "sla": "72h",
      "schema_url": "/sop/customer-onboarding/schema"
    },
    {
      "name": "lead-qualification",
      "version": "1.0",
      "description": "Qualify an inbound lead and score their fit",
      "tags": ["growth", "sales", "qualification"],
      "inputs_summary":  "lead_name (string, required), lead_email (string, required), source (enum: website|linkedin|referral, required)",
      "outputs_summary": "score (number), qualified (boolean)",
      "sla": null,
      "schema_url": "/sop/lead-qualification/schema"
    }
  ]
}
```

The `inputs_summary` / `outputs_summary` fields are human-readable strings meant for an agent's prompt or an admin list. For full field types (including `required_if`, enum values, object schemas) fetch the schema.

---

### `GET /sop/:name/schema`

Returns the full, YAML-derived definition for a process. This is the `.sop.yaml` file content re-rendered as JSON. Agents consume this to understand exactly what inputs to send and what outputs to expect.

**Request**

```bash
curl http://localhost:3000/sop/customer-onboarding/schema
```

**Query parameters**

| Param | Type | Default | Meaning |
|---|---|---|---|
| `version` | string | latest | Pin to a specific version (e.g. `1.0`) |

**Response** — `200 OK`

The response is the raw definition. Top level has `opensop` (format version) and `process` (the definition body):

```json
{
  "opensop": "0.1",
  "process": {
    "name": "lead-qualification",
    "version": "1.0",
    "description": "Qualify an inbound lead and score their fit",
    "owner": "growth-team",
    "trigger": { "type": "api" },
    "inputs": [
      { "name": "lead_name",  "type": "string", "required": true },
      { "name": "lead_email", "type": "string", "format": "email", "required": true },
      { "name": "source",     "type": "enum",   "values": ["website", "linkedin", "referral"], "required": true }
    ],
    "outputs": [
      { "name": "score",     "type": "number",  "from": "steps.score-lead.outputs.score" },
      { "name": "qualified", "type": "boolean", "from": "steps.score-lead.outputs.qualified" }
    ],
    "steps": [
      { "id": "collect-context", "type": "form",         "...": "..." },
      { "id": "score-lead",      "type": "automated",    "...": "..." },
      { "id": "notify-team",     "type": "notification", "...": "..." }
    ],
    "tags": ["growth", "sales", "qualification"]
  }
}
```

**Errors**

| Status | Body | When |
|---|---|---|
| `404` | `{"error":"not_found","message":"process \"x\" not found"}` | No active process by that name (or no matching version) |

---

## Execution

### `POST /sop/:name/start`

Starts a new instance. The engine validates `inputs` against the process's declared input schema, then advances through any auto-executing prefix (e.g. `automated` steps before the first `form`). The response is the instance state *after* that initial advance, so a `form` step typically shows up in `sub_state=waiting_for_input` on first response.

**Request**

```bash
curl -X POST http://localhost:3000/sop/lead-qualification/start \
  -H "Content-Type: application/json" \
  -H "X-SOP-Token: $OPENSOP_API_TOKEN" \
  -d '{
    "inputs": {
      "lead_name":  "Ana García",
      "lead_email": "ana@example.com",
      "source":     "website"
    },
    "metadata": {
      "source_system": "crm",
      "external_id":   "lead_8821"
    }
  }'
```

**Body**

| Field | Type | Required | Meaning |
|---|---|---|---|
| `inputs` | object | yes | Values for every required process input. Keys must match `process.inputs[*].name`. |
| `metadata` | object | no | Free-form key/value for your own tracking. The engine adds `actor` automatically. |

**Response** — `201 Created`

```json
{
  "id": "fea4a13c-227d-40e6-8713-4208b4ee983b",
  "process": { "name": "lead-qualification", "version": "1.0" },
  "state": "running",
  "inputs":  { "lead_name": "Ana García", "lead_email": "ana@example.com", "source": "website" },
  "outputs": {},
  "metadata": { "source_system": "crm", "external_id": "lead_8821", "actor": "agent" },
  "started_at":   "2026-04-21T13:25:45Z",
  "completed_at": null,
  "error": null,
  "links": {
    "self":   "/sop/lead-qualification/fea4a13c-...",
    "steps":  "/sop/lead-qualification/fea4a13c-.../steps",
    "cancel": "/sop/lead-qualification/fea4a13c-.../cancel"
  },
  "steps": [
    {
      "id": "eb7c0072-...",
      "step_id": "collect-context",
      "name": "Collect lead context",
      "type": "form",
      "state": "active",
      "sub_state": "waiting_for_input",
      "inputs":  { "lead_name": "Ana García" },
      "outputs": {},
      "decided_by": null,
      "confidence": null,
      "position": 1,
      "started_at":   "2026-04-21T13:25:45Z",
      "completed_at": null,
      "error": null,
      "links": { "submit": "/sop/lead-qualification/fea4a13c-.../steps/collect-context/submit" }
    },
    { "step_id": "score-lead",  "type": "automated",    "state": "pending", "...": "..." },
    { "step_id": "notify-team", "type": "notification", "state": "pending", "...": "..." }
  ]
}
```

The top-level `state` progresses through: `pending` → `running` → `completed` | `failed` | `cancelled`.

Each step has `state` (`pending`, `active`, `completed`, `failed`, `skipped`) plus an optional `sub_state` describing *why* an active step is waiting (`waiting_for_input`, `waiting_for_callback`, `waiting_for_approval`, `escalated`, `waiting_for_subprocess`).

**Errors**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | No active process by that name |
| `422` | `invalid_inputs` | Required input missing, type mismatch, enum value not allowed, etc. |
| `422` | `unknown_step_type` | Process YAML references a step type the engine doesn't implement |

---

### `GET /sop/:name/:id`

Fetch the full current state of an instance. Always returns the most recent state plus every step. Poll this endpoint while waiting on long-running work.

**Request**

```bash
curl http://localhost:3000/sop/lead-qualification/fea4a13c-227d-40e6-8713-4208b4ee983b \
  -H "X-SOP-Token: $OPENSOP_API_TOKEN"
```

**Response** — `200 OK`

Same shape as the `POST .../start` response (see above).

**Errors**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | No instance with that `id` under that process name |

---

### `GET /sop/:name/:id/steps`

Compact view — just the steps, no instance envelope. Useful when you only need step state.

**Request**

```bash
curl http://localhost:3000/sop/lead-qualification/fea4a13c-.../steps \
  -H "X-SOP-Token: $OPENSOP_API_TOKEN"
```

**Response** — `200 OK`

```json
{
  "steps": [
    { "step_id": "collect-context", "type": "form", "state": "completed", "outputs": { "budget": 12000, "timeline": "immediate" }, "...": "..." },
    { "step_id": "score-lead",      "type": "automated", "state": "completed", "outputs": { "score": 84, "qualified": true }, "...": "..." },
    { "step_id": "notify-team",     "type": "notification", "state": "completed", "...": "..." }
  ]
}
```

---

### `POST /sop/:name/:id/steps/:step_id/submit`

Submit outputs for an active step. Used for:

- **`form` steps** — a human or agent supplies the fields (`sub_state=waiting_for_input`)
- **`judgment` steps** — a human or agent supplies the decision (`sub_state=escalated`)
- **`approval` steps** — a human approves or rejects (`sub_state=waiting_for_approval`)
- **Retrying `failed` steps** — supply corrected outputs after a failure

For `automated`, `webhook`, `notification`, `wait`, and `subprocess` steps, the engine submits internally — you don't call this endpoint for them. (Webhook callbacks arrive via `POST /sop/webhooks/:callback_id`.)

**Request**

```bash
curl -X POST \
  http://localhost:3000/sop/lead-qualification/fea4a13c-.../steps/collect-context/submit \
  -H "Content-Type: application/json" \
  -H "X-SOP-Token: $OPENSOP_API_TOKEN" \
  -d '{
    "outputs": {
      "budget":   12000,
      "timeline": "immediate",
      "notes":    "Has active RFP, wants to decide this quarter"
    },
    "decided_by": "agent:sales-copilot",
    "confidence": 0.93
  }'
```

**Body**

| Field | Type | Required | Meaning |
|---|---|---|---|
| `outputs` | object | yes | Values matching the step's declared outputs. Keys must match `step.outputs[*].name`. |
| `decided_by` | string | no | Who made the decision. Defaults to the token's actor (`"agent"` or `"system"`). Free-form but conventionally `"human:<id>"`, `"agent:<id>"`, or `"webhook"`. |
| `confidence` | number | no | 0.0–1.0 confidence score. For `judgment` steps, below the process's `confidence_threshold` may trigger escalation. |

**Response** — `200 OK`

```json
{
  "step": {
    "step_id": "collect-context",
    "state": "completed",
    "outputs": { "budget": 12000, "timeline": "immediate", "notes": "..." },
    "decided_by": "agent:sales-copilot",
    "confidence": 0.93,
    "completed_at": "2026-04-21T13:26:12Z",
    "...": "..."
  },
  "instance": {
    "state": "completed",
    "outputs": { "score": 84, "qualified": true },
    "completed_at": "2026-04-21T13:26:13Z",
    "steps": [ "...all steps, including ones that auto-advanced after submission..." ]
  }
}
```

The engine may advance through several steps after a single submission (all the `automated` / `notification` / `wait` steps between this one and the next human-gated step). The response always reflects the state after all cascading advances complete.

**Errors**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | Instance or step not found |
| `422` | `step_not_submittable` | Step is not in an active or failed state — e.g. it's already completed, pending, or skipped |
| `422` | `invalid_inputs` | `outputs` don't match declared schema (missing required, wrong type, etc.) |
| `422` | `invalid_transition` | Step could not be advanced (rare; usually a race condition) |

---

### `POST /sop/:name/:id/cancel`

Cancels an instance. Sets the instance `state` to `cancelled`, records the reason, and writes a `Sop::Event` of type `"instance.cancelled"`. All active steps are marked `skipped`. No cascading actions are rolled back — whatever already happened (account created, email sent) stays happened.

**Request**

```bash
curl -X POST http://localhost:3000/sop/lead-qualification/fea4a13c-.../cancel \
  -H "Content-Type: application/json" \
  -H "X-SOP-Token: $OPENSOP_API_TOKEN" \
  -d '{ "reason": "lead unresponsive after 10 days" }'
```

**Body**

| Field | Type | Required | Meaning |
|---|---|---|---|
| `reason` | string | no | Free-form. Stored on the instance and in the cancellation event. |

**Response** — `200 OK`

Same shape as `GET /sop/:name/:id`, with `state: "cancelled"` and `completed_at` populated.

**Errors**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | Instance not found |
| `422` | `invalid_transition` | Instance is already in a terminal state (completed/failed/cancelled) |

---

## Admin

### `GET /sop/instances`

List instances across all processes. Intended for ops dashboards and monitoring.

**Request**

```bash
curl "http://localhost:3000/sop/instances?state=running&limit=50" \
  -H "X-SOP-Token: $OPENSOP_API_TOKEN"
```

**Query parameters**

| Param | Type | Default | Meaning |
|---|---|---|---|
| `state` | string | — | Filter by instance state (`running`, `completed`, `failed`, `cancelled`) |
| `process` | string | — | Filter by process name |
| `limit` | int | 50 | Max rows. Clamped to 200. |
| `offset` | int | 0 | Pagination offset |

**Response** — `200 OK`

```json
{
  "instances": [
    {
      "id": "fea4a13c-...",
      "process": { "name": "lead-qualification", "version": "1.0" },
      "state": "running",
      "inputs":  { "...": "..." },
      "outputs": {},
      "metadata": { "actor": "agent" },
      "started_at": "2026-04-21T13:25:45Z",
      "completed_at": null,
      "error": null,
      "links": { "...": "..." }
      // NOTE: `steps` is omitted from the list view. Fetch the instance
      // individually if you need them.
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}
```

---

## Webhook callbacks

### `POST /sop/webhooks/:callback_id`

Inbound webhook receiver. A process's `webhook` step creates a `Sop::Callback` with a unique `callback_id`. The third-party provider POSTs here when it has an answer. The engine records the payload, merges it into the step's outputs, and advances the instance.

**This endpoint does not require `X-SOP-Token`** — third parties wouldn't know the token. If you need callback-level auth, encode a secret in the `callback_id` itself (it's a random UUID, so it's unguessable) or add HMAC verification at the application layer.

**Request**

```bash
curl -X POST http://localhost:3000/sop/webhooks/a8a3d2f9-... \
  -H "Content-Type: application/json" \
  -d '{
    "entity_id":         "mnx_8821",
    "compliance_status": "approved"
  }'
```

The keys in the JSON body should match the declared `outputs:` of the webhook step that registered this callback.

**Response** — `200 OK`

```json
{ "status": "received" }
```

**Errors**

| Status | `error` | When |
|---|---|---|
| `404` | `not_found` | No pending callback at that path (wrong ID, already received, or expired) |
| `409` | `callback_already_resolved` | This callback was already `received` or marked `expired` |
| `422` | `invalid_callback_payload` | Payload didn't satisfy the step's declared outputs. Raw payload is still persisted on the `Sop::Callback` row — no data loss. |

---

## Third-party webhook triggers

### `POST /sop/triggers/:process_name`

Lets a SaaS provider (Cal.com, Stripe, Typeform, HubSpot, DocuSign, etc.) start an OpenSOP process instance directly from its own webhook delivery — no host-side adapter required. Auth is HMAC signature verification against the raw request body, configured per-process in the YAML.

**This endpoint does not require `X-SOP-Token`.** The declared HMAC scheme is the authentication.

**Setup:**

1. Declare a webhook trigger in the process YAML (see [`SPEC.md`](../SPEC.md) §2.2).
2. Set the secret env var named in `trigger.auth.secret_env`.
3. Configure the provider to POST to `https://<your-opensop>/sop/triggers/<process-name>` and paste the same secret into the provider's signature-secret field.

**Request** (from the provider's perspective)

```
POST /sop/triggers/consult-request
Content-Type: application/json
X-Cal-Signature-256: sha256=ab12ef...<hmac hex of body>

{
  "type": "BOOKING_CREATED",
  "uid": "bkg_abc123",
  "startTime": "2026-05-01T15:00:00Z",
  "attendees": [
    { "email": "ana@example.com", "name": "Ana García" }
  ]
}
```

**Responses**

| Status | Body | Meaning |
|---|---|---|
| 200 | `{"status":"started","instance_id":"..."}` | Instance created. |
| 200 | `{"status":"accepted","action":"logged","reason":"..."}` | Payload didn't satisfy the mapping or input validation failed. Logged; provider should NOT retry. |
| 400 | `{"error":"invalid_payload","message":"..."}` | Body is not valid JSON. |
| 401 | `{"error":"invalid_signature","message":"..."}` | HMAC mismatch or signature header missing. |
| 404 | `{"error":"not_found","message":"..."}` | Process name doesn't exist. |
| 404 | `{"error":"trigger_not_configured","message":"..."}` | Process has no webhook trigger declared. |
| 500 | `{"error":"trigger_misconfigured","message":"..."}` | Server secret env var unset. Check deployment config. |

**Log tags for ops:**

- `[Sop::TriggersController] MAPPING_REJECTED process=X reason=Y payload=...` — payload shape didn't match mapping
- `[Sop::TriggersController] INSTANCE_REJECTED process=X reason=Y inputs=...` — mapping produced inputs, but instance validation rejected them

Grep these to debug provider integrations that aren't creating instances.

**No replay protection in v0.2.** If the provider retries (after a transient 5xx), you'll get a second instance. Both carry the inbound payload in metadata — downstream `automated` steps can dedupe by provider-specific ID (`booking_id`, `event_id`, etc.). Proper dedupe (`sop_webhook_events` table) tracked in GAPS.md for a later version.

---

## Error response shape

All error responses share a common envelope:

```json
{
  "error":   "short_machine_code",
  "message": "human-readable description"
}
```

Possible `error` values:

| Value | HTTP | Source |
|---|---|---|
| `unauthorized` | 401 | Missing/invalid `X-SOP-Token` in strict mode |
| `not_found` | 404 | Process or instance not found |
| `callback_already_resolved` | 409 | Webhook callback already received or expired |
| `invalid_inputs` | 422 | Process inputs or step outputs don't match schema |
| `invalid_transition` | 422 | Cannot advance/cancel from current state |
| `invalid_definition` | 422 | Malformed process definition (shouldn't happen at runtime) |
| `unresolved_reference` | 422 | A `from:` reference couldn't be resolved (shouldn't happen; indicates a YAML bug) |
| `unknown_step_type` | 422 | Process references a step type the engine doesn't implement |
| `step_not_submittable` | 422 | Tried to submit to a step that isn't in `active` or `failed` state |
| `invalid_callback_payload` | 422 | Webhook payload doesn't match declared outputs |

---

## Instance and step state machines

### Instance states

```
pending ──▶ running ──▶ completed
              │
              ├──▶ failed      (a step raised a fatal error)
              └──▶ cancelled   (POST /cancel)
```

`pending` is transient — it only exists for the microseconds before `start` triggers the initial advance. By the time a response comes back, the instance is already `running` (or further along).

### Step states

```
pending ──▶ active ──▶ completed
              │
              ├──▶ failed      (step raised; retryable via submit)
              └──▶ skipped     (condition: evaluated to false, or instance cancelled)
```

When a step is `active`, its `sub_state` tells you *why* it's still running:

| `sub_state` | Meaning |
|---|---|
| `waiting_for_input` | `form` step awaiting `POST .../submit` |
| `escalated` | `judgment` step awaiting submission (either LLM low-confidence or no judgment router wired) |
| `waiting_for_approval` | `approval` step awaiting a human decision |
| `waiting_for_callback` | `webhook` step awaiting `POST /sop/webhooks/:callback_id` |
| `waiting_for_subprocess` | `subprocess` step awaiting child instance completion |
| `waiting_for_timer` | `wait` step with a `seconds:` or `until:` condition |

---

## What's stubbed (v0.2)

For transparency, the following are partially implemented — the endpoints work but the underlying step type is a stub:

- **`judgment`** — pauses at `escalated`; no LLM integration yet. Submit via the step endpoint.
- **`approval`** — pauses at `waiting_for_approval`. Submit via the step endpoint.
- **`subprocess`** — pauses at `waiting_for_subprocess`. No child instance is created yet.
- **`wait`** — returns immediately for `seconds:` durations (no actual sleep). Real timer support requires `solid_queue`.
- **`poll` response mode on webhooks** — not yet implemented. Use `sync` or `callback`.
- **Replay protection for trigger endpoint** — a duplicate provider delivery will create a second instance. Dedupe downstream in an `automated` step by provider-specific ID (e.g., Cal.com's `uid`, Stripe's `event.id`).
- **`retry.max` / `retry.backoff`** — parsed on automated steps but auto-retry not implemented. Use step re-submission instead.

Fully implemented: `form`, `automated`, `webhook` (sync + callback modes, with env/input/callback_url interpolation), `notification` (stub send — returns `notified: true`).

See [`SPEC.md`](../SPEC.md) §8 and [`HANDOFF.md`](../HANDOFF.md) for the full v0.2 roadmap.
