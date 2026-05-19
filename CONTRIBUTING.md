# Contributing to OpenSOP

Thanks for your interest in OpenSOP. This document covers how to contribute to the engine, how the project is structured, and — for forks that host private process libraries — how to keep your fork in sync with upstream.

---

## Project structure

OpenSOP is a Rails application with two concerns that deliberately live in different places:

| Concern | Lives in | What it is |
|---|---|---|
| **Engine** | `app/`, `lib/`, `config/`, `spec/` | The OpenSOP runtime: YAML parser, instance executor, step executors, REST API, admin UI. This is what you're contributing to when you fix bugs or add features. |
| **Processes** | `processes/` | `.sop.yaml` files that the engine loads at runtime. Some are shipped as public examples (`processes/examples/`). Forks may add private processes (`processes/coba/`, gitignored in this repo). |

This split is the point: the engine doesn't care where processes come from. Contribute to the engine here; keep your private processes in your own fork or a separate repo.

---

## Contributing to the engine

### Setup

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/install-git-hooks             # one-time, installs the secret-scan pre-commit hook
bin/rails opensop:demo            # full pipeline walkthrough
bin/rspec                         # 135 / 0
```

### Working with Claude Code

OpenSOP uses the [roundhouse](https://github.com/kurenn/roundhouse) Claude Code plugin for AI-assisted Rails development. If you're contributing through Claude Code:

```bash
claude plugin marketplace add kurenn/marketplace   # one-time per user
claude plugin install roundhouse@kurenn            # one-time install
```

Then use `/rails-feature` for new features, `/rails-bugfix` for bug reports, and the specialist skills (`/rails-models`, `/rails-controllers`, `/rails-views`, `/rails-services`, `/rails-tests`) when the scope is clearly one Rails layer. Full conventions are in [`CLAUDE.md`](./CLAUDE.md).

### Secret scanning

Two layers, both running [gitleaks](https://github.com/gitleaks/gitleaks):

- **Local pre-commit hook** (after `bin/install-git-hooks`) — blocks commits that contain detected secrets. Install gitleaks with `brew install gitleaks` (macOS) or see the [releases page](https://github.com/gitleaks/gitleaks/releases).
- **CI on every PR** (`.github/workflows/secret-scan.yml`) — the source of truth. Catches anything bypassed locally with `git commit --no-verify`.

Allowlist entries for known-safe placeholders (test fixtures, doc examples) live in `.gitleaks.toml`.

### Workflow

1. **Open an issue first** for non-trivial changes. A quick "here's what I'm thinking" saves rework.
2. **Branch from `main`**: `git checkout -b fix/short-description`.
3. **Make the change** with tests. New step types, field types, or API endpoints need spec coverage; see `spec/services/opensop/` and `spec/requests/sop/`.
4. **Run the full suite**: `bin/rspec` (all green). Run `bin/rubocop` if you've touched service code.
5. **Open a PR** against `Chosen9115/opensop:main`. The PR description should answer: what's the problem, how does this solve it, what did I test.

### Standards worth knowing

- **No `eval`, no `instance_eval`, no `system` with user input** in services. The `ConditionEvaluator` exists to give a safe expression layer — use it instead of reaching for `eval`.
- **Tailwind only** — no inline `style=""` attributes. Component classes go in `app/assets/tailwind/application.css`.
- **Full i18n key paths** — `t('opensop.namespace.key')`, not lazy `t('.foo')`. All UI strings route through `config/locales/opensop.en.yml`.
- **Sop:: namespace for models, Opensop:: for services.** The split is intentional (avoids collision with Ruby's top-level `::Process`).
- **Process definitions are the source of truth.** The DB caches them. `Opensop::Registry.load_all` re-syncs from disk.

See `HANDOFF.md` for the full architecture tour and where to make specific kinds of changes.

---

## Adding a process example

Public example processes live in `processes/examples/`. They should be:

- **Generic** — no company-specific integrations, no internal service names.
- **Runnable** — includes any required step scripts in `processes/examples/steps/`.
- **Spec-covered** — at minimum, a request spec that starts an instance and walks it to completion.
- **Documented** — a brief comment at the top of the YAML explaining what the process demonstrates.

`processes/examples/customer-onboarding.sop.yaml` is the canonical reference.

**A note on `run:` paths:** the engine resolves script paths relative to `processes/` (not relative to the YAML file). So a YAML at `processes/examples/my-process.sop.yaml` should reference its script as `./examples/steps/my-script.rb`, not `./steps/my-script.rb`. See `app/services/opensop/step_executors/automated.rb#resolve_script_path`.

---

## Forking for private process libraries

Many teams will run OpenSOP with their own private processes. The recommended topology:

```
Chosen9115/opensop          ← public, engine + example processes (this repo)
your-org/opensop-private    ← your private fork, tracks engine changes + hosts your processes
```

### First-time fork setup

In your local clone:

```bash
# Rename the default remote to match its role
git remote rename origin private

# Add the upstream public repo
git remote add public https://github.com/Chosen9115/opensop.git

# Verify
git remote -v
# private  https://github.com/your-org/opensop-private.git
# public   https://github.com/Chosen9115/opensop.git
```

Add a `processes/<your-org>/` directory for your private processes and gitignore it **in the public repo** (it's already gitignored upstream — check `.gitignore`). In your private fork, remove that ignore line so your processes get tracked.

### The upstream-first rule

**Engine changes (code in `app/`, `lib/`, `spec/`) always land in public first.**

Workflow:

1. Branch from `main` in your local clone.
2. Make the engine change + tests.
3. Push to **public** and open a PR against `Chosen9115/opensop`:
   ```bash
   git push public fix/my-branch
   ```
4. Get the PR reviewed and merged upstream.
5. Pull the merge into your local `main`:
   ```bash
   git checkout main
   git pull public main
   ```
6. Push the merged `main` to your private fork:
   ```bash
   git push private main
   ```

This keeps engine improvements flowing to the public standard and keeps your private fork a strict superset of public `main`.

### Keeping your fork in sync

On a regular cadence (weekly is a good default):

```bash
git checkout main
git pull public main         # pull latest from Chosen9115
git push private main        # sync to your fork
```

If you've been doing engine work correctly (upstream-first), this is a fast-forward. If it isn't, something got committed to your private fork that should have been upstream — reconcile it by cherry-picking that commit to a public-facing branch and opening a PR.

### Private processes

- **Private processes live only in your fork.** Store them in a dedicated directory (e.g. `processes/<your-org>/`) that's gitignored in the public repo.
- **Never commit private processes to a branch that pushes to `public`.** A quick safeguard: use a pre-push hook that refuses pushes to `public` if `processes/<your-org>/` has tracked files.
- **Treat the engine as stable API.** If an engine change would break your private processes, that's a signal the change needs a migration path — raise it in the upstream PR.

---

## Reporting issues

- **Bugs:** open an issue on `Chosen9115/opensop` with repro steps and what you expected to happen.
- **Security:** please don't open public issues for security reports. See [`SECURITY.md`](SECURITY.md) for the disclosure policy and reporting channels.
- **Spec proposals:** for changes to the `0.1` format, open a discussion first — the YAML format is a contract.

---

## License

OpenSOP is Apache 2.0. By contributing, you agree your contributions will be licensed under the same terms.
