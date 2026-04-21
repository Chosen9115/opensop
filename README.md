# OpenSOP

An open runtime for defining, executing, and exposing business processes as APIs.

Define a process in YAML → get a REST endpoint → agents and humans interact via the same API.

## Quick start

Requirements: Ruby 3.3.7, PostgreSQL, Node (for Tailwind).

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails opensop:demo   # Runs a full customer-onboarding pipeline end-to-end
bin/rails server          # Visit http://localhost:3000
```

## Documentation

| Doc | Audience | What it covers |
|---|---|---|
| [`SPEC.md`](./SPEC.md) | Architects, contributors | The formal OpenSOP 0.1 specification — process format, semantics, design rationale |
| [`docs/API.md`](./docs/API.md) | API consumers, integrators | Complete REST reference — every endpoint with curl examples, request/response schemas, error codes |
| [`docs/AGENT_GUIDE.md`](./docs/AGENT_GUIDE.md) | AI agents, developers authoring processes | Task-oriented playbooks: author from scratch, port an existing workflow, add a new webhook integration. Includes a self-check rubric. |
| [`docs/process-authoring.md`](./docs/process-authoring.md) | Developers | How to write a `.sop.yaml` — step types, `from:` references, conditions |
| [`docs/architecture.md`](./docs/architecture.md) | Engine contributors | How the instance executor works internally |
| [`HANDOFF.md`](./HANDOFF.md) | New contributors | What's built, where things live, conventions worth keeping |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | Contributors, forks | PR workflow + fork topology for private process libraries |
| [`processes/README.md`](./processes/README.md) | Process authors | Directory layout conventions (`examples/` vs `<your-org>/`) |

### Postman / Yaak / Insomnia collection

Import [`docs/opensop.postman.json`](./docs/opensop.postman.json) into your API client to get every endpoint pre-wired with realistic example bodies. Works with:

- **Yaak:** File → Import → pick `opensop.postman.json`
- **Postman:** File → Import → pick the file
- **Insomnia:** Application menu → Import/Export → Import from File
- **Bruno:** Collection menu → Import Collection → Postman Collection

The collection captures instance IDs automatically into variables, so you can run Discovery → Start Instance → Submit Step in order without copying UUIDs by hand.

## API at a glance

```
GET  /sop/                              List all processes
GET  /sop/:name/schema                  Get a process definition
POST /sop/:name/start                   Start an instance
GET  /sop/:name/:id                     Inspect instance state
GET  /sop/:name/:id/steps               List step states
POST /sop/:name/:id/steps/:step/submit  Advance a step
POST /sop/:name/:id/cancel              Cancel an instance
GET  /sop/instances                     List all instances
POST /sop/webhooks/:callback_id         Receive webhook callbacks
```

Auth: set `OPENSOP_API_TOKEN` and send `X-SOP-Token: <value>`. Unset = open (dev mode). Full details in [`docs/API.md`](./docs/API.md).

## Tests

```bash
bin/rspec
```

## UI

Process Library (`/processes`), Instance Dashboard (`/instances`), Dashboard (`/`).
Process Designer and Metrics views are planned for v0.2.

## Status

MVP per SPEC.md §8. Implemented: YAML parser, instance executor, automated + form + notification step types (real), judgment + approval + webhook + subprocess + wait (stubs), API + admin UI + RSpec coverage.

Planned: LLM-backed judgment, real outbound webhook HTTP, Process Designer, Metrics / constraint detection, event bus with webhook delivery.
