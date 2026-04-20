# OpenSOP — Architecture

How an OpenSOP instance gets from `start` to `completed`. Read this after [`SPEC.md`](../SPEC.md) §3 for the high-level picture; this doc covers the actual call flow inside the Rails app.

---

## Components at a glance

```
┌─────────────────────────────────────────────────────────────────┐
│  HTTP (controllers)                                             │
│  ─────────────────                                              │
│  Sop::*ApplicationController, DiscoveryController,              │
│  ProcessesController, InstancesController, StepsController,     │
│  WebhooksController                                             │
│                                                                 │
│  Ui::* — DashboardController, ProcessesController,              │
│  InstancesController, StepsController                           │
└─────────────────┬───────────────────────────────────────────────┘
                  │ delegates everything to
                  ▼
┌─────────────────────────────────────────────────────────────────┐
│  Engine (app/services/opensop/)                                 │
│                                                                 │
│   DefinitionParser ──┐                                          │
│                      ▼                                          │
│   Registry ──── persists ──→ Sop::Process                       │
│                                                                 │
│   InstanceExecutor ── creates ──→ Sop::Instance + Sop::Step[]   │
│        │                                                        │
│        │  for each step:                                        │
│        │   1. evaluate condition (ConditionEvaluator)           │
│        │   2. resolve inputs (InputResolver)                    │
│        │   3. dispatch (StepExecutor)                           │
│        │   4. write outputs back, advance or pause              │
│        │                                                        │
│        └──→ StepExecutor.for(type) → StepExecutors::*           │
└─────────────────┬───────────────────────────────────────────────┘
                  │ writes
                  ▼
┌─────────────────────────────────────────────────────────────────┐
│  Store (PostgreSQL — UUID PKs, JSONB)                           │
│  sop_processes, sop_instances, sop_steps, sop_events,           │
│  sop_callbacks                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Loading a definition

```
processes/examples/customer-onboarding.sop.yaml
            │
            ▼
Opensop::Registry.load_file(path)
            │
            ▼
Opensop::DefinitionParser.call(yaml_string)
            │  validates structure, step types, references
            ▼
