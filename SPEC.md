# OpenSOP — Specification v0.1

**Date:** 2026-04-18
**Authors:** Carlos Medellin + Claude (digital twin)
**Status:** Draft — foundational spec
**Domain:** opensop.ai
**License:** Open source (license TBD — likely Apache 2.0 or MIT)

---

## 1. What OpenSOP Is

OpenSOP is an open standard and runtime for defining, storing, executing, and exposing business processes as APIs.

**The problem:** Business processes live in people's heads, Word docs, PDFs, Notion pages, and tribal knowledge. They're written for humans to read and follow. In the agentic era, processes need to be readable by both humans and machines — discoverable, callable, observable.

**The solution:** A standard format (OpenSOP Spec) for defining processes as structured objects with typed inputs/outputs, and a self-hostable runtime (OpenSOP Engine) that executes process instances and auto-generates APIs from definitions.

**Core beliefs:**

1. **The process definition IS the API contract.** Define a process, get an API. No separate API layer to build.
2. **Processes are company IP.** Self-hostable, stored in your own repo or database, never leaves your infrastructure unless you choose.
3. **Every step has a type.** Automated, judgment, approval, form, webhook — the platform knows which steps need a human, which need an LLM, and which just run.
4. **Agents are first-class consumers.** The discovery endpoint lets any agent understand what a company does and how to interact with it.
5. **Start simple, harden over time.** A process can begin as a 3-step checklist and evolve into a fully automated pipeline. The format supports the full spectrum.

---

## 2. The Process Definition Format

### 2.1 Primitives

The format has four primitives:

| Primitive | What it is | Analogy |
|-----------|------------|---------|
| **Process** | A named sequence of steps that transforms inputs into outputs | A recipe |
| **Step** | A single unit of work with typed inputs, outputs, and a step type | A recipe instruction |
| **Field** | A typed input or output (string, number, enum, file, reference) | An ingredient or result |
| **Instance** | A running execution of a process, with state | A meal being cooked |

### 2.2 Process definition

A process is defined in YAML (or JSON). Here's the minimal structure:

```yaml
# Every process file starts with this
opensop: "0.1"

process:
  name: customer-onboarding
  version: "1.0"
  description: "Onboard a new business customer for cross-border banking"
  owner: banking-team

  # What starts this process
  trigger:
    type: api          # api | webhook | schedule | manual
    # For schedule (not yet implemented): cron: "0 9 * * 1-5"
    # For webhook (implemented since v0.2): see the full schema below
    # in §2.2 "Webhook triggers".

  # What goes IN to the process (provided at start)
  inputs:
    - name: company_name
      type: string
      required: true
    - name: contact_email
      type: string
      format: email
      required: true
    - name: country
      type: enum
      values: [US, MX]
      required: true
    - name: source_channel
      type: enum
      values: [website, linkedin, email, referral, cold-outbound]
    - name: deal_id
      type: string
      description: "External CRM reference"

  # What comes OUT when the process completes
  outputs:
    - name: account_id
      type: string
    - name: member_id
      type: string
    - name: status
      type: enum
      values: [approved, rejected]
    - name: rejection_reason
      type: string
      required_if: "status == rejected"

  # The steps
  steps:
    - id: collect-business-info
      name: "Collect business information"
      type: form
      description: "Gather company details, ownership, fiscal address"
      inputs:
        - name: company_name
          from: process.inputs.company_name
        - name: contact_email
          from: process.inputs.contact_email
      outputs:
        - name: business_record
          type: object
          schema:
            legal_name: string
            rfc: string
            fiscal_address: string
            industry: string
            annual_revenue: number
      timeout: 7d
      on_timeout: notify-and-wait

    - id: verify-documents
      name: "Verify KYB documents"
      type: automated
      description: "Check uploaded documents against requirements"
      inputs:
        - name: business_record
          from: steps.collect-business-info.outputs.business_record
        - name: documents
          type: file[]
          accept: [pdf, jpg, png]
      outputs:
        - name: verification_result
          type: enum
          values: [complete, incomplete, invalid]
        - name: missing_documents
          type: string[]
      run: ./steps/verify-documents.py
      retry:
        max: 3
        backoff: exponential

    - id: review-application
      name: "Review application"
      type: judgment
      description: "Assess risk and decide whether to approve"
      inputs:
        - name: business_record
          from: steps.collect-business-info.outputs.business_record
        - name: verification_result
          from: steps.verify-documents.outputs.verification_result
      outputs:
        - name: decision
          type: enum
          values: [approve, reject, request-more-info]
        - name: risk_notes
          type: string
        - name: rejection_reason
          type: string
          required_if: "decision == reject"
      # Judgment config
      judgment:
        allow_agent: true           # LLM can fill this step
        require_human_review: false  # But human override is available
        confidence_threshold: 0.9   # If agent confidence < 90%, escalate to human
        escalation: manual          # How to escalate: manual | queue | slack

    - id: submit-to-compliance
      name: "Submit to compliance provider"
      type: webhook
      description: "Send entity to compliance provider for review"
      condition: "steps.review-application.outputs.decision == 'approve'"
      inputs:
        - name: business_record
          from: steps.collect-business-info.outputs.business_record
      outputs:
        - name: entity_id
          type: string
        - name: compliance_status
          type: enum
          values: [pending, approved, rejected]
      webhook:
        method: POST
        url: "${COMPLIANCE_PROVIDER_URL}/entities"
        headers:
          Authorization: "Bearer ${COMPLIANCE_API_KEY}"
        body_template: ./steps/compliance-payload.json
        # How to get the result back
        response_mode: callback    # callback | poll | sync
        callback_path: /webhooks/compliance/receive
        poll_interval: 1h
        poll_timeout: 7d

    - id: create-account
      name: "Create customer account"
      type: automated
      condition: "steps.submit-to-compliance.outputs.compliance_status == 'approved'"
      inputs:
        - name: business_record
          from: steps.collect-business-info.outputs.business_record
        - name: entity_id
          from: steps.submit-to-compliance.outputs.entity_id
      outputs:
        - name: account_id
          type: string
        - name: member_id
          type: string
      run: ./steps/create-account.py

    - id: send-welcome
      name: "Send welcome email"
      type: automated
      inputs:
        - name: contact_email
          from: process.inputs.contact_email
        - name: account_id
          from: steps.create-account.outputs.account_id
      outputs:
        - name: email_sent
          type: boolean
      run: ./steps/send-welcome.py

  # What happens on failure
  on_error:
    notify:
      channel: slack
      target: "#banking-ops"
    retry_policy: step-level    # Each step has its own retry config

  # Metadata for discovery
  tags: [banking, onboarding, compliance, kyb]
  sla:
    target: 72h
    warning: 48h
```

