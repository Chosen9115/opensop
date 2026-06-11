# OpenSOP CLI — install instructions for agents

You are an AI coding agent (Claude Code, Codex, Cursor, etc.) that a user has asked to set up OpenSOP CLI on their machine. Follow this file end-to-end. Pause to ask the user only at the explicit `[ASK]` points below; otherwise proceed.

## What you're installing

`opensop-cli` — a single bash file that:
- runs processes locally with no server (default behavior — no daemon, no curl required), AND
- talks to OpenSOP server runtimes via the `/sop/*` HTTP API when `--remote` or `--server <url>` is passed

There is no compiled artifact, no package manager, no daemon. The file *is* the binary. Current version: **0.8.0** (local-first default).

Source of truth: <https://github.com/Chosen9115/opensop-cli> · Releases: <https://github.com/Chosen9115/opensop-cli/releases>

## Step 1 — Prerequisites check

Run these checks. If anything is missing, install it (use Homebrew on macOS, apt/yum on Linux) and re-check. Don't ask the user unless an install step would need their password.

```bash
bash --version  # need 4.0+; macOS ships 3.2 by default — install bash 4+ via `brew install bash` if 3.x is detected
jq --version    # required; install via `brew install jq` (macOS) or `apt install -y jq` (Debian/Ubuntu)
curl --version  # almost always present; install via the system package manager if not
```

If `bash --version` reports 3.x and the user is on macOS, install bash 4+ via Homebrew. Don't try to make opensop work with bash 3 — the CLI targets 4+.

## Step 2 — Install the binary

### Primary path (one-liner)

```bash
sudo curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop-cli/main/bin/opensop -o /usr/local/bin/opensop && sudo chmod +x /usr/local/bin/opensop
```

If `sudo` triggers a password prompt, **let the user enter it themselves** — do not ask them to share their password. If the user prefers not to use `sudo`, fall back to:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop-cli/main/bin/opensop -o ~/.local/bin/opensop
chmod +x ~/.local/bin/opensop
```

Then confirm `~/.local/bin` is in their `PATH` (it usually is; otherwise add `export PATH="$HOME/.local/bin:$PATH"` to their shell rc and tell them to start a new shell).

### Fallback (from source — hermetic environments)

If network access to `raw.githubusercontent.com` is blocked:

```bash
git clone https://github.com/Chosen9115/opensop-cli.git /tmp/opensop-cli
sudo cp /tmp/opensop-cli/bin/opensop /usr/local/bin/opensop
sudo chmod +x /usr/local/bin/opensop
```

## Step 3 — Verify the install

```bash
opensop --version  # must print: opensop 0.8.0
opensop --help     # must show the help text; verify the "LOCAL EXECUTION (default — no server required)" section is present
```

If `--version` reports something other than `0.8.0`, the install pulled an older cached version — re-run Step 2.

If `opensop` is not found on `PATH` after install, you installed to a directory the shell doesn't know about. Check `which opensop` and add the directory to `PATH` accordingly.

## Step 4 — Configure for the user's use case

[ASK] Two paths. Ask the user which they want, and execute the matching subsection:

**A. Local mode** — no server needed. The user wants to author and run processes on-machine (the default in v0.8+).

**B. Remote server** — the user has (or plans to have) an OpenSOP server running and wants the CLI to talk to it.

### Path A — local mode (default; recommended for first-time exploration)

No config needed. The CLI runs processes locally out of the box. To organize processes using the v0.6 cell primitive (directory-scoped resolution + lineage tracking), pick a directory to root the user's "workspace cell" in:

[ASK] Ask the user where they want their OpenSOP workspace to live (a sensible default: `~/opensop`). Then:

```bash
mkdir -p <WORKSPACE_DIR>
cd <WORKSPACE_DIR>
opensop init                              # creates .opensop/manifest.yaml — this directory is now an OpenSOP "cell"
opensop scope                             # confirms the cell is recognized
```

### Path B — point at a remote server

```bash
opensop config set url <SERVER_URL>     # e.g., https://demo.opensop.ai
opensop config set token <API_TOKEN>    # the server-issued API token
```

[ASK] Ask the user for the server URL and token. If they don't have a server yet but want to try OpenSOP, suggest the public demo: `https://demo.opensop.ai` (token: `demo-public-token-resets-daily`).

