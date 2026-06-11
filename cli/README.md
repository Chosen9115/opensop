# opensop-cli

A bash CLI for running and managing OpenSOP processes — locally on your machine, or against any OpenSOP server. One file; only `jq` required for local use.

## Why

OpenSOP is an open standard for executable processes — define a YAML, get a typed REST API. This CLI runs those processes locally (no server, no daemon, no network) and can also talk to a running OpenSOP server over its `/sop/*` HTTP API. It exists so agents (and humans) can drive OpenSOP from any terminal, immediately.

## Two backends: local (default) and remote (`--remote`)

The CLI is one interface to **two backends**. By default it runs processes **locally on your machine** — no Rails app, no daemon, no network, no `curl`:

```bash
opensop run ./greet.sop.json --input name=Ana       # local: runs on this machine, no server
opensop run lead-qualification --input lead_name=Ana # local: looks up the process in the cell chain
```

Add `--remote` (or `--server <url>`) to talk to an OpenSOP server instead:

```bash
opensop --remote run lead-qualification --input lead_name=Ana   # remote: hits the configured server
opensop --server https://demo.opensop.ai list                    # remote: one-call server override
```

Local execution needs only `bash` + `jq`. Remote needs `curl` too.

```bash
opensop run ./greet.sop.json           # run a process locally
opensop list [dir]                     # list .sop.json processes in the cell chain
opensop runs                           # list local runs
opensop show <run_id>                  # a local run's manifest + per-step receipts
bash test/test.sh                      # golden test
```

> **`--local` flag:** accepted for backwards compatibility but now a no-op (local is already the default). Scripts using `opensop run ./x.sop.json --local` continue to work; they will see a deprecation note on stderr. Drop `--local` from new scripts.

**Process format:** `.sop.json` (jq-native), mirroring `SPEC.md` v0.6. **Step I/O contract:** each step gets the accumulated context (inputs + prior outputs) on stdin and in `$OSL_CONTEXT`; its JSON stdout merges back under the step id. **Step types (local — v0.7 full SPEC parity):**

| Type | Pause? | Resume trigger | Notes |
|---|---|---|---|
| `automated` / `shell` | No | — | Runs a shell script; JSON stdout merged into context |
| `noop` | No | — | Pass-through; no execution |
| `form` | Yes — `waiting_for_input` | `submit --output k=v` | Collects structured human/agent input |
| `approval` | Yes — `waiting_for_approval` | `submit --output decision=approve\|reject` | Defaults to `decision` enum; fully configurable |
| `wait` | `wait.seconds` → No; `wait.until` → Yes — `waiting_for_callback` | `submit` (no outputs required) | `wait.seconds` completes immediately with `{waited:true}` |
| `llm` | No | — | Calls Anthropic Claude; requires `ANTHROPIC_API_KEY`; model must start with `claude` |
| `webhook` | sync → No; callback → Yes — `waiting_for_callback` | `submit --output k=v` | sync asserts 2xx; poll mode not yet implemented |
| `subprocess` | Propagates child pause | child resume | Recursive local execution; depth-guarded (max 16) |

**Pause/resume lifecycle:** when a step pauses the run, `manifest.status` becomes `waiting` and `manifest.waiting` records the step, reason, and what outputs are expected. Resume with:

```bash
opensop submit <run_id> <step-id> --output key=value
```

Execution re-enters at `cursor.next_index` — never re-runs completed steps.

**Step executor (v0.6):** each step may declare `executor: internal|external`. `external` = work happens in an outside process (script, webhook), OpenSOP orchestrates and receives the receipt; `internal` = the OpenSOP runtime handles the step itself. Optional; defaults apply per step type (`automated`/`shell`/`webhook` → external, `noop`/`form`/`approval`/`notification`/`wait`/`judgment` → internal). Invalid values fail loudly at parse time. The effective executor is recorded in each step's audit receipt. **Receipts:** `$OPENSOP_LOCAL_HOME/runs/<id>/{manifest.json, audit.jsonl, context.json}`. As of v0.6: when cwd is inside an OpenSOP cell, `$OPENSOP_LOCAL_HOME` defaults to the active cell's `.opensop/` (receipts land alongside the processes that produced them); outside any cell it defaults to `~/.opensop-local`. Explicit env override always wins. **Name resolution (v0.6):** inside a cell, `opensop run <name>` looks up `processes/<name>.sop.json` in the active cell, then each ancestor cell (nearest wins). Explicit file paths still work as before. The same process file is meant to run on a server runtime *and* locally — portability is the point.

