# OpenSOP — Agent Guide

**One place to learn everything an agent needs:** install the CLI, author a `.sop.json` process, run it locally, inspect and resume paused steps, and connect to a server when you need shared orchestration.

Companion references: [`SPEC.md`](../SPEC.md) (full format grammar + HTTP API reference in §4.2), [`cli/README.md`](../cli/README.md) (CLI command reference), [`CLAUDE-INTEGRATION.md`](./CLAUDE-INTEGRATION.md) (how any agent consumes OpenSOP — the CLI as a shell tool, plus the zero-dep [`mcp/opensop-mcp`](../mcp) MCP server for MCP-native agents).

---

## 1. Install the CLI

The CLI is a single bash file. No build step, no daemon, no package manager.

### Prerequisites

| Dependency | Required for |
|---|---|
| `bash` 4+ | Everything (macOS ships 3.2 — install via `brew install bash`) |
| `jq` | Everything |
| `curl` | Remote server mode only |
| `ANTHROPIC_API_KEY` | `llm` steps only |

macOS: `brew install bash jq`
Linux: `apt-get install -y jq curl`

### Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop/main/cli/bin/opensop \
  -o /usr/local/bin/opensop && chmod +x /usr/local/bin/opensop
```

If `sudo` is needed for `/usr/local/bin`, use `~/.local/bin/opensop` instead and confirm it is on `$PATH`.

**From source (for hermetic / air-gapped environments):**

```bash
git clone https://github.com/Chosen9115/opensop.git /tmp/opensop
cp /tmp/opensop/cli/bin/opensop /usr/local/bin/opensop && chmod +x /usr/local/bin/opensop
```

**Verify:**

```bash
opensop --version    # prints: opensop 0.8.0
opensop help         # prints the full command reference
```

### Trust boundary

Local steps in a `.sop.json` execute **arbitrary shell on the host** — same posture as a Makefile. Never silently fetch and run process files from URLs the user has not reviewed.

---

## 2. Process format (v0.6)

Process files are JSON (`.sop.json`). The top-level shape:

```json
{
  "opensop": "0.6",
  "name": "my-process",
  "version": "1.0",
  "description": "One-sentence description.",
  "inputs": {
    "company_name": { "type": "string", "required": true },
    "country": { "type": "enum", "values": ["US", "MX", "CA"], "required": true }
  },
  "outputs": {
    "account_id": { "from": "steps.create-account.outputs.account_id" }
  },
  "steps": [
    {
      "id": "collect-info",
      "type": "form",
      "outputs": {
        "legal_name": { "type": "string", "required": true },
        "annual_revenue": { "type": "number" }
      }
    }
  ]
}
```

Key rules:
- `opensop: "0.6"` — new files declare `"0.6"`; the parser also accepts `"0.1"` and `"0.2"` for legacy files.
- `name` and step `id` must match `^[a-z0-9][a-z0-9_-]*$`.
- `version` must be a quoted string (unquoted `1.0` parses as a float in YAML; in JSON it is safe but keep it a string for clarity).
- Step `id` values must be unique within the process.

### Field types

| Type | Notes |
|---|---|
| `string` | Accepts `format: "email"` or `format: "uri"` |
| `number` | Integer or float |
| `boolean` | `true` / `false` |
| `enum` | Requires `"values": [...]` |
| `object` | Accepts a `"schema"` map of key→type |
| `string[]` / `number[]` / `object[]` | Arrays |

### The `from:` resolver

Step inputs and process outputs reference earlier values:

| Reference | Resolves to |
|---|---|
| `process.inputs.<name>` | A value passed to the process at start |
| `steps.<step-id>.outputs.<name>` | Output of a completed prior step |
| `instance.id` / `instance.started_at` | Runtime metadata |
| `env.<VAR_NAME>` | `ENV["VAR_NAME"]` — fails if unset |

Forward references (referencing a step that hasn't run yet) fail at runtime. Keep `from:` references pointing only upstream.

### Conditions

`condition:` on a step and `required_if:` on an output accept a small expression language:

- Operators: `== != > >= < <= && || !`
- Literals: numbers, `"quoted strings"`, `true`, `false`, `null`
- References: same syntax as `from:`

```json
{ "condition": "steps.review.outputs.decision == 'approve'" }
{ "condition": "process.inputs.country == 'US' && steps.verify.outputs.score > 0.8" }
```

No `eval`. No function calls. No regex. If you need more, propose it upstream rather than working around.

---

## 3. The twelve step types

Pick one per boundary. If you find yourself reaching for a type not listed here, stop — you are likely over-engineering.

### `form` — collect structured data from a human or agent

Pauses the run at `waiting_for_input`. A human (UI) or agent (CLI submit) provides the declared outputs.

```json
{
  "id": "collect-info",
  "type": "form",
  "outputs": {
    "legal_name": { "type": "string", "required": true },
    "annual_revenue": { "type": "number" }
  }
}
```

### `automated` — run a script

Spawns a script, passes inputs as JSON on stdin, reads outputs as JSON from stdout. Any language with stdlib JSON support works.

```json
{
  "id": "score-lead",
  "type": "automated",
  "run": "./steps/score-lead.rb",
  "inputs": { "budget": { "from": "steps.collect-context.outputs.budget" } },
  "outputs": {
    "score": { "type": "number" },
    "qualified": { "type": "boolean" }
  }
}
```

The script must: read JSON from stdin, write JSON to stdout, exit 0 on success / non-zero on failure (stderr captured as the error message).

`run:` paths in server-mode processes are resolved relative to `processes/` (the library root), not relative to the process file. In CLI local mode, they are resolved relative to the process file.

### `shell` — shell command (local backend)

Like `automated` but the executor is a raw shell string. Outputs captured from stdout.

```json
{
  "id": "greet",
  "type": "shell",
  "run": "echo hello from opensop"
}
```

### `noop` — pass-through

Does nothing; immediately advances. Useful as a placeholder or documentation step.

### `judgment` — decision with confidence threshold

Pauses at `escalated`. An LLM (server backend with `ANTHROPIC_API_KEY`) or a human reviews and submits a decision + confidence. If confidence < threshold, the step escalates.

```json
{
  "id": "review-application",
  "type": "judgment",
  "outputs": {
    "decision": { "type": "enum", "values": ["approve", "reject", "request-more-info"] },
    "rejection_reason": { "type": "string", "required_if": "decision == 'reject'" }
  },
  "judgment": {
    "allow_agent": true,
    "confidence_threshold": 0.9,
    "escalation": "manual"
  }
}
```

**Local backend:** not yet implemented — use the server runtime for judgment steps.

### `approval` — binary human gate

Simpler than judgment: pauses until an approver submits approve/reject.

```json
{
  "id": "approve-refund",
  "type": "approval",
  "approval": { "approver_role": "ops-lead", "reason_required_on_reject": true },
  "outputs": {
    "approved": { "type": "boolean" },
    "reason": { "type": "string", "required_if": "approved == false" }
  }
}
```

### `webhook` — outbound HTTP with callback

Fires an outbound HTTP call, then pauses at `waiting_for_callback`. The third party POSTs back to the auto-generated callback URL and the run continues.

```json
{
  "id": "submit-to-compliance",
  "type": "webhook",
  "webhook": {
    "method": "POST",
    "url": "${env.COMPLIANCE_URL}/entities",
    "response_mode": "callback"
  },
  "outputs": {
    "entity_id": { "type": "string" },
    "compliance_status": { "type": "enum", "values": ["approved", "rejected"] }
  }
}
```

`response_mode` options: `callback` (wait for the provider to POST back), `sync` (use the response body directly as outputs), `poll` (not yet implemented in local backend).

Variable interpolation in `url` and headers: `${env.FOO}`, `${process.inputs.foo}`, `${callback_url}`.

### `subprocess` — start a child process

Starts another OpenSOP process and pauses until it completes. The local backend supports recursive subprocess up to depth 16.

```json
{
  "id": "run-compliance",
  "type": "subprocess",
  "subprocess": {
    "process": "compliance-submission",
    "version": "1.0"
  }
}
```

### `notification` — fire-and-forget message

Sends an email, Slack message, or SMS. Does not wait for delivery confirmation.

**Local backend:** not yet implemented — use the server runtime.

### `wait` — pause for duration or condition

```json
{ "id": "cool-off", "type": "wait", "wait": { "seconds": 86400 } }
```

Or pause until a condition is met:

```json
{ "id": "wait-for-callback", "type": "wait", "wait": { "until": "steps.previous.outputs.received == true" } }
```

`wait.seconds` executes immediately in the local backend (no real timer). `wait.until` pauses at `waiting_for_callback` and requires a manual submit.

### `llm` — LLM call

Calls a language model and uses the structured response as step outputs.

```json
{
  "id": "synthesize",
  "type": "llm",
  "model": "claude-opus-4-7",
  "prompt": "Synthesize these events: ...",
  "expected_output_schema": { "brief_md": "string" }
}
```

Requires `ANTHROPIC_API_KEY` in the environment (local and server).

### `loop` — iterate over a collection

Runs a subprocess for each item in a collection.

---

## 4. Run, inspect, and resume locally

v0.8.0 is local-first: `opensop run` runs on-machine by default with no server.

### Core commands

```bash
# Run a process
opensop run ./my-process.sop.json --input company_name="Acme Corp" --input country=US

