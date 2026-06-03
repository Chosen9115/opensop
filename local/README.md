# opensop-local — serverless local execution

`opensop-local` runs an OpenSOP process **on your machine, with no server** — no Rails app, no daemon, no network. It reads a process definition, runs its steps in order, threads a JSON context between them, and writes an append-only on-disk receipt for every step.

This is the missing "local runtime" piece. Until now the story was: author a process → it runs on the Rails runtime, and `opensop-cli` is a thin HTTP client to that server. `opensop-local` lets you **run the same kind of process with just the CLI** — ideal for development, CI, air-gapped/edge environments, and lightweight agents that can't carry a Ruby runtime.

**Dependencies:** `bash` + `jq`. That's it. (Optional: `yq` or `python3`+PyYAML for `.sop.yaml` → JSON conversion.)

## Quick start

```bash
local/bin/opensop-local run local/examples/greet.sop.json --input name=opensop
local/bin/opensop-local runs                 # past runs
local/bin/opensop-local show <run_id>        # manifest + per-step receipts
local/bin/opensop-local list local/examples  # discover .sop.json processes
```

Run the test:

```bash
bash local/test/test.sh    # PASS: 2 steps ran, context threaded, receipts written
```

## Process format (`.sop.json`)

The local runtime reads JSON process definitions (`jq`-native, zero extra deps). The shape mirrors `SPEC.md`:

```json
{
  "name": "greet",
  "version": "1.0",
  "inputs": { "name": "world" },
  "steps": [
    { "id": "build",  "type": "automated", "run": "steps/build.sh" },
    { "id": "render", "type": "shell", "run": "jq -r '.build.greeting' <<< \"$OSL_CONTEXT\"" }
  ]
}
```

To run an existing `.sop.yaml` locally, convert it first (only needs a YAML parser):

```bash
local/bin/opensop-local import-yaml process.sop.yaml   # → process.sop.json
```

## The step I/O contract

Each step receives the **accumulated run context** as JSON, both on **stdin** and in the env var **`$OSL_CONTEXT`**. The context is the process inputs plus every prior step's output, keyed by step id.

A step prints a JSON object to stdout; that object is merged into the context under the step's id. Non-JSON stdout is stored as `{"stdout": "..."}`. A non-zero exit fails the step (and the run, unless the step sets `"continue_on_error": true`).

```
context at step N  =  { ...inputs, "<step1.id>": {...}, ..., "<stepN-1.id>": {...} }
```

## Step types (local)

| type | behavior | status |
|---|---|---|
| `automated` | run a script (`run:` path; resolved vs the process dir, then its parent) | ✅ |
| `shell` | run an inline command | ✅ |
| `noop` | no-op (returns `{}`) | ✅ |
| `form` / `approval` | interactive prompt / pause+resume | 🔜 |
| `llm` | pluggable model command | 🔜 |
| `webhook` / `notification` | outbound HTTP / message | 🔜 (use `shell` + `curl` today) |
| `subprocess` / `wait` | child process / timer | 🔜 |

The deterministic core (`automated`/`shell`/`noop`) is enough to run most real pipelines locally today; the rest are the roadmap for full SPEC parity.

## Audit / receipts

Every run writes to `$OPENSOP_LOCAL_HOME/runs/<run_id>/` (default `~/.opensop-local`):

- `manifest.json` — process, inputs, status, timings
- `audit.jsonl` — one receipt line per step: `{run_id, step, type, status, exit_code, started_at, ended_at, output}`
- `context.json` — the final accumulated context
- `<step>.stderr.log` — per-step stderr

This is the local equivalent of the server's database receipts — fully inspectable after the fact, no server required.

## Design notes / portability

- **Same process file should run on the Rails runtime and locally.** Portability is the point. The local runtime honors the SPEC process shape; the step-type table above is the locally-supported subset.
- **Context threading is whole-context by default.** `from:` expression resolution (e.g. `from: steps.x.outputs.y`) is a planned addition for exact server parity; today each step gets the full context and selects what it needs.
- Pure bash; no build step. Drop `local/bin/opensop-local` on your `PATH` and go.

## Status

Initial contribution: the runtime (`automated`/`shell`/`noop`), JSON process format, on-disk receipts, a YAML→JSON converter, a worked example, and a golden test. Battle-tested driving a real lightweight agent's daily procedures. Follow-ups: `from:` resolution, `form`/`approval`/`llm` step types, and making the top-level inspection commands (`runs`/`show`/`status`) local-aware in `opensop-cli` itself.