> **⚠ Trust boundary:** local steps execute as shell **on your machine** — a `.sop.json`'s `shell`/`automated` steps run arbitrary commands. Only run process files you trust (same posture as a `Makefile` or an npm `postinstall`). This matters most for agents: don't `opensop run` a process file you just fetched from an untrusted source.
>
> **Note on `--local`:** accepted for backwards compatibility but now a deprecated no-op (v0.8+ default is local). In v0.5–v0.7 `--local` opted into local execution; in v0.8 local is the default so `--local` can simply be dropped from scripts — no other migration needed. For a local dev *server*, use `opensop --server http://localhost:3000` or `opensop config set url http://localhost:3000`.

## Install

### One line

```bash
curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop-cli/main/bin/opensop -o /usr/local/bin/opensop && chmod +x /usr/local/bin/opensop
```

### From source

```bash
git clone https://github.com/Chosen9115/opensop-cli.git
cp opensop-cli/bin/opensop /usr/local/bin/
chmod +x /usr/local/bin/opensop
```

### Requirements

- `bash` 4+ (any modern macOS or Linux)
- `jq` — `brew install jq` / `apt install jq`
- `curl` — for the **remote backend** only (`--remote` / `--server`); local execution doesn't need it

## Quick start

### Local (no server)

Drop a process file and run it — no config required:

```bash
# Write a minimal process
cat > greet.sop.json <<'JSON'
{ "name": "greet", "inputs": [{"name":"name","type":"string","required":true}],
  "steps": [{ "id": "say", "type": "shell", "executor": "external",
              "run": "echo \"hello, $name\"" }] }
JSON

opensop run ./greet.sop.json --input name=Ana
opensop runs               # list all local runs
opensop show <run_id>      # receipts + audit log
```

Inside an OpenSOP cell (`opensop init`), bare process names resolve automatically:

```bash
opensop run greet --input name=Ana   # looks up processes/greet.sop.json in the cell chain
```

### Remote server

Point the CLI at a server (the public demo is at `demo.opensop.ai`):

```bash
opensop config set url https://demo.opensop.ai
opensop config set token demo-public-token-resets-daily
```

Discover what processes are registered:

```bash
$ opensop --remote list
agent-pr-review                  developer-tooling, code-review, agent-harness, ai  An agent reviews a PR diff…
lead-qualification               growth, sales, qualification              Qualify an inbound lead and score…
```

Search by intent (works locally too — scans the cell chain):

```bash
$ opensop --remote search lead
2     lead-qualification           (growth, sales, qualification)  Qualify an inbound lead and score their fit
```

Start a remote run:

```bash
opensop --remote run lead-qualification \
  --input lead_name="Ana García" \
  --input lead_email=ana@example.com \
  --input source=website
```

You'll get a run ID back. The CLI caches the ID → process name mapping so subsequent commands take just the ID:

```bash
opensop --remote status <run-id>
opensop --remote steps <run-id>
```

Advance a paused step (form / judgment / approval):

```bash
opensop --remote submit <run-id> collect-context \
  --output budget=12000 \
  --output timeline=immediate \
  --output notes="Strong fit, spoke to CEO" \
  --decided-by agent:my-bot \
  --confidence 0.92
```

Preview a remote process without executing it:

```bash
opensop --remote dry-run lead-qualification \
  --input lead_name="Ana García" \
  --input lead_email=ana@example.com \
  --input source=website
```

This validates inputs against the process schema and describes each step — no run is created. Exit code 1 if validation fails.

Cancel a run:

```bash
opensop --remote cancel <run-id> --reason "lead unresponsive"
```

List all runs on the server:

```bash
opensop --remote instances --state running --limit 20
```

## Worked example

