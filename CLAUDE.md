## OpenSOP Configuration

- **Rails 8.1.3** / **Ruby 3.3.7** / **RSpec** / **Hotwire (Turbo + Stimulus)** / **importmap** / **Tailwind CSS** / **PostgreSQL**
- Review swarm config at `.claude-on-rails/context.md`
- Read the full product spec at `SPEC.md`

## What OpenSOP Is

OpenSOP is an open standard and runtime for defining, storing, executing, and exposing business processes (SOPs) as APIs. A company defines their processes as structured YAML (or via the UI), and the platform automatically exposes them as REST endpoints. Agents and humans interact with processes through the same API.

**Core primitives:** Process, Step, Field, Instance.
**Step types:** form, automated, judgment, approval, webhook, subprocess, notification, wait.
**The key insight:** The process definition IS the API contract. Define a process, get an API.

## Workflow Guidelines

### 1. Plan Before Building
- For architectural decisions or multi-step tasks, outline your approach before writing code
- If something goes sideways, stop and re-plan — don't keep pushing a broken approach
- Write detailed specs upfront to reduce ambiguity

### 2. Refine Before Planning (MANDATORY for feature requests)
- **You MUST invoke the prompt-refiner skill (hybrid mode) before planning any new feature** — do NOT skip this step or plan directly
- If the skill is not installed, install it automatically by running: `mkdir -p ~/.claude/skills/prompt-refiner && curl -sL https://raw.githubusercontent.com/kurenn/prompt-refiner-skill/main/SKILL.md -o ~/.claude/skills/prompt-refiner/SKILL.md` — then proceed with the skill
- The refined spec becomes the source of truth for the swarm — all specialist tasks derive from it
- Skip refinement only for bug fixes, small tweaks, or tasks where the user provides a detailed spec already

### 3. Subagent Strategy (MANDATORY)
- **You MUST delegate implementation to specialist agents** — do NOT edit files directly when a specialist agent exists for that domain
- The architect (you) plans the work, breaks it into tasks by Rails layer, and delegates each piece to the appropriate specialist
- One task per specialist for focused execution
- Coordinate results and verify the specialists' output works together
- Only use Read/Grep/Glob directly for research and planning — all code changes go through specialists

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Run tests, check logs, demonstrate correctness
- Diff behavior between main and your changes when relevant

### 5. Autonomous Bug Fixing
- When given a bug report: fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them

## Domain-Specific Rules

### Process Definition Format
- Process definitions are YAML files with extension `.sop.yaml`
- The `opensop` key at root specifies the format version (currently `"0.1"`)
- Every process has: name, version, description, inputs, outputs, steps
- Steps reference previous step outputs via `from:` syntax
- Conditions use simple boolean expressions
- See `SPEC.md` §2 for the full format specification

### Step Types
- `form` — collects data from human or agent
- `automated` — runs a script (any language, detected by extension)
- `judgment` — LLM or human decision, with confidence threshold and escalation
- `approval` — binary gate, human must approve/reject
- `webhook` — outbound HTTP call, supports sync/callback/poll response modes
- `subprocess` — starts another OpenSOP process
- `notification` — fire-and-forget message (email, Slack, SMS)
- `wait` — pause until condition or timer

### API Convention
All process API endpoints live under `/sop/`:
- `GET /sop/` — discovery (list all processes)
- `GET /sop/:name/schema` — process definition
- `POST /sop/:name/start` — start instance
- `GET /sop/:name/:id` — instance state
- `GET /sop/:name/:id/steps` — all step states
- `POST /sop/:name/:id/steps/:step_id/submit` — advance a step
- `POST /sop/:name/:id/cancel` — cancel instance
- `GET /sop/instances` — list all instances
- `GET /sop/metrics` — process metrics
- `POST /sop/webhooks/:callback_id` — receive webhook callbacks

### Auth
- API key auth via `X-SOP-Token` header
- Process-level access control defined in process YAML

