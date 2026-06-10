# OpenSOP — Specification v0.6

**Date:** 2026-06-10
**Authors:** Chosen9115 + Claude (digital twin)
**Status:** Current — authoritative cross-repo contract
**Domain:** opensop.ai
**License:** Apache 2.0

> This document supersedes SPEC.md v0.1 and SPEC-v0.2.md.
> All content from those files has been folded in and reconciled against the
> running code. Where the prior documents said one thing and the code does
> another, the code governs — discrepancies are noted inline.

---

## 1. What OpenSOP Is

OpenSOP is an open standard and runtime for defining, storing, executing, and
exposing business processes as APIs. Define a process in YAML (or JSON), get a
REST API. Humans and agents call the same endpoints.

**Core beliefs:**

1. **The process definition IS the API contract.** Define a process, get an API.
2. **Processes are company IP.** Self-hostable; never leaves your infrastructure unless you choose.
3. **Every step has a type.** The platform knows which steps need a human, which need an LLM, and which just run.
4. **Agents are first-class consumers.** The discovery endpoint lets any agent understand what a company does.
5. **LLM creativity belongs inside deterministic gates.** Agent steps have typed inputs, explicit outputs, validation, receipts, and checks before side effects.

---

## 2. The Process Definition Format

### 2.1 The one logical model — two serializations

A process definition is a single logical object. It can be serialized two ways,
and both are canonical. The parser accepts either form.

**Wrapped envelope (standard — for server registration and YAML files):**

```yaml
opensop: "0.6"

process:
  name: lead-qualification
  version: "1.0"
  description: "Qualify an inbound lead and assign to a rep"
  inputs:
    - name: lead_name
      type: string
      required: true
    - name: lead_email
      type: string
      format: email
      required: true
    - name: source
      type: enum
      values: [website, linkedin, email, referral]
  outputs:
    - name: qualified
      type: boolean
    - name: assigned_to
      type: string
  steps:
    - id: score-lead
      type: llm
      model: claude-sonnet-4-6
      prompt: "Score this lead 1-10: name={{ lead_name }}, source={{ source }}"
      expected_output_schema:
        score: number
        rationale: string
      outputs:
        - { name: score, type: number }
        - { name: rationale, type: string }
    - id: assign
      type: form
      inputs:
        - name: score
          from: steps.score-lead.outputs.score
      outputs:
        - name: assigned_to
          type: string
```

**Flat local shorthand (`.sop.json` — for local execution without a server):**

```json
{
  "name": "greet",
  "inputs": { "name": "World" },
  "steps": [
    { "id": "say-hello", "type": "shell", "run": "echo Hello $( jq -r .name <<<"$OSL_CONTEXT" )" }
  ]
}
```

The flat form omits the `opensop` version key and the `process:` wrapper.
The CLI (`bin/opensop`) accepts both; the server runtime requires the wrapped
form for registration.

**Spec version policy:**

| Value | Accepted by |
|---|---|
| `"0.1"` | Server parser, CLI `schema validate` |
| `"0.2"` | Server parser, CLI `schema validate` |
| `"0.6"` | Server parser, CLI `schema validate` |

New process files should declare `opensop: "0.6"`. Files declared at `"0.1"` or
`"0.2"` continue to parse and run unchanged — this spec is additive.

---

### 2.2 Process object fields

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Process identifier. Slug-style, e.g. `customer-onboarding`. |
| `version` | Yes | Semver string, e.g. `"1.0"`. |
| `description` | Yes | Human-readable purpose. |
| `inputs` | No | Array of Field objects (see §2.4). |
| `outputs` | No | Array of Field objects declared at process level. |
| `steps` | Yes | Ordered array of Step objects (see §2.5). |
| `trigger` | No | How the process starts (see §2.3). |
| `owner` | No | Team or user label. |
| `tags` | No | Array of strings for discovery/filtering. |
| `sla` | No | `{target: "72h", warning: "48h"}`. |
| `on_error` | No | `{notify: {channel, target}, retry_policy}`. |
| `access` | No | `{start: [], view: [], advance: [], admin: []}`. |

---

### 2.3 Triggers

Declares how a new instance of this process is started.

**API trigger (default — any authenticated POST starts a new instance):**

```yaml
trigger:
  type: api
```

**Webhook trigger (third-party SaaS → OpenSOP):**

```yaml
trigger:
  type: webhook
  auth:
    scheme: hmac-sha256          # only supported scheme
    secret_env: CAL_WEBHOOK_SECRET
    header: X-Cal-Signature-256
    encoding: hex                # hex | base64
    prefix: ""                   # optional; stripped before comparing
  input_mapping:
    attendee_email: "${payload.attendees.0.email}"
    attendee_name:  "${payload.attendees.0.name}"
    meeting_time:   "${payload.startTime}"
    source:         "cal.com"    # literal value
```

Endpoint: `POST /sop/triggers/<process-name>`.
The declared HMAC scheme authenticates the request; `X-SOP-Token` is NOT
required on trigger endpoints.

| Condition | Status | Body |
|---|---|---|
| Instance started | 200 | `{"status":"started","instance_id":"..."}` |
| Mapping failed or input validation failed | 200 | `{"status":"accepted","action":"logged","reason":"..."}` |
| Malformed JSON body | 400 | `{"error":"invalid_payload",...}` |
| HMAC mismatch or missing signature header | 401 | `{"error":"invalid_signature",...}` |
| Process not found | 404 | `{"error":"not_found",...}` |
| No webhook trigger configured | 404 | `{"error":"trigger_not_configured",...}` |
| Secret env var unset | 500 | `{"error":"trigger_misconfigured",...}` |

