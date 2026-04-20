# Authoring an OpenSOP process

A practical guide to writing a `.sop.yaml` file and getting it running. The full format spec is in [`SPEC.md`](../SPEC.md) §2; this doc covers the workflow and the gotchas.

---

## The fastest path

1. Create `processes/<subdir>/<my-process>.sop.yaml` with the structure below. Public examples live in `processes/examples/`; private processes in your fork typically go under `processes/coba/` or a name your fork reserves in its `.gitignore`.
2. Write any scripts your `automated` steps reference under `processes/<subdir>/steps/`.
3. `bin/rails opensop:load_processes` to register the process (or `bin/rails db:seed`).
4. `bin/rails server` and visit `/processes` — your process appears in the library.
5. Start an instance via the API or the admin UI.

The repo on disk is the source of truth. The DB is a cache. The registry recursively globs `processes/**/*.sop.yaml`, so any subdirectory works.

---

## Minimum viable definition

```yaml
opensop: "0.1"

process:
  name: hello-world          # lowercase, hyphens/underscores, must match \A[a-z0-9][a-z0-9_-]*\z
  version: "1.0"             # quote it — YAML interprets unquoted 1.0 as a float
  description: "A trivial process"

  inputs:
    - name: greeting_target
      type: string
      required: true

  outputs:
    - name: message
      type: string
      from: steps.compose.outputs.text

  steps:
    - id: compose
      name: "Compose the greeting"
      type: form
      outputs:
        - name: text
          type: string
```

That's a complete, valid process. Load it, start an instance with `inputs: {greeting_target: "world"}`, fill the form with `text: "hello, world"`, and the instance completes with `outputs: {message: "hello, world"}`.

---

## The eight step types

| Type | Status | When to use |
|------|--------|-------------|
| `form` | ✅ real | A human (or agent) needs to provide structured data |
| `automated` | ✅ real | Something deterministic should happen — call a script |
| `notification` | ✅ stub (returns immediately) | Fire-and-forget message; no actual sending |
| `webhook` | 🟡 inbound only | Pause until a third party POSTs to a callback URL |
| `judgment` | 🟡 stub (escalates) | Decision that requires reasoning; LLM not yet wired |
| `approval` | 🟡 stub (waits) | Binary gate — someone must approve |
| `subprocess` | 🟡 stub (waits) | Run another process and wait for its outputs |
| `wait` | 🟡 partial | Pause until a time elapses or a condition is met |

The "stub" status means the engine pauses the instance at the right point — you can still complete the step manually (or via API submit). They just don't yet have automated execution.

---

## How fields work

Every input/output declares a `name` and a `type`. Types from [SPEC §2.4](../SPEC.md#24-field-types):

```
string  number  boolean  enum  date  datetime
file    file[]  string[]  object  reference  currency
```

Add `required: true` on inputs that must be provided. Add `values: [...]` on enums.

For nested objects, use a `schema:`:

```yaml
- name: business_record
  type: object
  schema:
    legal_name: string
    rfc: string
    annual_revenue: number
```

This is enforced loosely today — the engine doesn't validate every nested key against the schema, but the schema is preserved and rendered in the UI.

---

## Wiring data between steps

Use `from:` to pull data from elsewhere:

```yaml
inputs:
  - name: business_record
    from: steps.collect-info.outputs.business_record   # ← from a previous step's output
  - name: country
    from: process.inputs.country                        # ← from the process's inputs
  - name: api_key
    from: env.COMPLIANCE_API_KEY                        # ← from an env var
  - name: started_at
    from: instance.started_at                           # ← from instance metadata
```

If a `from:` reference can't be resolved at execution time (the source step hasn't completed, the env var is unset), the engine raises `UnresolvedReference` and fails the step. **Exception:** if the field also has `required_if:`, an unresolved reference yields `nil` and the conditional logic decides what to do.

---

## Conditionals

A step can have a `condition:` that determines whether it runs:

```yaml
- id: send-rejection-email
  name: "Notify the customer of the rejection"
  type: notification
  condition: "steps.review.outputs.decision == 'reject'"
  ...
```

If the condition evaluates to false, the step is marked `skipped` and the engine moves on.

Outputs can have `required_if:`:

```yaml
- name: rejection_reason
  type: string
  from: steps.review.outputs.rejection_reason
  required_if: "status == 'rejected'"
```