### 2.3 Step types

| Type | Description | Who executes | Example |
|------|-------------|--------------|---------|
| **form** | Collects data from a human (or agent filling a form) | Human via UI, agent via API | "Fill out company details" |
| **automated** | Runs code — a script, function, or service call | Machine (script at `run:` path) | "Validate document checksums" |
| **judgment** | Requires a decision based on context. Can be filled by LLM or human. | LLM or human (configurable) | "Should we approve this application?" |
| **approval** | Binary gate — someone (or some role) must approve/reject | Human (with optional LLM pre-screen) | "Manager approves expense over $10K" |
| **webhook** | Calls an external system and waits for a response | Machine (HTTP call) | "Submit to compliance provider" |
| **subprocess** | Starts another OpenSOP process and waits for completion | OpenSOP runtime | "Run the KYC sub-process" |
| **notification** | Sends a message (email, Slack, SMS) — fire and forget | Machine | "Notify team of new application" |
| **wait** | Pauses until a condition is met or a time elapses | Timer/event | "Wait 24h, then check status" |

### 2.4 Field types

| Type | Description | Example |
|------|-------------|---------|
| `string` | Text | `"Acme Corp"` |
| `number` | Numeric (integer or decimal) | `42`, `3.14` |
| `boolean` | True/false | `true` |
| `enum` | One of a defined set of values | `"approved"` from `[approved, rejected]` |
| `date` | ISO 8601 date | `"2026-04-18"` |
| `datetime` | ISO 8601 datetime | `"2026-04-18T10:30:00Z"` |
| `file` | File reference (path or URL) | uploaded PDF |
| `file[]` | Array of files | multiple documents |
| `string[]` | Array of strings | `["missing_rfc", "missing_address"]` |
| `object` | Nested structure with schema | `{ legal_name: "Acme", rfc: "ABC123" }` |
| `reference` | ID pointing to another process instance or external record | `deal_id`, `member_id` |
| `currency` | Amount + currency code | `{ amount: 1500.00, currency: "USD" }` |

### 2.5 Expressions and conditions

Steps can have conditions (skip if not met) and field values can reference outputs from previous steps:

```yaml
# Reference syntax
from: process.inputs.company_name           # From process input
from: steps.verify-documents.outputs.result  # From a step's output
from: env.COMPLIANCE_API_KEY                 # From environment variable
from: instance.started_at                    # From instance metadata

# Condition syntax (simple boolean expressions)
condition: "steps.review.outputs.decision == 'approve'"
condition: "steps.verify.outputs.score >= 0.8"
condition: "steps.verify.outputs.result != 'invalid'"
required_if: "status == 'rejected'"
```

### 2.6 Process composition

Processes can call other processes via the `subprocess` step type:

```yaml
- id: run-kyc
  name: "Run KYC verification"
  type: subprocess
  process: kyc-verification    # Name of another OpenSOP process
  inputs:
    - name: person_name
      from: steps.collect-info.outputs.owner_name
    - name: country
      from: process.inputs.country
  outputs:
    - name: kyc_status
      type: enum
      values: [passed, failed, manual_review]
```

This enables **process libraries** — a company builds small, reusable processes (KYC, send-email, create-invoice) and composes them into larger workflows.

### 2.7 Versioning

Process definitions are versioned. Running instances are pinned to the version they started on.

```yaml
process:
  name: customer-onboarding
  version: "2.0"
  replaces: "1.0"             # Marks 1.0 as deprecated
  migration: ./migrations/v1-to-v2.py  # Optional: migrate in-flight v1 instances
```

### 2.2 Webhook triggers (starting a process from a third-party tool)

When a process needs to be kicked off by a SaaS webhook (Cal.com bookings, Stripe events, HubSpot form submissions, DocuSign completions, etc.), declare a webhook trigger:

```yaml
process:
  name: consult-request
  version: "1.0"

  trigger:
    type: webhook
    auth:
      scheme: hmac-sha256              # only scheme in v0.2
      secret_env: CAL_WEBHOOK_SECRET   # env var with the shared secret
      header: X-Cal-Signature-256      # header the provider sends
      encoding: hex                    # hex | base64 (default: hex)
      prefix: "sha256="                # optional; stripped before compare
    input_mapping:
      attendee_email: "${payload.attendees.0.email}"
      attendee_name:  "${payload.attendees.0.name}"
      meeting_time:   "${payload.startTime}"
      booking_id:     "${payload.uid}"
      source:         "cal.com"                       # literal value

  inputs:
    - { name: attendee_email, type: string, required: true }
    - { name: attendee_name,  type: string, required: true }
    # ...
```

**Endpoint:** the engine exposes `POST /sop/triggers/<process-name>`. Configure the provider to post there.

**Auth:** the declared HMAC scheme IS the authentication — the trigger endpoint does NOT require `X-SOP-Token`. The engine verifies the signature against the raw request body using the secret resolved from the declared `secret_env`.

**Input mapping:** uses the same `${...}` syntax as webhook step interpolation, plus a new namespace `${payload.X.Y.Z}` for the inbound JSON body. Integer array indices are supported (`payload.attendees.0.email`). Literal values pass through (`source: "cal.com"`).

**Response modes:**

