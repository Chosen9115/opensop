# OpenSOP Agent Implementation Guide

**Audience:** an AI agent being asked to author, port, or extend business processes on OpenSOP. You have been given this document plus the target repository. Everything you need to produce a valid `.sop.yaml` and wire it up is here.

**Companion docs:** [`SPEC.md`](../SPEC.md) (formal format spec), [`API.md`](./API.md) (runtime endpoints), [`processes/examples/`](../processes/examples/) (working references).

---

## 1. What you are being asked to do

Your work falls into one of three shapes. Identify which one, then jump to the matching playbook at the end of this doc.

| Task shape | Playbook |
|---|---|
| "Here's a process description — write it as OpenSOP YAML" | **Playbook A: Author from scratch** |
| "Here's our existing Rails state machine / controller flow — port it to OpenSOP" | **Playbook B: Port an existing workflow** |
| "Integrate this new provider (compliance, KYC, payments) as a step" | **Playbook C: Add a webhook integration** |

Always:

1. **Read the user's description twice.** List the concrete artifacts at each boundary: what comes in, what goes out, what humans decide, what systems integrate, what happens if a step fails.
2. **Match each boundary to a step type** (§3 below). Don't invent step types. The canonical eight are `form`, `automated`, `judgment`, `approval`, `webhook`, `subprocess`, `notification`, `wait`.
3. **Write the YAML in one pass**, then **self-check against §5** before claiming you're done.

---

## 2. The OpenSOP 0.1 format in one page

Every process is a single YAML file with this top-level shape:

```yaml
opensop: "0.1"                 # format version — always "0.1"

process:
  name: snake-or-kebab-case    # must match /^[a-z0-9][a-z0-9_-]*$/
  version: "1.0"               # QUOTE IT — unquoted 1.0 is parsed as a float
  description: "One-sentence description of what this process does."
  owner: "team-name"           # free-form; shown in UI
  tags: [tag1, tag2]           # free-form; used for filtering

  trigger:
    type: api                  # only "api" is implemented in v0.1

  inputs:                      # what the caller must / may provide to POST /start
    - name: company_name
      type: string
      required: true
    - name: country
      type: enum
      values: [US, MX, CA]
      required: true
    - name: deal_id
      type: string
      description: "External CRM reference"
      # optional — no `required: true`

  outputs:                     # what the process emits on completion
    - name: account_id
      type: string
      from: steps.create-account.outputs.account_id
    - name: rejection_reason
      type: string
      from: steps.review.outputs.rejection_reason
      required_if: "status == 'rejected'"      # condition expression

  steps:                       # ordered list — execution follows this order
    - id: collect-info         # must match /^[a-z0-9][a-z0-9_-]*$/, unique within the process
      name: "Collect business information"
      type: form
      description: "Gather company details"
      inputs:                  # values resolved at step start from process inputs / earlier steps
        - name: company_name
          from: process.inputs.company_name
      outputs:                 # keys the step must produce
        - name: business_record
          type: object
          schema:
            legal_name: string
            rfc: string
      condition: "..."         # optional — if evaluates false, step is skipped
      timeout: 7d              # optional — parsed but not enforced in v0.1
      on_timeout: notify-and-wait

    - id: verify-docs
      type: automated
      run: ./examples/steps/verify-documents.rb   # path relative to processes/
      inputs:
        - name: business_record
          from: steps.collect-info.outputs.business_record
      outputs:
        - name: verification_result
          type: enum
          values: [complete, incomplete]
      retry:
        max: 3
        backoff: exponential   # parsed but auto-retry not implemented yet

    # ... more steps ...

  on_error:                    # optional
    notify:
      channel: slack
      target: "#ops-alerts"

  sla:
    target: 72h
    warning: 48h
```

### Field reference types

Every `inputs[*]` and `outputs[*]` entry has `name` and `type`. Allowed `type` values:

| Type | Notes |
|---|---|
| `string` | Also accepts `format: email` or `format: uri` for light validation |
| `number` | Integer or float |
| `boolean` | `true` / `false` |
| `enum` | Must be accompanied by `values: [a, b, c]` |
| `object` | Accepts a `schema:` hash mapping keys to type strings |
| `string[]` / `number[]` / `object[]` | Arrays of primitives or objects |