When `required_if` is false, the field is dropped from the final outputs (not emitted as `nil`, not present at all). When it's true, the field IS required — if `from:` resolves to nil, the step fails validation.

The expression grammar is small but real: `==`, `!=`, `>`, `>=`, `<`, `<=`, `&&`, `||`, `!`, parens, single/double-quoted strings, numbers, booleans. **There is no `eval`** — anything that looks like code (`system(...)`, backticks, method calls) raises `InvalidExpression`.

---

## Writing an automated step

```yaml
- id: verify-documents
  name: "Verify uploaded documents"
  type: automated
  inputs:
    - name: documents
      from: steps.collect-info.outputs.documents
  outputs:
    - name: verification_result
      type: enum
      values: [complete, incomplete, invalid]
    - name: missing_documents
      type: string[]
  run: ./examples/steps/verify-documents.rb
```

> **Path resolution:** `run:` paths are resolved relative to `processes/` (the whole library root), not relative to the YAML file. A YAML in `processes/examples/` referencing `./examples/steps/X.rb` is correct; so is a YAML in `processes/coba/` referencing `./coba/steps/X.rb`. Implementation: `app/services/opensop/step_executors/automated.rb#resolve_script_path`.

The script lives at `processes/examples/steps/verify-documents.rb`. The engine:

1. Resolves the inputs hash
2. Runs the script via `Open3.capture3`
3. Passes the inputs as JSON via stdin
4. Reads stdout, parses as JSON
5. Validates the result against the `outputs:` schema
6. Persists the outputs and continues

Minimum viable script:

```ruby
#!/usr/bin/env ruby
require "json"

input = JSON.parse(STDIN.read)

# ...do work using input...

puts JSON.dump({
  "verification_result" => "complete",
  "missing_documents" => []
})
```

Make it executable: `chmod 0755 processes/examples/steps/verify-documents.rb`.

Scripts can be in any language with stdlib JSON support — Ruby, Python, Node, Go, Bash with `jq`. The engine doesn't care; it just runs the file.

**Failure handling:**

- Script not found → step fails immediately, clear error
- Script exits non-zero → step fails with the captured stderr in the error
- Script stdout is not JSON → step fails
- Output doesn't match schema → step fails

Retry config (`retry.max`, `retry.backoff`) is parsed and stored, but auto-retry isn't implemented yet. Today, fix the underlying issue and the step needs to be re-submitted manually (or run a fresh instance).

---

## Writing a form step

```yaml
- id: collect-business-info
  name: "Collect business information"
  type: form
  description: "Gather company details from the customer"
  inputs:
    - name: company_name
      from: process.inputs.company_name
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
```

When the engine reaches this step, it pauses at `active/waiting_for_input`. The admin UI renders a form for the declared outputs. An agent can submit via:

```
POST /sop/<process>/<instance_id>/steps/collect-business-info/submit
{
  "outputs": {
    "business_record": {
      "legal_name": "Acme Corp",
      "rfc": "ABC010101",
      ...
    }
  },
  "decided_by": "agent"
}
```

`timeout:` (e.g. `7d`, `48h`) is parsed and stored but not currently enforced — `on_timeout: notify-and-wait` is metadata only for now.

---

## Writing a webhook step

```yaml
- id: submit-to-compliance
  name: "Submit entity to compliance provider for review"
  type: webhook
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
    callback_path: /webhooks/compliance/receive
    poll_timeout: 7d
```

**Today (MVP):** the engine creates a `Sop::Callback` row with an auto-generated callback URL like `/sop/webhooks/<uuid>`, pauses the step at `active/waiting_for_callback`, and stops. **No outbound HTTP call is made.** You're expected to give the third party the callback URL out-of-band.

When the third party POSTs to the callback URL with declared outputs, the step completes:

```
POST /sop/webhooks/<uuid>
{"entity_id": "mnx_442", "compliance_status": "approved"}
```

The keys in the payload should match the step's declared outputs. The engine merges them into `step.outputs` at the top level and validates against the schema.

**v0.2 plan:** the engine will actually POST to the `webhook.url` (with body templating from `body_template`) inside an ActiveJob, then either wait for the callback or poll based on `response_mode`.

---

## Writing a judgment step