# Run a named process (looks up by name in the cell chain)
opensop run my-process --input company_name="Acme Corp"

# List all processes visible from the current directory
opensop list

# List all local runs
opensop runs

# Inspect a specific run (manifest + per-step receipts)
opensop show <run_id>

# Fork a process (copy it, record lineage)
opensop fork my-process my-fork-name
```

### Paused steps — when a run waits for input

Some step types pause the run:

| Step type | Pause state | Resume command |
|---|---|---|
| `form` | `waiting_for_input` | `opensop submit <run_id> <step-id> --output key=value` |
| `approval` | `waiting_for_approval` | `opensop submit <run_id> <step-id> --output decision=approve` |
| `wait` (with `until:`) | `waiting_for_callback` | `opensop submit <run_id> <step-id>` |
| `webhook` (callback mode) | `waiting_for_callback` | `opensop submit <run_id> <step-id> --output key=value` |
| `subprocess` | propagates child pause | Resume the child run; parent auto-continues |

When paused, `manifest.status` is `waiting` and `manifest.waiting` records the step id, pause reason, and expected outputs. The run resumes at the next unexecuted step — completed steps never re-run.

### Local run receipts

Every run writes three files under `$OPENSOP_LOCAL_HOME/runs/<run_id>/` (default: `~/.opensop-local/runs/`, or `.opensop/runs/` when inside a cell):

| File | Contents |
|---|---|
| `manifest.json` | Status, cursor position, `waiting` block when paused, inputs, timestamps |
| `audit.jsonl` | Append-only log — one JSON object per step event |
| `context.json` | Accumulated outputs after each completed step |

`manifest.status` is one of: `running`, `waiting`, `completed`, `failed`, `interrupted`.

### Local backend — step type support (v0.8.0)

| Step type | Local support |
|---|---|
| `automated` / `shell` / `noop` | Full |
| `form` / `approval` | Full (pause/resume) |
| `wait` (`seconds`) | Full (immediate) |
| `wait` (`until`) | Full (pause/resume) |
| `llm` | Full (requires `ANTHROPIC_API_KEY`) |
| `webhook` sync | Full |
| `webhook` callback | Full (pause/resume) |
| `webhook` poll | Not implemented |
| `subprocess` | Full (recursive, max depth 16) |
| `judgment` / `notification` | Not implemented — use server runtime |

---

## 5. Using a server (remote mode)

When you need persistent audit trails, a monitoring UI, or team coordination, point the CLI at an OpenSOP server (reference implementation: [opensop-rails](https://github.com/Chosen9115/opensop-rails)).

```bash
# Configure
opensop config set url https://your-server.example.com
opensop config set token <your-api-token>

