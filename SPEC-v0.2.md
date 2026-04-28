# OpenSOP — Specification v0.2 (Additive Diff)

**Status:** Draft. Targets the next minor release.
**Built on:** [`SPEC.md`](./SPEC.md) v0.1. Everything in 0.1 still works unchanged.
**Theme:** *Make OpenSOP capable of running agentic LLM-driven processes.* Derived from the HermesOS mapping experiment (see [`docs/v0.2-roadmap.md`](./docs/v0.2-roadmap.md) for context).

A `.sop.yaml` file declaring `opensop: "0.2"` may use any feature in this document. Files declaring `opensop: "0.1"` must continue to parse and run as before.

---

## What's new in 0.2

| § | Addition | New SPEC.md anchor | Status |
|---|---|---|---|
| 2.5 | `llm` step type | §2.5 (new step type row) | ✅ Shipped (Phase 1) |
| 2.6 | `tools:` capability list on `llm` and `automated` | §2.5 (extended) | ✅ Shipped (Phase 1) — runtime sandbox advisory on `automated` |
| 2.7 | Collection outputs (`collection: true` + `item_schema`) | §2.4 (extended) | ✅ Shipped (Phase 1) |
| 2.8 | `exit_when:` step-level early-exit with outputs | §2.5 (new step field) | ✅ Shipped (Phase 2) |
| 2.9 | `loop:` step (for_each / repeat_until / while) | §2.5 (new step type row) | ✅ Shipped (Phase 2) |
| 2.10 | Triggers: `interval:`, `at: […]`, real `schedule:` (cron) | §2.2 (extended) | 🚧 Parser-only for `interval:` (Phase 3 will add the scheduler); 📋 Roadmapped for `schedule:` cron and `at: […]` (Phase 3, parser will reject today) |
| 2.11 | Fan-out subprocess (`fan_out:` on `subprocess`) | §2.5 (extended) | 📋 Roadmapped (Phase 4) — parser will reject today |
| 2.12 | Process `post_review:` hook | §2.1 (process-level field) | 📋 Roadmapped (Phase 5) |
| 2.13 | Inter-instance shared state (`instance.shared_state.<key>`) | §2.4 reference syntax + §2.1 declaration | 📋 Roadmapped (Phase 5) |

**Status legend:** ✅ Shipped (live on `main`, deployed to opensop.fly.dev) · 🚧 Parser-only (definition parses today, runtime arrives in a later phase) · 📋 Roadmapped (parser will reject) · 🔮 Deferred to v0.3.

**Deferred to v0.3** (intentionally out of scope for v0.2):
- 🔮 `async: true` on steps — needs the data shapes from §2.7/§2.9/§2.11 to settle first.
- 🔮 Templates / `extends:` — overlay/override semantics deserve their own milestone.

---

## §2.5 — `llm` step type (NEW)

**Status:** ✅ Shipped — live on opensop.fly.dev (Phase 1).

A first-class call to a language model with structured output. Distinct from:
- `judgment` — *decision* with confidence threshold and human escalation.
- `automated` — *script* (any language) via stdin/stdout JSON.

### Shape

```yaml
- id: classify-intent
  name: "Classify user intent"
  type: llm
  model: claude-sonnet-4-7         # required; resolves via opensop.config.yaml provider table
  prompt_file: prompts/classify.md   # OR `prompt: "..."` inline (mutually exclusive)
  tools: [Read, Grep]                # optional; runtime-enforced — see §2.6
  retry_on_incomplete: true          # default true; retries when output fails schema validation
  max_retries: 2                     # default 2
  expected_output_schema:            # required; shape that the LLM response must conform to
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
  on_timeout: error
```

### Semantics

1. The runtime renders `prompt` / `prompt_file` with the resolved `inputs:` available as template variables (`{{ message }}`).
2. The configured provider (Anthropic by default; see §6.5) is called with the prompt and the declared `tools:`.
3. The response is parsed as JSON and validated against `expected_output_schema`.
4. On schema failure: if `retry_on_incomplete: true`, retry up to `max_retries` with a corrective system message; otherwise the step transitions to `failed`.
5. Validated fields populate the step's `outputs:`.

> Schema validation is strict by default. After `max_retries + 1` attempts fail validation, the step transitions to `failed` with an error listing each missing or wrong-typed field. The corresponding `Sop::LlmCall` row records `status: schema_failed` with the raw response in `response_payload` for debugging.

### Events emitted

- `step.llm.requested` — model, prompt hash, tool list
- `step.llm.responded` — input/output token counts, cost (when reported by provider)
- `step.llm.retry` — per failed attempt
- `step.completed` / `step.failed`

### `expected_output_schema` mini-grammar

A YAML map from field name to type. Types may be:
- Scalars: `string | number | boolean`
- Enum: `enum[a, b, c]`
- Object: nested map (recursive)
- Array: `array[<type>]` — interacts with §2.7

