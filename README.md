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
process:
  name: customer-onboarding
  version: "1.0"
  trigger:
    type: api
  inputs:
    - name: company_name
      type: string
      required: true
  steps:
    - id: collect-details
      name: "Collect contact details"
      type: form
      outputs:
        - name: contact_email
          type: string
          format: email

    - id: provision-account
      name: "Provision account"
      type: automated
      run: ./scripts/provision.rb
      inputs:
        - name: email
          from: steps.collect-details.outputs.contact_email
      outputs:
        - name: account_id
          type: string

    - id: send-welcome
      name: "Send welcome email"
      type: notification
      inputs:
        - name: account_id
          from: steps.provision-account.outputs.account_id
```

**Get the API** (no glue code):

```bash
$ curl -X POST localhost:3000/sop/customer-onboarding/start \
    -H "X-SOP-Token: $TOKEN" \
    -d '{"company_name": "Acme"}'

{ "instance_id": "01HX...", "next_step": "collect-details" }
```

**Humans and agents drive it the same way.** A human submits the form via the UI. An agent submits it via `POST /sop/customer-onboarding/:id/steps/collect-details/submit`. Same endpoint. Same state. Same audit log.

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

## Authentication

OpenSOP uses **passkeys** (WebAuthn) for admin UI authentication. Each deployment supports multiple admin users; sign-in is sole-factor (the passkey is multi-factor by definition — biometric + device).

### Required environment variables (production)

| Variable | Purpose |
|---|---|
| `RESEND_API_KEY` | Resend API key for delivery |
| `OPENSOP_MAILER_FROM` | From address, e.g. `"OpenSOP <noreply@your-domain>"` |
| `OPENSOP_RP_ID` | WebAuthn relying-party ID (apex domain) |
| `OPENSOP_ORIGIN` | Full origin, e.g. `https://opensop.your-domain.com` |
| `OPENSOP_BOOTSTRAP_EMAIL` | Email for the first admin (only honored once on a fresh deploy) |
| `OPENSOP_RP_NAME` | (optional) Display name. Defaults to `OpenSOP`. |
| `OPENSOP_MAILER_MODE` | (optional) `send` (prod default) or `log` (dev/test default) |

### First-run bootstrap

Set `OPENSOP_BOOTSTRAP_EMAIL` to the email you want to use as the first admin. On boot, OpenSOP will:

1. Create a `User` row with that email
2. Issue a one-time invitation token (valid 7 days)
3. Print the invitation URL to the application logs
4. Write the URL to `tmp/opensop_first_login.txt` (mode 0600)

Visit the URL, register your first passkey on a device that supports WebAuthn (any modern Mac, iPhone, Android, Windows Hello, or hardware key), and you're signed in. From there:

- Manage your passkeys at `/account/passkeys`
- Invite additional admins at `/account/users`
- View active sessions at `/account/sessions`

### Account recovery

If you lose all your passkeys, click **"I lost my passkey"** on the sign-in page. We'll email a one-time recovery link. From there you can register a new passkey or revoke all and start over.

### Lost/forgot bootstrap email?

If `User.count == 0`, just set `OPENSOP_BOOTSTRAP_EMAIL` and redeploy — the bootstrap will run again. Otherwise sign in as any existing admin and use `/account/users` to invite the right one.

### API authentication

API endpoints under `/sop/*` continue to use the `X-SOP-Token` header backed by `OPENSOP_API_TOKEN`. This is unchanged.

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