The 200-with-logged-reason is deliberate: providers like Cal.com send multiple
event types to one endpoint. When the payload does not match the mapping, the
engine logs it but returns 200 so the provider does not retry.

**Supported HMAC providers:**

| Provider | Signature header | Encoding | Prefix |
|---|---|---|---|
| Cal.com | `X-Cal-Signature-256` | hex | — |
| Stripe | `Stripe-Signature` | hex | `v1=` |
| HubSpot | `X-HubSpot-Signature-v3` | hex | — |
| Typeform | `Typeform-Signature` | base64 | `sha256=` |
| GitHub | `X-Hub-Signature-256` | hex | `sha256=` |

> Stripe's timestamp-scoped HMAC variant is not yet supported. Twilio uses HMAC-SHA1, also not implemented.

**Interval trigger (parser-only — scheduler not yet wired):**

```yaml
trigger:
  type: interval
  interval: 30m      # 5s minimum; s / m / h / d suffixes
```

The parser stores `interval_seconds` on the trigger record. Runtime scheduling is
roadmapped. The parser rejects cron (`schedule:`) and time-of-day (`at: [...]`)
forms today.

**Manual trigger:**

```yaml
trigger:
  type: manual
```

Equivalent to API trigger but signals human intent in the definition.

---

### 2.4 Field types

| Type | Description | Example value |
|---|---|---|
| `string` | Text | `"Acme Corp"` |
| `number` | Integer or decimal | `42`, `3.14` |
| `boolean` | True/false | `true` |
| `enum` | One of a declared set | `"approved"` with `values: [approved, rejected]` |
| `date` | ISO 8601 date | `"2026-06-10"` |
| `datetime` | ISO 8601 datetime | `"2026-06-10T09:00:00Z"` |
| `file` | File reference (path or URL) | uploaded PDF |
| `file[]` | Array of files | multiple documents |
| `string[]` | Array of strings | `["item-a", "item-b"]` |
| `object` | Nested structure with schema | `{ legal_name: "Acme", rfc: "ABC123" }` |
| `reference` | ID pointing to another record | `deal_id`, `member_id` |
| `currency` | Amount + currency code | `{ amount: 1500.00, currency: "USD" }` |

**Collection outputs (v0.2):**

Any output field may declare `collection: true` with an `item_schema`:

```yaml
outputs:
  - name: classifications
    type: object
    collection: true
    item_schema:
      label: string
      score: number
```

Collection reference syntax:

| Syntax | Meaning |
|---|---|
| `steps.classify.outputs.classifications` | The whole array |
| `steps.classify.outputs.classifications[*]` | All items (used by `for_each:`) |
| `steps.classify.outputs.classifications[0]` | Indexed access |
| `steps.classify.outputs.classifications[*].label` | Pluck a field across all items |

---

### 2.5 Reference syntax

Inside `from:`, `condition:`, `exit_when:`, and `required_if:`:

| Prefix | Source |
|---|---|
| `process.inputs.<name>` | Process-level input provided at start |
| `steps.<step-id>.outputs.<name>` | Output of a completed step |
| `env.<NAME>` | Environment variable |
| `instance.<field>` | Instance metadata (`started_at`, etc.) |
| `loop.<as-name>` | Loop iteration variable (body steps only) |
| `instance.shared_state.<key>` | Inter-instance shared state (roadmapped — parser rejects today) |

---

### 2.6 Expressions and conditions

Simple boolean expressions used in `condition:`, `exit_when:`, and `required_if:`:

```yaml
condition: "steps.review.outputs.decision == 'approve'"
condition: "steps.verify.outputs.score >= 0.8"
condition: "steps.verify.outputs.result != 'invalid'"
required_if: "status == 'rejected'"
exit_when: "outputs.score < 0.4"
```

Evaluated by `Opensop::ConditionEvaluator` (server) or jq (CLI local engine).
No `eval`, no arbitrary code — the evaluator handles `==`, `!=`, `>=`, `<=`, `>`, `<` against literal scalars.

---

### 2.7 Process versioning

```yaml
process:
  name: customer-onboarding
  version: "2.0"
  replaces: "1.0"
```

Running instances are pinned to the version they started on. `replaces` marks
the prior version as deprecated.

---

## 3. Step Types — Complete Reference

### 3.1 Capability matrix

For each step type, the table shows its status in each profile. "Working" means
the step executes end-to-end in production. "Stubbed" means the executor class
exists and the instance transitions to a terminal/waiting state, but the core
business logic is not implemented. "Not in profile" means the step type is not
dispatched or recognized in that profile.

| Step type | Server profile | Local profile (CLI v0.6) | Primary waiting reason |
|---|---|---|---|
| `automated` | Working | Working | — (synchronous) |
| `shell` | Not in profile | Working (local-only extension) | — (synchronous) |
| `noop` | Not in profile | Working (local-only extension) | — (synchronous) |
| `form` | Working | Working | `waiting_for_input` |
| `approval` | Working | Working (pause) | `waiting_for_approval` |
| `llm` | Working | Not in profile (falls to unsupported) | — |
| `judgment` | Stubbed — escalates to human | Not in profile | `escalated` |
| `webhook` | Working (sync + callback); poll stubbed | Not in profile | `waiting_for_callback` |
| `subprocess` | Stubbed — pauses instance | Not in profile | `waiting_for_callback` |
| `notification` | Stubbed — returns `{notified: true}` immediately | Not in profile | — |
| `wait` | Partial — `wait.seconds` returns immediately; `wait.until` pauses | Not in profile | `waiting_for_callback` |
| `loop` | Working (`for_each` / `repeat_until` / `while`) | Not in profile | — |

