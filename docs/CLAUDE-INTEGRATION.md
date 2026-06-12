# Agent Integration — how any agent consumes OpenSOP

There are two ways for an agent to drive OpenSOP, both **local-first** (no server required):

- **Path A — the CLI as a plain shell tool.** Any agent that can run a command can use OpenSOP: it just shells out to `opensop ... --json` and parses stdout. Zero integration code. This works with terminal-backed agents (Claude Code, a Hermes-style agent with a shell backend, a cron job, a Makefile).
- **Path B — the MCP server.** For MCP-native agents (Claude Desktop, and any other MCP client), `mcp/opensop-mcp` exposes the same agent loop as nine MCP tools over stdio. Zero dependencies beyond `bash` + `jq`.

Pick whichever fits the agent. The contract underneath is identical — both shell out to the same local CLI.

---

## The agent loop

discover → preview → run → resume → audit. Every command runs locally against `.sop.json` files by default; add `--remote` only when you need a shared server.

### 1. Discover — what already exists?

```bash
opensop list                                   # processes visible from the cwd (cell chain)
opensop search lead qualification --json       # ranked keyword search
opensop suggest "qualify a new sales lead" --json   # inverse: task → single best match
```

Prefer `search` / `suggest` over scanning `list` — they surface the right process from intent, not name recall.

### 2. Preview — validate before running

```bash
opensop dry-run lead-qualification \
  --input lead_name="Alice Example" \
  --input lead_email=alice@example.com \
  --input source=website \
  --json
```

`dry-run` validates inputs against the declared schema and walks each step. No run is created. Exit 1 if validation fails.

### 3. Run — execute locally

```bash
opensop run lead-qualification \
  --input lead_name="Alice Example" \
  --input lead_email=alice@example.com \
  --json
```

You get a run manifest back. If a step pauses (form / approval / wait / webhook callback), `manifest.status` is `waiting` and `manifest.waiting` records the step id, pause reason, and expected outputs.

### 4. Resume — advance paused steps

```bash
opensop status <run_id> --json                 # is it waiting? on which step?
opensop submit <run_id> collect-context \
  --output budget=12000 \
  --output notes="Strong fit" \
  --decided-by agent:my-bot \
  --confidence 0.92 \
  --json
```

Execution re-enters at the next unexecuted step — completed steps never re-run.

### 5. Audit — inspect what happened

```bash
opensop runs                                   # all local runs (id, status, process)
opensop show <run_id> --json                   # manifest + per-step receipts
```

---

## Path A — the CLI as a tool

Any agent that can execute shell calls `opensop` directly and reads the output. No SDK, no HTTP, no bindings.

- Add `--json` for machine-readable output. (Without it the CLI is TTY-aware: pretty in a terminal, JSON when piped.)
- **Success** prints JSON to **stdout** and exits `0`.
- **Errors** print a JSON envelope `{error, message, hint?}` to **stderr** and exit nonzero. Parse stderr the same way you parse stdout.

```bash
$ opensop run ./greet.sop.json --input name="Alice Example" --json
{"id":"...","process":"greet","status":"completed", ...}

$ opensop run ./missing.sop.json --json 2>&1 1>/dev/null
{"error":"file_not_found","message":"file does not exist: ./missing.sop.json"}
```

Note: `opensop list` emits a plain text/TSV listing (one process per line), not JSON — it is meant for human and quick-scan use. `search`, `suggest`, `dry-run`, `run`, `status`, `show` emit JSON under `--json`.