Fields can be marked `required: true`. On outputs, `required_if: "<condition>"` makes them conditionally required.

### The `from:` resolver

Any step input (and process output) can reference values produced earlier. Resolution syntax:

| Reference | Resolves to |
|---|---|
| `process.inputs.<name>` | A value the caller passed to `/start` |
| `steps.<step-id>.outputs.<name>` | A value produced by a prior step |
| `instance.id` / `instance.started_at` / `instance.metadata.<key>` | Runtime instance attributes |
| `env.<VAR_NAME>` | A process environment variable |

If a `from:` cannot resolve, the engine raises `unresolved_reference` (422). This is a YAML bug, not a user error.

### The condition expression language

`condition:`, `required_if:`, and similar fields accept a tiny expression language. **No `eval`.** Supports:

- Operators: `== != > >= < <= && || !`
- Parentheses
- Literals: numbers, quoted strings (`'foo'` or `"foo"`), `true`, `false`, `null`
- References: same syntax as `from:` — `steps.x.outputs.y`, `process.inputs.z`, etc.
- Bare identifiers (for `required_if` only) — resolve against the step's own outputs: `required_if: "status == 'rejected'"` looks up `status` in the current step's outputs.

Examples:

```yaml
condition: "steps.review.outputs.decision == 'approve'"
condition: "process.inputs.country == 'US' && steps.verify.outputs.score > 0.8"
required_if: "verification_result != 'complete'"
```

---

## 3. Step-type reference

Pick one per boundary. If you find yourself reaching for a type that isn't listed, stop — you're probably over-engineering.

### `form` — collect data from a human or agent

The engine pauses the instance at `sub_state=waiting_for_input`. A caller (human via UI, agent via API) submits the step's declared `outputs` via `POST /sop/:name/:id/steps/:step_id/submit`.

```yaml
- id: collect-business-info
  type: form
  name: "Collect business information"
  outputs:
    - name: legal_name
      type: string
      required: true
    - name: annual_revenue
      type: number
```

**Use for:** every boundary where a human (or delegated agent) provides structured data. The KYB form, the "enter payment amount" field, the content brief.

### `automated` — run a script

The engine spawns a script, pipes `inputs` as JSON on stdin, reads outputs as JSON from stdout. Works for any language with stdlib JSON support.

```yaml
- id: score-lead
  type: automated
  run: ./examples/steps/score-lead.rb    # path relative to processes/, not to this YAML
  inputs:
    - name: budget
      from: steps.collect-context.outputs.budget
  outputs:
    - name: score
      type: number
    - name: qualified
      type: boolean
```

The script must:
- Read JSON from stdin → a hash matching the declared `inputs`
- Write JSON to stdout → a hash matching the declared `outputs`
- Exit 0 on success, non-zero on failure (stderr captured as the error)

**Use for:** deterministic computation. Scoring, validation, string manipulation, lookups that don't need a human.

### `judgment` — decision with confidence

The engine pauses at `sub_state=escalated`. A caller (LLM or human) submits a decision + confidence. If `confidence < judgment.confidence_threshold`, the engine can escalate (v0.1: just stays in `escalated` — submit manually).

```yaml
- id: review-application
  type: judgment
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
  judgment:
    allow_agent: true
    require_human_review: false
    confidence_threshold: 0.9
    escalation: manual
```

**Use for:** subjective decisions where the right answer isn't always deterministic. Loan approvals, content moderation, risk assessment.

### `approval` — binary human gate

Simpler than `judgment`. Just waits for an approve/reject from a named role.

```yaml
- id: approve-refund
  type: approval
  approval:
    approver_role: "ops-lead"
    reason_required_on_reject: true
  outputs:
    - name: approved
      type: boolean
    - name: reason
      type: string
      required_if: "approved == false"
```

**Use for:** policy gates that don't need discussion. Refund over $500, schema change approval, publishing a template.