> **"Not in profile" in the local engine** means the step falls to the `*` arm of
> the dispatch case in `_local_step_loop`, which sets `rc=2` and fails the step
> with "unsupported step type for local execution: \<type\>". The run transitions
> to `failed` unless `continue_on_error: true` is set.

### 3.2 Step fields common to all types

| Field | Required | Description |
|---|---|---|
| `id` | Yes | Step identifier. Pattern: `[a-z0-9][a-z0-9_-]*`. |
| `name` | No | Human-readable label. |
| `type` | Yes | One of the 10 types listed in §3.1. |
| `inputs` | No | Array of field references resolved at runtime. |
| `outputs` | No | Declared output fields (name, type, optional schema). |
| `condition` | No | Boolean expression; step is skipped when false. |
| `exit_when` | No | Boolean expression; if true after step completes, process terminates immediately with `exit_outputs`. |
| `exit_outputs` | No | Literal key-value map merged into process outputs on early exit. |
| `continue_on_error` | No | `true` = run continues even if this step fails. |
| `executor` | No | Audit metadata only. See §6. |

---

### 3.3 `automated` — run a script

Executes a script (any language, detected by extension or shebang). The engine
passes resolved inputs as JSON via stdin; the script returns JSON via stdout.

```yaml
- id: verify-documents
  type: automated
  run: steps/verify-documents.py
  validation: strict            # lenient (default) | strict
  retry:
    max: 3
    backoff: exponential
  timeout: 60                   # seconds; default 60 (server)
  inputs:
    - name: business_record
      from: steps.collect-info.outputs.business_record
  outputs:
    - name: verification_result
      type: enum
      values: [complete, incomplete, invalid]
```

**Server execution protocol:**
1. Resolve inputs from previous steps.
2. JSON-encode inputs, pipe to script via stdin (`OSL_CONTEXT` env also available).
3. Read JSON from stdout as outputs.
4. Validate against `outputs:` schema; on failure: retry per `retry:`, then fail step.

**`validation:` modes (v0.2):**

| Mode | Behavior |
|---|---|
| `lenient` (default) | Missing declared output keys silently become `null` downstream. |
| `strict` | Any declared output key absent from stdout JSON fails the step immediately with a listing of missing keys. Extra keys are permitted. Type validation is not yet enforced; presence only. |

**Local engine (CLI):** resolves the script path relative to the process file's
directory, then the parent directory. Passes context JSON via `OSL_CONTEXT` env
and stdin. Non-JSON stdout is wrapped as `{stdout: "..."}`.

---

### 3.4 `shell` — local-only inline script

Local extension not present in the server runtime.

```json
{ "id": "greet", "type": "shell", "run": "echo Hello, world" }
```

Runs `bash -c <run>` with context JSON on stdin. On the server, `shell` is not a
recognized type and the instance will fail.

---

### 3.5 `noop` — no-op placeholder

Local extension not present in the server runtime. Returns `{}` immediately. Useful
as a placeholder step during development.

```json
{ "id": "placeholder", "type": "noop" }
```

---

### 3.6 `form` — collect data from a human or agent

```yaml
- id: collect-info
  type: form
  inputs:
    - name: company_name
      from: process.inputs.company_name
  outputs:
    - name: business_record
      type: object
      schema:
        legal_name: string
        rfc: string
  timeout: 7d
  on_timeout: notify-and-wait
```

**Semantics:** the executor returns `{waiting: "waiting_for_input"}` immediately.
The instance pauses. Submission via
`POST /sop/<name>/<id>/steps/<step_id>/submit` (server) or
`opensop submit <run_id> <step-id> --local --output k=v` (local) advances the step.

---

### 3.7 `approval` — binary gate

```yaml
- id: manager-approval
  type: approval
  approvers: [manager-role]
  timeout: 48h
  outputs:
    - name: approved
      type: boolean
    - name: notes
      type: string
```

**Semantics:** executor returns `{waiting: "waiting_for_approval"}`. Advances on
`submit`. In the local engine, the step pauses with reason `waiting_for_approval`.

---

### 3.8 `llm` — first-class LLM call (v0.2)

```yaml
- id: classify-intent
  type: llm
  model: claude-sonnet-4-6
  prompt_file: prompts/classify.md    # OR inline prompt: "..."
  tools: [Read, Grep]                 # optional; passed to the provider
  retry_on_incomplete: true           # default true
  max_retries: 2                      # default 2
  expected_output_schema:
    intent: enum[question, task, complaint]
    confidence: number
    rationale: string
  inputs:
    - name: message
      from: process.inputs.user_message
  outputs:
    - { name: intent, type: enum, values: [question, task, complaint] }
    - { name: confidence, type: number }
    - { name: rationale, type: string }
  timeout: 2m
```

**Server semantics:**
1. Render `prompt` / `prompt_file` with `{{ var }}` substitution over resolved inputs.
2. Call configured provider (Anthropic by default for `claude-*` models).
3. Validate response against `expected_output_schema`.
4. On schema failure: retry with a corrective preamble up to `max_retries`; then fail.

Events: `step.llm.requested`, `step.llm.responded`, `step.llm.retry`.

**`expected_output_schema` mini-grammar:** `string | number | boolean | enum[a,b,c] | object (nested) | array[<type>]`.

