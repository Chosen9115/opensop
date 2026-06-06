# OpenSOP — Claude Code Project Guide

**Stack:** Rails 8.1.3 / Ruby 3.3.7 / RSpec / Hotwire (Turbo + Stimulus) / importmap / Tailwind / PostgreSQL / Solid Queue / Solid Cache

OpenSOP is an open standard and runtime for defining business processes (SOPs) as APIs. Define a process in YAML, get a REST API automatically. Humans and agents drive the same endpoints. Full spec at [`SPEC.md`](./SPEC.md).

---

## Commands

```bash
bin/setup                                            # initial setup (deps + DB + git hooks)
bin/dev                                              # boot the app (Rails + tailwindcss:watch via Procfile.dev)
bin/rails s                                          # rails server only
bin/jobs                                             # Solid Queue worker
bin/rails opensop:load_processes                     # sync processes/ from disk into DB
bundle exec rspec                                    # full test suite
bundle exec rspec spec/requests/sop/                 # /sop/* API specs only
bin/rubocop                                          # lint
bin/brakeman                                         # static security scan
bin/bundler-audit                                    # dep CVE check
bin/ci                                               # run the full CI suite locally
bin/rails console                                    # repl with engine loaded
bin/deploy                                           # deploy to Fly.io
```

---

## How work happens on this project

These four rules apply to every non-trivial task. Trivial = typos, copy edits, single-line config, comment fixes, obviously-safe one-file changes. Anything else follows the workflow below.

### 1. Features → `/rails-feature` (roundhouse plugin)

For new features and any cross-cutting Rails work, **invoke the `/rails-feature` skill** from the roundhouse plugin (`@kurenn/roundhouse`). It owns: prompt refinement, triage, specialist dispatch (models, controllers, views, services, tests, jobs, etc.), TDD red→green, and conditional security/database gates.

- Use `/rails-feature` for: new features, multi-layer changes, behavioral work, anything touching the process executor, step executors, or the public `/sop/*` API
- Use `/rails-bugfix` for: bug reports with a stack trace, failing test, or reproducible misbehavior
- Use specialist mode (`/rails-models`, `/rails-controllers`, `/rails-views`, `/rails-services`, `/rails-tests`) only when the scope is clearly one Rails layer
- Edit directly only for: trivial changes (see above) and pure docs/config tweaks
- Don't manually orchestrate specialists — let the skill triage. Over-spawning is the most common failure mode.

The legacy `claude-on-rails` swarm has been removed (this is why `claude-swarm.yml` and `.claude-on-rails/` no longer exist). Roundhouse triages each task into trivial / single-domain / cross-cutting and dispatches only the specialists actually needed.

### 2. Always work in a worktree

Every meaningful change starts in a git worktree off `main`, never on `main` directly.

```sh
git worktree add .worktrees/<short-feature-name> -b <branch-name>
cd .worktrees/<short-feature-name>
```

Branch naming: `feature/...`, `fix/...`, `chore/...`, `refactor/...`. Keep the worktree directory name short.

### 3. Self-rate before declaring done

When implementation finishes (tests green, manual verification done), **before** opening the PR:

1. Rate the work **1–10** across each axis: **correctness, simplicity, test coverage, naming, performance risk, security risk, process-model fidelity** *(does the change respect Process/Step/Instance primitives and the process.yaml-as-API-contract invariant?)*
2. Pick the lowest-scoring axis. State one concrete improvement that would raise it.
3. Apply that improvement — unless doing so expands scope beyond the original task. If it does expand scope, note it as a follow-up instead.
4. Re-run tests if you changed code in step 3.
5. Include the ratings + the improvement (or follow-up) in the PR description.

If you can't honestly rate every axis ≥7, the work isn't done. Iterate until it is.

### 4. Always finish with a PR

After self-rating, push the branch and open a PR with `gh pr create`. The PR description must include:

- **Summary** — what changed and why (1–3 bullets)
- **Self-rating** — the 7-axis scores from step 3 above
- **Improvement applied** — what you changed in the polish pass, or follow-ups deferred
- **Test plan** — how to verify, including manual steps for UI changes

Don't leave work uncommitted on a worktree branch.

---

## Core principles

- **Simplicity first** — minimal-impact changes, no speculative abstractions, no extra error handling for impossible cases
- **Root causes, not workarounds** — fix the underlying issue; no temporary patches
- **Verify before claiming done** — run tests, demonstrate correctness, never assert green without proof
- **Plan before building** — for multi-step work, write the plan first; if it goes sideways, replan rather than push through a broken approach
- **Autonomous on bugs** — given a bug report, fix it. Point at logs/errors/failing tests and resolve them without hand-holding.
- **Process-first design** — every feature is thought of in terms of "how would this look as an OpenSOP process?". The process YAML is the API contract; the engine is the runtime that honors it.

---