```yaml
- id: review-application
  name: "Review the application"
  type: judgment
  inputs:
    - name: business_record
      from: steps.collect-info.outputs.business_record
  outputs:
    - name: decision
      type: enum
      values: [approve, reject, request-more-info]
    - name: risk_notes
      type: string
    - name: rejection_reason
      type: string
      required_if: "decision == 'reject'"
  judgment:
    allow_agent: true
    require_human_review: false
    confidence_threshold: 0.9
    escalation: manual
```

**Today (MVP):** the step is marked `active/escalated` immediately. There is no LLM call. A human (or agent via API) submits the decision via the same submit endpoint as a form step.

**v0.2 plan:** the engine will assemble the context (description + inputs + expected outputs schema), call the configured LLM provider, parse the structured response, check confidence, and either auto-advance or escalate per the `judgment:` config.

---

## Naming and IDs

- **Process names:** lowercase, hyphens or underscores. Match `\A[a-z0-9][a-z0-9_-]*\z`. Used in URLs, so keep them short and readable.
- **Step IDs:** same constraints, scoped to the process. Used in `from:` references, conditions, and URLs.
- **Versions:** strings, semver-ish. Quote them in YAML (`version: "1.0"`).

A process is uniquely keyed by `(name, version)`. Bump the version when you make a breaking change to inputs/outputs/steps. In-flight instances stay pinned to their starting version.

---

## Putting it together — a real example

```yaml
opensop: "0.1"

process:
  name: lead-qualification
  version: "1.0"
  description: "Qualify an inbound lead and notify the team"
  owner: sales-team
  tags: [sales, lead]

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
      values: [website, linkedin, referral]

  outputs:
    - name: score
      type: number
      from: steps.score-lead.outputs.score
    - name: qualified
      type: boolean
      from: steps.score-lead.outputs.qualified

  steps:
    - id: collect-context
      name: "Collect qualification context"
      type: form
      outputs:
        - name: budget
          type: number
        - name: timeline
          type: enum
          values: [immediate, "3m", "6m", unknown]
        - name: notes
          type: string

    - id: score-lead
      name: "Compute lead score"
      type: automated
      inputs:
        - name: budget
          from: steps.collect-context.outputs.budget
        - name: timeline
          from: steps.collect-context.outputs.timeline
      outputs:
        - name: score
          type: number
        - name: qualified
          type: boolean
      run: ./examples/steps/score-lead.rb

    - id: notify-team
      name: "Notify the sales team"
      type: notification
      condition: "steps.score-lead.outputs.qualified == true"
```

This process is shipped with the repo at `processes/examples/lead-qualification.sop.yaml`. Run it with `bin/rails opensop:demo_leads`.

---

## Common pitfalls

- **Unquoted version `1.0`** parses as a float → renders as `1` in some places. Always quote: `version: "1.0"`.
- **Forgetting to make scripts executable.** `chmod 0755`.
- **Missing `from:` reference targets.** If you reference `steps.foo.outputs.bar`, that step must (a) exist, (b) declare `bar` as an output, (c) complete successfully before the consumer step runs.
- **Free-text expressions in `condition:`.** The grammar is intentionally tiny. Anything fancier than comparisons-and-booleans isn't supported.
- **Step IDs with capital letters or spaces.** Won't validate. Use `lowercase-with-hyphens`.
- **Output schemas with deep nesting** for `object` types — render fine in the YAML, less fine in the UI form (renders as a JSON textarea today). For complex schemas, consider splitting into multiple top-level outputs.

---

## Iterating on a process

After editing a `.sop.yaml`:

```bash
bin/rails opensop:load_processes      # Re-parse and upsert
```

If you bumped the version, a new row is added; old in-flight instances keep their old definition. If you kept the version, the existing row is updated in place — but **in-flight instances see the change immediately** for the steps they haven't reached yet. Be careful with this in production.

To clear all running instances:

```bash
bin/rails runner 'Sop::Callback.delete_all; Sop::Event.delete_all; Sop::Step.delete_all; Sop::Instance.delete_all'
```

---

## Going further

- [`SPEC.md`](../SPEC.md) §2.6 — process composition (`subprocess` step type — stub today)
- [`SPEC.md`](../SPEC.md) §2.7 — versioning and migration scripts
- [`SPEC.md`](../SPEC.md) §3.5 — process-level access control
- [`docs/architecture.md`](./architecture.md) — how the engine actually runs your process