**Local engine:** not dispatched. Falls to unsupported arm, fails with `rc=2`.

---

### 3.9 `judgment` — LLM or human decision

```yaml
- id: review-application
  type: judgment
  judgment:
    allow_agent: true
    require_human_review: false
    confidence_threshold: 0.9
    escalation: manual
  inputs:
    - name: business_record
      from: steps.collect-info.outputs.business_record
  outputs:
    - name: decision
      type: enum
      values: [approve, reject, request-more-info]
    - name: rejection_reason
      type: string
      required_if: "decision == 'reject'"
```

**Server status — stubbed.** The `Judgment` executor does not call an LLM. It
emits a `step.escalated` event with `reason: "llm_router_not_implemented"` and
returns `{waiting: "escalated"}`. The instance waits for a human to submit via
the API.

**Local engine:** not dispatched.

---

### 3.10 `webhook` — outbound HTTP call

```yaml
- id: submit-to-compliance
  type: webhook
  condition: "steps.review.outputs.decision == 'approve'"
  webhook:
    method: POST
    url: "${env.COMPLIANCE_URL}/entities"
    headers:
      Authorization: "Bearer ${env.COMPLIANCE_API_KEY}"
    body_template: steps/compliance-payload.json   # optional; else inputs used
    response_mode: callback                         # REQUIRED — sync | callback | poll
    poll_timeout: 7d
  inputs:
    - name: business_record
      from: steps.collect-info.outputs.business_record
  outputs:
    - name: entity_id
      type: string
    - name: compliance_status
      type: enum
      values: [pending, approved, rejected]
```

**`webhook` block fields:**

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Outbound request URL. Supports `${env.X}`, `${inputs.X}`, `${callback_url}`. |
| `method` | Yes | HTTP verb: `GET`, `POST`, `PUT`, `PATCH`, or `DELETE`. |
| `response_mode` | **Yes** | How the step handles the response. Must be one of `sync`, `callback`, or `poll`. No default — omitting this field is a parse error. |
| `headers` | No | Key/value map of request headers. Values support template interpolation. |
| `body_template` | No | Path to a JSON body template under `processes/`. If omitted, step inputs are sent as JSON. |
| `poll_timeout` | No | Expiry for callback/poll waiting (e.g. `7d`, `2h`). |

**Response modes:**

| Mode | Server status | Semantics |
|---|---|---|
| `sync` | Working | Fire-and-return; HTTP response body is the step outputs. |
| `callback` | Working | Auto-generates callback URL (`/sop/webhooks/<uuid>`), injects as `${callback_url}`. Instance pauses until the third party POSTs to that URL. |
| `poll` | Stubbed | Not implemented; the executor raises `StepFailure`. |

**URL / header interpolation:** `${env.X}` resolves environment variables; `${inputs.X}` resolves step inputs; `${callback_url}` injects the generated callback path.

**Local engine:** not dispatched.

---

### 3.11 `subprocess` — start a child process

```yaml
- id: run-kyc
  type: subprocess
  process: kyc-verification
  inputs:
    - name: person_name
      from: steps.collect-info.outputs.owner_name
  outputs:
    - name: kyc_status
      type: enum
      values: [passed, failed, manual_review]
```

**Server status — stubbed.** The `Subprocess` executor emits
`step.subprocess_pending` and returns `{waiting: "waiting_for_callback"}`. No
child instance is started. The step must be advanced manually.

**Local engine:** not dispatched.

---

### 3.12 `notification` — fire-and-forget message

```yaml
- id: send-welcome
  type: notification
  channel: email
  to: "${steps.collect-info.outputs.contact_email}"
  template: templates/welcome.html
```

**Server status — stubbed.** The `Notification` executor returns
`{outputs: {notified: true, email_sent: true}}` immediately without sending
anything. The instance advances.

**Local engine:** not dispatched.

---

### 3.13 `wait` — pause until condition or timer

```yaml
- id: wait-for-compliance
  type: wait
  wait:
    seconds: 3600           # OR:
    until: "steps.check.outputs.ready == true"
```

**Server behavior:**
- `wait.seconds` present: returns `{outputs: {waited: true, seconds: N}}` immediately (does not actually sleep — synchronous stub).
- `wait.until` present: returns `{waiting: "waiting_for_callback"}` and pauses.

**Local engine:** not dispatched.

---

### 3.14 `loop` — iteration (v0.2)

```yaml
- id: process-each-lead
  type: loop
  loop:
    for_each: steps.fetch-leads.outputs.leads[*]   # OR repeat_until / while
    as: lead
    max_iterations: 100
    aggregate:
      results: concat
  body:
    - id: enrich
      type: llm
      inputs:
        - { name: lead, from: loop.lead }
      outputs:
        - { name: enriched, type: object }
  outputs:
    - { name: results, type: object, collection: true, item_schema: { name: string, score: number } }
```

**Variants:**

| Variant key | Termination |
|---|---|
| `for_each: <collection>` | Items exhausted |
| `repeat_until: "<expr>"` | Predicate true at end of iteration |
| `while: "<expr>"` | Predicate true at start of iteration |

`max_iterations` accepts a positive integer literal OR `{{ process.inputs.<name> }}`.
`aggregate` per output: `sum` (numbers), `concat` (arrays/strings), `last` (final iteration only).

**Server status:** Working.

**Local engine:** not dispatched.

---

### 3.15 `exit_when` — step-level early exit (v0.2)

A per-step field, not a step type. Applies to any step.