A full `lead-qualification` run from start to completion on the remote server — what each command returns and what to do next.

**Step 1: start the run**

```
$ opensop --remote run lead-qualification \
    --input lead_name="Ana García" \
    --input lead_email=ana@example.com \
    --input source=website

✓ started lead-qualification
  id:    e33baee4-84d3-4d04-b902-2f50437d8191
  state: running

waiting:
  collect-context (form): waiting_for_input

next:  opensop status e33baee4-84d3-4d04-b902-2f50437d8191
```

The run is paused at the first step — a `form` step waiting for human or agent input.

**Step 2: inspect the steps**

```
$ opensop --remote steps e33baee4-84d3-4d04-b902-2f50437d8191

collect-context    form           active    waiting_for_input
score-lead         automated      pending
notify-team        notification   pending
```

**Step 3: submit the paused step**

```
$ opensop --remote submit e33baee4-84d3-4d04-b902-2f50437d8191 collect-context \
    --output budget=12000 \
    --output timeline=immediate \
    --output notes="Strong fit, spoke to CEO" \
    --decided-by agent:my-bot \
    --confidence 0.92

✓ submitted collect-context (completed) — run running
next:  opensop status e33baee4-84d3-4d04-b902-2f50437d8191
```

The form step is complete. The runtime moves to `score-lead` (automated) and `notify-team` (notification) automatically.

**Step 4: poll until done**

```
$ opensop --remote status e33baee4-84d3-4d04-b902-2f50437d8191

run:      e33baee4-84d3-4d04-b902-2f50437d8191
process:  lead-qualification
state:    completed (2026-05-08T20:28:41Z)

  ✓ collect-context              form
  ✓ score-lead                   automated
  ✓ notify-team                  notification
```

That's the run-pause-submit-poll lifecycle. The receipt is stored in the runtime's database; `opensop --remote instances --process lead-qualification` will show all historical runs.

## Output modes

By default the CLI is **TTY-aware**: pretty-printed in a terminal, JSON when piped.

```bash
opensop list                    # pretty in terminal, JSON when piped
opensop list --json             # always JSON
opensop list --pretty           # always pretty (well, always indented JSON outside a TTY)
opensop status <id> | jq ...    # piping → JSON automatically
```

When `--json` is set, **errors also emit JSON to stderr**: server errors round-trip via `{error, message, ...}` from the engine (augmented with `_meta.http_status`); CLI-side errors (config missing, file not found, invalid input, unknown command, etc.) emit `{error, message, hint?}` from the same envelope. Agents can parse stderr the same way they parse stdout.

```bash
$ opensop --json schema validate /nonexistent.yaml 2>&1 1>/dev/null
{"error":"file_not_found","message":"file does not exist: /nonexistent.yaml"}
```

Set `NO_COLOR=1` to disable ANSI color.

## Input forms

Three ways to provide inputs to `run` (and outputs to `submit`):

```bash
# Inline JSON
opensop run X --inputs '{"lead_name": "Ana", "source": "website"}'

# JSON file
opensop run X --inputs-file ./inputs.json

# Key=Value pairs (repeatable; values that look like JSON parse as JSON)
opensop run X \
  --input lead_name="Ana García" \
  --input source=website \
  --input budget=12000 \
  --input urgent=true
```

For `submit`, swap `--inputs/--input` for `--outputs/--output`, plus optional `--decided-by` and `--confidence`.

You can also attach metadata to a `run`:

```bash
opensop run lead-qualification \
  --input lead_name=Ana \
  --metadata source_system=crm \
  --metadata external_id=lead_8821
```

## Configuration

Config lives at `~/.opensop/config` (or `$OPENSOP_HOME/config` if set). Two values:

```
OPENSOP_URL="https://your-server"
OPENSOP_TOKEN="your-x-sop-token"
```

Override per-call via env vars:

```bash
OPENSOP_URL=https://prod.opensop.ai opensop --remote list
```

> **Note:** `OPENSOP_URL` alone does not enable remote mode — pair it with `--remote` or `--server`.

To point at a local dev **server** for a single call, use `--server` or set `OPENSOP_URL`:

```bash
opensop --server http://localhost:3000 list                       # hit your dev server
OPENSOP_URL=http://localhost:3000 opensop --remote run lead-qualification ... # test against it before prod
```

## Process authoring

The CLI supports the full authoring loop for `.sop.yaml` files — from lint to registration.

**Step 1: lint your file**

`schema validate` is fully client-side (no server round-trip). It checks structural requirements using `yq` (mikefarah/yq v4+) if installed, or `python3` + PyYAML as a fallback:

```bash
opensop schema validate ./my-process.sop.yaml
```

What it checks:

- Top-level `opensop` version field present
- `process` object with `name`, `version`, `description`, `inputs` (array), `steps` (array)
- Each step has `id` and `type`; `type` is one of the known values (`form`, `automated`, `judgment`, `approval`, `webhook`, `notification`, `subprocess`, `loop`, `llm`, `wait`)
- Each input has `name` and `type`
- All `from:` reference strings match `steps.X.outputs.Y` or `process.inputs.Y`

Exit 0 if valid, 1 if errors. Use `--json` to get a structured `{file, valid, errors}` object.

**Step 2: preview execution**

Run `dry-run` to validate inputs against the process schema and walk through each step's description without creating an instance:

```bash
opensop dry-run my-process --input foo=bar
```

Exit 0 if inputs are valid, 1 if validation fails.

**Step 3: register** (requires a remote server)

```bash
opensop --remote register ./my-process.sop.yaml
# or: opensop --server https://your-server register ./my-process.sop.yaml
```

POSTs the file to `/sop/processes/register`. On success, prints `registered <name>@<version>`. If the server returns 401/403, registration may be admin-only — check your token scope or use the dashboard at `<OPENSOP_URL>/admin`.

`register` always requires `--remote` or `--server`; calling it without either exits with `usage_error`.

## Subcommand reference

Commands marked **[remote]** require `--remote` or `--server <url>`. All others default to local.

| Command | Purpose |
|---|---|
| **Discovery** | |
| `opensop list [--tag <tag>]` | List processes in the cell chain (local) or from the server (**[remote]** with `--remote`) |
| `opensop search <keyword> [...]` | Ranked text search over process names, descriptions, and tags |
| `opensop suggest "<task description>"` | Describe a task in prose; get the top-matching process back |
| `opensop schema <name>` | **[remote]** Full process definition (`GET /sop/<name>/schema`) — requires `--remote` or `--server` |
| **Inspection** | |
| `opensop status <run_id>` | State of a local run (or **[remote]** `GET /sop/<name>/<id>` with `--remote`) |
| `opensop steps <run_id>` | Per-step state of a local run (or **[remote]** with `--remote`) |
| `opensop diff <id1> <id2>` | Compare two runs of the same process |
| `opensop history --process <name> [--limit N]` | Recent runs of a specific process, newest-first |
| `opensop compass` | Top processes by run-count, recency, and failure rate |
| **Execution** | |
| `opensop run <name\|file> [opts]` | Start a local run (or **[remote]** `POST /sop/<name>/start` with `--remote`) |
| `opensop dry-run <name\|file> [opts]` | Validate inputs + preview steps — no run created |
| `opensop submit <run_id> <step-id> [opts]` | Resume a paused local run (or **[remote]** with `--remote`) |
| `opensop cancel <run_id> [--reason TEXT]` | Cancel a local run (or **[remote]** with `--remote`) |
| `opensop runs` | List all local runs |
| `opensop show <run_id>` | Local run manifest + per-step receipts |
| **Authoring** | |
| `opensop register <process.yaml>` | **[remote]** POST a `.sop.yaml` to `/sop/processes/register` — requires `--remote` or `--server` |
| `opensop schema validate <file.yaml>` | Client-side YAML lint — always local, no server round-trip |
| **Cells (v0.6)** | |
| `opensop init [--name N] [--parent PATH]` | Create `.opensop/` in cwd; cwd becomes the active cell. Auto-detects parent from ancestor cell when present. |
| `opensop scope` | Print the active cell + ancestor chain (nearest-first); errors if cwd is not inside a cell |
| `opensop annotate <skill> <event-type> <json>` | Append a policy event to the skill's lineage history in the active cell. Event type is open-string; data is whatever JSON the policy needs. |
| `opensop lineage <skill>` | Print a skill's lineage entry (status, metadata, history) in the active cell. Returns the empty default if no events have been recorded yet. |
| `opensop fork <name> [--from <cell>]` | Materialize an ancestor cell's skill in the active cell. Copies `processes/<name>.sop.json` over, then records a lineage entry with `forked_from = {cell, forked_at, snapshot}` where `snapshot` captures the parent's `status` and `metadata`. Child's live status + metadata start empty (policy decides what to do with the snapshot). Refuses to overwrite an existing skill. |
| `opensop list --conflicts` | Inside a cell, walk the chain and **mark shadowed entries**. The first occurrence of each filename (nearest cell that has it) is tagged `← active`; subsequent occurrences in ancestors are tagged `← shadowed by [cell-name]`. |
| **Admin** | |
| `opensop instances [--state X] [--process Y]` | List runs — local by default; **[remote]** paginated `GET /sop/instances` with `--remote` |
| **Config** | |
| `opensop config [set <key> <value>]` | Manage remote server config (url + token) |
| `opensop help` | Full help |

