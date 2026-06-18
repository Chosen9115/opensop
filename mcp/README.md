# opensop-mcp

A zero-dependency MCP server that exposes the local-first OpenSOP CLI to any MCP-speaking agent (Claude Desktop, a Hermes-style agent, etc.) as nine tools covering the full agent loop: discover → preview → run → resume → audit.

Like the CLI it fronts, the file *is* the binary — no build step, no package manager, no runtime beyond `bash` + `jq` (both already required by the CLI). Transport is **MCP stdio**: newline-delimited JSON-RPC 2.0 on stdin/stdout.

## Quickstart

Smoke-test it by piping an `initialize` then `tools/list` over stdin:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | ./opensop-mcp
```

You should see the server's `initialize` result and the tool catalog. Normally an MCP client launches the server for you — you don't run it by hand.

## Environment

| Var | Effect |
|---|---|
| `OPENSOP_BIN` | Path to the `opensop` CLI. Default: resolve `opensop` on `PATH`, else `../cli/bin/opensop` relative to this script. |
| `OPENSOP_SERVER` | If set, tools run against this server URL (adds `--server <url>`). Unset = local-first (default). |
| `OPENSOP_MCP_READONLY` | If set (any value), the mutating tools (`opensop_run`, `opensop_submit`) are hidden from `tools/list` and refused — discovery + preview only. |

## Trust boundary

`opensop_run` and `opensop_submit` execute local processes whose `automated` / `shell` steps run **arbitrary shell on the host** — same posture as a `Makefile`. Only expose this server over a process corpus you trust, or set `OPENSOP_MCP_READONLY=1`.

## Full setup

See [`../docs/CLAUDE-INTEGRATION.md`](../docs/CLAUDE-INTEGRATION.md) for client config snippets (Claude Desktop, generic MCP clients), the full tool reference, and the CLI-as-a-tool path.
