<p align="center">
  <img src="docs/images/hero.png" alt="A person and a small robot walking together down a stone path toward the mountains and the rising sun." width="100%" />
</p>

# OpenSOP

> Process as Infrastructure for agentic processes.

**Terraform is to cloud resources what OpenSOP is to agentic processes.**

Agentic processes are infrastructure. Version them. Fork them. Run them locally, with no server. Keep the receipts.

Read [MANIFESTO.md](./MANIFESTO.md) for the full thesis.

---

## The problem

Agents are good at doing steps and bad at remembering which steps. Left alone, an agent re-invents the procedure every time — slowly, inconsistently, unauditably. And when a step fails, it fills the gap with confident-sounding prose instead of stopping.

A morning briefing makes this concrete. Pull Slack, Gmail, Calendar, Notion, then synthesize. Without a harness, Calendar times out at 7:51:34. The agent doesn't say that — it says _"your schedule looks clear this morning."_ You had two meetings.

**OpenSOP makes "the agent can't launder missing data" mechanical.** A process declares its steps; each step declares what it requires. When Calendar fails, the runtime stops. It does not ask the LLM to fill the gap. You get back exactly what was collected — with a receipt.

---

## Quick start (local, no server)

```bash
# 1. Install the CLI (one file, deps: bash 4+ + jq)
curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop/main/cli/bin/opensop \
  -o opensop && chmod +x opensop

# 2. Initialize a process cell in your project
./opensop init

# 3. Author a process (or ask your agent to write one)
cat > greet.sop.json <<'EOF'
{
  "opensop": "0.6",
  "process": {
    "name": "greet",
    "version": "1.0",
    "description": "A simple greeting process",
    "inputs": [{ "name": "name", "type": "string", "required": true }],
    "steps": [
      {
        "id": "say-hello",
        "name": "Say hello",
        "type": "automated",
        "run": "echo \"Hello, $OSL_INPUT_NAME!\""
      }
    ]
  }
}
EOF

# 4. Run it — no server, no network, no account
./opensop run ./greet.sop.json --input name=Ana
```

Every run writes append-only receipts under `.opensop/runs/<id>/`. Query them with `opensop show <run_id>`.

---

## The CLI is the primary interface

`cli/bin/opensop` is a single bash file with no build step, no package manager, no compiled artifact. It is the product. The file is the binary.

**Local execution is the default.** `run`, `list`, `search`, `suggest`, `status`, `steps`, `diff`, `runs`, `show` — all execute locally against `.sop.json` files with no server, no curl, no account. Remote is opt-in.

```bash
# Local (default — no server):
opensop run ./morning-briefing.sop.json --input date=2026-06-11
opensop submit <run_id> fetch-calendar --output success=true --output events='{...}'
opensop status <run_id>
opensop list
opensop runs
opensop show <run_id>

# Remote (opt-in — requires a running OpenSOP server):
opensop config set url https://your-server.example.com
opensop config set token $TOKEN
opensop --remote list
opensop --remote run lead-qualification --input lead_name="Ana García"
opensop --remote status <run-id>
opensop --server https://your-server.example.com register ./my-process.sop.yaml
```

`--local` is a deprecated no-op kept for script compatibility. Local is now the default.

`register` and `schema <name>` (server-side schema fetch) are remote-only — they talk to a running OpenSOP server.

**Install:**

```bash
curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop/main/cli/bin/opensop \
  -o opensop && chmod +x opensop
```

The CLI source lives at [`cli/bin/opensop`](./cli/bin/opensop) in this repo.

---

## A process is a file

One serialization, one model (SPEC v0.6):

- **`.sop.json`** — the canonical format for local CLI execution (what `opensop run` reads)
- **`.sop.yaml`** — YAML variant accepted by server implementations for `POST /sop/processes/register`

The same process lives in your repo, reviews in your PRs, ships in your commits. Fork it. Version it. The lineage is recorded, not copied-and-forgotten in a doc.

The morning-briefing process:

```yaml
opensop: "0.6"
process:
  name: morning-briefing
  version: "1.0"
  trigger: { type: schedule, cron: "50 7 * * 1-5" }
  inputs:
    - { name: date, type: string, format: date, required: true }
  steps:
    - id: fetch-slack
      name: Fetch Slack
      type: automated
      run: ./scripts/fetch-slack.sh
      outputs:
        - { name: success, type: boolean }
        - { name: unread_count, type: number }

    - id: fetch-gmail
      name: Fetch Gmail
      type: automated
      run: ./scripts/fetch-gmail.sh
      outputs:
        - { name: success, type: boolean }

    - id: fetch-calendar
      name: Fetch Calendar
      type: automated
      run: ./scripts/fetch-calendar.sh
      outputs:
        - { name: success, type: boolean }
        - { name: events, type: object }

    - id: synthesize
      name: Synthesize brief
      type: llm
      model: claude-opus-4-7
      expected_output_schema:
        brief: string
      condition: |
        steps.fetch-slack.outputs.success == true &&
        steps.fetch-gmail.outputs.success == true &&
        steps.fetch-calendar.outputs.success == true
      prompt: "Synthesize a 200-word brief from these sources..."
      outputs:
        - { name: brief, type: string }

    - id: deliver
      name: Deliver to Slack
      type: notification
      channel: slack
      to: "#daily-briefings"
      body: "{{ steps.synthesize.outputs.brief }}"
```

The `condition:` on the synthesize step is what makes "the agent can't launder missing data" mechanical: if any fetch returned `success: false`, the LLM is never asked.

---

## The standard

Twelve step types, strict semantics:

| Step type | What it does | Local execution |
|---|---|---|
| `automated` | Run a script (any language, detected by extension) | Full |
| `shell` | Alias for `automated` | Full |
| `noop` | No-op placeholder; passes context through | Full |
| `form` | Collect data from a human or agent | Pauses (waiting_for_input); resume via `submit` |
| `approval` | Binary gate — a human must approve or reject | Pauses (waiting_for_approval); resume via `submit` |
| `wait` | Pause until a condition or timer | `wait.seconds` completes immediately; `wait.until` pauses |
| `llm` | Direct LLM call with prompt + expected output schema | Full (requires `ANTHROPIC_API_KEY`; model must start with `claude`) |
| `webhook` | Outbound HTTP call (sync or callback) | Sync completes with response; callback pauses |
| `subprocess` | Start another OpenSOP process | Full (depth-guarded at 16 levels) |
| `notification` | Fire-and-forget message (email, Slack, SMS) | Server-side only |
| `judgment` | LLM or human decision with confidence threshold and escalation | Server-side only |
| `loop` | Iterate over a list, accumulating outputs | Server-side only |

Full grammar in [`SPEC.md`](./SPEC.md).

---

## Real-world proof: gbrain, mineralized

