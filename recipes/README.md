# OpenSOP Recipe Library

A growing collection of reusable, shareable `.sop.json` process files — ready to pull, inspect, and adapt.

## Layout

```
recipes/<author>/<slug>.sop.json
```

- **`author`** — a GitHub username or organisation name (namespace). `opensop` is reserved for officially maintained recipes.
- **`slug`** — a short kebab-case name that uniquely identifies the recipe within the author namespace.

Example: `recipes/opensop/daily-standup-notes.sop.json`

## How to pull a recipe

```bash
# Pull the latest version (from main)
opensop pull opensop/daily-standup-notes

# Pull and pin to an immutable commit SHA for reproducibility
opensop pull opensop/daily-standup-notes@a1b2c3d

# Write to a specific path instead of the default ./<slug>.sop.json
opensop pull opensop/daily-standup-notes --output ~/processes/standup.sop.json

# Verify the file matches a known SHA-256 (supply the hash out-of-band)
opensop pull opensop/daily-standup-notes --verify <sha256-hex>
```

The CLI writes the file and prints a summary (name, version, step count, step types, source, SHA-256). It never executes the file automatically. Always review before running:

```bash
opensop dry-run ./daily-standup-notes.sop.json
```

## How to import from a local file or stdin

```bash
# Import from a file
opensop import ./my-recipe.sop.json

# Import from stdin (e.g. after piping curl output)
curl -fsSL <url> | opensop import -
```

`import` validates, writes, and prints a summary — same as `pull`, same safety contract. Never auto-runs.

## Safety note

**A recipe's shell/automated steps execute arbitrary commands on your machine** — the same trust boundary as a `Makefile` or `npm postinstall`. Before running a recipe, **read its `run` commands directly** — they are plain JSON:

```bash
jq '(.process.steps // .steps)[] | {id, type, run}' <file>   # or just open the file
```

`opensop dry-run <file>` validates inputs and previews the step *flow*, but it does **not** print command bodies — so it is not a substitute for reading the steps above.

The `sha256` printed after every pull is for pinning and identification (both the file and the hash come from the same GitHub origin — they confirm transfer integrity and help you reproduce exact versions, not authenticate against a third party). Supply `--verify <sha256>` to enforce a hash you obtained out-of-band.

## Official recipes (`opensop/`)

| Slug | Description |
|---|---|
| `daily-standup-notes` | Collect standup answers (yesterday / today / blockers) and format a concise summary |
| `triage-bug-report` | Walk through bug report fields with a judgment step; emit a prioritised triage summary |
| `release-checklist` | Approval-gated release checklist: confirm each item before marking the release ready |

## How to contribute

1. Fork the repo and create your recipe under `recipes/<your-github-username>/`.
2. Each recipe must be a valid `.sop.json` that passes `opensop dry-run`.
3. Include the `recipe` object with `source`, `install`, and at least one tag.
4. Use only safe, synthetic examples — no PII, no secrets, no destructive commands.
5. Open a pull request. The title should be `feat(recipes): add <author>/<slug>`.

Recipes that contain destructive shell commands, network calls to untrusted endpoints, or secrets will be rejected.