### `webhook` — outbound integration with callback

Registers a callback URL, pauses at `sub_state=waiting_for_callback`. The third party (compliance provider, KYC vendor, etc.) POSTs results to that URL; the engine merges them into the step's outputs and continues.

```yaml
- id: submit-to-compliance
  type: webhook
  condition: "steps.review-application.outputs.decision == 'approve'"
  inputs:
    - name: business_record
      from: steps.collect-info.outputs.business_record
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
    body_template: ./examples/steps/compliance-payload.json
    response_mode: callback
    callback_path: /sop/webhooks/compliance
    poll_timeout: 7d
```

**v0.1 limitation:** the engine does NOT yet make the outbound HTTP call. It creates the callback URL and waits. You're expected to pass the callback URL to the provider via whatever mechanism they support (webhook config in their dashboard, API registration, etc.). The inbound callback receiver at `POST /sop/webhooks/:callback_id` is fully wired.

**Use for:** third-party integrations with async responses. Compliance providers, KYC vendors, payment processors, any API with "we'll call you back when we're done."

### `subprocess` — start a child process

Starts another OpenSOP process as a child. The parent pauses at `sub_state=waiting_for_subprocess` until the child reaches a terminal state.

```yaml
- id: run-compliance
  type: subprocess
  subprocess:
    process: compliance-submission
    version: "1.0"
    inputs:
      - name: business_record
        from: steps.collect-info.outputs.business_record
  outputs:
    - name: compliance_status
      from: subprocess.outputs.compliance_status
```

**v0.1 limitation:** stubbed — parent pauses, but no child is actually started. Submit manually to proceed.

**Use for:** reusing a process across multiple parent processes. A shared compliance submission, a shared payment routing process.

### `notification` — fire-and-forget message

Sends an email, Slack message, SMS, etc. The engine does NOT wait for delivery confirmation.

```yaml
- id: send-welcome
  type: notification
  inputs:
    - name: contact_email
      from: process.inputs.contact_email
  outputs:
    - name: email_sent
      type: boolean
```

**v0.1 implementation:** stubbed — returns `{ "notified": true }` instantly. No actual send. Wire up the real send in `app/services/opensop/step_executors/notification.rb` when you need it.

**Use for:** welcome emails, Slack notifications to ops channels, SMS alerts.

### `wait` — pause

Pause the process for a duration or until a condition becomes true.

```yaml
- id: cool-off
  type: wait
  wait:
    seconds: 86400               # 24 hours
    # OR
    until: "steps.callback.outputs.received == true"
```

**v0.1 limitation:** `seconds:` returns immediately (no real timer). `until:` pauses but has no polling loop — submit manually to proceed.

**Use for:** cool-off periods, scheduled follow-ups, delayed escalations.

---

## 4. How the engine runs your YAML

Knowing this helps you author correctly the first time.

1. **Load.** `Opensop::Registry.load_all` recursively globs `processes/**/*.sop.yaml`, validates each against `Opensop::DefinitionParser`, upserts into `sop_processes` (name + version as primary key).
2. **Start.** `POST /sop/:name/start` validates inputs, creates a `sop_instance`, creates one `sop_step` per step in the YAML (all in `pending`), then calls `InstanceExecutor.advance!`.
3. **Advance.** The executor walks steps in order. For each:
   - Evaluate `condition:` if present. If false → skip.
   - Resolve `inputs:` via the `from:` resolver.
   - Dispatch to the step executor for the type (`Opensop::StepExecutors::<Type>`).
   - **Blocking types** (`form`, `judgment`, `approval`, `webhook`, `subprocess`, `wait` w/ `until:`) → step stays `active` with a `sub_state`. The engine stops advancing until the block clears.
   - **Non-blocking types** (`automated`, `notification`, `wait` w/ `seconds:`) → execute synchronously, mark `completed`, continue to the next step.
4. **Submit.** When a human/agent/webhook submits outputs via the API, the engine validates them, marks the step `completed`, and calls `advance!` again to run the next batch of non-blocking steps.
5. **Complete.** When there are no more steps, the executor resolves the process-level `outputs:` (via `from:` references) and marks the instance `completed`.

