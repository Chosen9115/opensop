# OpenSOP — Agent Quick-Start

This file auto-discovers to agents scanning the repo root.

Full guide: [`docs/AGENTS.md`](docs/AGENTS.md)

The guide covers: install, discover (search/suggest/help --json), run (receipts, structured output, error codes), build (step types, data flow), openSOP-ize (turn a prose skill into a versioned process), and iterate/evolve (fork, annotate, lineage).

Quick-start commands:

```bash
opensop help agents              # agent-oriented command summary (CLI)
opensop help --json              # machine-readable command index
opensop search <keyword>         # find a process
opensop suggest "<task>"         # intent-based match
opensop run <name|file> --input k=v
opensop status <run_id> --json   # check state
opensop show <run_id> --json     # full receipt
```

Trust boundary: local `shell` and `automated` steps execute arbitrary code on the host. Only run process files you have reviewed.