To teach an agent *when* to reach for OpenSOP, paste a short habit block into its `CLAUDE.md` — see [`AGENTS.md` §9](./AGENTS.md#9-adding-opensop-habits-to-an-agents-claudemd).

---

## Path B — the MCP server

`mcp/opensop-mcp` is a zero-dependency MCP server: a single `bash` file (deps: `bash` + `jq` only, the same as the CLI). It speaks **MCP stdio** — newline-delimited JSON-RPC 2.0 on stdin/stdout — and shells out to the local CLI for every tool. No pip, no npm, no build step.

### Run it

The server reads JSON-RPC from stdin. To smoke-test it (initialize, then list tools):

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | mcp/opensop-mcp
```

It resolves the CLI automatically: `OPENSOP_BIN` if set, else `opensop` on `PATH`, else `../cli/bin/opensop` relative to the server. Normally you don't run it by hand — an MCP client launches it.

### Claude Desktop

Add an entry to `claude_desktop_config.json` (`~/Library/Application Support/Claude/` on macOS):

```json
{
  "mcpServers": {
    "opensop": {
      "command": "/absolute/path/to/opensop/mcp/opensop-mcp",
      "env": {
        "OPENSOP_BIN": "/absolute/path/to/opensop/cli/bin/opensop"
      }
    }
  }
}
```

Add `"OPENSOP_MCP_READONLY": "1"` to the `env` block to expose discovery + preview only (no `opensop_run` / `opensop_submit`) — see [Trust & safety](#trust--safety).

### Generic MCP client

Any MCP client that launches a stdio server works the same way — command + args + env:

```json
{
  "command": "/absolute/path/to/opensop/mcp/opensop-mcp",
  "args": [],
  "env": {
    "OPENSOP_BIN": "/absolute/path/to/opensop/cli/bin/opensop",
    "OPENSOP_MCP_READONLY": "1"
  }
}
```

A Hermes-style agent (or any other MCP-capable agent) registers it the same way: it is a standard stdio MCP server, so whatever config shape the client uses for stdio servers applies — point `command` at the absolute path to `mcp/opensop-mcp` and supply the `env` block.

### Tool reference

Results are `{content:[{type:"text", text}], isError}`. The `text` is the CLI's JSON output; a CLI error comes back with `isError:true` carrying the `{error, message, hint}` envelope.

| Tool | Arguments | Returns |
|---|---|---|
| `opensop_list` | `dir?` | Processes visible from `dir` (default: cwd) — the cell chain listing |
| `opensop_search` | `keywords` | `{query, results:[{score, name, tags, description}]}` |
| `opensop_suggest` | `task`, `threshold?` | `{task, match}` — single best match (null below threshold) |
| `opensop_dry_run` | `process`, `inputs?` | `{process, valid, validation_errors, steps}` — preview, no run |
| `opensop_run` | `process`, `inputs?` | The run manifest; `status:"waiting"` if a step pauses |
| `opensop_status` | `run_id` | `{id, process, state, started_at, completed_at, waiting, steps}` |
| `opensop_submit` | `run_id`, `step_id`, `outputs`, `decided_by?`, `confidence?` | Updated manifest after resuming the waiting step |
| `opensop_show` | `run_id` | `{manifest, steps:[receipts]}` — full audit trail |
| `opensop_runs` | — | All local runs (id, status, process, started_at) |

`opensop_run` and `opensop_submit` are the only mutating tools; they are hidden and refused when `OPENSOP_MCP_READONLY` is set.

---

## Trust & safety

`opensop_run` and `opensop_submit` execute local processes whose `automated` / `shell` steps **run arbitrary shell on the host** — the same posture as a `Makefile` or an npm `postinstall`. Only point the server at a process corpus you trust.

| Env var | Effect |
|---|---|
| `OPENSOP_BIN` | Path to the CLI. Default: `opensop` on `PATH`, else `../cli/bin/opensop` relative to the server. |
| `OPENSOP_MCP_READONLY` | Set (any value) → discovery + preview only. `opensop_run` / `opensop_submit` are hidden from `tools/list` and refused. Safe default for an untrusted corpus. |
| `OPENSOP_SERVER` | Set → route tools through this server URL (adds `--server <url>`). Unset = local-first (default). |

For an untrusted corpus, set `OPENSOP_MCP_READONLY=1` so an agent can discover and preview processes but never execute them.