## Task Specification Template

When starting any non-trivial implementation, structure the work as follows before writing code:

### What
[One sentence: what the user sees when this is done]

### User Flow
1. [Page/screen -> action -> result]
2. [...]

### Constraints
- Files to modify: [list, or "only existing files"]
- Schema changes: yes/no
- New routes: [list, or "none"]
- New dependencies: [list, or "none"]
- Must preserve: [list existing behavior that must not break]

### Implementation Order
1. [data/schema/service layer]
2. [API/route layer]
3. [UI/view layer]
4. [specs — request specs for new/changed endpoints, component specs for new/changed components]

### Execution Strategy
Before writing any code, assess whether to parallelize:

**Parallelize when ALL of these are true:**
- Work splits into 2+ groups with NO shared files
- Each group can build/compile independently
- Task touches 5+ files across 2+ layers

**If parallelizing:** create a table of agents with disjoint file ownership, run independent agents in background worktrees, then run a final integration agent in foreground.

**Otherwise:** execute the implementation order sequentially in a single thread.

### Success Metrics
Each agent (or sequential step) must have a concrete, verifiable exit condition.

| Step | Metric | How to verify |
|------|--------|---------------|
| Schema/data | Migrations run, seed succeeds | `rails db:migrate` |
| API/routes | All endpoint tests pass | `bundle exec rspec spec/requests/...` |
| UI | Components render without errors | `bundle exec rspec spec/components/...` |
| Specs | New/changed behavior has spec coverage | `bundle exec rspec <relevant spec files>` |
| Integration | Full user flow works end-to-end | [specific test command or manual steps] |

### Review Phase
After all implementation is complete, run two review agents in parallel:

**Technical Review Agent:**
- Run the full test suite, report pass/fail with specifics
- Walk through each user flow step and verify correct responses
- Check for regressions

**UI Review Agent:**
- Take screenshots of each step in the user flow
- Check: correct content renders, correct order, no layout breakage, interactive elements work

Both review agents report back. If either flags issues, fix them and re-run.

## UI / Styling Rules (MANDATORY)

- **Tailwind only** — never use inline `style=""` attributes
- **Full i18n key paths** — always use `t('opensop.namespace.key')`, never lazy lookup
- **Always use Rails form builder helpers** when a form object is available
- **Heroicons only** for icons (via `heroicon` gem if added, or inline SVG from heroicons.com)

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Don't over-engineer.
- **Root Causes**: Find and fix root causes. No temporary workarounds.
- **Process-First Design**: Every feature should be thought of in terms of "how would this look as an OpenSOP process?"

## Swarm Architecture

The following specialized agents work together to implement requests. **Each agent MUST be called for its domain — never edit files directly when a specialist exists:**

| Role | Agent | Responsibility |
|------|-------|----------------|
| **Architect** | *(you)* | Plans, coordinates, delegates, verifies |
| **Models** | `models` | ActiveRecord models, associations, validations, migrations |
| **Database** | `database` | Schema design, query optimization, N+1 detection |
| **Controllers** | `controllers` | Request handling, routing, controller logic |
| **Views** | `views` | Views, layouts, partials, ViewComponent, assets |
| **Stimulus** | `stimulus` | Stimulus.js controllers, Turbo integration |
| **Tailwind** | `tailwind` | Tailwind CSS styling, responsive design |
| **Services** | `services` | Service objects, business logic, the process engine |
| **Jobs** | `jobs` | Background jobs, ActiveJob, async processing |
| **Tests** | `tests` | Test specs, factories, test coverage |
| **I18n** | `i18n` | Internationalization, localization, translations |
| **DevOps** | `devops` | Deployment, Docker, CI/CD, GCP Cloud Run |
| **Security** | `security` | Security auditing, vulnerability detection |
| **Documentation** | `documentation` | API docs, YARD docs, project documentation |

**Implementation order**: models/database -> controllers -> services -> views/stimulus/tailwind -> tests