```yaml
- id: gate
  type: automated
  run: steps/gate.sh
  outputs:
    - { name: score, type: number }
  exit_when: "outputs.score < 0.4"
  exit_outputs:
    outcome: "rejected_low_score"
    reason: "Score below threshold"
```

If the predicate is true after step completion, the process terminates
immediately with `instance.exited_early` and the literal `exit_outputs`. Not
an error — `instance.state` becomes `"completed"`.

---

## 4. The Server Runtime

### 4.1 Components

| Component | Responsibility |
|---|---|
| **Definition Registry** (`Opensop::Registry`) | Loads `.sop.yaml` from `processes/`, upserts into `sop_processes`. `bin/rails opensop:load_processes` re-syncs. |
| **Instance Executor** (`Opensop::InstanceExecutor`) | Orchestrates an instance: resolves inputs, evaluates conditions, dispatches step executors, handles early exit. |
| **Step Executors** (`Opensop::StepExecutors::*`) | One class per step type. See §3. |
| **Condition Evaluator** (`Opensop::ConditionEvaluator`) | The only safe path for user-authored expressions. No `eval`, no `instance_eval`. |
| **Input Resolver** (`Opensop::InputResolver`) | Resolves `from:` references against instance state. |
| **LLM Provider** (`Opensop::LlmProviders::Anthropic`) | Calls Anthropic for `llm` steps. Provider resolved by model name prefix (`claude-*`). |
| **API Gateway** | Rails controllers under `/sop/*`. Auto-generated from process definitions. |

### 4.2 Server API surface

```
GET  /sop/                                  List processes
GET  /sop/:name/schema                      Process definition
POST /sop/:name/start                       Start an instance
GET  /sop/:name/:id                         Instance state + steps
GET  /sop/:name/:id/steps                   All step states
POST /sop/:name/:id/steps/:step_id/submit   Advance a waiting step
POST /sop/:name/:id/cancel                  Cancel an instance
GET  /sop/instances                         List all instances (paginated)
GET  /sop/metrics                           Process metrics
POST /sop/webhooks/:callback_id             Receive inbound webhook callbacks
POST /sop/triggers/:name                    Webhook-triggered process start
```

Auth: `X-SOP-Token: <api_key>`. Trigger endpoints authenticate via the declared
HMAC scheme instead; `X-SOP-Token` is not required there.

### 4.3 Server instance lifecycle

```
start() → RUNNING
           │
    ┌──────┼──────────────┐
    ▼      ▼              ▼
 STEP:  STEP:          STEP:
 active waiting        skipped
        │              (condition false)
        ▼
 submit_step()
        │
        ▼
 STEP: completed → next step
                 → early exit (exit_when true) → instance COMPLETED
                 │
                 ▼ (all steps done)
           instance COMPLETED | FAILED | CANCELLED
```

**Instance states:** `pending` → `running` → `completed` | `failed` | `cancelled`

**Step states:** `pending` → `active` → `completed` | `failed` | `skipped`

**Step sub-states (while active):** `running` | `waiting_for_input` | `waiting_for_approval` | `waiting_for_callback` | `escalated`

### 4.4 Server data model

```sql
CREATE TABLE sop_processes (
  id         UUID PRIMARY KEY,
  name       VARCHAR NOT NULL,
  version    VARCHAR NOT NULL,
  definition JSONB NOT NULL,        -- full parsed YAML
  owner      VARCHAR,
  tags       TEXT[],
  status     VARCHAR DEFAULT 'active',
  created_at TIMESTAMP NOT NULL,
  UNIQUE(name, version)
);

CREATE TABLE sop_instances (
  id               UUID PRIMARY KEY,
  process_id       UUID REFERENCES sop_processes(id),
  process_name     VARCHAR NOT NULL,
  process_version  VARCHAR NOT NULL,
  state            VARCHAR NOT NULL,
  inputs           JSONB,
  outputs          JSONB,
  metadata         JSONB,
  started_at       TIMESTAMP,
  completed_at     TIMESTAMP,
  error            TEXT,
  created_at       TIMESTAMP NOT NULL
);

CREATE TABLE sop_steps (
  id           UUID PRIMARY KEY,
  instance_id  UUID REFERENCES sop_instances(id),
  step_id      VARCHAR NOT NULL,
  step_name    VARCHAR,
  step_type    VARCHAR NOT NULL,
  state        VARCHAR NOT NULL,
  sub_state    VARCHAR,
  inputs       JSONB,
  outputs      JSONB,
  decided_by   VARCHAR,
  confidence   FLOAT,
  attempt      INTEGER DEFAULT 1,
  position     INTEGER NOT NULL,
  started_at   TIMESTAMP,
  completed_at TIMESTAMP,
  error        TEXT,
  created_at   TIMESTAMP NOT NULL
);

CREATE TABLE sop_events (
  id          UUID PRIMARY KEY,
  instance_id UUID REFERENCES sop_instances(id),
  step_id     VARCHAR,
  event_type  VARCHAR NOT NULL,
  actor       VARCHAR,
  data        JSONB,
  created_at  TIMESTAMP NOT NULL
);

CREATE TABLE sop_callbacks (
  id            UUID PRIMARY KEY,
  instance_id   UUID REFERENCES sop_instances(id),
  step_id       VARCHAR NOT NULL,
  callback_path VARCHAR NOT NULL UNIQUE,
  status        VARCHAR DEFAULT 'pending',
  response      JSONB,
  expires_at    TIMESTAMP,
  created_at    TIMESTAMP NOT NULL
);
```

---

