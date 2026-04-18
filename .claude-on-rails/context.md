# OpenSOP — Development Context

## What This Project Is

OpenSOP is an open source platform that lets companies define, store, execute, and expose business processes (SOPs) as APIs. It's built as a Rails 8 application with both an API layer and a web UI.

## Architecture Overview

### Core Engine
- **Definition Registry** — loads and validates `.sop.yaml` process definitions
- **Instance Executor** — runs process instances, tracks state, handles step transitions
- **Store** — PostgreSQL tables for processes, instances, steps, events, callbacks
- **API Gateway** — auto-generated REST endpoints from process definitions
- **Judgment Router** — LLM integration for judgment steps (Anthropic Claude)
- **Event Bus** — emits events on state changes, delivers webhooks

### Data Model
- `sop_processes` — process definitions (parsed YAML stored as JSONB)
- `sop_instances` — running/completed process instances
- `sop_steps` — step executions (one row per step per instance)
- `sop_events` — audit log (every state change)
- `sop_callbacks` — pending webhook callbacks
- `sop_api_tokens` — API authentication tokens

### API Endpoints (under `/sop/`)
- Discovery: `GET /sop/`, `GET /sop/:name/schema`
- Execution: `POST /sop/:name/start`, `GET /sop/:name/:id`, `POST /sop/:name/:id/steps/:step_id/submit`
- Admin: `GET /sop/instances`, `GET /sop/metrics`
- Webhooks: `POST /sop/webhooks/:callback_id`

### UI (Rails views + Hotwire)
- Process Library — catalog of all defined processes
- Process Designer — visual builder for defining processes
- Instance Dashboard — view/manage running instances
- Process Metrics — step-level performance, constraint detection

### Tech Stack
- Rails 8.1.3, Ruby 3.3.7, PostgreSQL
- Hotwire (Turbo + Stimulus), Tailwind CSS, ViewComponent
- RSpec for testing, FactoryBot for fixtures
- Docker + GCP Cloud Run for deployment

## Key Patterns
- Service objects for engine logic (in `app/services/opensop/`)
- Process definitions stored as YAML, loaded into DB as JSONB
- Step execution via stdin/stdout JSON protocol (any language)
- Webhook callbacks with polling fallback
- Judgment steps with LLM provider abstraction

## File Structure Convention
```
app/
  controllers/
    sop/              # Process API controllers
    ui/               # Web UI controllers
  models/
    sop/              # Namespaced models (Process, Instance, Step, Event, etc.)
  services/
    opensop/          # Engine services (executor, parser, judgment_router, etc.)
  components/         # ViewComponent UI components
  views/
    ui/               # Web UI views
    layouts/          # Application layouts
config/
  routes/
    sop.rb            # API routes
    ui.rb             # UI routes
spec/
  requests/sop/       # API request specs
  models/sop/         # Model specs
  services/opensop/   # Engine service specs
```