## OpenSOP domain rules

### Process definition format

- Process definitions are YAML files with extension `.sop.yaml` under `processes/`
- The `opensop` key at root specifies the format version (currently `"0.1"`)
- Every process has: `name`, `version`, `description`, `inputs`, `outputs`, `steps`
- Steps reference upstream outputs via `from:` syntax
- Conditions use simple boolean expressions
- See [`SPEC.md`](./SPEC.md) §2 for the full grammar

### Step types

- `form` — collects data from human or agent
- `automated` — runs a script (any language, detected by extension)
- `judgment` — LLM or human decision, with confidence threshold and escalation
- `approval` — binary gate, human must approve/reject
- `webhook` — outbound HTTP, supports `sync` / `callback` / `poll` response modes
- `subprocess` — starts another OpenSOP process
- `notification` — fire-and-forget message (email, Slack, SMS)
- `wait` — pause until condition or timer

### API surface

All process API endpoints live under `/sop/`:

```
GET  /sop/                                 List processes
GET  /sop/:name/schema                     Get process definition
POST /sop/:name/start                      Start an instance
GET  /sop/:name/:id                        Inspect instance state
GET  /sop/:name/:id/steps                  List step states
POST /sop/:name/:id/steps/:step_id/submit  Advance a step
POST /sop/:name/:id/cancel                 Cancel an instance
GET  /sop/instances                        List all instances
GET  /sop/metrics                          Process metrics
POST /sop/webhooks/:callback_id            Receive webhook callbacks
POST /sop/triggers/:name                   Webhook-triggered process start
```

### Auth

- API key auth via the `X-SOP-Token` header (`OPENSOP_API_TOKEN` env var)
- The engine fails closed in production when the token is unset (returns `503 server_misconfigured`)
- Process-level access control is declared in the process YAML itself

---

## UI / styling rules (non-negotiable)

1. **Tailwind only** — never inline `style=""` attributes
2. **Full i18n key paths** — always `t('opensop.namespace.key')`, never lazy `t('.key')`
3. **Rails form builder helpers** — `f.text_field`, `f.select`, etc. when a form object exists; never raw `<input>`, `<select>`, `<textarea>`
4. **Heroicons only** for icons (via the `heroicon` gem helper or inline SVG from heroicons.com)
5. **Component specs required** — new ViewComponents need specs in `spec/components/` covering rendering, variants, slots, edge cases

---

## Architectural conventions (still enforced after the swarm removal)

`/rails-feature` knows these — but they apply to manual edits too:

- **`Sop::` namespace for models, `Opensop::` for services.** Avoids collision with Ruby's top-level `::Process`. Models live in `app/models/sop/`; services in `app/services/opensop/`.
- **Process definitions are the source of truth on disk.** The database caches them. `Opensop::Registry.load_all` re-syncs from `processes/`. Migrations don't seed processes — `bin/rails opensop:load_processes` (or the deploy_setup task on first deploy) does.
- **Step executors live under `Opensop::StepExecutors::`.** One class per step type. New step types need: a YAML schema entry, an executor class, a request-spec walkthrough that drives an instance through the new type end-to-end.
- **`Opensop::ConditionEvaluator` is the only safe path to evaluate user-authored expressions.** No `eval`, no `instance_eval`, no `system` with interpolated input — full stop. This is enforced by code review.
- **Idempotent seeds.** `db/seeds.rb` calls `Opensop::Registry.load_all`, which upserts process definitions from disk. Safe to re-run on every deploy.
- **Implementation order for cross-cutting work:** models / migrations → policies (when added) → controllers → services / step executors → views / Stimulus / Tailwind → tests
- **Production secrets come from platform env vars, not Rails encrypted credentials.** `SECRET_KEY_BASE`, `OPENSOP_API_TOKEN`, `OPENSOP_UI_USER`/`OPENSOP_UI_PASSWORD` are set directly via the platform's secret store. `RAILS_MASTER_KEY` is only needed if a fork puts something in `credentials.yml.enc` that the app actually reads.

---

## Footguns

- **Never `eval` user-authored expressions.** `Opensop::ConditionEvaluator` is the only safe path. No `eval`, no `instance_eval`, no `system` with interpolated input. Enforced by code review.
- **Process YAML is the API contract.** Schema changes to `processes/*.sop.yaml` are public-API-breaking. Either gate behind the format version, or write a migration in the registry loader.
- **Don't fight the `Sop::` / `Opensop::` split.** Models live in `Sop::` (avoids Ruby's top-level `::Process`); services live in `Opensop::`. Reversing it breaks the autoloader.
- **Step executors must be idempotent on retry.** Background-driven steps can re-run; assume so.
- **`db/seeds.rb` is idempotent by design** via `Opensop::Registry.load_all`, which upserts from `processes/`. Don't add raw inserts that aren't idempotent.