## 5. The Local Execution Backend

### 5.1 What it is

The CLI (`bin/opensop`) includes a self-contained local execution engine. When
`--local` is passed, no server, no network, and no curl are required. Steps run
as ordinary processes on the local machine.

**Trust boundary:** local steps run arbitrary shell on the host — the same
posture as a Makefile. Only run process files you trust.

**Stack:** Bash 4+ (also tested on 3.2), jq. No daemons, no background
processes, no blocking sleeps.

### 5.2 Process file format (local)

The local engine accepts:
- The full wrapped format (`opensop: "0.6"`, `process: {...}`) — same as the server.
- The flat shorthand format: `{ "name", "inputs", "steps" }` (no version key, no `process` wrapper).

Files use the `.sop.json` extension. YAML files are not parsed locally (the CLI's
`schema validate` subcommand handles YAML validation, but `run --local` requires JSON).

### 5.3 Step dispatch (local engine)

The `_local_step_loop` function dispatches on step type:

| Type | Local behavior |
|---|---|
| `automated` | Runs `run:` as a bash script. Context JSON on stdin + `$OSL_CONTEXT`. Non-JSON stdout → `{stdout: "..."}`. Script path resolved relative to process file. |
| `shell` | Runs `run:` via `bash -c`. Same env as `automated`. |
| `noop` | Returns `{}` immediately. |
| `form` | Pauses run. Appends `{status:"waiting", reason:"waiting_for_input"}` to `audit.jsonl`. Returns `"waiting:<index>"`. |
| `approval` | Pauses run. Appends `{status:"waiting", reason:"waiting_for_approval"}` to `audit.jsonl`. Returns `"waiting:<index>"`. |
| anything else | Sets `rc=2`, fails step with "unsupported step type for local execution: \<type\>". Run fails unless `continue_on_error: true`. |

The `executor` field (see §6) is resolved to a default value for audit recording but
does NOT change dispatch behavior.

### 5.4 Run directory artifacts

Every local run creates `$OPENSOP_LOCAL_HOME/runs/<run_id>/`:

| File | Description |
|---|---|
| `manifest.json` | Run state. Rewritten atomically (temp + mv) after every state transition. |
| `audit.jsonl` | Append-only receipt log. One JSON line per step event. Never overwritten. |
| `context.json` | Live checkpoint of accumulated step outputs. Rewritten atomically after every completed step. Resume reads this to re-enter without re-running completed work. |
| `<step-id>.stderr.log` | Temporary stderr capture; folded into the audit receipt at step end, then deleted. |

`OPENSOP_LOCAL_HOME` defaults to the active cell's `.opensop/` when cwd is inside
a cell; otherwise `~/.opensop-local`. An explicit env var always wins.

### 5.5 manifest.json schema

```json
{
  "run_id": "20260610T090000Z-1234-56789",
  "process": "lead-qualification",
  "process_file": "/absolute/path/to/lead-qualification.sop.json",
  "started_at": "2026-06-10T09:00:00Z",
  "status": "running",
  "inputs": { "lead_name": "Alice", "lead_email": "alice@example.com" },

  "ended_at": "...",       // present when status is completed|failed|interrupted

  "cursor": {              // present while status is waiting
    "next_index": 2        // 0-based index of the FIRST step to run on resume
  },

  "waiting": {             // present while status is waiting
    "step": "collect",     // step id of the paused step
    "index": 1,            // 0-based index of the paused step
    "reason": "waiting_for_input",
    "expects": {
      "outputs": ["email", "opt_in"],
      "schema": [...]      // full inputs array for validation
    },
    "since": "2026-06-10T09:00:01Z"
  }
}
```

**`manifest.status` state machine:**

```
running → completed   (all steps finished)
        → failed      (step failed without continue_on_error)
        → waiting     (form/approval/other pause step encountered)
        → interrupted (process killed mid-run; set by EXIT trap)

waiting → running     (local_submit called; cleared before re-entering loop)
        → completed   (via local_submit → _local_step_loop)
        → failed      (via local_submit → _local_step_loop)
        → waiting     (another pause encountered during resume)
```

**`cursor.next_index`** is the 0-based index of the **first step to run on resume**
(the step immediately after the paused step). `waiting.index` holds the paused
step's own index. `local_submit` reads `cursor.next_index` and passes it directly
to `_local_step_loop` as `start_index`.

### 5.6 audit.jsonl receipt schema

Each line is a JSON object:

```json
{
  "run_id": "...",
  "step": "collect",
  "type": "form",
  "executor": "internal",
  "status": "waiting",            // completed | failed | waiting
  "exit_code": 0,                 // present when status is completed|failed
  "started_at": "...",
  "ended_at": "...",              // present when status is completed|failed
  "output": { ... },              // present when status is completed|failed
  "stderr": "...",                // present only when non-empty
  "decided_by": "human:alice"     // present when --decided-by passed to submit
}
```

The waiting receipt (for form/approval) omits `exit_code`, `ended_at`, and `output`.
The completion receipt added by `local_submit` always includes `exit_code: 0`.

### 5.7 Pause and resume protocol

**Pause (local_run encounters a form/approval step):**

1. `_local_step_loop` appends a `"waiting"` receipt to `audit.jsonl` and returns `"waiting:<i>"`.
2. `local_run` writes `manifest.status = "waiting"` with `cursor` and `waiting` blocks.
3. The CLI exits 0 (a clean pause is not a failure).

**Resume (`opensop submit <run_id> <step-id> --local`):**

