# `processes/` — the process library

This directory is the OpenSOP process library: example `.sop.json` and `.sop.yaml` process definitions that demonstrate the spec and serve as starting points.

The local CLI (`opensop run`) executes `.sop.json` files directly — no server, no database. A conforming server loads from a `processes/` directory on boot and registers definitions into its own cache. Both consumers read the same files; the format is the same.

## Layout

```
processes/
├── README.md                   ← this file
├── examples/                   ← public, canonical examples
│   ├── customer-onboarding.sop.yaml
│   ├── lead-qualification.sop.yaml
│   └── steps/                  ← scripts the example YAMLs reference
│       ├── create-account.rb
│       ├── score-lead.rb
│       ├── send-welcome.rb
│       ├── verify-documents.rb
│       └── compliance-payload.json
└── <your-org>/                 ← private processes in your fork (gitignored in this repo)
    ├── my-process.sop.yaml
    └── steps/
        └── my-script.rb
```

## Running a process locally

```bash
opensop run ./processes/examples/customer-onboarding.sop.yaml --input company_name="Acme Corp"
```

The CLI runs the process on-machine: no server, no network, no account. Paused steps (form, approval, wait with `until:`) resume via `opensop submit <run_id> <step-id> --output key=value`.

## How `run:` paths resolve

When an `automated` step references a script via `run:`, the path resolves differently depending on the backend:

- **Local CLI:** path is relative to the process file.
- **A conforming server:** path is relative to the `processes/` root, not the YAML file. A YAML at `processes/examples/customer-onboarding.sop.yaml` must write `run: ./examples/steps/verify-documents.rb`.

## For forks with private processes

The public repo's `.gitignore` reserves `/processes/coba/` and `/processes/private/`. In a private downstream fork, add your process files under the reserved name — they track in your fork but never leak upstream on a merge-down. If you need a different name, add the entry to your fork's `.gitignore` (and remove the ignore in the fork so the files track there).

See `CONTRIBUTING.md` for the upstream-first sync workflow.
