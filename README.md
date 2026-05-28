<p align="center">
  <img src="docs/images/hero.png" alt="A person and a small robot walking together down a stone path toward the mountains and the rising sun." width="100%" />
</p>

# OpenSOP

> The open standard for executable processes. Define once in YAML, run as a typed REST API, observe with append-only receipts.

**OpenAPI describes APIs. OpenSOP describes the work behind them.**

OpenSOP is not a no-code workflow builder. It is not an LLM orchestration framework. It is not a BPM tool with a new paintjob. It is a specification format with a reference runtime: define a process in YAML, get a typed REST API, collect append-only receipts. That's the full contract.

A customer reports a bad parse at 2 a.m. You open the logs. Nothing useful. The engineer who wrote the script left six months ago. The Notion runbook is two product cycles stale.

This is a process-storage problem, not a debugging problem. The process lived in three disconnected places — a Notion doc, a Slack thread, and three engineers' heads — and none of them were queryable. Humans forget them. Agents improvise around them. The process drifts.

OpenSOP collapses all three into one artifact. Write the process in YAML. Get a typed REST API for free. Humans submit forms; agents POST JSON; both drive the same endpoints, against the same state, with the same audit log.

---

## Try it in 30 seconds

**Exploring?** Hit the live demo — no install, resets daily:

```bash
curl -H "X-SOP-Token: demo-public-token-resets-daily" https://demo.opensop.ai/sop/
```

**Setting up for your team?** Tell your AI agent (Claude Code, Cursor, codex, …):

> _Read and follow https://raw.githubusercontent.com/Chosen9115/opensop/main/INSTALL_FOR_AGENTS.md to set up OpenSOP for me._

**Prefer to run it yourself?**

```bash
curl -fsSL https://raw.githubusercontent.com/Chosen9115/opensop/main/scripts/install.sh | bash
```

Working OpenSOP at `http://localhost:3000` in about 90 seconds. For manual setup see [`INSTALL.md`](./INSTALL.md).

---

## What changes when you use OpenSOP

Three places where it pays off, in order of leverage:

- **Pre-deploy gates that block regressions before they merge.** A `condition:` on a `webhook` step ("only deploy if the test suite returned green") is one YAML line. Engineering finds out about regressions before reverting, not after.
- **~10× faster MTTR on production bugs.** When a customer reports a parsing bug, you don't `fly logs | grep | reconstruct`. You query `step_states` for that instance. Inputs, outputs, retries, durations — every step's full state lives queryably in SQLite/Postgres.
- **One artifact is the runbook, the API, and the onboarding doc.** `parse-customer-ddq.sop.yaml` is the spec, the executable contract, and the doc you hand to a new ops person. No more three-source drift.

LLMs are good at judgment, synthesis, and code generation. They are bad at staying inside operational boundaries. **OpenSOP keeps the creative part narrow.** Each agentic workflow is a named process with typed inputs, explicit outputs, structured prompts, schema validation, size caps, critical-path exclusions, and ground-truth checks before side effects. The LLM does the part it's good at. The runtime catches schema drift, hallucinated files, scope creep, and unsafe changes before they touch production.

---

## Agents plan. The runtime runs.

We built OpenSOP because we got tired of agents saying they did things when they didn't. We wanted to audit their work — and then noticed something else: most of what we were asking agents to do was deterministic. CLI calls. File reads. Data fetches. **What's better than an agent at deterministic work than an actual code runtime? Cheaper than tokens, faster than an agent, consistent and reliable.**

So OpenSOP splits the contract. The agent's job is the creative bits — synthesis, judgment, the parts that genuinely require intelligence. The runtime's job is everything else: ordering steps, blocking until each one returns, refusing to advance when a required input is missing, writing an auditable log after every run. **The agent doesn't run the process. The runtime does.**

A morning briefing makes this concrete. You ask for one: pull Slack, Gmail, Calendar, Notion, Circleback, then synthesize. Four of those are CLI calls. One requires an LLM.

Without a harness, the Calendar API times out at 7:51:34. The agent doesn't say that. It says _"your schedule looks clear this morning — no urgent meetings flagged."_ You start your day assuming you're free. You had two meetings. You missed them. No exception thrown, no log entry — just absence of data laundered into a clean sentence.

