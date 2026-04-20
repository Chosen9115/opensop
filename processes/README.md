# `processes/` — the process library

This directory holds `.sop.yaml` process definitions that the engine loads at runtime. It is the source of truth; the database is a cache rebuilt from these files on boot or via `bin/rails opensop:load_processes`.

## Layout

```
processes/
├── README.md                   ← this file
├── examples/                   ← public, shipped-with-engine examples
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

## How the engine finds processes

`Opensop::Registry.load_all` (see `app/services/opensop/registry.rb`) does a recursive glob for `**/*.sop.yaml` under this directory, so **any subdirectory works**. You can add `processes/coba/`, `processes/private/`, `processes/my-team/` — whatever convention your fork uses — and the engine picks it up automatically.

## How `run:` paths resolve

When an `automated` step references a script via `run:`, the engine resolves the path **relative to `processes/`**, not relative to the YAML file. For example, a YAML at `processes/examples/customer-onboarding.sop.yaml` references its script as:

```yaml
run: ./examples/steps/verify-documents.rb
```

…which resolves to `processes/examples/steps/verify-documents.rb`. If you're authoring a private process at `processes/coba/onboarding-v2.sop.yaml` with a script at `processes/coba/steps/kyb.rb`, reference it as:

```yaml
run: ./coba/steps/kyb.rb
```

The implementation lives in `app/services/opensop/step_executors/automated.rb#resolve_script_path`.

## For forks with private processes

The public repo's `.gitignore` reserves the names `/processes/coba/` and `/processes/private/`, so:

- **In the public repo (`Chosen9115/opensop`)**: those directories are invisible. Nothing to see here.
- **In a private downstream fork**: add your process files under the reserved name and they'll track in your fork but never leak upstream on a merge-down. If you need a different name, add the entry to your fork's `.gitignore` (and remember to remove the ignore in the fork itself so the files track there).

See `CONTRIBUTING.md` for the full upstream-first sync workflow.