To stress-test the "agents plan, runtime runs" thesis, we OpenSOPized six workflows from [gbrain](https://github.com/garrytan/gbrain) (Garry Tan's open-source knowledge brain for agents):

| Process | Steps | LLM steps | Deterministic steps |
|---|---|---|---|
| `gbrain-meeting-ingest` | 8 | 1 | 7 |
| `gbrain-data-research-tracker` | 9 | 1–2 | 7–8 |
| `gbrain-dream-consolidation-audit` | 7 | 1 | 6 |
| `gbrain-skill-authoring` | 9 | 2 | 7 |
| `gbrain-retrieval-regression` | 10 | 1 | 9 |
| `gbrain-upgrade-migration` | 14 | 1 | 13 |
| **Total across 6 processes** | **57** | **~7** | **~50** |

~88% of agent operations moved from LLM calls to deterministic code. Most "agent decisions" weren't really decisions — they were CLI calls or data fetches dressed up as cognitive work.

---

## Optional server

The CLI runs processes locally with no server. When you need shared orchestration, a team audit log, or a monitoring UI, you can point the CLI at a server implementation of the [SPEC.md](./SPEC.md) `/sop/*` contract.

**Reference implementation:** [Chosen9115/opensop-rails](https://github.com/Chosen9115/opensop-rails) — a Rails 8 server that implements the full spec. It adds:

- **Team visibility** — shared audit log, admin UI dashboard, process metrics
- **Shared orchestration** — multi-actor workflows where humans and agents drive the same endpoints
- **Webhook-triggered processes** — HMAC-verified inbound triggers with `input_mapping`
- **Auto-generated REST API** — every registered process gets the same endpoints automatically

The `/sop/*` API contract is specified in [`SPEC.md`](./SPEC.md). Any conforming server works with the CLI's `--remote` flag — you are not locked to the reference implementation.

---

## Status

OpenSOP is at MVP per [`SPEC.md`](./SPEC.md) §8. Honest accounting:

**Local CLI (v0.8.0):**
- `automated`, `shell`, `noop`, `llm`, `webhook` (sync), `subprocess`, `form`, `approval`, `wait` (seconds) — full local execution
- `wait` (until) — pauses run; resume via `submit`; long-timer support tracked
- `webhook` (callback) — pauses run; local callback wiring not yet implemented
- Cells / fractal addressing (v0.6) — `init`, `scope`, `fork`, `lineage`, `annotate`

**Reference server (opensop-rails):**
- Real and exercised in production: YAML parser, instance executor, REST API, admin UI, RSpec coverage, audit-trail receipts. Step types that execute fully end-to-end: `form`, `automated`, `webhook` (sync + callback modes), `loop`, `llm`. Third-party webhook triggers (`trigger: type: webhook`) are real — HMAC-verified, with `input_mapping` templating.
- Partial: `judgment` (LLM routing wired via the CLI; server-side LLM router pending), `approval` (state transitions work; no human-facing approval queue UI yet), `notification` (state machine + parsing complete; executor returns `notified: true` without dispatching — wire your channel adapters before relying on it), `subprocess` (parses; doesn't yet spawn the child instance), `wait` (returns immediately for `seconds:` durations; long timer support tracked).
- Planned next: `webhook` poll-mode response, replay protection for inbound triggers, LLM-backed judgment router, subprocess execution, real `wait` timers, Process Designer UI, metrics + constraint detection, embedding-based `suggest` once catalogs cross ~150 entries.

---

## Used internally at Coba

[Coba](https://coba.ai) runs internal operations and scheduled engineering agents on OpenSOP. Improvements that come out of that work flow upstream first.

`opensop-worker` is a Rust daemon scheduling specialized agents across Rails projects. They review PRs, bump dependencies, resolve conflicts, re-run CI, generate `AGENTS.md` files, write release notes, and handle the small engineering chores humans usually defer or forget. Each job is a typed `.sop.yaml` process — named steps, bounded inputs and outputs, structured prompts, parsed responses, size caps, git diff checks, append-only receipts. The agents do the creative work. OpenSOP provides the rails.

---

## Documentation

| Doc | For | Covers |
|---|---|---|
| [`MANIFESTO.md`](./MANIFESTO.md) | Everyone | The thesis — why processes are infrastructure |
| [`SPEC.md`](./SPEC.md) | Architects + implementors | Formal OpenSOP 0.6 specification and `/sop/*` API contract |
| [`docs/AGENTS.md`](./docs/AGENTS.md) | Agent builders + process authors | Install, format reference, authoring playbook, self-check rubric |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | Forks | PR workflow + private process libraries |
| [opensop-rails](https://github.com/Chosen9115/opensop-rails) | Self-hosters | Reference server: install, API docs, architecture |

---

## Contributing

PRs welcome. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) first — especially if you're forking to keep a private process library alongside the public engine.

## License

Apache 2.0. See [`LICENSE`](./LICENSE).

---

**Ready to ship your first process?** Install the CLI, run `opensop init`, author a `.sop.json`, run it. No server required.

[Star the repo](https://github.com/Chosen9115/opensop) if OpenSOP is useful — it tells us the standard is worth hardening.