Sop::Process.upsert(name, version, definition: hash)
```

`Registry.load_all` walks `processes/**.sop.yaml`, parses each, and upserts by `(name, version)`. Idempotent. The seed task `db/seeds.rb` calls it on `bin/rails db:seed`.

If the YAML changes but the version stays the same, the row is updated in place. If you bump the version, a new row is added; existing instances keep referring to their snapshotted `process_version` and will still resolve against the older definition (stored in their `Sop::Process` row).

---

## Starting an instance

```ruby
Opensop::InstanceExecutor.start(process: ..., inputs: { ... }, metadata: { ... })
```

What happens, in order:

1. **Validate inputs.** `process.definition['process']['inputs']` declares required fields and types. Missing or wrong-type → `Opensop::InstanceExecutor::InvalidInputs`.
2. **Create `Sop::Instance`** in `pending`, snapshotting `process_name` and `process_version` (so the instance survives if the process is later updated/archived).
3. **Create `Sop::Step` rows** — one per step in the definition, with `state: pending`, correct `position`, and the static fields (`step_id`, `step_name`, `step_type`).
4. **Emit `instance.started`** event.
5. **Transition instance to `running`**, set `started_at`.
6. **Call `advance!(instance)`** to try to make progress.

`start` returns the instance. The caller can inspect `instance.state` and `instance.steps` immediately.

---

## Advancing — the heart of it

```
advance!(instance)
      │
      ▼
find next step where state == pending  (ordered by position)
      │
      ├─ none left & last terminal? ────→ finalize_instance!
      │                                       │
      │                                       └─ resolve process outputs
      │                                          (with required_if)
      │                                          → instance.completed
      ▼
evaluate step.condition (if any)
      │
      ├─ false? ───→ mark step :skipped, emit event, recurse
      │
      ▼
mark step :active/:running, started_at = now
      │
      ▼
resolve step.inputs via InputResolver
      │
      ├─ raises UnresolvedReference? ──→ step :failed, instance :failed
      │
      ▼
dispatch to StepExecutor.for(step.type).call(step, instance, step_definition)
      │
      ├─ returns { outputs: ... } ──→ validate outputs against schema
      │                                  │
      │                                  ├─ valid? → step :completed, recurse
      │                                  └─ invalid? → step :failed, instance :failed
      │
      ├─ returns { waiting: sub_state } ──→ step :active/:<sub_state>,
      │                                       emit waiting event, STOP
      │
      └─ raises ──→ step :failed (with error msg), instance :failed
```

Everything inside `advance!` runs in a single transaction. Events are written as part of the same transaction so the audit log can never lag.

---

## Submitting a step from outside (form, judgment, approval, webhook callback)

```ruby
Opensop::InstanceExecutor.submit_step(
  instance: ...,
  step_id: "...",
  outputs: { ... },
  decided_by: "human:carlos"
)
```

1. Find the step. Must be in a "submittable" sub_state: `waiting_for_input`, `waiting_for_approval`, `escalated`, `waiting_for_callback`, or in `failed` (for retry).
2. Validate the submitted outputs against the step's declared output schema (honoring `required_if`).
3. Write outputs, set `decided_by`, mark step `completed`. Emit `step.completed`.
4. Call `advance!(instance)` to continue.

This is what powers:

- The admin UI form on a `waiting_for_input` step.
- An agent (or human) calling `POST /sop/:name/:id/steps/:step_id/submit`.
- The webhook receiver — it submits the callback payload as the step's outputs.

---

## Reference resolution

`Opensop::InputResolver` handles `from:` references in step inputs and process outputs.

| Reference | Resolves to |
|-----------|-------------|
| `process.inputs.<name>` | `instance.inputs[name]` |
| `steps.<step_id>.outputs.<name>` | The named output of a completed step on the same instance |
| `env.<VAR>` | `ENV[VAR]` |
| `instance.<field>` | Direct columns first (`id`, `started_at`), then `instance.metadata[field]` |

Unresolved references raise `Opensop::InputResolver::UnresolvedReference` — UNLESS the field carries a `required_if:` (in which case the resolver returns `nil` and the gating logic decides whether to drop the field).

---

## `required_if` — two-pass output resolution

`Opensop::InstanceExecutor#resolve_process_outputs` does this for the process-level `outputs:` block:

1. **Pass 1:** Resolve every output's `from:` (or literal `value:`) into a scratch hash. `UnresolvedReference` → `nil` for `required_if`-gated fields, raise otherwise.
2. **Pass 2:** For each field with `required_if:`, evaluate the condition via `Opensop::ConditionEvaluator.new(instance: ..., extra: scratch).call(expr)`. If the condition is **false**, delete the key from the final outputs hash.

The same gating runs in `validate_outputs!` for step-level outputs when `submit_step` is called.

The `extra:` hash lets `required_if` reference sibling outputs by bare name (e.g. `"status == 'rejected'"` resolves `status` against the just-resolved scratch outputs).

---

## ConditionEvaluator — the safe expression layer

`Opensop::ConditionEvaluator` is a tiny recursive-descent parser. It supports:

- Literals: numbers, single/double-quoted strings, `true`, `false`, `nil`
- References: any valid `InputResolver` path (`process.inputs.x`, `steps.y.outputs.z`, `env.X`, `instance.<f>`), plus bare identifiers (resolved against `extra:`)
- Comparison: `==`, `!=`, `>`, `>=`, `<`, `<=`
- Boolean: `&&`, `||`, `!`
- Parentheses

It does **not** support method calls, interpolation, backticks, or anything resembling executable code. There is **no `eval`** anywhere in the engine. Trying to evaluate `"system('rm -rf /')"` raises `InvalidExpression`.

---

## Step execution protocol (automated steps)

From [SPEC §6.3](../SPEC.md#63-step-execution-model). `Opensop::StepExecutors::Automated`:

```
ENGINE                                   SCRIPT
  │                                        │
  │ resolve inputs                         │
  │                                        │
  │ Open3.capture3(script_path, stdin: JSON.dump(inputs))
  ├───────────────────────────────────────►│
  │                                        │ JSON.parse(STDIN.read)
  │                                        │ ...do work...
  │                                        │ puts JSON.dump(outputs)
  │◄───────────────────────────────────────┤
  │ JSON.parse(stdout)                     │ exit 0
  │                                        │
  │ validate against step output schema    │
  │ persist                                │
  │ recurse via advance!                   │
```

Scripts can be in any language with a JSON-capable stdlib. The engine detects nothing — it just runs the file at `run:` (path resolved relative to `Rails.root.join('processes')`).

Failure modes (all → step `failed`, instance `failed`, error string captured):

- Script not found
- Script exits non-zero
- Script stdout is not valid JSON
- Output validation fails

Retry config (`retry.max`, `retry.backoff`) is parsed and the `attempt` column exists, but auto-retry is **not yet implemented**. A failed automated step needs manual retry today (which is also not yet implemented as a UI action).

---

## Webhook step — current behavior

```
Engine reaches a webhook step
        │
        ▼
Opensop::StepExecutors::Webhook.call
        │
        │ Creates a Sop::Callback row with:
        │   callback_path = "/sop/webhooks/<uuid>"  (auto-generated)
        │   step_id, instance_id
        │   expires_at (parsed from poll_timeout, e.g. "7d")
        │
        ▼
Returns { waiting: "waiting_for_callback" }
        │
        ▼
Step is paused. Engine stops advancing this instance.

(Nothing is sent outbound. The third party must already know the callback URL.)
```

When the third party POSTs:

```
POST /sop/webhooks/<uuid>  body: {entity_id: "mnx_442", compliance_status: "approved"}
        │
        ▼
Sop::WebhooksController#receive
        │
        │ Find Sop::Callback by callback_path. 404 if missing, 409 if already received.
        │ Persist payload to callback.response, mark callback :received.
        │
        │ Build merged_outputs:
        │   if payload.is_a?(Hash) → step.outputs.merge(payload.deep_stringify_keys)
        │   else                   → step.outputs.merge("webhook_response" => payload)
        │
        ▼
Opensop::InstanceExecutor.submit_step(outputs: merged_outputs)
        │
        │ Validates outputs, marks step :completed, calls advance!
        │
        ▼
200 {status: "received"}

(If validation fails: 422 {error: "invalid_callback_payload"} —
 callback row is still saved with the raw payload. No data loss.)
```

To add **outbound** webhook calls (v0.2), wrap the HTTParty/Net::HTTP call in an ActiveJob queued from the executor. Don't block `advance!`.

---

## Events — the audit / integration surface

Every state transition writes to `sop_events` in the same transaction as the state change:

| Event type | When |
|------------|------|
| `instance.started` | After `start` creates the instance |
| `instance.completed` | After all steps terminal and outputs resolved |
| `instance.failed` | After a step failure propagates |
| `instance.cancelled` | After `cancel!` |
| `step.started` | When the step transitions `pending` → `active` |
| `step.completed` | When outputs are written and validated |
| `step.failed` | On exception or invalid outputs |
| `step.skipped` | When `condition:` evaluates to false |
| `step.waiting_for_input` | Form step paused |
| `step.waiting_for_callback` | Webhook step paused |
| `step.waiting_for_approval` | Approval step paused |
| `step.escalated` | Judgment step paused (no LLM yet) |
| `step.subprocess_pending` | Subprocess step paused (stub) |

Each event has `actor` (`system` | `agent` | `human:<id>`) and a JSONB `data` payload. The audit log section on the instance detail page reads from this table.

To add a new integration target (e.g. publishing to a message bus, writing to an external log, sending to Slack), the cleanest seam is an `after_create` callback on `Sop::Event` or a polling job that streams new events. Don't tap into `InstanceExecutor` directly.

---

## Authentication

Single-token API auth. The header `X-SOP-Token` must match `ENV['OPENSOP_API_TOKEN']`. If the env var is unset, the API is open and a `Rails.logger.warn` fires on first request.

`POST /sop/webhooks/:callback_id` is exempt — third parties don't have an API token. (No HMAC verification yet — that's a v0.2 hardening item.)

The admin UI has no auth at all yet. Self-host on a private network or behind a reverse proxy with auth.

---

## Where the engine ends and the UI begins

The hard rule: **everything the UI can do, the API can do.** The UI is just an HTTP client of the same controllers (it shares the engine, not the JSON serialization).

- `Sop::*` controllers render JSON, never HTML.
- `Ui::*` controllers render HTML, never JSON, and call the engine the same way the API controllers do (`Opensop::InstanceExecutor.submit_step` etc.).
- Both surfaces produce the same `Sop::Event` audit trail.

This means an agent and a human can't diverge in capability. If you add a feature, expose it on both surfaces.