## Local cache

The CLI caches `id → process name` mappings in `~/.opensop/instances.tsv` — a plain TSV of `id`, `name`, `created_at`, `url`. This is used by the remote backend so `opensop --remote status <id>` doesn't require re-typing the process name. Safe to delete at any time; the CLI rebuilds it from `/sop/instances` on the next cache miss.

## Authentication

The CLI sends `X-SOP-Token` on every request when the token is set. The OpenSOP server can run in two modes:

- **Token unset, dev/test environment** — server allows all requests (logs a warning)
- **Token set** — every non-webhook request must match; mismatch returns 401

In production the server **fails closed** (503 with `server_misconfigured`) when the token is unset, so `opensop list` against a misconfigured prod will return that error from the server, not a silent open API.

## Use with Claude Code (and other agents)

The CLI was designed so an agent can use OpenSOP without writing HTTP requests. See [`docs/CLAUDE-INTEGRATION.md`](docs/CLAUDE-INTEGRATION.md) for the recipe — a small CLAUDE.md snippet that teaches the agent when to reach for `opensop` instead of doing things ad-hoc.

The short version: when an agent recognizes that what it's about to do is a multi-step process, it runs it with `opensop run`, polls `opensop status`, and submits step outputs as it works. Local runs need no server; add `--remote` to involve the runtime's database.

For discovery, agents should use `opensop search` or `opensop suggest` rather than scanning the full `list` output — they surface the right process from intent, not from name recall.

## Limitations

- **Bash 4+** assumed. Default macOS bash is 3.2 — install a newer one (`brew install bash`) or run via `/usr/local/bin/bash`.
- **`register` may be admin-only.** Some OpenSOP deployments restrict `/sop/processes/register` to admin tokens. If you get a 401/403, check your token scope or use the dashboard.
- **No inbound webhook receiver.** The CLI doesn't run a server, so it can't receive webhook callbacks over the network. `webhook` steps in `callback` mode pause the run — resume manually with `opensop submit <run_id> <step-id>`. The OpenSOP server runtime handles live inbound callbacks at `/sop/webhooks/<callback_id>`.
- **`webhook` poll mode** is not yet implemented in the local backend (mirrors the server runtime's current state). The step exits non-zero with a clear message.
- **`llm` step type** requires `ANTHROPIC_API_KEY` and outbound HTTPS to `api.anthropic.com`. Local runs without network access cannot execute `llm` steps.
- **`judgment` and `notification` step types** are not yet implemented in the local backend; they will fail the run with a clear error. Use the server runtime for processes that rely on these types.

## Contributing

Issues and pull requests welcome. The whole CLI is one bash file (`bin/opensop`); read it top-to-bottom in 10 minutes.

If you find a `set -u` bug (very common in bash with empty arrays), open an issue — there are corners where `${array[@]}` triggers "unbound variable" if not guarded.

## License

MIT — see [LICENSE](LICENSE).