| Condition | Status | Body |
|---|---|---|
| Instance started successfully | 200 | `{"status":"started","instance_id":"..."}` |
| Payload missing a mapped key, OR instance input validation failed | 200 | `{"status":"accepted","action":"logged","reason":"..."}` |
| Malformed JSON body | 400 | `{"error":"invalid_payload",...}` |
| HMAC mismatch or signature header absent | 401 | `{"error":"invalid_signature",...}` |
| Process not found | 404 | `{"error":"not_found",...}` |
| Process has no webhook trigger | 404 | `{"error":"trigger_not_configured",...}` |
| Secret env var unset at runtime | 500 | `{"error":"trigger_misconfigured",...}` |

The 200-with-logged-reason response is deliberate: providers like Cal.com send multiple event types to one endpoint (e.g. `BOOKING_CREATED` with attendees, `BOOKING_CANCELLED` without). When the payload doesn't match the mapping, the engine logs the rejection with a distinctive tag (`MAPPING_REJECTED` / `INSTANCE_REJECTED`) but returns 200 so the provider doesn't retry. If you need to handle multiple event types, declare separate processes or add a dispatch step.

**Supported providers on day one:**

| Provider | Signature header | Encoding | Prefix |
|---|---|---|---|
| Cal.com | `X-Cal-Signature-256` | hex | — |
| Stripe | `Stripe-Signature` | hex | `v1=` (with `t=...,`) — **timestamp-scoped variant not yet supported; use at your own risk** |
| HubSpot | `X-HubSpot-Signature-v3` | hex | — |
| Typeform | `Typeform-Signature` | base64 | `sha256=` |
| GitHub | `X-Hub-Signature-256` | hex | `sha256=` |

Twilio uses HMAC-SHA1 which is not yet implemented — track v0.3 for that.

---

## 3. The Runtime Architecture

### 3.1 Components

```
┌──────────────────────────────────────────────────────────────┐
│                     OPENSOP ENGINE                            │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐│
│  │  DEFINITION  │  │  INSTANCE    │  │      STORE           ││
│  │  REGISTRY    │  │  EXECUTOR    │  │                      ││
│  │              │  │              │  │  Process definitions ││
│  │  Loads YAML  │  │  Runs steps  │  │  Instance state      ││
│  │  Validates   │  │  Tracks      │  │  Step I/O data       ││
│  │  Versions    │  │  state       │  │  Audit log           ││
│  │  Indexes     │  │  Handles     │  │  (PostgreSQL,        ││
│  │              │  │  timeouts,   │  │   SQLite, or DuckDB) ││
│  │              │  │  retries,    │  │                      ││
│  │              │  │  conditions  │  │                      ││
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘│
│         │                 │                      │            │
│  ┌──────┴─────────────────┴──────────────────────┴──────────┐│
│  │                    API GATEWAY                            ││
│  │                                                           ││
│  │  Auto-generated from process definitions:                 ││
│  │                                                           ││
│  │  Discovery:                                               ││
│  │    GET  /sop/                     → list all processes    ││
│  │    GET  /sop/{name}/schema        → process definition   ││
│  │                                                           ││
│  │  Execution:                                               ││
│  │    POST /sop/{name}/start         → start instance        ││
│  │    GET  /sop/{name}/{id}          → instance state        ││
│  │    GET  /sop/{name}/{id}/steps    → all step states       ││
│  │    POST /sop/{name}/{id}/steps/{step}/submit  → advance  ││
│  │    POST /sop/{name}/{id}/cancel   → cancel instance       ││
│  │                                                           ││
│  │  Webhooks (inbound):                                      ││
│  │    POST /sop/webhooks/{callback_id}  → receive callbacks  ││
│  │                                                           ││
│  │  Admin:                                                   ││
│  │    GET  /sop/instances            → list all instances    ││
│  │    GET  /sop/metrics              → process metrics       ││
│  └───────────────────────────────────────────────────────────┘│
│                                                               │
│  ┌───────────────────────────────────────────────────────────┐│
│  │                 JUDGMENT ROUTER                            ││
│  │                                                           ││
│  │  When a judgment/approval step is reached:                ││
│  │    1. Check if agent is allowed (allow_agent: true)       ││
│  │    2. If yes → call configured LLM with step context      ││
│  │    3. Check confidence against threshold                  ││
│  │    4. If confident → auto-advance                         ││
│  │    5. If not → escalate (queue, Slack, email)             ││
│  │    6. Human can always override agent decision            ││
│  └───────────────────────────────────────────────────────────┘│
│                                                               │
│  ┌───────────────────────────────────────────────────────────┐│
│  │                 EVENT BUS                                  ││
│  │                                                           ││
│  │  Every state change emits an event:                       ││
│  │    instance.started                                       ││
│  │    instance.completed                                     ││
│  │    instance.failed                                        ││
│  │    step.started                                           ││
│  │    step.completed                                         ││
│  │    step.failed                                            ││
│  │    step.waiting_for_input                                 ││
│  │    step.escalated                                         ││
│  │                                                           ││
│  │  Consumers: webhook endpoints, Slack, email, logs, agents ││
│  └───────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
```

### 3.2 Instance lifecycle

```
                    ┌─────────┐
        start() →   │ RUNNING │
                    └────┬────┘
                         │
           ┌─────────────┼──────────────┐
           ▼             ▼              ▼
     ┌──────────┐  ┌──────────┐  ┌──────────┐
     │ STEP:    │  │ STEP:    │  │ STEP:    │
     │ active   │  │ waiting  │  │ skipped  │
     │          │  │ (form,   │  │ (cond.   │
     │ running  │  │  webhook │  │  false)  │
     │ code or  │  │  callback│  │          │
     │ judgment │  │  approval│  │          │
     └────┬─────┘  └────┬─────┘  └──────────┘
          │              │
          ▼              ▼
     ┌──────────┐  ┌──────────┐
     │ STEP:    │  │ STEP:    │
     │ completed│  │ failed   │
     └────┬─────┘  └────┬─────┘
          │              │
          │         retry? ──yes──► back to active
          │              │
          ▼         no   ▼
     next step    ┌──────────┐
          │       │ INSTANCE │
          │       │ FAILED   │
          ▼       └──────────┘
     ┌──────────┐
     │ INSTANCE │
     │ COMPLETED│
     └──────────┘
```