1. `local_submit` reads `manifest.json`; asserts `status == "waiting"` and `waiting.step == <step-id>`.
2. Validates submitted outputs against `waiting.expects.schema` (required, type, enum).
3. Injects outputs into `context.json` under the step id.
4. Appends a `"completed"` receipt to `audit.jsonl` (with `decided_by` when `--decided-by` is passed). The type field in this receipt is derived from the process file's step definition, not hardcoded.
5. Flips manifest to `status = "running"`, clears `waiting` and `cursor`.
6. Re-enters `_local_step_loop` at `cursor.next_index` — **never** re-runs steps at a lower index.
7. On another pause: writes a new `waiting` block. On completion/failure: finalizes manifest with `ended_at`.

---

## 6. The `executor` Field

```yaml
steps:
  - id: verify
    type: automated
    executor: external    # optional; internal | external
```

**`executor` is audit metadata only.** It is never used to branch dispatch logic.
Omitting it is fine; the engine derives a default for the audit receipt based on
step type.

**Default values (per type):**

| Type | Default executor |
|---|---|
| `automated`, `shell`, `webhook` | `external` |
| `noop`, `form`, `approval`, `notification`, `wait`, `judgment` | `internal` |
| anything else | `external` |

**Allowed values:** `internal` | `external`. Any other value is rejected at parse
time with a `parse_error` before any steps run.

The server runtime does not yet read `executor` from the definition; the
field is declared in the YAML spec for forward compatibility with audit tooling
that wants to know where a step's work happens.

---

## 7. The Cell Substrate

### 7.1 What a cell is

A cell is any directory containing `.opensop/manifest.yaml`. Cells nest — a cell
may declare a parent cell. The cell chain (active cell + ancestors) provides
a name resolution scope for local process files.

`.opensop/manifest.yaml` schema:

```yaml
name: my-project
parent: ../parent-cell    # relative or absolute path; or "null" for a root cell
```

### 7.2 Cell commands

| Command | Description |
|---|---|
| `opensop init [--name N] [--parent P]` | Create `.opensop/` in cwd. Parent auto-detected from ancestor walk if not given. |
| `opensop scope` | Print the active cell + ancestor chain (nearest first). Fails when cwd is not inside any cell. |
| `opensop annotate <skill> <type> <json>` | Append a policy event to the skill's lineage history in the active cell. |
| `opensop lineage <skill>` | Print a skill's lineage entry (status, metadata, history). |
| `opensop fork <name> [--from <cell>]` | Copy an ancestor cell's skill (`.sop.json`) into the active cell and record `forked_from` snapshot. |

### 7.3 Name resolution

When `opensop run <name> --local` is called with a bare name (not a file path):

1. Walk up from cwd to find the active cell root.
2. Check `<cell-root>/processes/<name>.sop.json`.
3. Walk ancestor chain (nearest first), check same path.
4. First match wins. Error if none found.

This is nearest-wins resolution, analogous to `$PATH`.

`opensop list --local` enumerates the full chain with cell name tags.
`opensop list --local --conflicts` marks shadowed entries (later in chain,
same filename as an earlier entry).

### 7.4 `OPENSOP_LOCAL_HOME`

When cwd is inside a cell and `OPENSOP_LOCAL_HOME` is not set explicitly, it
defaults to `<active-cell-root>/.opensop/`. Explicit env var always wins. Run
directories (§5.4) land under `$OPENSOP_LOCAL_HOME/runs/`.

### 7.5 Lineage schema

`<cell-root>/.opensop/lineage.json` is a JSON object keyed by skill logical name:

```json
{
  "lead-qualification": {
    "logical_name": "lead-qualification",
    "forked_from": {
      "cell": "/abs/path/to/parent",
      "forked_at": "2026-06-10T09:00:00Z",
      "snapshot": { "status": "", "metadata": {} }
    },
    "history": [
      { "at": "2026-06-10T09:01:00Z", "type": "promote", "data": { "to": "m2" } }
    ],
    "status": "active",
    "metadata": {}
  }
}
```

The substrate stores; policies (external) populate via `annotate` and read via
`lineage`. The substrate does not interpret `status` or `metadata`.

---

## 8. The Agent Interface

### 8.1 Discovery

```
GET /sop/
```

Returns the process catalog. Agents use this to discover what a company can do.

```json
{
  "processes": [
    {
      "name": "lead-qualification",
      "version": "1.0",
      "description": "Qualify an inbound lead",
      "tags": ["sales", "qualification"],
      "inputs_summary": "lead_name (string, required), lead_email (email, required), source (enum)",
      "outputs_summary": "qualified (boolean), assigned_to (string)",
      "schema_url": "/sop/lead-qualification/schema"
    }
  ]
}
```

### 8.2 Schema

```
GET /sop/lead-qualification/schema
```

Returns the full process definition. Agents use this to understand exact inputs,
outputs, and step structure before starting an instance.

### 8.3 Execution flow

```
POST /sop/lead-qualification/start
  Body: { "inputs": { "lead_name": "Alice", "lead_email": "alice@example.com", "source": "website" } }
  Response: { "id": "<instance-id>", "state": "running", "steps": [...] }

GET /sop/lead-qualification/<id>
  → check state; if a step is waiting_for_input, fill it

POST /sop/lead-qualification/<id>/steps/collect/submit
  Body: { "outputs": { "assigned_to": "rep-bob" } }
  Response: { "instance": { "state": "completed" }, "step": { "state": "completed" } }
```

### 8.4 CLI agent integration

Agents can use the CLI (`bin/opensop`) to drive OpenSOP without hand-writing HTTP.