Verify:

```bash
opensop --remote list                     # should list registered processes from the server
```

## Step 5 — Walk the user through one working example

Drop a tiny example process and run it, so the user sees the CLI work end-to-end before you sign off.

For Path B (server mode), if their server already has processes, use one of those — `opensop --remote list` will show the catalog. For Path A (local mode):

```bash
mkdir -p <WORKSPACE_DIR>/processes
cat > <WORKSPACE_DIR>/processes/hello.sop.json <<'JSON'
{ "name": "hello", "inputs": {},
  "steps": [ { "id": "greet", "type": "shell", "executor": "external", "run": "echo hello from opensop" } ] }
JSON

cd <WORKSPACE_DIR>
opensop list                              # should show: [<workspace-name>]  hello  <path>
opensop run hello                         # runs the process; receipt lands in <WORKSPACE_DIR>/.opensop/runs/
opensop runs                              # lists the run
```

## Step 6 — Confirm with the user and hand off

Tell the user, in plain text:

- The CLI version they have (`opensop --version`)
- Where it was installed (`which opensop`)
- Which path they're set up for (A: server URL; B: workspace cell path)
- One next-step suggestion based on their path:
  - Path A: "Edit `processes/*.sop.json` in your workspace to author processes. `opensop run <name>` runs them. `opensop init` in a subfolder creates a nested cell that inherits processes from this one."
  - Path B: "Try `opensop --remote search <keyword>` to find processes, or `opensop --remote schema <name>` to inspect one. Add `--remote` to any command to route it to the configured server."
- Where to read more: `opensop help`, the [README](https://github.com/Chosen9115/opensop-cli#readme), or the [v0.8.0 release notes](https://github.com/Chosen9115/opensop-cli/releases/tag/v0.8.0).

## Trust boundary (read this before running anything you didn't author)

Local steps in a `.sop.json` execute **arbitrary shell on the host machine** — same posture as a `Makefile` or an npm `postinstall` script. If you (the agent) are asked to `opensop run` a process file the user has not personally authored or vetted, treat it as you would running an unknown shell script: stop and ask the user to confirm. Do not silently fetch and run `.sop.json` files from URLs.

## Common issues + how to handle them

| Symptom | Cause | Fix |
|---|---|---|
| `opensop --version` reports `0.5.0` after install | Cached or older binary in PATH | Run `which opensop` to see what's resolving; remove or replace it |
| `declare: -A: invalid option` while running a v0.6 cell-aware command | bash 3.x in use | Install bash 4+ (`brew install bash`) and re-run; the shebang `#!/usr/bin/env bash` picks the first `bash` in PATH |
| `jq: command not found` | jq missing | Install via `brew install jq` / `apt install -y jq` |
| `Permission denied` on `/usr/local/bin/opensop` | Filesystem perms or SIP | Use the `~/.local/bin/opensop` fallback in Step 2 |
| `config_missing` error on `opensop --remote list` | No URL set | Run `opensop config set url <URL>` or use `opensop --server <url> list`. |
| `not inside an OpenSOP cell` on `opensop scope` | cwd is outside the workspace cell | `cd` into the cell, or run `opensop init` to create one |
| Network blocked from `raw.githubusercontent.com` | Corporate proxy / hermetic env | Use the from-source fallback in Step 2 |

## When to stop and ask the user

You should pause and ask **only** at the explicit `[ASK]` markers above — those are decisions only the user can make (workspace location, server credentials, A-vs-B path). Everything else is mechanical: run the commands, verify, move on.

If a command fails for a reason not covered by the "Common issues" table above, report the failure to the user with the exact command and the error message, and ask for direction before retrying. Don't loop on a failing install.

---

**Done?** Tell the user OpenSOP CLI is installed at version 0.8.0 and they can start with `opensop help`.