Instance states: `pending` → `running` → `completed` | `failed` | `cancelled`
Step states: `pending` → `active` → `completed` | `failed` | `skipped`
Sub-states for active: `running` | `waiting_for_input` | `waiting_for_callback` | `waiting_for_approval` | `escalated`

### 3.3 Data model (what the Store holds)

```sql
-- Process definitions (loaded from YAML, indexed for API)
CREATE TABLE sop_processes (
  id            UUID PRIMARY KEY,
  name          VARCHAR NOT NULL,
  version       VARCHAR NOT NULL,
  description   TEXT,
  definition    JSONB NOT NULL,        -- Full parsed YAML
  owner         VARCHAR,
  tags          TEXT[],
  status        VARCHAR DEFAULT 'active',  -- active | deprecated | archived
  created_at    TIMESTAMP NOT NULL,
  UNIQUE(name, version)
);

-- Process instances (running or completed)
CREATE TABLE sop_instances (
  id            UUID PRIMARY KEY,
  process_id    UUID REFERENCES sop_processes(id),
  process_name  VARCHAR NOT NULL,
  process_version VARCHAR NOT NULL,
  state         VARCHAR NOT NULL,      -- pending | running | completed | failed | cancelled
  inputs        JSONB,                 -- Process-level inputs provided at start
  outputs       JSONB,                 -- Process-level outputs (filled on completion)
  started_at    TIMESTAMP,
  completed_at  TIMESTAMP,
  error         TEXT,
  metadata      JSONB,                 -- External references (deal_id, member_id, etc.)
  created_at    TIMESTAMP NOT NULL
);

-- Step executions (one row per step per instance)
CREATE TABLE sop_steps (
  id            UUID PRIMARY KEY,
  instance_id   UUID REFERENCES sop_instances(id),
  step_id       VARCHAR NOT NULL,      -- Matches step.id in definition
  step_name     VARCHAR NOT NULL,
  step_type     VARCHAR NOT NULL,      -- form | automated | judgment | approval | webhook | ...
  state         VARCHAR NOT NULL,      -- pending | active | completed | failed | skipped
  sub_state     VARCHAR,               -- running | waiting_for_input | escalated | ...
  inputs        JSONB,                 -- Resolved inputs for this step
  outputs       JSONB,                 -- Step outputs (filled on completion)
  started_at    TIMESTAMP,
  completed_at  TIMESTAMP,
  error         TEXT,
  attempt       INTEGER DEFAULT 1,     -- Current retry attempt
  decided_by    VARCHAR,               -- 'agent' | 'human:{user_id}' | 'system'
  confidence    FLOAT,                 -- Agent confidence (for judgment steps)
  created_at    TIMESTAMP NOT NULL
);

-- Audit log (every state change, every decision)
CREATE TABLE sop_events (
  id            UUID PRIMARY KEY,
  instance_id   UUID REFERENCES sop_instances(id),
  step_id       VARCHAR,
  event_type    VARCHAR NOT NULL,      -- instance.started, step.completed, step.escalated, ...
  actor         VARCHAR,               -- system | agent | human:{id}
  data          JSONB,                 -- Event-specific payload
  created_at    TIMESTAMP NOT NULL
);

-- Webhook callbacks (pending external responses)
CREATE TABLE sop_callbacks (
  id            UUID PRIMARY KEY,
  instance_id   UUID REFERENCES sop_instances(id),
  step_id       VARCHAR NOT NULL,
  callback_path VARCHAR NOT NULL UNIQUE,  -- /sop/webhooks/{this_id}
  status        VARCHAR DEFAULT 'pending', -- pending | received | expired
  response      JSONB,
  expires_at    TIMESTAMP,
  created_at    TIMESTAMP NOT NULL
);
```

### 3.4 Deployment options

OpenSOP Engine is self-hostable. Multiple deployment options:

| Mode | Store | Use Case |
|------|-------|----------|
| **Local** | SQLite | Development, single-user, prototyping |
| **Single server** | PostgreSQL | Small team, internal processes |
| **Cloud** | PostgreSQL on managed DB | Production, multi-team |
| **Embedded** | SQLite/DuckDB | Embedded in another app (e.g., an internal admin tool) |

The engine itself is a single binary (or container) with no external dependencies beyond the database. Process scripts (the `run:` paths) execute in a sandboxed environment.

### 3.5 Auth model

Simple API key auth for v1:

```
X-SOP-Token: {api_key}
```

Process-level access control:

```yaml
process:
  name: customer-onboarding
  access:
    start: [sales-team, website-webhook]    # Who can start instances
    view: [sales-team, ops-team, agents]    # Who can view instance state
    advance: [ops-team]                      # Who can manually advance steps
    admin: [admin]                           # Who can modify the process definition
```

---

## 4. The Agent Interface

### 4.1 Discovery

An agent interacting with a company running OpenSOP can discover all available processes:

```
GET /sop/
```

Response:
```json
{
  "processes": [
    {
      "name": "customer-onboarding",
      "version": "1.0",
      "description": "Onboard a new business customer for cross-border banking",
      "tags": ["banking", "onboarding", "compliance"],
      "inputs_summary": "company_name (string, required), contact_email (email, required), country (enum: US|MX)",
      "outputs_summary": "account_id (string), member_id (string), status (enum: approved|rejected)",
      "sla": "72h",
      "schema_url": "/sop/customer-onboarding/schema"
    },
    {
      "name": "send-payment",
      "version": "1.0",
      "description": "Send a cross-border payment from USD to MXN",
      ...
    }
  ]
}
```

### 4.2 Schema

An agent can read the full schema of a process to understand exactly what inputs it needs and what outputs it produces:

```
GET /sop/customer-onboarding/schema
```

Returns the full process definition (inputs, outputs, steps with their types and I/O). This is the machine-readable equivalent of an SOP document.

### 4.3 Agent as step executor

When a judgment step has `allow_agent: true`, the engine calls the configured LLM with:

```json
{
  "process": "customer-onboarding",
  "step": "review-application",
  "step_description": "Assess risk and decide whether to approve",
  "inputs": {
    "business_record": { "legal_name": "Acme Logistics, Inc.", ... },
    "verification_result": "complete"
  },
  "expected_outputs": {
    "decision": { "type": "enum", "values": ["approve", "reject", "request-more-info"] },
    "risk_notes": { "type": "string" },
    "rejection_reason": { "type": "string", "required_if": "decision == reject" }
  },
  "context": {
    "process_inputs": { ... },
    "previous_steps": [ ... ]
  }
}
```

The LLM returns structured outputs matching the expected schema. The engine validates them, checks confidence, and either advances or escalates.

### 4.4 The protocol vision

Long-term, OpenSOP becomes a protocol — like OpenAPI for processes:

```
# An agent discovers a company's capabilities
GET https://api.company.com/.well-known/opensop → process catalog

# An agent starts a process at that company
POST https://api.company.com/sop/customer-onboarding/start

# An agent checks on progress
GET https://api.company.com/sop/customer-onboarding/{id}
```

Any company running OpenSOP is instantly agent-interoperable. No bespoke integration.
The `.well-known/opensop` convention (like `.well-known/openid-configuration`) makes discovery automatic.

---

## 5. Example: A Financial Services Company

Consider a financial services company operating three disparate systems — a core banking service, a CRM, and an internal admin tool — each with its own process logic implemented in Rails state machines, service objects, and controller flows. This is a common shape, and a useful lens for seeing what OpenSOP replaces.

> *Other example use cases will be added here as teams adopt the system. PRs welcome.*

### 5.1 Candidate processes

Their production line maps naturally to a set of OpenSOP processes:

| Process | Steps | Typical current state |
|---------|-------|-----------------------|
| `customer-onboarding` | collect-info → verify-docs → review → submit-compliance → create-account → welcome | Lives as a Rails state machine in the banking service. Port to OpenSOP definition. |
| `compliance-submission` | prepare-entity → submit-to-provider → wait-for-response → handle-result | Lives as service objects around a compliance-provider integration. Port as a subprocess. |
| `send-payment` | select-recipient → enter-amount → get-quote → review → confirm → execute | Lives as a controller flow. Port as a process. |
| `lead-qualification` | receive-lead → enrich → score → assign → contact | Partially lives in the CRM. Formalize as a process. |
| `content-publication` | draft → review → approve → publish → track | Doesn't exist yet. Define as a process. |
| `deal-pipeline` | inbound → talking → demo → onboarding → compliance → activation → recurring | Lives across multiple systems. Unify as a single process. |

### 5.2 Orchestrating across systems with OpenSOP

Companies in this shape often build a bespoke orchestrator to bridge systems. OpenSOP replaces most of it:

- **Custom pipeline API** → replaced by the OpenSOP Engine (it IS the API layer)
- **Custom constraint engine** → a scheduled process that reads instance metrics from the engine
- **Sub-agents with hand-wired context** → agents that start and advance process instances via the OpenSOP API
- **Unified "pipeline" table** → replaced by `sop_instances` + `sop_steps` (the process state IS the unified view)

The orchestrator doesn't need to bridge three systems anymore. Each system registers its processes with OpenSOP. The orchestrator reads process state from one place.

### 5.3 Migration path

