# OpenSOP

> Open standard for processes — humans and agents.

OpenAPI describes APIs. OpenSOP describes the work behind them.

Define a business process once in YAML. OpenSOP serves it as a REST API that humans and agents drive through the same endpoints, with one audit trail.

---

## The 30-second pitch

You have a process — onboard a customer, approve an expense, triage a ticket, ship a release. Today it lives in a Notion doc, a Slack thread, and three engineers' heads. Agents can't execute it reliably. New hires re-derive it. It drifts.

OpenSOP turns the process itself into the API contract.

**Define the process** (`processes/onboarding.sop.yaml`):

```yaml
opensop: "0.1"
name: customer_onboarding
version: 1
inputs:
  - { name: company_name, type: string }
steps:
  - id: collect_details
    type: form
    fields:
      - { name: contact_email, type: email }
  - id: provision_account
    type: automated
    script: scripts/provision.rb
    inputs:
      email: { from: collect_details.contact_email }
  - id: send_welcome
    type: notification
    channel: email
    template: welcome
```

**Get the API** (no glue code):

```bash
$ curl -X POST localhost:3000/sop/customer_onboarding/start \
    -H "X-SOP-Token: $TOKEN" \
    -d '{"company_name": "Acme"}'

{ "instance_id": "01HX...", "next_step": "collect_details" }
```

**Humans and agents drive it the same way.** A human submits the form via the UI. An agent submits it via `POST /sop/customer_onboarding/:id/steps/collect_details/submit`. Same endpoint. Same state. Same audit log.

---

## Why this exists

Three jobs that today live in three disconnected places:

- **Operations writes the runbook** in Notion or Confluence — readable, but dead.
- **Engineering builds the API** — alive, but drifting from the runbook.
- **AI agents need a contract** — they get neither, and improvise.

OpenSOP collapses all three into one artifact. The runbook is the API. The API is what agents call. Operations, engineering, and AI share one source of truth for how the company actually does the work.

---

## The standard

A process is a sequence of typed steps. OpenSOP defines eight step types, each with strict semantics:

| Step type | What it does |
|---|---|
| `form` | Collect data from a human or agent |
| `automated` | Run a script (any language, detected by extension) |
| `judgment` | LLM or human decision, with confidence threshold and escalation |
| `approval` | Binary gate — a human must approve or reject |
| `webhook` | Outbound HTTP call (sync, callback, or poll) |
| `subprocess` | Start another OpenSOP process |
| `notification` | Fire-and-forget message (email, Slack, SMS) |
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

Auth: set `OPENSOP_API_TOKEN`, send `X-SOP-Token: <value>` on every request. Full reference in [`docs/API.md`](./docs/API.md).

---

## Run it locally

Requirements: Ruby 3.3.7, PostgreSQL, Node (for Tailwind).

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails opensop:demo     # End-to-end customer-onboarding pipeline
bin/rails server           # http://localhost:3000
```

`opensop:demo` runs a full process from start to finish — form submission, automated step, notification — and prints the audit trail. If that runs cleanly, your install is sound.

---

## What's real, what's stubbed

OpenSOP is at MVP per [`SPEC.md`](./SPEC.md) §8. Honest accounting:

- **Implemented:** YAML parser, instance executor, REST API, admin UI, RSpec coverage. `form`, `automated`, and `notification` step types are real.
- **Stubbed** (still callable, but no I/O): `judgment`, `approval`, `webhook`, `subprocess`, `wait`. State transitions work; side effects don't yet.
- **Planned for v0.2:** LLM-backed judgment, real outbound webhook delivery, Process Designer UI, metrics and constraint detection.

---

## Documentation

| Doc | For | Covers |
|---|---|---|
| [`SPEC.md`](./SPEC.md) | Architects | Formal OpenSOP 0.1 specification |
| [`docs/API.md`](./docs/API.md) | Integrators | Every endpoint, with curl examples |
| [`docs/AGENT_GUIDE.md`](./docs/AGENT_GUIDE.md) | Agent builders | Authoring playbooks + self-check rubric |
| [`docs/process-authoring.md`](./docs/process-authoring.md) | Process authors | How to write a `.sop.yaml` |
| [`docs/architecture.md`](./docs/architecture.md) | Contributors | How the executor works internally |
| [`HANDOFF.md`](./HANDOFF.md) | New contributors | Where things live, conventions |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | Forks | PR workflow + private process libraries |

A pre-wired Postman/Yaak/Insomnia/Bruno collection is at [`docs/opensop.postman.json`](./docs/opensop.postman.json).

---

## Used in production

[Coba](https://coba.ai) runs its internal operations on OpenSOP. Improvements that come out of that work flow upstream first.

---

## Contributing

PRs welcome. Read [`CONTRIBUTING.md`](./CONTRIBUTING.md) first — especially if you're forking to keep a private process library alongside the public engine.

## License

MIT. See [`LICENSE`](./LICENSE).

---

**If this idea matters to you, [⭐ star the repo](https://github.com/Chosen9115/opensop).** It's how we know the standard has a future.