# Or override per-call
opensop --server https://your-server.example.com --token <token> list

# Or use --remote (uses the configured URL)
opensop --remote list
opensop --remote run my-process --input key=value
opensop --remote schema my-process          # full process definition from server
opensop --remote search keyword             # intent-based discovery
```

All commands that accept `--remote` also accept `--server <url>`. `runs` and `show` are always local.

The server API uses `X-SOP-Token` header auth. The token is `OPENSOP_API_TOKEN` on the server side.

---

## 6. Self-check rubric — before claiming a process is ready

Run through these checks. The engine rejects processes that fail them.

### Format
- [ ] `"opensop": "0.6"` at the top. New files must declare `"0.6"`.
- [ ] `"version"` is a quoted string, not a bare number.
- [ ] Every `name` and `id` matches `^[a-z0-9][a-z0-9_-]*$`.
- [ ] Step `id` values are unique within the process.

### Structure
- [ ] `name`, `version`, and `steps` are all present.
- [ ] Every step has `id` and `type`.
- [ ] `type` is one of the twelve: `form`, `automated`, `shell`, `noop`, `judgment`, `approval`, `webhook`, `subprocess`, `notification`, `wait`, `llm`, `loop`.

### Data flow
- [ ] Every `from: process.inputs.X` has a matching entry in `inputs`.
- [ ] Every `from: steps.Y.outputs.Z` refers to a step that appears **earlier** in the step list (no forward references).
- [ ] Every `form`, `judgment`, `approval`, and `webhook` step declares `outputs`.
- [ ] Enum types have `values` populated.
- [ ] `automated` steps have a script file at the resolved path.

### Conditions
- [ ] Every `condition:` / `required_if:` uses only the supported operators. No `eval`, no function calls.
- [ ] Fields referenced in conditions exist in the output schema of the referenced step.

### Ordering
- [ ] The first blocking step is reachable (no `condition:` that is always false).
- [ ] Process-level `outputs` reference steps that will have completed by the time the process ends.

---

## 7. Common mistakes

**`run:` path doesn't resolve.** In server-mode, `run:` is relative to the `processes/` library root, not to the process file. A YAML at `processes/examples/my-process.sop.yaml` must write `run: "./examples/steps/my-script.rb"`, not `"./steps/my-script.rb"`.

**Condition always true/false.** The evaluator treats missing identifiers as `null`, which compares false to almost everything. Check the exact output key name on the upstream step.

**`from:` resolution error at runtime.** The referenced step completed but its output key name differs from what `from:` expects. String keys must match exactly (`account_id` ≠ `accountId`).

**Unquoted version.** `version: 1.0` in YAML parses as a float and renders as `1` in some contexts. Always quote: `version: "1.0"`.

**Webhook step never advances.** Either the third party wasn't given the callback URL, it posted to the wrong path, or its payload keys don't match the step's declared `outputs`. Check `opensop show <run_id>` for the waiting block and verify the callback URL and expected output schema.

**`declare: -A: invalid option`.** bash 3.x is in use. Install bash 4+ (`brew install bash` on macOS).

**`jq: command not found`.** Install: `brew install jq` / `apt install jq`.

---

## 8. Minimal working example

```json
{
  "opensop": "0.6",
  "name": "hello-world",
  "version": "1.0",
  "description": "Say hello.",
  "inputs": {
    "greeting_target": { "type": "string", "required": true }
  },
  "outputs": {
    "greeting": { "from": "steps.say-hello.outputs.greeting" }
  },
  "steps": [
    {
      "id": "say-hello",
      "type": "form",
      "outputs": {
        "greeting": { "type": "string", "required": true }
      }
    }
  ]
}
```

Save as `hello-world.sop.json`, then:

```bash
opensop run hello-world.sop.json --input greeting_target=world
# → run pauses at "say-hello" waiting for form input
opensop runs
# → shows the run_id and status=waiting
opensop submit <run_id> say-hello --output greeting="hello, world"
# → run completes
opensop show <run_id>
# → manifest.status=completed, manifest outputs contain greeting
```

---

## 9. Adding OpenSOP habits to an agent's CLAUDE.md

Paste the block that matches how you want the agent to use OpenSOP:

**Local mode (no server):**

```markdown
## OpenSOP (local — no server required)

