# OpenSOP

An open runtime for defining, executing, and exposing business processes as APIs.

Define a process in YAML -> get a REST endpoint -> agents and humans interact via the same API.

See SPEC.md for the full specification.

## Quick start

Requirements: Ruby 3.3.7, PostgreSQL, Node (for Tailwind), yarn/npm optional.

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails opensop:demo   # Runs a full customer-onboarding pipeline end-to-end
bin/rails server          # Visit http://localhost:3000
```

## API

- GET  /sop/                              List all processes
- GET  /sop/:name/schema                  Get a process definition
- POST /sop/:name/start                   Start an instance
- GET  /sop/:name/:id                     Inspect instance state
- GET  /sop/:name/:id/steps               List step states
- POST /sop/:name/:id/steps/:step/submit  Advance a step
- POST /sop/:name/:id/cancel              Cancel an instance
- GET  /sop/instances                     List all instances
- POST /sop/webhooks/:callback_id         Receive webhook callbacks

Auth: set `OPENSOP_API_TOKEN` and send `X-SOP-Token: <value>`. Unset = open (dev mode).

## Tests

    bin/rspec

## UI

Process Library (`/processes`), Instance Dashboard (`/instances`), Dashboard (`/`).
Process Designer and Metrics views are planned for v0.2.

## Status

MVP per SPEC.md §8. Implemented: YAML parser, instance executor, automated + form + notification step types (real), judgment + approval + webhook + subprocess + wait (stubs), API + admin UI + RSpec coverage.

Planned: LLM-backed judgment, real outbound webhook HTTP, Process Designer, Metrics/constraint detection, event bus with webhook delivery.