Key property: **you can always pause-resume.** Any step type that waits on humans or third parties is idempotent — submitting the same outputs twice is safe (the engine rejects the second submit with `step_not_submittable`).

---

## 5. Self-check before you're done

Run through this rubric before claiming a YAML is ready. These are the checks the engine itself runs — failing any of them means your YAML will be rejected at load.

### Syntax

- [ ] `opensop: "0.1"` at the top (with the quotes).
- [ ] `version:` is a quoted string, not a bare `1.0` (YAML parses that as a float).
- [ ] Every `name:` and `id:` matches `^[a-z0-9][a-z0-9_-]*$`.
- [ ] No tabs in indentation (YAML requires spaces).

### Structure

- [ ] `process.name`, `process.version`, `process.steps` are all present.
- [ ] `steps:` is an ordered list; step `id`s are unique within the process.
- [ ] Every step has `id` and `type`.
- [ ] `type` is one of: `form`, `automated`, `judgment`, `approval`, `webhook`, `subprocess`, `notification`, `wait`.

### Inputs / outputs

- [ ] Every input referenced by a `from: process.inputs.X` exists in `process.inputs`.
- [ ] Every `from: steps.Y.outputs.Z` refers to a step that appears *earlier in the step list* (forward references fail).
- [ ] Every `automated` step with a `run:` path has the script file at the resolved location (`processes/<run-path>`, because `run:` is relative to `processes/`, not the YAML).
- [ ] Every `form`, `judgment`, `approval`, `webhook` step declares `outputs:` (the engine needs to know what shape to validate against).
- [ ] Enum types have `values: [...]` populated.

### Conditions

- [ ] Every `condition:` / `required_if:` expression uses only the allowed operators (§2). No `eval`-like constructs.
- [ ] Referenced fields in conditions exist (same rules as `from:` above).

### Ordering

- [ ] The first blocking step (typically a `form`) is reachable from start — no `condition:` blocks it all the time.
- [ ] Any step referenced by a later step's `from:` is upstream of that step.
- [ ] `process.outputs[*].from:` references steps that will exist at completion time.

If any box above is unchecked, fix before submitting. Load it with `bin/rails opensop:load_processes` to get the engine's exact error message.

---

## 6. Common mistakes

Real mistakes observed when agents (and humans) author processes. Each has a fast recognition heuristic.

### "My `run:` path doesn't work"

**Symptom:** `script not found at /path/processes/examples/steps/script.rb`.

**Cause:** `run:` paths are resolved relative to `processes/`, not relative to the YAML file. A YAML at `processes/examples/my-process.sop.yaml` must reference its script as `./examples/steps/my-script.rb`, not `./steps/my-script.rb`.

See [`processes/README.md`](../processes/README.md).

### "My condition is always true / always false"

**Symptom:** steps skip that shouldn't, or run that shouldn't.

**Cause:** the condition references a field that doesn't exist in outputs — the expression evaluator treats missing identifiers as `nil`, which compares `false` to almost everything. Check the exact output key name on the upstream step.

### "YAML is loading but `/start` returns `invalid_inputs`"

**Symptom:** caller gets 422 with `"invalid_inputs"` even though the body looks right.

**Cause:** the input field has `required: true` but the JSON body uses a different key name (case sensitivity, `-` vs `_`). The input name in YAML must match the JSON body key exactly.

### "Webhook step never advances"

**Symptom:** step stuck at `sub_state=waiting_for_callback` forever.

**Causes:**
1. The third party wasn't told about the callback URL. The engine doesn't auto-register — for v0.1, pass the URL to the provider out-of-band (their dashboard, a registration API, whatever).
2. The third party posted to the wrong URL. Check `callback_path` in the step definition matches what the provider hit.
3. The provider's payload keys don't match the step's declared `outputs:` (returns 422, keeps the step open). Check the provider's response schema.

### "`from:` resolution error"

**Symptom:** `unresolved_reference` error at runtime.