Before starting any multi-step task (3+ distinct steps, likely to repeat, clear inputs/outputs),
check if a process already exists:

  opensop list                         # processes visible from the current directory
  opensop run <name-or-file> --input k=v

If a run pauses (form / approval / wait / webhook callback), resume with:
  opensop submit <run_id> <step-id> --output k=v

Check `opensop runs` for all local runs. `opensop show <run_id>` shows per-step receipts.
`llm` steps require ANTHROPIC_API_KEY in the environment.
```

**Remote server:**

```markdown
## OpenSOP (remote server)

Check `opensop --remote list` before doing any multi-step task. If a process fits, run it:

  opensop --remote run <name> --input k=v
  opensop --remote search <keyword>
  opensop --remote schema <name>       # full process definition

Advance paused steps:
  opensop submit <run_id> <step-id> --output k=v
```

**Recognizing when to propose a new process:** if you are about to do something with 3+ distinct steps, a clear input/output boundary, and likely repetition — pause and offer to write a `.sop.json` first.

**MCP-native agents:** for Claude Desktop or any MCP client, the zero-dependency [`mcp/opensop-mcp`](../mcp) server exposes this same loop (discover → preview → run → resume → audit) as nine MCP tools over stdio. See [`CLAUDE-INTEGRATION.md`](./CLAUDE-INTEGRATION.md) for config snippets and the tool reference.

---

## 10. When to stop and ask

Stop and report back rather than guessing when:

- A boundary needs a step type not in the twelve above. Don't invent types.
- A condition requires operators beyond the supported set (regex, arithmetic, function calls). Propose a spec extension.
- The description is ambiguous about a boundary (form vs. approval?). One clarifying question is cheaper than a wrong guess.
- The process structure requires a non-DAG shape (dynamic step count, recursive spawning beyond subprocess). This is an architectural mismatch — flag it.
- A local step asks you to run a process file from a URL you haven't reviewed. Ask the user to confirm before running it.