With OpenSOP, that briefing is a process. Five steps, each a deterministic CLI fetch with a required `success: true` output. Calendar fails at step three; the runtime stops. It does not ask the LLM to fill the gap. You get back exactly what was collected — _"Slack ✓ (3 unread DMs), Gmail ✓ (14 threads), Calendar unavailable at 07:51:34, Notion + Circleback skipped, synthesis not run"_ — with a receipt. Honest, partial, useful.

Better yet: **agents can write the process for you.** A new `.sop.yaml` takes seconds with the right prompt. **Create, test, audit, iterate, improve, cement** — now you have a process that runs without an agent in the loop. Auditability is the superpower; reliability is the moat. Your processes — not the agent, not the model — are what compound.

---

## Define once, get the API

The YAML:

```yaml
opensop: "0.1"
process:
  name: customer-onboarding
  version: "1.0"
  trigger: { type: api }
  inputs:
    - { name: company_name, type: string, required: true }
  steps:
    - id: collect-details
      type: form
      outputs:
        - { name: contact_email, type: string, format: email }

    - id: provision-account
      type: automated
      run: ./scripts/provision.rb
      inputs:
        - { name: email, from: steps.collect-details.outputs.contact_email }
      outputs:
        - { name: account_id, type: string }

    - id: send-welcome
      type: notification
      inputs:
        - { name: account_id, from: steps.provision-account.outputs.account_id }
```

The API (auto-generated, no glue code):

```bash
$ curl -X POST localhost:3000/sop/customer-onboarding/start \
    -H "X-SOP-Token: $TOKEN" \
    -d '{"company_name": "Acme"}'

{ "instance_id": "01HX...", "state": "running" }
```

Humans and agents drive it the same way. A human submits the form via the admin UI. An agent submits via `POST /sop/customer-onboarding/<id>/steps/collect-details/submit`. Same endpoint. Same state. Same audit log.

---

## Which runtime fits your work?

Two runtimes, one spec. Both consume the same `.sop.yaml` files and produce the same receipts. The difference is lifetime and audience:

| | **Hosted runtime** (this repo) | **Portable runtime** ([`opensop-cli`](https://github.com/Chosen9115/opensop-cli)) |
|---|---|---|
| **Best for** | Multi-team workflows: DDQs, customer onboarding, expense approval, release deploys, week-long async flows | Agent-embedded skills: cron-driven routines, CI checks, mineralized agent procedures |
| **Lifetime** | Always-on Rails app | Ephemeral — invoked, executes, exits |
| **State** | Central Postgres + dashboard | Per-workdir `.opensop/` directory |
| **Async patterns** | Native — `wait`, approvals, callback webhooks, escalations | Synchronous; long-running async hands off to a hosted runtime |
| **Audience** | Humans + teams who need a dashboard | Single agents who need a contract |
| **Install** | `docker compose up` (this repo) | `curl \| sh` (the CLI repo) |

Most stacks end up using both. An agent runs a mineralized skill locally on the portable runtime; when the result needs to be visible across the team, `opensop push` syncs the receipts to the hosted dashboard. The spec is the wire format; the runtimes coexist.

---

## The companion CLI

[`opensop-cli`](https://github.com/Chosen9115/opensop-cli) is a single-file bash client that talks to any OpenSOP runtime. It's also where most agents start their work:

```bash
opensop search "qualify a sales lead"          # ranked text retrieval over registered processes
opensop suggest "I want to review a PR"        # inverse retrieval — describe the task, get a process
opensop schema lead-qualification              # inspect inputs, outputs, steps
opensop dry-run lead-qualification --input ... # validate inputs + walk what each step would do, no execution
opensop run lead-qualification --input ...     # start an instance
opensop status <id>                            # poll until completed
opensop diff <id1> <id2>                       # compare two runs of the same process
opensop schema validate ./my.sop.yaml          # lint a process spec before registering
```

The CLI's design center is **discovery latency** — the time between "I have a task" and "there's already a process for that." If an agent can't quickly answer the second, it re-derives the steps from scratch every time. `search` and `suggest` close that gap, which is the reason agents reach for OpenSOP at all.

---

## The standard

Ten step types, strict semantics:

| Step type | What it does |
|---|---|
| `form` | Collect data from a human or agent |
| `automated` | Run a script (any language, detected by extension) |
| `judgment` | LLM or human decision with confidence threshold and escalation |
| `approval` | Binary gate — a human must approve or reject |
| `webhook` | Outbound HTTP call (sync, callback, or poll) |
| `subprocess` | Start another OpenSOP process |
| `notification` | Fire-and-forget message (email, Slack, SMS) |
| `loop` | Iterate over a list, accumulating outputs |
| `llm` | Direct LLM call with prompt + tools + expected output schema |
| `wait` | Pause until a condition or timer |

Steps reference upstream outputs via `from:`. Conditions are simple boolean expressions. The full grammar is in [`SPEC.md`](./SPEC.md).

---

## The API surface

Every process gets the same endpoints, automatically:

```
GET  /sop/                              List processes
GET  /sop/:name/schema                  Get process definition
POST /sop/:name/start                   Start an instance
GET  /sop/:name/:id                     Inspect instance state
GET  /sop/:name/:id/steps               List step states
POST /sop/:name/:id/steps/:step/submit  Advance a step
POST /sop/:name/:id/cancel              Cancel an instance
GET  /sop/instances                     List all instances
POST /sop/webhooks/:callback_id         Receive webhook callbacks
```

Auth: set `OPENSOP_API_TOKEN`, send `X-SOP-Token: <value>` on every request. Admin UI uses passkeys (WebAuthn). Full reference in [`docs/API.md`](./docs/API.md); first-admin bootstrap in [`INSTALL.md`](./INSTALL.md).

---

## Used internally at Coba

[Coba](https://coba.ai) runs internal operations and scheduled engineering agents on OpenSOP. Improvements that come out of that work flow upstream first.

We use OpenSOP to harness our own army of agents — running development operations and internal admin workflows. Reliably.

`opensop-worker` is one of them: a Rust daemon scheduling 11 specialized agents across our Rails projects. The agents review PRs, bump dependencies, resolve conflicts, re-run CI, generate `AGENTS.md` files, write release notes, and handle small engineering chores humans usually defer or forget. Each job is a typed process with named steps, bounded inputs and outputs, structured prompts, parsed responses, size caps, git diff checks, and append-only receipts. **The agents do the creative work. OpenSOP provides the rails.**

---

## Status

OpenSOP is at MVP per [`SPEC.md`](./SPEC.md) §8. Honest accounting:

- **Real and exercised in production**: YAML parser, instance executor, REST API, admin UI, RSpec coverage, audit-trail receipts. The following step types execute fully end-to-end: `form`, `automated`, `notification`, `webhook` (sync + callback modes), `loop`, `llm`.
- **Partial**: `judgment` (LLM routing wired via the CLI; server-side LLM router pending), `approval` (state transitions work; no human-facing approval queue UI yet), `subprocess` (parses; doesn't yet spawn the child instance), `wait` (returns immediately for `seconds:` durations; long timer support tracked).
- **Planned next**: `webhook` poll-mode response, replay protection for inbound triggers, Process Designer UI, metrics + constraint detection, embedding-based `suggest` once catalogs cross ~150 entries.

---

## Documentation

| Doc | For | Covers |
|---|---|---|
| [`INSTALL.md`](./INSTALL.md) · [`INSTALL_FOR_AGENTS.md`](./INSTALL_FOR_AGENTS.md) | Self-hosters | Full install + first-admin bootstrap (human-readable and agent-readable variants) |
| [`SPEC.md`](./SPEC.md) | Architects | Formal OpenSOP 0.1 specification |
| [`docs/API.md`](./docs/API.md) | Integrators | Every endpoint, with curl examples |
| [`docs/AGENT_GUIDE.md`](./docs/AGENT_GUIDE.md) | Agent builders | Authoring playbooks + self-check rubric |
| [`docs/process-authoring.md`](./docs/process-authoring.md) | Process authors | How to write a `.sop.yaml` |
| [`docs/architecture.md`](./docs/architecture.md) | Contributors | How the executor works internally |
| [`HANDOFF.md`](./HANDOFF.md) | New contributors | Where things live, conventions |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | Forks | PR workflow + private process libraries |

A pre-wired Postman/Yaak/Insomnia/Bruno collection is at [`docs/opensop.postman.json`](./docs/opensop.postman.json).

---

## Contributing

PRs welcome. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) first — especially if you're forking to keep a private process library alongside the public engine.

## License

Apache 2.0. See [`LICENSE`](./LICENSE).

---

**Ready to ship your first process?** The fastest path is the agent one-liner at the top of this file. If you'd rather read first: [`INSTALL.md`](./INSTALL.md) for humans, [`INSTALL_FOR_AGENTS.md`](./INSTALL_FOR_AGENTS.md) for agents.

[Star the repo](https://github.com/Chosen9115/opensop) if OpenSOP is useful — it tells us the standard is worth hardening.