### Why not just use `automated`?

Authors should not have to write a script wrapper to call an LLM. Factoring the LLM out as a first-class step gives the engine a place to handle: provider selection, prompt versioning, token accounting, retry/repair on schema violations, and tool-permission enforcement.

---

## §2.6 — `tools:` capability list (NEW)

**Status:** ✅ Shipped (Phase 1) — declaration and registration are live; runtime sandbox on `automated` steps is advisory (declared in YAML, surfaced in the UI, not yet enforced).

A declared, runtime-enforced list of capabilities a step is allowed to use.

### On `llm` steps
The list is passed through to the provider as the available tools (Anthropic tool-use, etc.). The runtime registers each tool and intercepts calls.

### On `automated` steps
The script's runtime is sandboxed to the declared tools. Calls to undeclared tools fail loudly. (For v0.2 this is *advisory* — declared in YAML, surfaced in the UI, enforced once a sandbox lands. See [`docs/v0.2-roadmap.md`](./docs/v0.2-roadmap.md).)

### Tool registry

Workspace-level config in `opensop.config.yaml`:

```yaml
tools:
  Read:
    handler: builtin:read_file
    description: "Read a file from a permitted path"
  Slack:
    handler: webhook
    url: https://hooks.slack.com/...
```

Built-in tools shipped with v0.2: `Read`, `Grep`, `Glob`, `Write` (subject to `paths:` allowlist), `WebFetch`.

---

## §2.7 — Collection outputs (NEW)

**Status:** ✅ Shipped — live on opensop.fly.dev (Phase 1).

Lets a step emit *N items* of the same shape — the data backbone for loops and fan-out.

```yaml
outputs:
  - name: classifications
    type: object
    collection: true
    item_schema:
      label: string
      score: number
```

### Reference syntax

| Syntax | Meaning |
|---|---|
| `steps.classify.outputs.classifications` | The whole array |
| `steps.classify.outputs.classifications[*]` | All items (used by `for_each:`) |
| `steps.classify.outputs.classifications[0]` | Indexed access |
| `steps.classify.outputs.classifications[*].label` | Pluck a field across items |

The runtime validates each item against `item_schema` at step completion.

---

## §2.8 — `exit_when:` (NEW)

**Status:** ✅ Shipped — live on opensop.fly.dev (Phase 2).

Step-level early-exit. If the predicate is true at step end, the *process* terminates with the literal `exit_outputs:` and emits `instance.completed`. Not an error.

```yaml
- id: gate
  type: automated
  outputs:
    - { name: score, type: number }
  exit_when: "outputs.score < 0.4"
  exit_outputs:
    outcome: "rejected_low_score"
    reason: "Score below threshold"
```

Predicate grammar: identical to existing `condition:` (SPEC.md §2 line 275).
`exit_outputs:` is merged into the process outputs as if produced by the final step.

---

## §2.9 — `loop:` step type (NEW)

**Status:** ✅ Shipped — live on opensop.fly.dev (Phase 2). Supports `for_each`, `repeat_until`, `while` with `sum` / `concat` / `last` aggregation.

```yaml
- id: process-each-lead
  type: loop
  loop:
    for_each: steps.fetch-leads.outputs.leads[*]   # OR repeat_until: "outputs.done == true"
    as: lead                                       # iteration variable name
    max_iterations: 100                            # required for repeat_until / while
    aggregate:
      results: concat                              # sum | concat | last
  body:
    - id: enrich
      type: llm
      inputs:
        - { name: lead, from: loop.lead }
      outputs:
        - { name: enriched, type: object }
  outputs:
    - { name: results, type: object, collection: true, item_schema: { ... } }
```

> `max_iterations:` accepts a literal positive integer OR a single `{{ process.inputs.<name> }}` template (resolved at instance start). Other reference forms (e.g. `steps.*.outputs.*`) are not supported.

### Variants

| Variant | Termination |
|---|---|
| `for_each: <collection>` | Items exhausted |
| `repeat_until: "<predicate>"` | Predicate true at end of iteration |
| `while: "<predicate>"` | Predicate true at start of iteration |

### Aggregation

Per declared loop output, choose: `sum` (numbers), `concat` (collections / strings), `last` (final iteration only). Custom aggregation requires an additional `automated` step downstream.

### State

Each iteration creates a `sop_step_iteration` row (new table; see roadmap). The iteration variable is referenceable inside `body:` as `loop.<as>`.

---

## §2.10 — Triggers (EXTENDED)

**Status:** 🚧 Mixed — `interval:` parses today (parser-only; the scheduler that consumes it is Phase 3). `schedule:` (cron) and `at: […]` are 📋 Roadmapped (Phase 3); the parser will reject those forms today.