**Cause:** the referenced step completed but its output hash has a different key than what `from:` expects. Your YAML declares `outputs: [{name: account_id}]` but the script wrote `{accountId: "..."}` — string keys, exact match required.

---

## 7. Playbooks

Execute one of these based on what you were asked for.

---

### Playbook A: Author a process from a description

**Input:** a prose description of a workflow.

**Steps:**

1. **List the boundaries.** Read the description and list each point where data enters, leaves, or waits. Each boundary is a step. Typical boundaries:
   - "User fills in X" → `form`
   - "System validates/computes Y" → `automated`
   - "Human decides approve/reject" → `approval` or `judgment`
   - "External provider does Z" → `webhook`
   - "Email/Slack notification" → `notification`
   - "Wait N days / until callback" → `wait`

2. **List process inputs.** What does the caller need to provide at `/start`? These are values that cannot be computed — IDs, names, choices.

3. **List process outputs.** What does the process emit at completion? These are almost always `from:` references to terminal step outputs.

4. **Order the steps.** Dependencies must flow forward. If step 3 needs data from step 1, put them in order; never reference a later step.

5. **Write the YAML** top-down: `opensop` → `process.name/version/description` → `inputs` → `outputs` → `steps` → `tags`.

6. **Run the self-check in §5.**

7. **Save to `processes/<your-org>/<process-name>.sop.yaml`** (or `processes/examples/...` if it's a public example).

8. **Load and test:**

   ```bash
   bin/rails opensop:load_processes
   curl -X POST http://localhost:3000/sop/<process-name>/start \
     -H "Content-Type: application/json" \
     -d '{"inputs": {...}}'
   ```

9. **Iterate.** If you get `invalid_inputs` or `unresolved_reference`, fix the YAML and reload. The engine will reload definitions (upsert by `name + version`) — no need to restart the server.

---

### Playbook B: Port an existing Rails state machine / workflow

**Input:** existing code that implements a workflow. Typically a Rails state machine (AASM, state_machines gem, or hand-rolled enum), a controller flow, or service objects.

**Steps:**

1. **Map the states.** List every state the entity can be in (e.g. `draft → submitted → reviewing → approved → provisioning → active`).

2. **Map each state transition to a step type.** Transitions triggered by:
   - User action (form submit, click approve) → `form`, `approval`, or `judgment`
   - Async computation or DB work → `automated`
   - External HTTP call with callback → `webhook`
   - Email/SMS/Slack → `notification`
   - Scheduled delay → `wait`
   - Calling another workflow → `subprocess`

3. **Extract the state-machine's guards as `condition:` expressions.** If the current code has `can_approve? if documents_verified? && amount < 10_000`, that becomes `condition: "steps.verify.outputs.verification_result == 'complete' && process.inputs.amount < 10000"` on the approval step.

4. **Extract side effects into step outputs.** If the current code does `create_account!(customer)` in the `activating` state, the outputs of the corresponding `automated` step are whatever `create_account!` returns — `account_id`, `member_id`, etc.

5. **Extract the final entity state as process outputs.** If the workflow ends with a `customer.status = approved` and an `account_id`, the process outputs are `status` and `account_id`, both `from:` references to the relevant step outputs.

6. **Wire side-effect scripts.** For each `automated` step, write the script that does the actual work. Move logic from the Rails service object into the script (or have the script invoke the service object via a Rails runner).

7. **Leave the old code alone initially.** Run both systems in parallel. Start an OpenSOP instance for new records, keep the old state machine for in-flight ones. Cut over when stable.

8. **Run the self-check in §5.**

**Worked example — porting a customer onboarding state machine:**

Existing Rails code:

```ruby
class Customer < ApplicationRecord
  # State machine with: pending → verifying_docs → reviewing → submitting_to_compliance →
  #                    creating_account → welcoming → active
  #
  # Transitions triggered by:
  #  - pending → verifying_docs: when CustomerController#submit_application runs
  #  - verifying_docs → reviewing: automatic after DocumentVerifier job
  #  - reviewing → submitting: when an ops lead clicks "approve"
  #  - submitting → creating_account: on Monex callback (webhook)
  #  - creating_account → welcoming: automatic after BankingService.create
  #  - welcoming → active: after WelcomeMailer sends
end
```

OpenSOP port:

```yaml
opensop: "0.1"
process:
  name: customer-onboarding
  version: "1.0"
  inputs:
    - name: company_name
      type: string
      required: true
    - name: contact_email
      type: string
      format: email
      required: true
  outputs:
    - name: account_id
      from: steps.create-account.outputs.account_id
    - name: status
      from: steps.review.outputs.decision
  steps:
    - id: collect-info
      type: form
      outputs:
        - { name: business_record, type: object, schema: { legal_name: string, rfc: string } }
    - id: verify-docs
      type: automated
      run: ./coba/steps/verify-documents.rb
      inputs: [{ name: business_record, from: steps.collect-info.outputs.business_record }]
      outputs: [{ name: verification_result, type: enum, values: [complete, incomplete] }]
    - id: review
      type: judgment
      inputs: [{ name: business_record, from: steps.collect-info.outputs.business_record }]
      outputs: [{ name: decision, type: enum, values: [approve, reject] }]
    - id: submit-to-compliance
      type: webhook
      condition: "steps.review.outputs.decision == 'approve'"
      webhook:
        method: POST
        url: "${COMPLIANCE_URL}/entities"
        response_mode: callback
        callback_path: /sop/webhooks/compliance
      outputs:
        - { name: entity_id, type: string }
        - { name: compliance_status, type: enum, values: [approved, rejected] }
    - id: create-account
      type: automated
      condition: "steps.submit-to-compliance.outputs.compliance_status == 'approved'"
      run: ./coba/steps/create-account.rb
      outputs: [{ name: account_id, type: string }]
    - id: send-welcome
      type: notification
      inputs: [{ name: contact_email, from: process.inputs.contact_email }]
```

Note how each state transition maps cleanly to a step type, and each `condition:` encodes a guard that used to live in Ruby.

---

### Playbook C: Add a new webhook integration (e.g. second compliance provider)

**Input:** an existing process that has a `webhook` step for one provider. You need to add a second provider (alternate compliance vendor, backup KYC, geo-specific routing) without disrupting the first.

**Approach:** add a new `webhook` step with a `condition:` that routes traffic. Both providers stay supported; the condition decides which runs.

**Steps:**

1. **Identify the routing key.** What determines which provider to use? Usually an input (`country`, `customer_tier`) or a prior step output (`risk_score`).

2. **Add a second `webhook` step.** Copy the existing one, change the `id`, `url`, `callback_path`, and add a `condition:` that inverts (or partitions) the first provider's condition.

3. **Normalize outputs.** The two providers must produce the same `outputs:` shape — otherwise downstream steps that depend on `steps.<provider>.outputs.entity_id` break. Two options:
   - **A (preferred):** make the two webhook steps produce identical output schemas. Add `from:` references in subsequent steps that tolerate either (a small `automated` aggregator step: `entity_id: steps.provider-a.outputs.entity_id || steps.provider-b.outputs.entity_id`).
   - **B:** make the next step reference whichever provider ran, via a `condition:`-gated transformation step.

4. **Add the new provider's callback URL to their dashboard/API** the same way you did for the first.

5. **Test both paths.** Start an instance that triggers provider A, then one that triggers provider B. Verify both complete.

**Worked example — adding a second compliance provider:**

Before (single provider):

```yaml
- id: submit-to-compliance
  type: webhook
  webhook:
    method: POST
    url: "${PROVIDER_A_URL}/entities"
    callback_path: /sop/webhooks/provider-a
    response_mode: callback
  outputs:
    - { name: entity_id, type: string }
    - { name: compliance_status, type: enum, values: [approved, rejected] }
```

After (two providers, routed by country):

```yaml
# US customers go to Provider A
- id: submit-to-provider-a
  type: webhook
  condition: "process.inputs.country == 'US'"
  webhook:
    method: POST
    url: "${PROVIDER_A_URL}/entities"
    callback_path: /sop/webhooks/provider-a
    response_mode: callback
  outputs:
    - { name: entity_id, type: string }
    - { name: compliance_status, type: enum, values: [approved, rejected] }

# MX / everyone else goes to Provider B
- id: submit-to-provider-b
  type: webhook
  condition: "process.inputs.country != 'US'"
  webhook:
    method: POST
    url: "${PROVIDER_B_URL}/onboarding/submit"
    callback_path: /sop/webhooks/provider-b
    response_mode: callback
  outputs:
    - { name: entity_id, type: string }            # note: same name as provider-a
    - { name: compliance_status, type: enum, values: [approved, rejected] }

# Aggregator — picks whichever ran. Downstream steps reference THIS step.
- id: resolve-compliance
  type: automated
  run: ./coba/steps/resolve-compliance.rb
  inputs:
    - { name: provider_a_result, from: steps.submit-to-provider-a.outputs.entity_id }
    - { name: provider_b_result, from: steps.submit-to-provider-b.outputs.entity_id }
    - { name: provider_a_status, from: steps.submit-to-provider-a.outputs.compliance_status }
    - { name: provider_b_status, from: steps.submit-to-provider-b.outputs.compliance_status }
  outputs:
    - { name: entity_id, type: string }
    - { name: compliance_status, type: enum, values: [approved, rejected] }
```

`resolve-compliance.rb` is a trivial script that picks whichever input is non-null.

**Key property:** the existing `create-account` step doesn't need to change. It still references `steps.submit-to-compliance.outputs.entity_id`... wait, no — now it needs to reference `steps.resolve-compliance.outputs.entity_id`. That's the one downstream change. Make it, and the rest of the process continues to work.

---

## 8. After the YAML: testing end-to-end

Once your YAML loads without error, exercise it:

```bash
# 1. Confirm it loaded
bin/rails opensop:load_processes
# → should list your process

# 2. Confirm it appears in discovery
curl http://localhost:3000/sop/ | jq '.processes[] | select(.name == "<your-name>")'

# 3. Start an instance with real inputs
curl -X POST http://localhost:3000/sop/<your-name>/start \
  -H "Content-Type: application/json" \
  -d '{"inputs": { "...": "..." }}'
# → capture the instance id

# 4. Submit each human-gated step in order
curl -X POST http://localhost:3000/sop/<your-name>/<id>/steps/<step-id>/submit \
  -H "Content-Type: application/json" \
  -d '{"outputs": { "...": "..." }}'

# 5. Verify final state
curl http://localhost:3000/sop/<your-name>/<id>
# → instance.state should be "completed"
# → instance.outputs should contain your declared process outputs
```

If any step fails, fetch the instance state — the `error` field on both the instance and the individual step will have the exact message.

---

## 9. When to ask for help

Stop and report back to your requester (don't keep trying) if:

- A step's behavior needs a step type that isn't in the eight listed. Don't invent types.
- A condition needs operators beyond the basic set (regex, arithmetic, function calls). Propose adding them to the engine rather than working around.
- The prose description is ambiguous about a boundary (is this a `form` or an `approval`?). One clarifying question is cheaper than a wrong guess.
- The process requires behavior that cannot be expressed as a DAG of steps (loops, dynamic step count, recursive subprocess spawning). This is an architectural mismatch — flag it.

---

## Appendix: Minimal working example

The smallest valid process — one step, one input, one output:

```yaml
opensop: "0.1"
process:
  name: hello-world
  version: "1.0"
  description: "Say hello"
  trigger:
    type: api
  inputs:
    - name: greeting_target
      type: string
      required: true
  outputs:
    - name: greeting
      type: string
      from: steps.say-hello.outputs.greeting
  steps:
    - id: say-hello
      type: form
      outputs:
        - name: greeting
          type: string
          required: true
  tags: [demo]
```

Save to `processes/examples/hello-world.sop.yaml`, load with `bin/rails opensop:load_processes`, start with `curl -X POST http://localhost:3000/sop/hello-world/start -d '{"inputs":{"greeting_target":"world"}}' -H 'Content-Type: application/json'`. The instance will pause at `say-hello` waiting for a submission.