1. **Deploy OpenSOP** alongside existing systems (don't replace anything)
2. **Define processes** as OpenSOP YAML (start with customer-onboarding)
3. **Wire existing systems as step executors** — e.g., the banking service's onboarding controller becomes the `run:` target for onboarding steps
4. **Move orchestration to OpenSOP** — the reporting agent reads from `/sop/instances` instead of querying three databases
5. **Harden** — as processes prove out, move step execution from agent-mediated to automated

---

## 6. Technical Decisions

### 6.1 Implementation language

**Recommendation: Ruby (Rails)** for the engine.

Why:
- Rails is a widely used, approachable stack for process automation work
- Standard container deployment (Docker → any host: Cloud Run, Fly.io, Render, Heroku, self-hosted)
- Convention-over-configuration aligns with the "define process, get API" philosophy
- ActiveRecord + PostgreSQL for the store
- Good YAML parsing ecosystem
- Fastest path to production

Alternative: Go or Rust for a single-binary distribution. Consider for v2 if adoption demands it.

### 6.2 Process definition storage

Processes are defined in YAML files, stored in a git repo. The engine loads them on startup (or via reload endpoint).

```
company-processes/
├── customer-onboarding.sop.yaml
├── send-payment.sop.yaml
├── compliance-submission.sop.yaml
├── lead-qualification.sop.yaml
├── steps/
│   ├── verify-documents.py
│   ├── create-account.py
│   ├── compliance-payload.json
│   └── send-welcome.py
└── opensop.config.yaml          # Engine configuration
```

The repo IS the source of truth. The engine reads from it. Git history IS the version history.

### 6.3 Step execution model

Automated steps run scripts. The engine:
1. Resolves inputs from previous steps
2. Passes inputs as JSON via stdin (or environment variables)
3. Runs the script in a sandboxed process
4. Reads outputs from stdout (JSON)
5. Validates outputs against the step's output schema
6. Stores outputs and advances

```
ENGINE → stdin: {"business_record": {...}} → SCRIPT → stdout: {"verification_result": "complete"} → ENGINE
```

Scripts can be in any language (Python, Ruby, Node, Bash, Go). The engine detects runtime by file extension or shebang.

### 6.4 Judgment step execution

When a judgment step is reached:
1. Engine assembles context (step description, inputs, expected outputs, previous steps)
2. Calls configured LLM provider (Anthropic, OpenAI, local model)
3. Parses structured output
4. Checks confidence against threshold
5. If confident → auto-advance, record `decided_by: agent`
6. If not → escalate, record `sub_state: escalated`
7. Human can always override via API: `POST /sop/{name}/{id}/steps/{step}/submit`

LLM provider config:

```yaml
# opensop.config.yaml
judgment:
  provider: anthropic
  model: claude-sonnet-4-6
  api_key_env: ANTHROPIC_API_KEY
  default_confidence_threshold: 0.85
  escalation_channel: slack
  escalation_target: "#ops-review"
```

---

## 7. The UI

The UI ships with the engine. It's not a separate product — it's how non-technical people interact with OpenSOP. Three surfaces: **Build**, **Operate**, **Observe**.

### 7.1 Build — Process Designer

The process designer lets anyone define a process visually. No YAML required.

```
┌──────────────────────────────────────────────────────────────────┐
│  OPENSOP — Process Designer                          [Save] [▶]  │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  customer-onboarding  v1.0                    [Settings ⚙]  │ │
│  │  "Onboard a new business customer"                          │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  PROCESS INPUTS                                                   │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐        │
│  │ company_name   │ │ contact_email  │ │ country        │        │
│  │ string • req   │ │ email • req    │ │ enum: US,MX    │  [+]   │
│  └────────────────┘ └────────────────┘ └────────────────┘        │
│                                                                   │
│  STEPS                                                            │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  1 ○ Collect business info                        [form]  │  │
│  │     in: company_name, contact_email                        │  │
│  │     out: business_record (object)                          │  │
│  │     timeout: 7 days                                        │  │
│  ├────────────────────────────────────────────────────────────┤  │
│  │  2 ○ Verify documents                        [automated]  │  │
│  │     in: business_record, documents (file[])                │  │
│  │     out: verification_result (enum), missing_docs (str[])  │  │
│  │     script: steps/verify-documents.py                      │  │
│  ├────────────────────────────────────────────────────────────┤  │
│  │  3 ◆ Review application                       [judgment]  │  │
│  │     in: business_record, verification_result               │  │
│  │     out: decision (approve/reject/more-info)               │  │
│  │     agent: allowed • threshold: 90% • escalate: manual     │  │
│  ├────────────────────────────────────────────────────────────┤  │
│  │  4 ○ Submit to compliance                      [webhook]  │  │
│  │     condition: decision == 'approve'                       │  │
│  │     in: business_record                                    │  │
│  │     out: entity_id, compliance_status                      │  │
│  │     POST → ${COMPLIANCE_PROVIDER_URL}/entities             │  │
│  ├────────────────────────────────────────────────────────────┤  │
│  │  5 ○ Create account                          [automated]  │  │
│  │     condition: compliance_status == 'approved'             │  │
│  │     in: business_record, entity_id                         │  │
│  │     out: account_id, member_id                             │  │
│  ├────────────────────────────────────────────────────────────┤  │
│  │  6 ○ Send welcome email                      [automated]  │  │
│  │     in: contact_email, account_id                          │  │
│  │     out: email_sent (boolean)                              │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                           [+ Step]│
│                                                                   │
│  PROCESS OUTPUTS                                                  │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐        │
│  │ account_id     │ │ member_id      │ │ status         │        │
│  │ string         │ │ string         │ │ enum           │  [+]   │
│  └────────────────┘ └────────────────┘ └────────────────┘        │
│                                                                   │
│  [Export YAML]  [Test Run]  [Publish v1.0]                        │
└──────────────────────────────────────────────────────────────────┘
```

**Key interactions:**

- **Add a step:** Click [+ Step], choose type from dropdown (form, automated, judgment, approval, webhook, subprocess, notification, wait). A step card appears with type-specific fields to fill in.
- **Define inputs/outputs:** Click [+] on any step card to add a field. Pick name, type (from dropdown), and whether it's required. For `from:` references, a dropdown shows all available outputs from previous steps and process inputs.
- **Conditions:** Toggle "Add condition" on a step → expression builder with dropdowns for available fields, operators, and values. No free-text expressions needed.
- **Reorder steps:** Drag and drop step cards.
- **Judgment config:** When step type is "judgment," extra fields appear: allow agent (toggle), confidence threshold (slider), escalation method (dropdown).
- **Webhook config:** When step type is "webhook," fields appear for URL, method, headers, body template, response mode (sync/callback/poll).
- **Export YAML:** Generates the `.sop.yaml` file. The UI is a visual editor for the same format — YAML is always the source of truth.
- **Test Run:** Starts a test instance with sample data. Shows step-by-step execution in real time.
- **Publish:** Saves the process definition to the engine. Increments version if the process already exists.

**What the UI generates vs. what needs code:**

| Action | UI can do it | Needs code |
|--------|-------------|------------|
| Define process name, description, tags | Yes | — |
| Add/edit steps with types | Yes | — |
| Define inputs/outputs with types | Yes | — |
| Set conditions between steps | Yes | — |
| Configure judgment steps (threshold, escalation) | Yes | — |
| Configure webhook steps (URL, headers, response mode) | Yes | — |
| Write the actual script for an automated step | — | Yes (Python/Ruby/JS/Bash) |
| Define complex object schemas for step I/O | Partially (UI for simple objects, YAML for nested) | Deep nesting |
| Wire subprocess references | Yes (dropdown of existing processes) | — |

**The 80/20:** A non-technical person can design the entire process flow, define what data goes where, set conditions and judgment rules. An engineer only needs to write the scripts that automated steps execute. The process structure is accessible; the execution logic is code.

### 7.2 Operate — Instance Dashboard

The operations view shows all running and completed process instances.

```
┌──────────────────────────────────────────────────────────────────┐
│  OPENSOP — Instances                            [All Processes ▼]│
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │ Running  │ │ Waiting  │ │Completed │ │ Failed   │            │
│  │    12    │ │    8     │ │   143    │ │    3     │            │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘            │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ INSTANCE                  PROCESS           STATE    AGE    │ │
│  ├─────────────────────────────────────────────────────────────┤ │
│  │ ● Acme Logistics          customer-onboard  WAITING  3d    │ │
│  │   → stuck at: Submit to compliance (waiting for callback)   │ │
│  │                                                             │ │
│  │ ● Globex Freight          customer-onboard  WAITING  5d    │ │
│  │   → stuck at: Submit to compliance (waiting for callback)   │ │
│  │                                                             │ │
│  │ ◆ Freight Solutions LLC   customer-onboard  RUNNING  1h    │ │
│  │   → at: Review application (judgment — agent processing)    │ │
│  │                                                             │ │
│  │ ○ Weekly constraint report run-constraint    RUNNING  2m    │ │
│  │   → at: Compute metrics (automated — running)               │ │
│  │                                                             │ │
│  │ ✓ Aduanas del Pacífico    customer-onboard  DONE     12d   │ │
│  │   → completed in 4d 6h                                      │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  [Filters: process, state, date range, stuck > N days]            │
└──────────────────────────────────────────────────────────────────┘
```

**Click into an instance → Instance Detail:**

```
┌──────────────────────────────────────────────────────────────────┐
│  INSTANCE: Acme Logistics — customer-onboarding v1.0             │
│  Started: 2026-04-15  •  State: WAITING  •  ID: inst_abc123      │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  INPUTS                                                           │
│  company_name: Acme Logistics, Inc.                               │
│  contact_email: customer@example.com                              │
│  country: MX                                                      │
│  source_channel: linkedin                                         │
│  deal_id: dc_9f8a7b6c                                             │
│                                                                   │
│  STEPS                                                            │
│  ✓ 1. Collect business info        completed    2026-04-15 09:30  │
│       → business_record: {legal_name: "Acme Logistics, ...", ...} │
│                                                                   │
│  ✓ 2. Verify documents             completed    2026-04-15 10:15  │
│       → verification_result: complete                              │
│       → decided_by: system                                        │
│                                                                   │
│  ✓ 3. Review application           completed    2026-04-15 10:16  │
│       → decision: approve                                         │
│       → decided_by: agent (confidence: 0.94)                      │
│       → risk_notes: "Established transport company, 12yr history" │
│                                                                   │
│  ● 4. Submit to compliance         waiting      2026-04-15 10:17  │
│       → entity_id: mnx_442                                        │
│       → compliance_status: pending                                 │
│       → waiting for callback since 3d                              │
│       [Manual Override ▼]  [Retry Webhook]  [Skip Step]           │
│                                                                   │
│  ○ 5. Create account                pending                       │
│  ○ 6. Send welcome email            pending                       │
│                                                                   │
│  TIMELINE                                                         │
│  ──●──────●────●──●─────────────────────────────── →              │
│    start  s1   s2 s3  s4 waiting...                               │
│                                                                   │
│  [View Audit Log]  [Cancel Instance]                              │
└──────────────────────────────────────────────────────────────────┘
```

**Key interactions:**

- **Manual override on stuck steps:** Click [Manual Override] → fill in the step's expected outputs manually (e.g., set compliance_status to "approved" if you confirmed it by phone). Records `decided_by: human:{user_id}`.
- **Retry:** Re-execute a failed or timed-out step.
- **Skip:** Mark a step as skipped (with reason). Process advances to the next step.
- **Form steps:** When a step is `waiting_for_input`, the UI shows the form fields for the user to fill in and submit.
- **Approval steps:** Shows approve/reject buttons with optional notes field.
- **Judgment steps (escalated):** Shows the agent's recommendation with confidence score. Human can accept, override, or send back for re-evaluation.

### 7.3 Observe — Process Metrics

The metrics view shows process health — this is where the Theory of Constraints becomes visual.

```
┌──────────────────────────────────────────────────────────────────┐
│  OPENSOP — Metrics                       [Last 30 days ▼]        │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  customer-onboarding                                              │
│                                                                   │
│  Throughput: 8 completed / 30 days                                │
│  Avg cycle time: 6.2 days                                         │
│  In flight: 20 instances                                          │
│                                                                   │
│  STEP BREAKDOWN                                                   │
│  ┌────────────────────────┬────────┬──────────┬────────────────┐ │
│  │ Step                   │ WIP    │ Avg Time │ Conversion     │ │
│  ├────────────────────────┼────────┼──────────┼────────────────┤ │
│  │ 1. Collect info        │ 2      │ 1.2d     │ 85%           │ │
│  │ 2. Verify docs         │ 1      │ 0.1d     │ 92%           │ │
│  │ 3. Review application  │ 0      │ 0.01d    │ 78%           │ │
│  │ 4. Submit compliance   │ 14 ◄◄◄│ 4.8d     │ 40% ◄◄◄      │ │
│  │ 5. Create account      │ 1      │ 0.01d    │ 100%          │ │
│  │ 6. Send welcome        │ 0      │ 0.01d    │ 100%          │ │
│  └────────────────────────┴────────┴──────────┴────────────────┘ │
│                                                                   │
│  ◄◄◄ CONSTRAINT: Step 4 (Submit to compliance)                   │
│  14 instances stuck • 4.8 day avg wait • 40% pass-through        │
│  Top blocker: "Waiting for compliance callback" (12 of 14)       │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  FLOW DIAGRAM                                               │ │
│  │                                                             │ │
│  │  [85%]──►[92%]──►[78%]──►[40%]──►[100%]──►[100%]          │ │
│  │   s1       s2      s3     s4◄◄     s5       s6             │ │
│  │                          ████████                           │ │
│  │                          WIP: 14                            │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  JUDGMENT STATS (step 3: Review application)                      │
│  Agent decisions: 18  •  Human overrides: 3  •  Escalated: 2     │
│  Agent accuracy (vs. human override): 86%                         │
│                                                                   │
│  [Export CSV]  [Post to Slack]  [Set Alert: WIP > threshold]      │
└──────────────────────────────────────────────────────────────────┘
```

**Key features:**

- **Auto-constraint detection.** The platform identifies which step has the highest WIP relative to throughput and flags it. No human analysis needed — TOC is built into the metrics.
- **Alerts.** Set thresholds: "If WIP at step X exceeds N, notify #channel." This is the reporting-agent, but deterministic.
- **Judgment accuracy.** Track how often the LLM's decisions get overridden by humans. This is how you calibrate confidence thresholds over time.
- **Export.** CSV for spreadsheet people. Slack post for team visibility. API for agents.

### 7.4 Process Library

A catalog view of all defined processes. This is the internal "app store" of what the company can do.

```
┌──────────────────────────────────────────────────────────────────┐
│  OPENSOP — Processes                              [+ New Process] │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │  customer-onboarding  v1.0                  [banking]     │   │
│  │  Onboard a new business customer             6 steps      │   │
│  │  Owner: banking-team  •  SLA: 72h  •  20 in flight       │   │
│  │  [Edit]  [View Instances]  [View Metrics]  [Duplicate]    │   │
│  ├───────────────────────────────────────────────────────────┤   │
│  │  send-payment  v1.0                         [banking]     │   │
│  │  Send a cross-border payment USD→MXN         8 steps      │   │
│  │  Owner: banking-team  •  SLA: 24h  •  3 in flight        │   │
│  │  [Edit]  [View Instances]  [View Metrics]  [Duplicate]    │   │
│  ├───────────────────────────────────────────────────────────┤   │
│  │  lead-qualification  v1.0                   [sales]       │   │
│  │  Qualify inbound lead and assign to rep       4 steps     │   │
│  │  Owner: sales-team  •  SLA: 4h  •  5 in flight           │   │
│  │  [Edit]  [View Instances]  [View Metrics]  [Duplicate]    │   │
│  ├───────────────────────────────────────────────────────────┤   │
│  │  content-publication  v1.0                  [marketing]   │   │
│  │  Draft, review, approve and publish content   5 steps     │   │
│  │  Owner: carlos  •  SLA: 48h  •  1 in flight              │   │
│  │  [Edit]  [View Instances]  [View Metrics]  [Duplicate]    │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                   │
│  [Import from YAML]  [Browse Community Templates]                 │
└──────────────────────────────────────────────────────────────────┘
```

**[+ New Process]** opens the Process Designer (§7.1) with a blank canvas.
**[Duplicate]** copies an existing process as a starting point for a new one.
**[Import from YAML]** loads a `.sop.yaml` file directly.
**[Browse Community Templates]** (future) — pull from a public registry of process templates that companies have shared.

### 7.5 UI Tech Stack

| Choice | Rationale |
|--------|-----------|
| **Rails views (Hotwire/Turbo + Stimulus)** | Ships with the engine (no separate frontend deploy). Same stack as the engine. |
| **Tailwind CSS** | Fast to build. Utility-first CSS with strong Rails integration. |
| **ViewComponent** | Encapsulated UI components with Ruby-first ergonomics. |
| **Turbo Frames** | Step cards, instance lists, metrics panels update without full page reloads. |
| **Stimulus controllers** | Drag-and-drop step reorder, form builder interactions, condition builder. |

No React. No separate SPA. The UI is server-rendered Rails with Hotwire for interactivity. One deploy, one codebase, one team.

### 7.6 UI and API are the same thing

This is a critical design principle: **everything the UI does, the API can do.** The UI is a consumer of the same endpoints that agents use.

- Creating a process in the designer → `POST /sop/processes` with the definition
- Submitting a form step → `POST /sop/{name}/{id}/steps/{step}/submit`
- Viewing metrics → `GET /sop/metrics`
- Overriding a judgment → `POST /sop/{name}/{id}/steps/{step}/submit` with `decided_by: human`

The UI adds convenience (visual builder, drag-and-drop, dashboards) but introduces zero functionality that isn't available via API. An agent and a business person have the exact same capabilities — different interfaces, same platform.

---

## 8. What to Build First

### MVP (Week 1-2)

1. **Process definition parser** — load YAML, validate schema, index processes
2. **Instance executor** — start instance, run automated steps, track state
3. **API gateway** — discovery (`GET /sop/`), schema (`GET /sop/{name}/schema`), start (`POST /sop/{name}/start`), status (`GET /sop/{name}/{id}`)
4. **Store** — PostgreSQL tables (sop_processes, sop_instances, sop_steps, sop_events)
5. **One real process** — port `customer-onboarding` as the test case
6. **UI: Process Library + Instance Dashboard** — see all processes, see running instances, view instance detail with step states

### v0.2 (Week 3-4)

7. **UI: Process Designer** — visual builder for defining processes without YAML
8. **Judgment router** — LLM integration for judgment steps
9. **Webhook steps** — outbound calls + callback receiver
10. **Form steps** — UI and API endpoint for human input submission
11. **Event bus** — emit events on state changes, with webhook delivery
12. **Subprocess support** — one process calls another

### v0.3 (Week 5-8)

13. **UI: Metrics view** — step-level WIP, cycle time, conversion, auto-constraint detection
14. **Process composition** — libraries of reusable sub-processes
15. **Agent discovery protocol** — `.well-known/opensop` convention
16. **CLI** — `opensop init`, `opensop validate`, `opensop run`, `opensop deploy`
17. **Alerts** — WIP threshold notifications via Slack/email

---

## 8. Naming & Identity

**Project name:** OpenSOP
**Domain:** opensop.ai
**Tagline:** "Define your processes. Get your API."
**Repo:** `Chosen9115/opensop`
**License:** Apache 2.0 (permissive, enterprise-friendly, patent grant)

**Why "OpenSOP":**
- SOP (Standard Operating Procedure) is the term every business understands
- "Open" signals: open source, open standard, open protocol
- Short, memorable, googleable
- Domain available

---

## 9. What This Changes for a Custom Orchestrator

If a company builds on OpenSOP instead of a bespoke production-line orchestrator, the stack simplifies:

| Before (custom) | After (OpenSOP) |
|-----------------|-----------------|
| Pipeline API (new Rails service) | OpenSOP Engine (runs all process APIs) |
| Unified "pipeline" table | `sop_instances` + `sop_steps` (process state IS the unified view) |
| Custom webhook wiring | OpenSOP event bus + callback system |
| Sub-agent spawning with context | Agents call `/sop/{name}/start` and `/sop/{name}/{id}/steps/{step}/submit` |
| Constraint engine (custom script) | Scheduled process that reads `/sop/metrics` |
| Point-to-point system bridges | Each system is a step executor for shared OpenSOP processes |
| deal_id ↔ member_id mapping | Instance metadata carries both IDs through the process |

The orchestrator becomes an agent that:
1. Reads `/sop/` to see all processes and their instance states
2. Computes the constraint (which process/step has the most stuck instances)
3. Delegates to sub-agents who interact with processes via the standard API
4. Reports to Slack

**The platform does the plumbing. The agent does the thinking.**
