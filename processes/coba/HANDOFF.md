# Coba OpenSOP Fork — Handoff

> **Private to coba-ai/opensop.** Sits in `processes/coba/`, which is
> gitignored in the public Chosen9115 fork.

Last updated: **2026-04-27**

If you're an agent or a returning human picking up this project, read
this first. Then look at `MEMORY.md` for the architectural
conversations behind today's state.

---

## TL;DR

Coba runs a three-layer stack — **OpenSOP + n8n + DenchClaw** — with
a self-applicable **bootstrap loop** on top: a seed process
(`ship-a-process`) creates new processes, and a weekly **Toyota
Production Agent** (n8n cron) observes running processes and produces
kaizen cards.

Everything is in production. Today's job is to **let it run** and
read what comes out next Monday.

## What's live (2026-04-27)

### OpenSOP processes (https://opensop.fly.dev)

| Process | State | Phase |
|---|---|---|
| `consult-request` | LIVE | Cal.com booking → CRM (real traffic) |
| `website-lead-capture` | LIVE | Web3Forms email → IMAP → CRM (real traffic) |
| `lead-capture` | scaffolded | LinkedIn via Zapier; no campaign run yet |
| `campaign-lifecycle` | scaffolded | Marketing campaign mgmt |
| `member-onboarding` v1.0 | mapped | 15 steps; Phase A documentation only |
| `send-payment` v1.0 | mapped | 11 steps; Phase A documentation only |
| `ship-a-process` v1.0 | mapped | The seed — Process #1 |

### n8n workflows (https://n8n.coba.ai)

| Workflow | id | State |
|---|---|---|
| `Web3Forms → OpenSOP (website-lead-capture)` | `odpzEgcTEcyqVUhk` | ACTIVE |
| `TPA — Weekly Kaizen` | `avUCZrVibRGYVuWs` | ACTIVE; fires Mondays 09:07 ET |

Both workflows are version-controlled at https://github.com/coba-ai/n8n-workflows.

### DenchClaw

Laptop bridge under launchd; DuckDB at the laptop. Tailscale Funnel
exposes it publicly. `create-crm-record.rb` handles deduplicated
inserts with upsert-on-dedup (timestamped touch blocks appended to
existing deals' Notes).

---

## The bootstrap loop

Two things make this self-sustaining:

### 1. `ship-a-process` (the seed)

The meta-process. Self-applicable. When you want to map a new business
process, you start an instance of `ship-a-process` with the candidate
as input. The instance walks: confirm-candidate → gather-evidence →
draft-yaml → validate → commit-and-deploy → document-gaps →
schedule-tpa-review.

Today, an instance is driven conversationally (Carlos + Claude). Phase
B will swap the manual fly-ssh validation/deploy steps with real
automation. The shape is stable; the implementation gets richer over
time.

**Use it:** when adding ANY new process (customer-support, IFT, etc.),
default to "let's run ship-a-process for it." Don't reinvent the
mapping flow.

### 2. Toyota Production Agent (the kaizen loop)

A weekly n8n cron that:
1. GETs the last 100 instances from `/sop/instances`
2. Aggregates per-process metrics (count, last 7d, running, failed, failure rate)
3. Runs heuristic friction analysis (5 signals: ZERO_INSTANCES,
   ZERO_TRAFFIC, STUCK_RUNNING, HIGH_FAILURE, RECENT_ERROR)
4. Emits a markdown kaizen report

**Reading the output:** visit https://n8n.coba.ai → Executions tab →
the latest TPA run → click the **Analyze + compose kaizen** node →
the `report_markdown` field is the human-readable report.

**v0 limitations (next iterations):**
- Output stays in n8n exec logs (no Slack/GitHub posting yet)
- Analysis is heuristic only (no LLM-augmented kaizen suggestions yet)
- Per-step duration analysis deferred until steps-history endpoint exists

---

## What to do Monday after the TPA's first real fire

1. **Open https://n8n.coba.ai → workflow `avUCZrVibRGYVuWs` → Executions.**
2. **Click the most recent execution → Analyze + compose kaizen → Output.**
3. **Read the markdown report.** Today's dry-run already flagged:
   - `consult-request 971f1d4b` running 2.0d (likely abandoned)
   - `consult-request e2b43ade` running 2.5d (likely abandoned)
   - Several historical website-lead-capture errors (already fixed)
4. **For each kaizen card, decide:**
   - **Quick fix:** unblock + close the instance via OpenSOP admin UI.
   - **Pattern:** if the same kaizen card recurs across weeks, escalate
     to a fresh `ship-a-process` instance with the card as the brief.
   - **Noise:** mark and move on; the heuristic will refine over time.

## Operational reminders

### Where to make changes

- **Process YAMLs:** `processes/coba/<name>.sop.yaml`. Edit, commit,
  push to coba-ai/opensop, `fly deploy --app opensop`, then
  `fly ssh console -C "bin/rails opensop:load_processes" --app opensop`.
- **n8n workflows:** edit in n8n UI (or via API), then export to
  `coba-ai/n8n-workflows/workflows/<name>.json` and commit.
- **DenchClaw script:** `processes/coba/steps/create-crm-record.rb`.
  Bridge picks it up on next request — no restart needed.

### Where NOT to make changes

- **Public Chosen9115/opensop:** never push Coba-specific YAMLs or
  secrets. Engine-level changes go there as PRs (see PR #6 still open
  on GAP-8). Per `feedback_public_repo_secrets.md`.

### When something breaks

- **Member onboarding step fails:** check the step's `error` field
  via the OpenSOP admin UI; backoffice may need to manually unblock.
- **website-lead-capture stops landing leads:** check (a) Web3Forms
  delivers to `contact@coba.ai`; (b) n8n workflow active; (c) IMAP
  credential not expired (Gmail app passwords don't expire but the
  Workspace IMAP toggle might get flipped).
- **TPA produces no output:** check n8n credential `OpenSOP API Token`
  not expired; check schedule trigger fired (look for execution row).

## Pending decisions waiting on Carlos

1. Customer-support process: where does it actually live (inbox /
   Slack / ticketing / backoffice page)? Need that pointer to map.
2. Phase B wire-up for `member-onboarding` and `send-payment` —
   when revenue urgency demands real-time process tracking, the
   webhook step endpoints (currently placeholders) get built on the
   Coba Rails side.
3. n8n API key rotation (was pasted in-transcript 2026-04-24).
4. Slack/GitHub output for TPA reports (v0 → v1 upgrade).

## Where to look for context

- **Memory (auto-loaded each session):**
  `/Users/c/.claude/projects/-Users-c-Documents-coba-twin-repos-opensop/memory/`
- **`MEMORY.md`** — index of all memory files
- **`project_coba_current_state.md`** — running snapshot
- **`project_coba_bootstrap_loop.md`** — the seed + TPA architecture
- **`project_coba_stack_vision.md`** — why this stack, why this composition
- **`feedback_no_adapters.md`** — three-tier integration rule
- **`feedback_n8n_quirks.md`** — gotchas (Gmail spaces, sandbox, etc.)
- **`reference_n8n_instance.md`** — n8n.coba.ai operational pointer

---

_If you're an agent reading this without recent memory: hi. Read
`MEMORY.md` first, then `project_coba_bootstrap_loop.md`, then come
back here. The loop is set up to be picked up cold._