```bash
opensop list                                    # discover processes
opensop suggest "qualify a new inbound lead"    # intent-based lookup
opensop schema lead-qualification              # inspect full definition
opensop run lead-qualification \
  --input lead_name="Alice" \
  --input lead_email="alice@example.com" \
  --input source=website
opensop status <instance-id>
opensop submit <instance-id> collect \
  --output assigned_to="rep-bob"
```

For local processes (no server needed):

```bash
opensop run ./lead-qualification.sop.json --local --input lead_name="Alice"
opensop show <run_id>
opensop submit <run_id> collect --local --output assigned_to="rep-bob"
```

### 8.5 The `.well-known/opensop` convention (roadmapped)

Long-term: `GET https://api.example.com/.well-known/opensop` → process catalog.
Makes any company running OpenSOP discoverable without prior configuration, the
same way `.well-known/openid-configuration` works for OIDC.

---

## 9. Roadmapped Features

Features listed here are defined in this spec but not yet implemented in either
profile. The server parser rejects them unless noted.

| Feature | Roadmap note |
|---|---|
| `subprocess` fan-out (`fan_out:` modifier) | Phase 4 |
| `post_review:` process hook | Phase 5 |
| Inter-instance shared state (`shared_state_writes:`, `instance.shared_state.<key>`) | Phase 5 |
| `trigger.type: schedule` (cron) | Phase 3; parser rejects today |
| `trigger.type: interval` scheduler consumption | Phase 3; parser stores `interval_seconds` but no scheduler runs yet |
| `trigger.at: [...]` (multi-time daily) | Phase 3; parser rejects today |
| Webhook `response_mode: poll` | Not yet implemented; executor raises StepFailure |
| Subprocess actual child instance creation | Currently stubbed |
| Notification actual delivery | Currently stubbed |
| `judgment` LLM router | Currently stubbed; all judgments escalate to human |
| `async: true` on steps | Deferred to v0.3 |
| Template `extends:` | Deferred to v0.3 |

---

## 10. Examples

All examples use generic placeholders. No real credentials, no real PII.

### 10.1 Minimal local process

```json
{
  "name": "greet",
  "inputs": { "name": "World" },
  "steps": [
    { "id": "say-hello", "type": "shell", "run": "jq -r '\"Hello, \" + .name' <(cat)" }
  ]
}
```

Run: `opensop run ./greet.sop.json --local --input name=Alice`

### 10.2 Form pause and resume

```json
{
  "name": "collect-contact",
  "steps": [
    { "id": "intro", "type": "shell", "run": "echo starting" },
    {
      "id": "collect",
      "type": "form",
      "inputs": [
        { "name": "email", "type": "string", "required": true },
        { "name": "opt_in", "type": "boolean", "required": false }
      ]
    },
    { "id": "confirm", "type": "shell",
      "run": "jq -r '\"Got: \" + .collect.email' <(cat)" }
  ]
}
```

```bash
# Start — pauses at collect
opensop run ./collect-contact.sop.json --local --json
# → { "status": "waiting", "waiting": { "step": "collect", ... } }

# Resume
opensop submit <run_id> collect --local \
  --output email=alice@example.com \
  --output opt_in=true
# → { "status": "completed" }
```

### 10.3 Server process with LLM + webhook

```yaml
opensop: "0.6"

process:
  name: lead-intake
  version: "1.0"
  description: "Score an inbound lead and notify the CRM"

  inputs:
    - { name: lead_name,  type: string, required: true }
    - { name: lead_email, type: string, format: email, required: true }
    - { name: source,     type: enum,   values: [website, referral, cold], required: true }

  steps:
    - id: score
      type: llm
      model: claude-haiku-4-5
      prompt: |
        Score this lead 1-10.
        Name: {{ lead_name }}
        Source: {{ source }}
      expected_output_schema:
        score: number
        rationale: string
      outputs:
        - { name: score, type: number }
        - { name: rationale, type: string }

    - id: notify-crm
      type: webhook
      webhook:
        method: POST
        url: "${env.CRM_URL}/leads"
        headers:
          Authorization: "Bearer ${env.CRM_API_KEY}"
        response_mode: sync
      inputs:
        - { name: score, from: steps.score.outputs.score }
        - { name: lead_name, from: process.inputs.lead_name }
      outputs:
        - { name: crm_lead_id, type: string }
```

---

## Appendix A — Version history

| Version | Key additions |
|---|---|
| 0.1 | Initial spec: process model, 8 step types, instance lifecycle, API surface, server data model |
| 0.2 | `llm` step, `tools:`, collection outputs, `exit_when:`, `loop:` step, interval trigger (parser-only), `post_review:` hook (roadmapped), shared state (roadmapped), `validation:` on `automated` |
| 0.6 | Local execution backend (genuine local execution, no server), `.sop.json` flat format, run-dir artifacts (manifest/audit/context), pause/resume state machine, cell substrate (init/scope/annotate/lineage/fork), `shell` and `noop` local-only step types, `executor` audit field, `--conflicts` for list |

## Appendix B — Flat vs. wrapped envelope quick reference

```
FLAT (local shorthand):                     WRAPPED (server / YAML):
{                                           opensop: "0.6"
  "name": "greet",                          process:
  "inputs": {},                               name: greet
  "steps": [...]                              version: "1.0"
}                                             inputs: [...]
                                              steps: [...]
```

The local engine reads both. The server requires the wrapped form for registration.
`opensop schema validate` checks the wrapped form only.
