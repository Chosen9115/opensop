# Changelog

All notable changes to opensop-cli are documented here.

This project follows [Semantic Versioning](https://semver.org/) and the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

---

## [0.8.0] — 2026-06-11

> **BREAKING:** The default backend is now **LOCAL**. Commands that previously hit a remote server by default now run locally (no server, no curl). Scripts relying on the old default-remote behaviour must add `--remote` (uses the configured `OPENSOP_URL`) or `--server <url>`. The `--local` flag is now a deprecated no-op and can be omitted — it is still accepted for script compatibility but prints a deprecation note to stderr.
>
> **Migration:** any invocation of the form `opensop <cmd> [args]` that expected remote behaviour must become `opensop --remote <cmd> [args]` or `opensop --server <url> <cmd> [args]`.

### Changed (breaking)

- **Default backend flipped from REMOTE to LOCAL (U2a — Phase 2).**
  `REMOTE_MODE` (default `false`) controls routing for all dual commands (`run`, `list`, `search`, `suggest`, `dry-run`, `status`, `steps`, `submit`, `cancel`, `diff`, `instances`, `compass`, `history`). `--remote` sets `REMOTE_MODE=true` and uses the configured `OPENSOP_URL`; `--server <url>` sets the URL for the invocation and implies `--remote`. `--local` is now a deprecated no-op alias — accepted without error but prints `note: --local is now the default and can be omitted` to stderr (suppressed in `--json` mode). `register` with no `--remote`/`--server` exits with `usage_error` directing users to pass one of these flags. `curl` is only invoked in REMOTE mode. Config (`~/.opensop`) is only loaded in REMOTE mode — local runs are fully self-contained.

### Changed (non-breaking)

- **Vocabulary unified on "run(s)" (U2b).**
  User-facing messages, help text, and TTY output now say "run(s)" consistently instead of "instance(s)" for the local-default world. The `instances` command name is unchanged (it is an established verb), but its description now reads "list runs". Affected: `cmd_instances` pretty header, `local_instances` pretty header, `cmd_submit` TTY confirmation, resume hints, and usage-error strings in local engine functions.

### Added (Phase 1 — local parity for all dual commands)

- **`opensop cancel <run_id> [--reason TEXT]` — cancel a running or waiting local run (P1f).**
  `cmd_cancel` branches to `local_cancel` when `REMOTE_MODE != true` (default; no server, no curl).
  Only `running` or `waiting` runs can be cancelled — submitting cancel on a `completed`,
  `failed`, or already-`cancelled` run is rejected with a `usage_error` (mirroring the
  runtime's invalid-transition behaviour). On success: manifest `status` is set to
  `"cancelled"`, the `waiting` and `cursor` blocks are cleared, `ended_at` is written,
  and a `{type:"cancel", status:"cancelled", reason?}` receipt is appended to
  `audit.jsonl`. Output shape mirrors `cmd_cancel` (pretty: `ok "cancelled …" + reason
  line`; JSON: updated manifest piped through `emit_pretty_or_json`).

- **`opensop diff <run_id1> <run_id2>` — compare two local runs (P1e).**
  `cmd_diff` branches to `local_diff` when `REMOTE_MODE != true` (no server, no curl).
  `local_diff` reads each run's `manifest.json` (for `state`/`inputs`/`metadata`),
  `audit.jsonl` (for per-step receipts), and `context.json` (for final outputs), then
  emits an identical shape to the remote diff response:
  `{a:{id,state,started_at}, b:{id,state,started_at}, differences:[{path,a,b}], identical:true|false}`.
  Compared fields mirror the remote: top-level `state`, `inputs`, `outputs` (final
  context), `metadata`; per-step `state`, `sub_state`, `outputs`, `decided_by`,
  `exit_code`, `duration_ms`. Same-process guard is enforced (diff across different
  processes → `cli_error`). Unknown `run_id` → `die` with `instance_not_found`.
  Pretty rendering mirrors `cmd_diff`'s TTY table (bold path, red a:, green b:).

- **`opensop instances`, `opensop compass`, `opensop history --process <name>` — local admin views (P1d).**
  `cmd_instances`, `cmd_compass`, and `cmd_history` branch to `local_instances`,
  `local_compass`, and `local_history` when `REMOTE_MODE != true` (no server, no curl).
  `local_instances` enumerates `$OPENSOP_LOCAL_HOME/runs/*/manifest.json`, applies
  `--state`/`--process` filters and `--limit`/`--offset` pagination entirely in jq,
  and emits `{instances:[{id, process:{name}, state, started_at}], total:N}` — an
  identical shape to the remote `cmd_instances` response. `local_compass` applies the
  same group-by-process jq logic as remote `cmd_compass`, producing
  `{by_runs, by_recency, by_failure_rate}` from the local run corpus. `local_history`
  delegates to `local_instances --process <name>`, mirroring how `cmd_history`
  delegates to `cmd_instances`. All three route through `emit_pretty_or_json`; the
  pretty paths mirror their remote counterparts' TTY rendering (coloured state, ranked
  tables). Empty stores return empty arrays/zero totals, not errors.

- **`opensop status <run_id>` and `opensop steps <run_id>` — local run inspection (P1c).**
  `cmd_status` and `cmd_steps` branch to `local_status`/`local_steps` when
  `REMOTE_MODE != true`. Both read `$OPENSOP_LOCAL_HOME/runs/<run_id>/manifest.json`
  and `audit.jsonl` (no server, no curl). `local_status` emits a JSON shape
  identical to the remote GET `/sop/:name/:id` response
  (`{id, process:{name}, state, started_at, completed_at, waiting, steps}`),
  including per-step `{step_id, type, state, sub_state}` derived from audit
  receipts. `local_steps` emits `{run_id, steps:[...]}` with the full receipt
  fields (`exit_code`, `output`, `started_at`, `ended_at`). Both route through
  `emit_pretty_or_json`; the pretty path mirrors `cmd_status`'s TTY rendering
  (colored state, glyph per step). Unknown `run_id` → `die` with `instance_not_found`.

- **`opensop dry-run <name|file.sop.json>` — local process preview with input validation (P1b).**
  `cmd_dry_run` branches to `local_dry_run` when `REMOTE_MODE != true`. The local
  implementation resolves the process file via `_find_skill_in_cells` (bare name →
  cell chain) or an explicit path, normalises the `.sop.json`'s `inputs` field to
  array form, validates provided `--input`/`--inputs` against the declared schema
  (required/type/enum/email-format — same jq logic as the remote validator), and
  prints the step walkthrough via `walk_steps_preview`. No run directory is created.
  Output shape (pretty prose / `{process, valid, validation_errors, steps}` JSON)
  is identical to remote `cmd_dry_run`.

- **`opensop search <kw...>` — ranked text search over the cell-chain process corpus (P1a).**
  `cmd_search` branches to `local_search` when `REMOTE_MODE != true`. A shared
  helper `_enumerate_local_processes` walks the active cell + ancestors (nearest
  first, nearest-wins dedup by basename — same precedence as `list --conflicts`),
  reads each `.sop.json`, and builds a `{processes:[...]}` object compatible with
  the existing `score_processes` jq scorer. `local_search` scores against that
  corpus, returns the top 5, and produces an output shape identical to remote
  `cmd_search` (pretty table in a TTY, `{query, results}` JSON when piped).

- **`opensop suggest "<task>" [--threshold N]` — intent scoring over the cell-chain process corpus (P1a).**
  `cmd_suggest` branches to `local_suggest` when `REMOTE_MODE != true`. Uses the
  same `_enumerate_local_processes` corpus and the same top-1 + confidence formula
  as the remote path. Output shape (pretty prose / `{task, match}` JSON) is
  identical to remote `cmd_suggest`. `--threshold` is supported.

---

## [0.7.0] — 2026-06-10

### Changed

- **`webhook` `response_mode` is now required** (no default). Omitting it is a
  validation error in both `schema validate` and the local engine — removes the
  prior silent local-`sync` / runtime-`callback` divergence.
- **`webhook` callback mode fires the outbound request, then pauses** (runtime
  parity), instead of pausing without notifying the endpoint.
- **`webhook` fallback body (no `body_template`) resolves declared step inputs
  via `from:`** (InputResolver parity) instead of a bare context lookup — no
  longer over-shares the full accumulated context to the endpoint.
- **`${process.inputs.X}` supports nested dot-paths** in webhook templates.

### Added

- **`subprocess` step type — recursive local execution (U8).**
  The CLI exceeds the runtime here: the runtime only stubs subprocess (`StepExecutors::Subprocess`
  returns `waiting_for_callback`), but the local engine fully executes child processes. Fields:
  `process` (required — logical name resolved via `_find_skill_in_cells`, or an explicit path);
  `inputs[]` (optional array of `{name, from}` mappings resolved against the parent context —
  supports `steps.<id>.outputs.<field>`, `<stepid>.<field>` shorthand, bare context keys, and
  literal string fallback). Child runs are stored flat at `$OPENSOP_LOCAL_HOME/runs/<child_run_id>/`
  (same as top-level runs) to prevent exponentially growing paths from recursive processes; a
  symlink `<parent_run>/subprocess/<step-id>/<child_run_id>` is created for at-a-glance
  inspectability. Recursion depth is guarded by `OSL_DEPTH` (max 16): each subprocess arm
  increments the counter and refuses at `>= 16`, turning a self-referencing process into a
  `failed` receipt rather than an infinite loop or path explosion. Result mapping: child
  `completed` → the child's final `context.json` is merged into the parent context under the
  step id (all child step outputs accessible via `parent_ctx[step_id][child_step_id]`); child
  `waiting` → propagates as parent `waiting_for_callback` with `child_run_id` and `child_run_dir`
  recorded in the audit receipt for per-level resume; child `failed` → parent step fails
  (respects `continue_on_error`). `executor` defaults to `internal`. 10 new assertions covering:
  happy path (parent calls 1-step child, context merged), inspectable run dir, audit receipt
  (type=subprocess/executor=internal), 'after' step sees child output; failure paths: missing
  process file, missing 'process' field, failing child halts parent, depth guard rejects
  self-referencing process, `continue_on_error` lets parent complete despite failing child.

- **`opensop submit <run_id> <step-id> --local` — resume a paused run (U3).**
  Completes the local state machine. `cmd_submit` branches to `local_submit` when
  `LOCAL_MODE=true`. `local_submit` asserts the run is `waiting` on the named step,
  validates submitted outputs against `manifest.waiting.expects.schema` (required /
  type / enum checks — same logic as the dry-run validator), injects outputs into
  `context.json` under the step id, appends a `"completed"` receipt to
  `audit.jsonl` (includes `decided_by` when `--decided-by` is passed), flips
  manifest back to `"running"`, then re-enters `_local_step_loop` at
  `cursor.next_index` (the step after the pause point — never re-runs completed
  steps). Finalizes manifest on completion, failure, or a second pause. Exits 0 on
  completion; non-zero on failure. Does not require curl — the full
  form/noop/automated path works with jq only.

- **`form` step type — pause/resume state machine (U2).**
  A `form` step pauses the local run: `_local_step_loop` appends a `"waiting"`
  receipt to `audit.jsonl` (reason: `"waiting_for_input"`, byte-parity with the
  runtime's `StepExecutors::Form`) and returns `"waiting:<index>"`. `local_run`
  transitions the manifest to `status:"waiting"` and writes the full pause
  envelope: `cursor:{next_index}` and `waiting:{step, index, reason, expects,
  since}`. `expects.outputs` lists field names; `expects.schema` carries the full
  inputs array. No `ended_at` is written while waiting. The run exits 0 (a clean
  pause is not a failure). A TTY prints the resume hint:
  `opensop submit <run_id> <step-id> --local --output k=v`.
  The `_local_finalize_trap` already gates on `status=="running"` so a waiting
  manifest is never flipped to `"interrupted"` on EXIT. Prerequisite for U3
  (resume at cursor).

- **`opensop list --local --conflicts`.** Inside a cell, marks the first
  occurrence of each filename across the cell chain as `← active` and
  subsequent ones as `← shadowed by [cell-name]`. Same data as plain
  `list` — just annotated with PATH-style resolution preview. Deferred
  from v0.6 PR #9; lands here as post-release polish.

- **`webhook` step type — outbound HTTP with sync/callback modes (U7).**
  Mirrors `StepExecutors::Webhook` (`webhook.rb`) + `Opensop::Templating` (`${...}`
  dialect). Fields inside the nested `webhook:` block: `url` (required), `method`
  (default `POST`; `GET|POST|PUT|PATCH|DELETE`), `headers` (object), `body_template`
  (path relative to the `.sop.json` directory; else inputs-as-JSON), `response_mode`
  (`sync|callback|poll`). Template dialect: `${env.X}`, `${process.inputs.X}`,
  `${callback_url}`, bare `${X.Y.Z}` (→ accumulated context). Implemented in pure jq
  (no shell eval, no external renderer). **sync mode**: `require_curl` inside this arm
  only; fires a real curl call (or the `OSL_WEBHOOK_STUB` seam); asserts 2xx (else step
  fails); parses the response body as a JSON object into step outputs (empty body → `{}`);
  non-JSON body is a step failure. **callback mode**: appends a `waiting` audit receipt
  (`reason: "waiting_for_callback"`, `callback_id` included for tracing), then pauses
  the run via the same `waiting:<index>` protocol as `form`/`approval`/`wait.until`;
  operator resumes manually with `opensop submit <run_id> <step-id> --local --output k=v`
  (no inbound HTTP receiver — documented limitation of the local backend). **poll mode**:
  exits 2 with `"response_mode: poll is not implemented yet (see SPEC §8 roadmap)"`
  (byte-parity with the runtime's `raise StepFailure`). `executor` defaults to
  `external` (already in the per-type default map). Test seam: `OSL_WEBHOOK_STUB=
  "<code>:<body>"` (e.g. `OSL_WEBHOOK_STUB='200:{"result":"ok"}'`) skips curl and
  drives the full 2xx/non-2xx/parse pipeline without a real server. 20 new assertions
  covering: sync 2xx success, context threading, audit receipt, executor=external,
  sync non-2xx failure, empty body, non-JSON body, callback pause, waiting.reason,
  callback resume via submit, 'done' step after resume, poll rejection, missing url.

- **`llm` step type — synchronous LLM call via Anthropic Claude (U6).**
  Mirrors `StepExecutors::Llm` + `LlmProviders::Anthropic` exactly. Pipeline:
  (1) load prompt (inline `prompt:` or `prompt_file:` relative to the `.sop.json`
  directory); (2) substitute `{{ var }}` tokens from the accumulated context via
  jq; (3) POST to `https://api.anthropic.com/v1/messages` (headers:
  `x-api-key`, `anthropic-version: 2023-06-01`, `content-type`) with `model`,
  `max_tokens: 4096`, a schema-instructed `system` prompt, and the rendered user
  prompt; (4) extract the first text content block, strip `` ```json `` fences,
  parse as a JSON object; (5) validate against `expected_output_schema` (required
  / type / enum checks); (6) on validation failure, retry up to
  `max_retries + 1` total attempts (default 3) with a corrective preamble — or 1
  attempt when `retry_on_incomplete: false`. On success, the validated object is
  the step output and is threaded into context. On exhaustion, `manifest.status`
  is `"failed"`. `require_curl` is called inside this arm only (curl-free for all
  other step types). `ANTHROPIC_API_KEY` absence is a loud fatal error (parity
  with `LlmProviders::Anthropic#call`). Model must start with `"claude"` (parity
  with `Llm.default_provider_for`). Test seam: `OSL_LLM_STUB=<raw-text>` skips
  the network call and feeds the value directly into the fence-strip + schema
  validation pipeline (parity with `provider_resolver=` in the runtime specs).
  15 new assertions covering the happy path, fence-stripping, `{{ var }}`
  substitution, schema exhaustion, missing key, non-claude model, and
  `retry_on_incomplete: false`.

- **`wait` step type — synchronous and async pause/resume (U5).**
  Mirrors `StepExecutors::Wait` (`wait.rb`) exactly. Three dispatch paths based on
  the step's nested `wait:` block: (a) `wait.seconds` present → synchronous
  completion immediately with `{waited: true, seconds: <n>}` — no actual sleep
  (byte-parity with the runtime's MVP stub); (b) `wait.until` present → async
  pause with `reason: "waiting_for_callback"`, `until` recorded in the audit
  receipt as advisory metadata, resumed via `opensop submit <run_id> <step-id>
  --local`; (c) neither present → synchronous completion with `{waited: true}`.
  The async pause path drops through `local_run`'s `waiting_for_callback` branch
  (already the `*` fallthrough for unrecognised types) and `local_submit` resumes
  it correctly at `cursor.next_index`. Empty `expects.outputs/schema` means submit
  accepts any (or no) output. 16 new assertions covering all three paths including
  the failure path (second submit on a completed run is rejected).

- **`approval` step type — pause/resume state machine (U4).**
  An `approval` step pauses the local run: `_local_step_loop` appends a
  `"waiting"` receipt to `audit.jsonl` (reason: `"waiting_for_approval"`,
  byte-parity with the runtime's `StepExecutors::Approval`) and returns
  `"waiting:<index>"`. `local_run` transitions the manifest to
  `status:"waiting"` and writes the full pause envelope. When the step
  declares no `inputs[]` or `outputs[]`, `expects.outputs` defaults to
  `["decision"]` and `expects.schema` to a required enum field
  `decision: approve|reject`. On submit, the enum constraint is enforced
  (e.g. `decision=maybe` is rejected). `decided_by` is recorded in the
  completion receipt. Full round-trip: run → pause at approval →
  `opensop submit <run_id> <step-id> --local --output decision=approve`
  → remaining steps run and run completes.

- **`required_if` parity (U4).** The runtime's `validate_outputs!`
  supports `required_if:` — a field required only when a condition
  evaluates to true (e.g. `rejection_reason` required only when
  `decision == 'reject'`). The local validator cannot evaluate arbitrary
  condition expressions (no `ConditionEvaluator`), so it skips the
  unconditional required check for any schema field that declares
  `required_if`. Intentionally permissive — never more restrictive than
  the server. The gap is documented in a comment in `local_submit`.

### Changed (internal)

- **Extract `_local_step_loop` from `local_run` (U1 — pure refactor, zero behavior change).**
  The per-step execution kernel is now a standalone function
  `_local_step_loop <run_dir> <proc_file> <start_index> <ctx_json>`.
  It iterates steps from `start_index`, dispatches by type, threads context,
  writes audit receipts, and writes `context.json` after every completed step
  (live checkpoint). Returns one of `"completed"`, `"failed"`, or
  `"waiting:<index>"` via stdout. `local_run` sets up the run dir + manifest,
  delegates to the loop, then finalizes. Prerequisite for U3 (resume at cursor).

- **U3.5 keystone cleanup — cursor semantics, atomic writes, dead-code removal, dynamic type.**
  `cursor.next_index` now consistently stores the index of the **first step to run
  on resume** (paused step index + 1) — both in `local_run`'s waiting branch and
  in `local_submit`'s second-pause path. `local_submit` reads `cursor.next_index`
  directly without a +1 offset. Context checkpoints in `_local_step_loop` and
  `local_submit` are now written atomically (temp + mv) to prevent truncation from
  silently stripping outputs. Removed the duplicated `errors_json` validation block
  in `local_submit` (the dead first block using a here-string input that was
  immediately overwritten) and the unused `proc_file2` variable. The resumed-step
  completion receipt now derives its `type` from the process file
  (`jq ".steps[$wait_index].type"`) instead of hardcoding `"form"`.

## [0.6.0] — 2026-06-08

The cell substrate. Six PRs (#6, #7, #8, #9, #10, #11) added a fractal
addressing primitive, a substrate-level event log per skill, name resolution
across the cell chain, fork with lineage, per-cell receipts, and the
executor field. Backwards-compatible — every pre-v0.6 usage continues to
work; v0.6 features only activate inside a cell.

### Added

- **Cell primitive — `opensop init` and `opensop scope`.** A "cell" is a
  directory marked by `.opensop/manifest.yaml`. `init` creates one in cwd
  (auto-detecting the parent cell when an ancestor `.opensop/` exists);
  `scope` walks up from cwd and prints the active cell + ancestor chain.
  Pure-additive — no existing command behavior changes. Foundation for the
  rest of v0.6.
- **Lineage primitives — `opensop annotate` and `opensop lineage`.**
  Substrate-level event log per skill stored in `.opensop/lineage.json` in
  each cell. `annotate <skill> <event-type> <json>` appends a policy event
  to the skill's history (creates the lineage entry if it doesn't exist).
  `lineage <skill>` prints the entry (status, metadata, history) in the
  active cell, returning an empty default if no events have been recorded.
  Policy-neutral: the substrate stores `status` (open string), `metadata`
  (open object), and `history[].type` (open string); it doesn't interpret
  any of them. This is what evolution policies (e.g. mineralization) sit on
  top of to record promotions, demotions, locks, etc.
- **Fork mechanic — `opensop fork <name> [--from <cell>]`.** Materializes
  a copy of an ancestor cell's skill into the active cell and records a lineage
  entry with `forked_from = { cell, forked_at, snapshot }`. The `snapshot` is
  the parent's `status` and `metadata` captured opaquely — the substrate stores;
  evolution policies decide what to do with it (typical: inherit + mark
  unverified until first run in the child cell). Auto-detects the source via
  walk-up; pass `--from` to override. Refuses to overwrite an existing skill
  in the active cell.
- **Step executor field — `executor: internal|external`.** Steps in a
  `.sop.json` may declare where their work happens: `external` means the work
  is done by a process outside the OpenSOP runtime (script, webhook); the
  runtime orchestrates and receives the receipt. `internal` means the runtime
  handles the step directly. Field is optional; per-type defaults apply when
  absent (`automated`/`shell`/`webhook` → external, `noop`/`form`/`approval`/
  `notification`/`wait`/`judgment` → internal). Invalid values fail with
  `parse_error` at process load time — before any step runs and before a run
  directory is even created. The effective executor (explicit or defaulted)
  is recorded in each step's `audit.jsonl` entry. Formalizes the
  B-mode-vs-A-mode distinction and matches existing production patterns
  (deterministic external scripts producing typed receipts).

### Changed

- **Name resolution across the cell chain.** Two changes to the local
  engine when a cell is active:
  - `opensop run <name> --local` accepts a **bare logical name** (in addition
    to a file path). The name resolves to `processes/<name>.sop.json` in the
    active cell, then in each ancestor cell — nearest wins. Explicit file
    paths still work for backwards compatibility (paths are detected when the
    argument ends in `.sop.json` or contains `/`).
  - `opensop list --local` (no dir arg) now walks the active cell + ancestors
    when invoked from inside a cell, tagging each entry with `[cell-name]`.
    Passing an explicit `dir` keeps the original `find`-based behavior with
    no cell awareness.
- **`OPENSOP_LOCAL_HOME` default is now cell-aware.** When cwd is inside
  an OpenSOP cell AND the user has not explicitly set `OPENSOP_LOCAL_HOME`,
  local-mode receipts (`opensop run --local`, `opensop runs`, `opensop show`)
  now default to `<cell-root>/.opensop/` instead of the global
  `~/.opensop-local`. Receipts land alongside the processes that produced
  them, and each cell has its own receipt history. Outside any cell, the
  default is still `~/.opensop-local`. Explicit `OPENSOP_LOCAL_HOME=…` always
  wins. Backwards-compatible because it only kicks in when a `.opensop/`
  marker exists in cwd's path (no pre-v0.6 user has one).

---

## [0.5.0] — 2026-06-04

### Added

- **Local execution backend (`--local`) — no server.** The CLI now has two
  backends: by default it talks to a running OpenSOP server; with `--local` the
  *same commands* run on-machine against internal files — no Rails, no daemon,
  no network, no `curl` (just `bash` + `jq`). `opensop run <process>.sop.json
  --local` runs `automated`/`shell`/`noop` steps in order, threads a JSON
  context between them (stdin + `$OSL_CONTEXT`, stdout merged under the step id),
  and writes an append-only on-disk receipt per step
  (`$OPENSOP_LOCAL_HOME/runs/<id>/`, default `~/.opensop-local`). This is an
  extension of OpenSOP, not a separate tool.
- **`runs`** — list local runs. **`show <run_id>`** — a local run's manifest +
  per-step receipts (the local analogue of `instances` / `status`).
- **`list --local [dir]`** — discover internal `.sop.json` processes.
- A worked example (`examples/greet.sop.json` + `examples/steps/build.sh`) and a
  golden test (`test/test.sh`).

### Changed

- **BREAKING: `--local` now means *local execution*** (run against internal
  files). It previously aliased `OPENSOP_URL` to `http://localhost:3000`. For a
  local dev **server**, use `opensop config set url http://localhost:3000` or
  `OPENSOP_URL=http://localhost:3000` instead.

### Fixed

- **Failing steps are handled instead of aborting.** Under `set -e`, a non-zero
  step previously aborted the whole CLI before the failure receipt, manifest
  finalization, and `continue_on_error` could run. Step execution is now guarded
  so failures are recorded (`failed` receipt + manifest `status:"failed"`) and
  `continue_on_error` works.
- **`runs` / `show` no longer require `curl`** — they are always-local commands.
- **Interrupted runs no longer stick at `running`.** A killed/crashed run is
  finalized as `interrupted` via an EXIT trap.
- **Step `stderr` is captured** into the receipt (surfaced by `show`); empty
  stderr logs are no longer left behind.
- **Empty/malformed `steps` are rejected** up front instead of "completing"
  trivially. `run_id` hardened against same-second/recycled-PID collisions.
- Trust boundary documented (local steps run as shell — only run process files
  you trust), and failure-path regression tests added to `test/test.sh`.

---

## [0.4.1] — 2026-05-08

### Fixed

- **Cache priming on `history` and `instances`** — both subcommands now
  populate the local `id → process.name` map from every response row.
  Agents who use the discovery layer to find an instance and immediately
  inspect it no longer hit the cache-miss path.
- **Paginated cache-miss fallback in `lookup_name`** — the fallback now
  walks up to 1000 instances (5 pages of 200) before giving up, instead
  of stopping at the first 200. Defensive fix; rarely hit once cache
  priming is in.
- **Multi-word `search` and `suggest`** — queries are now tokenized on
  whitespace and scored per-token, with hyphenated process names also
  tokenized on `-`/`_`. `search "morning briefing"` now correctly
  matches `darwin-morning-briefing`. Single-word queries unchanged.

### Changed

- **Search/suggest corpus widened** — `inputs_summary` and
  `outputs_summary` (already in the `/sop/` discovery response, just
  unused) are now indexed alongside name + description + tags.
  Expected ~30% recall lift on "what produces X?" / "I want Y"
  intent queries. Reported by the Darwin agent.

---

## [0.4.0] — 2026-05-08

### Added

- **Structured CLI-side errors in `--json` mode.** When `--json` is set, every
  `die()`/`err()` call now emits `{"error": "<code>", "message": "<message>",
  "hint": "<hint>"}` to stderr instead of prose. Prose-mode default (TTY) is
  unchanged — fully backward-compatible.
- `_resolve_output_mode()` helper that respects `OUTPUT_MODE` before `main()`
  has finished stripping flags (e.g. very early dependency checks).
- Error codes for all CLI-side failure paths: `config_missing`,
  `missing_dependency`, `network_error`, `instance_not_found`, `usage_error`,
  `file_not_found`, `invalid_json`, `unknown_command`, `unknown_flag`,
  `parse_error`, `cli_error`.
- `hint` field on relevant codes (e.g. `config_missing` hints
  `opensop config set url <URL>`; `missing_dependency` for jq hints
  `brew install jq`).

### Changed

- **HTTP error path in `api_call`:** in `--json` mode, server error envelopes
  now pass through verbatim with a `_meta.http_status` field appended. The
  previous behavior (prose + raw JSON dump) is replaced by a single clean JSON
  object on stderr.
- `register` HTTP error path brought in line with the same `api_call` pattern.
- All `die "..."` call sites updated with explicit codes and hints where
  applicable.
- `file not found` wording normalised to `"file does not exist: <path>"` across
  `register` and `schema validate`.

---

## [0.3.1] — 2026-05-08

### Fixed

- `compass --json` shape now matches docs: top-level keys are
  `{by_runs, by_recency, by_failure_rate}` with consistent field names per
  slice (`{name, total}` / `{name, last_run_at}` /
  `{name, total, failures, rate}`).

---

## [0.3.0] — 2026-05-08

### Added

- `diff <id1> <id2>` — compare two instances of the same process field-by-field.
- `compass` — top processes by run-count, recency, and failure rate.
- `history --process <name> [--limit N]` — recent instances of a specific
  process, newest-first.
- `dry-run <name> [opts]` — client-side preview: validates inputs against the
  process schema and describes each step without creating an instance.
- `register <process.yaml>` — POST a `.sop.yaml` to `/sop/processes/register`.
- `schema validate <file.yaml>` — fully client-side YAML lint using `yq` (v4+)
  with `python3` + PyYAML as a fallback.
- `--local` global flag — overrides `OPENSOP_URL` to `http://localhost:3000`
  for a single call without changing config.

---

## [0.2.0] — 2026-05-08

### Added

- `search <keyword> [...]` — ranked text search over process names,
  descriptions, and tags.
- `suggest "<task description>"` — inverse retrieval: describe a task, get the
  top-matching process back with a confidence score.
- `list --tag <tag>` — client-side filter by tag.
- README worked example (full `lead-qualification` run from start to
  completion).
- Sample `opensop list` output in README.
- Lifted the cache-line note into its own README section.

---

## [0.1.0] — 2026-05-07

### Added

- Initial release.
- 9 subcommands: `list`, `schema`, `run`, `status`, `steps`, `submit`,
  `cancel`, `instances`, `config`.
- Instance-ID local cache (`~/.opensop/instances.tsv`) — maps instance IDs to
  process names so subsequent commands need only the ID.
- TTY-aware output: pretty-printed in a terminal, compact JSON when piped.
- `--json` / `--pretty` global flags.
- `X-SOP-Token` auth header support.
- `NO_COLOR` support.

[0.8.0]: https://github.com/Chosen9115/opensop-cli/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/Chosen9115/opensop-cli/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Chosen9115/opensop-cli/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Chosen9115/opensop-cli/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Chosen9115/opensop-cli/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Chosen9115/opensop-cli/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/Chosen9115/opensop-cli/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Chosen9115/opensop-cli/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Chosen9115/opensop-cli/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Chosen9115/opensop-cli/releases/tag/v0.1.0