SPEC.md §2.2 currently lists trigger types but only `api` is implemented. v0.2 adds:

```yaml
trigger:
  type: schedule
  schedule: "0 9 * * MON"          # cron, runtime-evaluated in workspace TZ
```

```yaml
trigger:
  type: interval
  interval: 30s                    # 5s minimum; supports s, m, h, d
```

> **`interval:` parsing rules (shipped today):**
> - Allowed unit suffixes: `s` (seconds), `m` (minutes), `h` (hours), `d` (days). Examples: `30s`, `5m`, `2h`, `1d`.
> - 5-second minimum.
> - The parser stores `interval_seconds:` on the trigger record. That field is the contract any future scheduler implementation must consume.
> - Parsing is shipped today; the scheduler that consumes `interval_seconds` is Phase 3.

```yaml
trigger:
  type: schedule
  at: ["10:07", "13:07", "16:07"]  # multi-time daily; mutually exclusive with cron `schedule:`
  timezone: "America/Mexico_City"
```

Backed by a Solid Queue–driven scheduler (see roadmap Phase 3).

---

## §2.11 — Fan-out subprocess (EXTENDED)

**Status:** 📋 Roadmapped — Phase 4. Parser will reject `fan_out:` today.

The existing `subprocess` step gets a `fan_out:` modifier:

```yaml
- id: process-each
  type: subprocess
  process: enrich-lead             # child process name
  fan_out:
    over: steps.fetch.outputs.leads[*]
    as: lead                       # bound to child's `process.inputs.lead`
    max_concurrency: 5
    aggregate:
      enriched_leads: concat
  outputs:
    - { name: enriched_leads, type: object, collection: true, item_schema: { ... } }
```

Each item spawns a child instance. Parent waits for all children. Child failure modes:
- `on_child_failure: fail` (default) — first failure fails the parent
- `on_child_failure: skip` — failed children produce no item; parent continues
- `on_child_failure: collect_errors` — failed children produce an `{ error: ... }` item

---

## §2.12 — `post_review:` process hook (NEW)

**Status:** 📋 Roadmapped — Phase 5. Parser will reject `post_review:` today.

A process-level observer that runs after every instance reaches a terminal state (`completed` or `failed`).

```yaml
process:
  name: customer-onboarding
  ...
  post_review:
    type: llm
    model: claude-haiku-4-7
    prompt_file: reviews/onboarding-review.md
    inputs:
      - { name: outputs, from: instance.outputs }
      - { name: events, from: instance.events }
    expected_output_schema:
      verdict: enum[clean, anomaly, regression]
      notes: string
    failure_mode: warn               # warn | notify | error
```

The hook itself is just a step — it can be `llm`, `automated`, `notification`, or `webhook`. The runtime treats failures per `failure_mode:`:
- `warn` — log + event, no further action
- `notify` — emit `instance.review.flagged` event for downstream consumers
- `error` — transition the instance to `review_failed` (does not roll back outputs)

---

## §2.13 — Inter-instance shared state (NEW)

**Status:** 📋 Roadmapped — Phase 5. Parser will reject `shared_state_writes:` and `instance.shared_state.<key>` references today.

A small, declared, observable global state per process. **Use sparingly** — it punctures the "each instance is self-contained" model.

### Declaration (process-level)

```yaml
process:
  name: lead-scorer
  ...
  shared_state_writes: [last_run_at, model_version]
```

### Reference syntax

```yaml
- id: skip-if-recent
  type: automated
  inputs:
    - name: last_run
      from: instance.shared_state.last_run_at
```

### Write semantics

A step may set `instance.shared_state.<key>` only if `<key>` appears in `shared_state_writes:`. Writes happen via a new well-known step output prefix: `_shared_state.<key>`.

```yaml
outputs:
  - { name: _shared_state.last_run_at, type: string }
```

Every read and write emits an event (`shared_state.read`, `shared_state.written`). Storage: new `sop_shared_state` table, scoped per process name. Concurrency: optimistic, last-writer-wins for v0.2; CAS in v0.3.

---

## Summary of new SPEC.md anchors

| New section | Topic |
|---|---|
| §2.5 (extended step-type table) | `llm`, `loop`, `fan_out:` modifier |
| §2.5 (per-step fields) | `tools:`, `exit_when:`, `exit_outputs:` |
| §2.4 (output features) | `collection: true`, `item_schema:` |
| §2.4 (reference syntax) | `[*]`, `[n]`, `.field` selectors; `instance.shared_state.<key>` |
| §2.2 (trigger types) | `interval:`, `at: […]`, real cron `schedule:` |
| §2.1 (process-level fields) | `post_review:`, `shared_state_writes:` |
| §6.5 (technical decisions, NEW) | LLM provider abstraction; tool registry |

These will be folded into `SPEC.md` proper when v0.2 ships.
