# OpenSOP — Process as Infrastructure

**Agentic processes are infrastructure. Treat them like it.**

We version our code, our schemas, our infra. But the *processes* — how a lead gets
qualified, how an invoice gets approved, how an incident gets handled — still live in
wikis, in someone's head, or get re-derived from scratch by an agent on every run. That's
not a knowledge problem. It's a missing primitive.

OpenSOP is that primitive: a process you can **declare, version, fork, run, and audit** —
a file in your repo, not a workflow trapped in a SaaS.

> **Terraform is to cloud resources what OpenSOP is to agentic processes.**

## Tenets

1. **Local-first.** A process runs on your machine — `opensop run` — with no server, no
   network, no account. The server is an option, never a prerequisite.
2. **A process is a file.** One declarative `.sop` artifact: inputs, steps, outputs.
   It lives in your repo, reviews in your PRs, ships in your commits.
3. **Forkable lineage.** Processes evolve like code. `fork` a process, adapt it, and the
   lineage is recorded — not copied-and-forgotten in a doc.
4. **Auditable by default.** Every run leaves receipts: what ran, what it decided, with
   what confidence, in what order. Determinism you can inspect after the fact.
5. **One surface for humans and agents.** The same process, the same commands, whether a
   person or an agent drives it. No second integration.
6. **The server is optional.** Want shared orchestration, a monitoring UI, a team audit
   log? Run the runtime. Don't want to? You lose nothing for the local loop.

## Why now

Agents are good at *doing* steps and bad at *remembering which steps*. Left alone, an agent
re-invents the procedure every time — slowly, inconsistently, unauditably. Give it a
process as infrastructure and it stops re-deriving and starts *executing* — the same way,
every time, with a receipt to prove it.

A process that runs the same way every time beats one that merely ran once.

— Build processes you can fork. Run them anywhere. Keep the receipts.
