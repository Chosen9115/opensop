# Installing opensop-cli for agent use

This guide covers installation, verification, and the minimal `CLAUDE.md` / skill-file setup that lets an agent drive OpenSOP processes — both against a server and via the `--local` backend (no server required).

## Requirements

| Dependency | Server backend | Local backend (`--local`) |
|---|---|---|
| `bash` 4+ | Required | Required |
| `jq` | Required | Required |
| `curl` | Required | Not needed |
| `ANTHROPIC_API_KEY` | Not needed | Required for `llm` steps only |

macOS ships bash 3.2 — install a newer one if needed:

```bash
brew install bash jq
```

On Linux (Debian/Ubuntu):

```bash
apt-get install -y jq curl
```

## Install

### One-line (recommended for CI / agent environments)

```bash
curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop-cli/main/bin/opensop \
  -o /usr/local/bin/opensop && chmod +x /usr/local/bin/opensop
```

### From source (for development / contribution)

```bash
git clone https://github.com/Chosen9115/opensop-cli.git
cp opensop-cli/bin/opensop /usr/local/bin/
chmod +x /usr/local/bin/opensop
```

### Verify

```bash
opensop --version          # prints: opensop 0.7.0
opensop help               # prints the full command reference
bash -n /usr/local/bin/opensop   # syntax check (should print nothing)
```

## Point the CLI at a server (optional)

Skip this section if you only need the `--local` backend.

```bash
opensop config set url https://demo.opensop.ai
opensop config set token demo-public-token-resets-daily
```

Override per-call with env vars:

```bash
OPENSOP_URL=https://prod.example.com opensop list
```

## The local backend — no server at all

Since v0.5, `--local` runs processes on-machine using only `bash` + `jq`. As of v0.7, all major step types are supported.

```bash
# Run a process locally
opensop run ./my-process.sop.json --local --input name=alice@example.com

# List local processes in the current directory
opensop list --local .

# Check all local runs
opensop runs

# Inspect a run's receipts
opensop show <run_id>
```

### Pause/resume

Steps that require external input (`form`, `approval`, `wait.until`, `webhook` callback mode) pause the run. The CLI prints a resume hint on pause. Resume with:

```bash
opensop submit <run_id> <step-id> --local --output key=value
```

`approval` steps default to `decision=approve|reject`. Pass `--decided-by <actor>` to record who or what made the decision.

### Step type support matrix (local backend, v0.7)

| Step type | Local support | Pause? | Resume signal |
|---|---|---|---|
| `automated` / `shell` | Full | No | — |
| `noop` | Full | No | — |
| `form` | Full | Yes — `waiting_for_input` | `submit --output k=v` |
| `approval` | Full | Yes — `waiting_for_approval` | `submit --output decision=approve\|reject` |
| `wait` (`seconds`) | Full | No | — |
| `wait` (`until`) | Full | Yes — `waiting_for_callback` | `submit` (no outputs required) |
| `llm` | Full | No | — (requires `ANTHROPIC_API_KEY`) |
| `webhook` sync | Full | No | — |
| `webhook` callback | Full | Yes — `waiting_for_callback` | `submit --output k=v` |
| `webhook` poll | Not implemented | — | — |
| `subprocess` | Full | Propagates child | Resume the child run |
| `judgment` | Not implemented | — | Use server runtime |
| `notification` | Not implemented | — | Use server runtime |

### Receipt layout

Every local run writes three files under `$OPENSOP_LOCAL_HOME/runs/<run_id>/`:

| File | Contents |
|---|---|
| `manifest.json` | Run-level metadata: `status`, `cursor`, `waiting` (when paused), `inputs`, `started_at`, `ended_at` |
| `audit.jsonl` | Append-only log — one JSON object per step event (started, completed, waiting, failed) |
| `context.json` | Live checkpoint — accumulated context after each completed step; rewritten atomically |

`manifest.status` is one of: `running`, `waiting`, `completed`, `failed`, `interrupted`.

`$OPENSOP_LOCAL_HOME` defaults to the active cell's `.opensop/` when inside a cell, else `~/.opensop-local`. Set the env var to override.

## Minimal CLAUDE.md / skill-file snippet

Paste the relevant block into your agent's `CLAUDE.md` or skill file depending on which backend you use.

### Server backend

```markdown
## OpenSOP

Check `opensop list` before doing any multi-step task — someone may have already
authored a process for it. Run with `opensop run <name> --input k=v`. Poll with
`opensop status <id>`. Advance paused steps with `opensop submit <id> <step-id>
--output k=v`. Use `opensop search` or `opensop suggest` for intent-based discovery.
```

### Local backend (no server)

```markdown
## OpenSOP (local mode)

Use `opensop run <file>.sop.json --local --input k=v` to run processes locally —
no server needed, just bash + jq.

If a run pauses (form / approval / wait / webhook callback), resume it with:
  opensop submit <run_id> <step-id> --local --output k=v

Check `opensop runs` for all local runs. `opensop show <run_id>` shows receipts.
`llm` steps require ANTHROPIC_API_KEY in the environment.
```

### Both backends (adaptive)

```markdown
## OpenSOP

Server available: use `opensop run <name> --input k=v` against the configured server.
No server / CI / edge: use `opensop run <file>.sop.json --local --input k=v`.
Paused steps (form / approval / wait / webhook): `opensop submit <run_id> <step-id> [--local] --output k=v`.
Discovery: `opensop search <keyword>` or `opensop suggest "<intent>"`.
```

## Troubleshooting

**`jq` not found:** Install jq (`brew install jq` / `apt install jq`).

**`command not found: opensop`:** The binary isn't on `$PATH`. Check `/usr/local/bin/opensop` exists and is executable (`chmod +x`).

**`llm` step fails with "ANTHROPIC_API_KEY not set":** Export the key before running: `export ANTHROPIC_API_KEY=sk-...REDACTED...`

**Run stuck in `waiting` status:** The step needs manual resume. Check `opensop show <run_id>` for the `waiting` block, then run `opensop submit <run_id> <step-id> --local --output k=v`.

**Syntax error in bin/opensop:** Run `bash -n /usr/local/bin/opensop` to check. Re-install from source to get a clean copy.

## See also

- [README](../README.md) — full command reference and worked examples
- [docs/CLAUDE-INTEGRATION.md](./CLAUDE-INTEGRATION.md) — deeper integration patterns (Pattern 1/2/3, mineralization candidates)
- [OpenSOP repo](https://github.com/Chosen9115/opensop) — reference Rails implementation
- [SPEC.md](https://github.com/Chosen9115/opensop/blob/main/SPEC.md) — process file format specification (v0.6)
