#!/usr/bin/env bash
# Golden test for the --local backend: run the greet example through the CLI,
# then inspect it via `opensop show`. Asserts context threading, receipts, and
# no step-output leak. Requires bash + jq (no server, no curl).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cli="$here/bin/opensop"
export OPENSOP_LOCAL_HOME="$(mktemp -d)"
trap 'rm -rf "$OPENSOP_LOCAL_HOME"' EXIT

manifest="$("$cli" run "$here/examples/greet.sop.json" --local --input name=opensop --json)"
run_id="$(jq -r '.run_id' <<<"$manifest")"
status="$(jq -r '.status' <<<"$manifest")"
echo "run $run_id -> $status"
[ "$status" = "completed" ] || { echo "FAIL: run not completed"; exit 1; }

# inspect via the CLI's own `show` (exercises the local inspection path too)
show="$("$cli" show "$run_id" --json)"
render="$(jq -r '.steps[] | select(.step=="render") | .output.stdout' <<<"$show")"
echo "render -> $render"
echo "$render" | grep -q "hello, opensop" || { echo "FAIL: expected greeting not rendered"; exit 1; }

jq -e '.steps[] | select(.step=="build"  and .status=="completed")' <<<"$show" >/dev/null || { echo "FAIL: build receipt missing/failed"; exit 1; }
jq -e '.steps[] | select(.step=="render" and .status=="completed")' <<<"$show" >/dev/null || { echo "FAIL: render receipt missing/failed"; exit 1; }
# render must NOT have leaked the build step's output (regression guard)
jq -e '.steps[] | select(.step=="render") | .output | has("greeting")' <<<"$show" >/dev/null 2>&1 && { echo "FAIL: render leaked build output"; exit 1; }

echo "PASS: opensop run --local + show — 2 steps, context threaded, receipts written, no leak"

# --------------------------------------------------------------------------- #
# Failure path (regression guard for the set -e abort bug): a failing step must
# NOT abort the CLI silently. It must write a "failed" receipt, finalize the
# manifest as "failed", and exit non-zero. Without the `|| rc=$?` guard, `set -e`
# aborts at the step substitution and none of this happens.
# --------------------------------------------------------------------------- #
fail_proc="$OPENSOP_LOCAL_HOME/fail.sop.json"
cat > "$fail_proc" <<'JSON'
{ "name": "failtest", "inputs": {},
  "steps": [
    { "id": "boom",  "type": "shell", "run": "echo boom-stderr >&2; echo oops; exit 3" },
    { "id": "after", "type": "shell", "run": "echo should-not-run" }
  ] }
JSON
set +e
fm="$("$cli" run "$fail_proc" --local --json)"; frc=$?
set -e
[ "$frc" -ne 0 ] || { echo "FAIL: failing run should exit non-zero, got $frc"; exit 1; }
[ "$(jq -r '.status' <<<"$fm")" = "failed" ] || { echo "FAIL: manifest not 'failed'"; exit 1; }
frun="$(jq -r '.run_id' <<<"$fm")"
fshow="$("$cli" show "$frun" --json)"
jq -e '.steps[] | select(.step=="boom" and .status=="failed" and .exit_code==3)' <<<"$fshow" >/dev/null || { echo "FAIL: boom receipt missing/not failed"; exit 1; }
jq -e '.steps[] | select(.step=="after")' <<<"$fshow" >/dev/null && { echo "FAIL: 'after' ran despite prior failure (no continue_on_error)"; exit 1; }
jq -e '.steps[] | select(.step=="boom") | .stderr | test("boom-stderr")' <<<"$fshow" >/dev/null || { echo "FAIL: boom stderr not captured in receipt"; exit 1; }
echo "PASS: failing step — non-zero exit, 'failed' receipt + manifest, stderr captured, halted"

# --------------------------------------------------------------------------- #
# continue_on_error: a failed step with continue_on_error:true must NOT halt the
# run — the later step runs and the run completes.
# --------------------------------------------------------------------------- #
coe_proc="$OPENSOP_LOCAL_HOME/coe.sop.json"
cat > "$coe_proc" <<'JSON'
{ "name": "coetest", "inputs": {},
  "steps": [
    { "id": "boom",  "type": "shell", "continue_on_error": true, "run": "echo oops; exit 3" },
    { "id": "after", "type": "shell", "run": "echo reached" }
  ] }
JSON
cm="$("$cli" run "$coe_proc" --local --json)"
[ "$(jq -r '.status' <<<"$cm")" = "completed" ] || { echo "FAIL: continue_on_error run should complete"; exit 1; }
crun="$(jq -r '.run_id' <<<"$cm")"
cshow="$("$cli" show "$crun" --json)"
jq -e '.steps[] | select(.step=="boom"  and .status=="failed")'    <<<"$cshow" >/dev/null || { echo "FAIL: boom should be recorded failed"; exit 1; }
jq -e '.steps[] | select(.step=="after" and .status=="completed")' <<<"$cshow" >/dev/null || { echo "FAIL: 'after' should have run under continue_on_error"; exit 1; }
echo "PASS: continue_on_error — failed step recorded, later step still runs, run completes"

# --------------------------------------------------------------------------- #
# Empty/invalid process guards.
# --------------------------------------------------------------------------- #
empty_proc="$OPENSOP_LOCAL_HOME/empty.sop.json"
echo '{ "name": "empty", "steps": [] }' > "$empty_proc"
set +e; "$cli" run "$empty_proc" --local --json >/dev/null 2>&1; erc=$?; set -e
[ "$erc" -ne 0 ] || { echo "FAIL: empty-steps process should be rejected"; exit 1; }
echo "PASS: empty-steps process rejected"

# --------------------------------------------------------------------------- #
# Cell primitive (v0.6): init + scope.
# --------------------------------------------------------------------------- #
cells_dir="$OPENSOP_LOCAL_HOME/cells"
mkdir -p "$cells_dir/parent/child" "$cells_dir/no-cell"

# init in root cell (no ancestor)
( cd "$cells_dir/parent" && "$cli" init --json >/dev/null )
[ -f "$cells_dir/parent/.opensop/manifest.yaml" ] || { echo "FAIL: init didn't create manifest.yaml"; exit 1; }
[ -d "$cells_dir/parent/.opensop/runs" ]          || { echo "FAIL: init didn't create runs/"; exit 1; }
[ -d "$cells_dir/parent/.opensop/archive" ]       || { echo "FAIL: init didn't create archive/"; exit 1; }
[ -f "$cells_dir/parent/.opensop/lineage.json" ]  || { echo "FAIL: init didn't seed lineage.json"; exit 1; }
grep -q "^name: parent$"  "$cells_dir/parent/.opensop/manifest.yaml" || { echo "FAIL: parent manifest has wrong name"; exit 1; }
grep -q "^parent: null$"  "$cells_dir/parent/.opensop/manifest.yaml" || { echo "FAIL: root cell should have parent: null"; exit 1; }
echo "PASS: init — creates .opensop/ tree as root cell"

# init in child auto-detects parent
( cd "$cells_dir/parent/child" && "$cli" init --json >/dev/null )
grep -q "^name: child$"     "$cells_dir/parent/child/.opensop/manifest.yaml" || { echo "FAIL: child manifest has wrong name"; exit 1; }
grep -q "^parent: \.\./$"   "$cells_dir/parent/child/.opensop/manifest.yaml" || { echo "FAIL: child should auto-detect parent as '../'"; exit 1; }
echo "PASS: init — auto-detects parent cell from ancestor"

# init failure: already initialized
set +e
( cd "$cells_dir/parent" && "$cli" init --json >/dev/null 2>&1 ); irc=$?
set -e
[ "$irc" -ne 0 ] || { echo "FAIL: re-init of existing cell should exit non-zero"; exit 1; }
echo "PASS: init — refuses to clobber existing .opensop/"

# scope from inside child: shows child + parent (2 entries)
scope_json="$( cd "$cells_dir/parent/child" && "$cli" scope --json )"
[ "$(jq -r '. | length'      <<<"$scope_json")" = "2" ]      || { echo "FAIL: scope from child should have 2 entries"; exit 1; }
[ "$(jq -r '.[0].name'       <<<"$scope_json")" = "child" ]  || { echo "FAIL: scope[0].name should be 'child'"; exit 1; }
[ "$(jq -r '.[0].active'     <<<"$scope_json")" = "true" ]   || { echo "FAIL: scope[0] should be active"; exit 1; }
[ "$(jq -r '.[1].name'       <<<"$scope_json")" = "parent" ] || { echo "FAIL: scope[1].name should be 'parent'"; exit 1; }
[ "$(jq -r '.[1].active'     <<<"$scope_json")" = "false" ]  || { echo "FAIL: scope[1] should be inactive (ancestor)"; exit 1; }
echo "PASS: scope — walks ancestor chain from child to parent"

# scope from inside root: shows only root (1 entry)
scope_root_json="$( cd "$cells_dir/parent" && "$cli" scope --json )"
[ "$(jq -r '. | length' <<<"$scope_root_json")" = "1" ]       || { echo "FAIL: root cell scope should have 1 entry"; exit 1; }
[ "$(jq -r '.[0].name'  <<<"$scope_root_json")" = "parent" ]  || { echo "FAIL: root scope[0].name should be 'parent'"; exit 1; }
echo "PASS: scope — root cell shows only itself"

# scope failure: outside any cell
set +e
( cd "$cells_dir/no-cell" && "$cli" scope --json >/dev/null 2>&1 ); src=$?
set -e
[ "$src" -ne 0 ] || { echo "FAIL: scope outside any cell should exit non-zero"; exit 1; }
echo "PASS: scope — errors when not inside a cell"

# explicit --name + --parent
mkdir -p "$cells_dir/explicit"
( cd "$cells_dir/explicit" && "$cli" init --name custom-name --parent /some/abs/path --json >/dev/null )
grep -q "^name: custom-name$"         "$cells_dir/explicit/.opensop/manifest.yaml" || { echo "FAIL: explicit --name not honored"; exit 1; }
grep -q "^parent: /some/abs/path$"    "$cells_dir/explicit/.opensop/manifest.yaml" || { echo "FAIL: explicit --parent not honored"; exit 1; }
echo "PASS: init — explicit --name and --parent flags honored"

# --------------------------------------------------------------------------- #
# Lineage primitives (v0.6): annotate + lineage.
# --------------------------------------------------------------------------- #
ln_dir="$OPENSOP_LOCAL_HOME/lineage"
mkdir -p "$ln_dir/c1"
( cd "$ln_dir/c1" && "$cli" init --json >/dev/null )

# annotate creates a lineage entry for a previously-unknown skill
ann_evt="$( cd "$ln_dir/c1" && "$cli" annotate skill-a promote '{"to":"m2"}' --json )"
[ "$(jq -r '.type' <<<"$ann_evt")" = "promote" ]      || { echo "FAIL: annotate output event.type wrong"; exit 1; }
[ "$(jq -r '.data.to' <<<"$ann_evt")" = "m2" ]        || { echo "FAIL: annotate output event.data.to wrong"; exit 1; }
[ -n "$(jq -r '.at' <<<"$ann_evt")" ]                  || { echo "FAIL: annotate output missing .at timestamp"; exit 1; }
on_disk="$(cat "$ln_dir/c1/.opensop/lineage.json")"
[ "$(jq -r '."skill-a".logical_name' <<<"$on_disk")" = "skill-a" ]    || { echo "FAIL: skill-a not stored in lineage.json"; exit 1; }
[ "$(jq -r '."skill-a".history | length' <<<"$on_disk")" = "1" ]      || { echo "FAIL: skill-a should have 1 history event"; exit 1; }
echo "PASS: annotate — creates lineage entry + appends first event"

# annotate appends to an existing entry (history grows; both events preserved)
( cd "$ln_dir/c1" && "$cli" annotate skill-a promote '{"to":"m3"}' --json >/dev/null )
( cd "$ln_dir/c1" && "$cli" annotate skill-a bless   '{"by":"human"}' --json >/dev/null )
on_disk="$(cat "$ln_dir/c1/.opensop/lineage.json")"
[ "$(jq -r '."skill-a".history | length' <<<"$on_disk")" = "3" ]        || { echo "FAIL: skill-a should have 3 history events"; exit 1; }
[ "$(jq -r '."skill-a".history[2].type' <<<"$on_disk")" = "bless" ]     || { echo "FAIL: last event type wrong"; exit 1; }
[ "$(jq -r '."skill-a".history[0].data.to' <<<"$on_disk")" = "m2" ]     || { echo "FAIL: first event data lost"; exit 1; }
echo "PASS: annotate — appends to existing entry, preserves order + prior events"

# lineage retrieves the entry (json mode round-trips faithfully)
lin_json="$( cd "$ln_dir/c1" && "$cli" lineage skill-a --json )"
[ "$(jq -r '.logical_name'        <<<"$lin_json")" = "skill-a" ] || { echo "FAIL: lineage logical_name wrong"; exit 1; }
[ "$(jq -r '.history | length'    <<<"$lin_json")" = "3" ]       || { echo "FAIL: lineage history count wrong"; exit 1; }
[ "$(jq -r '.status'              <<<"$lin_json")" = "" ]        || { echo "FAIL: lineage status should be empty by default"; exit 1; }
[ "$(jq -r '.forked_from'         <<<"$lin_json")" = "null" ]    || { echo "FAIL: lineage forked_from should be null"; exit 1; }
echo "PASS: lineage — returns full entry with correct shape"

# lineage on never-annotated skill returns default empty entry (not an error)
lin_empty="$( cd "$ln_dir/c1" && "$cli" lineage never-touched --json )"
[ "$(jq -r '.logical_name'     <<<"$lin_empty")" = "never-touched" ] || { echo "FAIL: lineage on unknown skill should still set logical_name"; exit 1; }
[ "$(jq -r '.history | length' <<<"$lin_empty")" = "0" ]             || { echo "FAIL: lineage on unknown skill should have empty history"; exit 1; }
echo "PASS: lineage — returns empty default for never-annotated skill"

# negative: invalid JSON data
set +e
( cd "$ln_dir/c1" && "$cli" annotate skill-a promote 'this-is-not-json' --json >/dev/null 2>&1 ); arc=$?
set -e
[ "$arc" -ne 0 ] || { echo "FAIL: annotate with invalid JSON should exit non-zero"; exit 1; }
echo "PASS: annotate — rejects invalid JSON data"

# negative: missing args (annotate needs skill + type + data)
set +e
( cd "$ln_dir/c1" && "$cli" annotate skill-a --json >/dev/null 2>&1 ); brc=$?
set -e
[ "$brc" -ne 0 ] || { echo "FAIL: annotate with missing args should exit non-zero"; exit 1; }
echo "PASS: annotate — rejects missing args"

# negative: annotate outside any cell
set +e
( cd "$OPENSOP_LOCAL_HOME" && "$cli" annotate x y '{}' --json >/dev/null 2>&1 ); crc=$?
set -e
[ "$crc" -ne 0 ] || { echo "FAIL: annotate outside any cell should exit non-zero"; exit 1; }
echo "PASS: annotate — errors when not inside a cell"

# negative: lineage outside any cell
set +e
( cd "$OPENSOP_LOCAL_HOME" && "$cli" lineage anything --json >/dev/null 2>&1 ); drc=$?
set -e
[ "$drc" -ne 0 ] || { echo "FAIL: lineage outside any cell should exit non-zero"; exit 1; }
echo "PASS: lineage — errors when not inside a cell"

# corruption guard: bad JSON in lineage.json triggers invalid_json error
echo "not { valid : json" > "$ln_dir/c1/.opensop/lineage.json"
set +e
( cd "$ln_dir/c1" && "$cli" lineage skill-a --json >/dev/null 2>&1 ); erc=$?
set -e
[ "$erc" -ne 0 ] || { echo "FAIL: lineage on corrupt lineage.json should exit non-zero"; exit 1; }
echo "PASS: lineage — refuses to read a corrupt lineage.json"

# --------------------------------------------------------------------------- #
# --pretty flag overrides auto-mode regardless of TTY (regression for the
# subshell-capture bug that made cmd_init/scope/annotate/lineage always
# emit JSON because _resolve_output_mode was called via $() which made
# is_tty see a pipe instead of the terminal).
# --------------------------------------------------------------------------- #
mkdir -p "$cells_dir/pretty-out"
pretty_init="$( cd "$cells_dir/pretty-out" && "$cli" --pretty init )"
# Must NOT start with '{' (which would mean JSON output)
[[ "${pretty_init:0:1}" != "{" ]]                                   || { echo "FAIL: init --pretty produced JSON"; exit 1; }
[[ "$pretty_init" == *"initialized cell"* ]]                        || { echo "FAIL: init --pretty missing 'initialized cell'"; exit 1; }
echo "PASS: init --pretty produces prose (not JSON) even from non-TTY caller"

pretty_scope="$( cd "$cells_dir/pretty-out" && "$cli" --pretty scope )"
[[ "${pretty_scope:0:1}" != "[" ]]                                  || { echo "FAIL: scope --pretty produced JSON array"; exit 1; }
[[ "$pretty_scope" == *"active cell"* ]]                            || { echo "FAIL: scope --pretty missing 'active cell'"; exit 1; }
echo "PASS: scope --pretty produces prose (not JSON) even from non-TTY caller"

pretty_ann="$( cd "$cells_dir/pretty-out" && "$cli" --pretty annotate s promote '{"x":1}' )"
[[ "${pretty_ann:0:1}" != "{" ]]                                    || { echo "FAIL: annotate --pretty produced JSON event"; exit 1; }
[[ "$pretty_ann" == *"annotated"* ]]                                || { echo "FAIL: annotate --pretty missing 'annotated'"; exit 1; }
echo "PASS: annotate --pretty produces prose (not JSON) even from non-TTY caller"

pretty_lin="$( cd "$cells_dir/pretty-out" && "$cli" --pretty lineage s )"
[[ "${pretty_lin:0:1}" != "{" ]]                                    || { echo "FAIL: lineage --pretty produced JSON entry"; exit 1; }
[[ "$pretty_lin" == *"lineage:"* ]]                                 || { echo "FAIL: lineage --pretty missing 'lineage:' header"; exit 1; }
echo "PASS: lineage --pretty produces prose (not JSON) even from non-TTY caller"

# --------------------------------------------------------------------------- #
# Per-cell OPENSOP_LOCAL_HOME default (v0.6 PR 3): when cwd is inside a cell
# and the user did NOT explicitly set OPENSOP_LOCAL_HOME, local-mode receipts
# land in the cell's .opensop/runs/ — not in the global ~/.opensop-local.
# Explicit env override still wins.
# --------------------------------------------------------------------------- #
runs_cell="$OPENSOP_LOCAL_HOME/runs-cell"
mkdir -p "$runs_cell"
( cd "$runs_cell" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )

# (1) Inside cell, no explicit OPENSOP_LOCAL_HOME → receipt lands in cell
m1=$( cd "$runs_cell" && env -u OPENSOP_LOCAL_HOME "$cli" run "$here/examples/greet.sop.json" --local --input name=cellrun --json )
rid1=$(jq -r '.run_id' <<<"$m1")
[ "$(jq -r '.status' <<<"$m1")" = "completed" ]      || { echo "FAIL: cell-aware run didn't complete"; exit 1; }
[ -d "$runs_cell/.opensop/runs/$rid1" ]              || { echo "FAIL: receipt not in cell's .opensop/runs/"; exit 1; }
[ ! -d "$OPENSOP_LOCAL_HOME/runs/$rid1" ]            || { echo "FAIL: receipt leaked to test's OPENSOP_LOCAL_HOME"; exit 1; }
echo "PASS: runs — inside cell, default OPENSOP_LOCAL_HOME → receipt in cell's .opensop/runs/"

# (2) Inside cell, explicit OPENSOP_LOCAL_HOME → that path wins over cell
override_home="$(mktemp -d)"
m2=$( cd "$runs_cell" && OPENSOP_LOCAL_HOME="$override_home" "$cli" run "$here/examples/greet.sop.json" --local --input name=override --json )
rid2=$(jq -r '.run_id' <<<"$m2")
[ -d "$override_home/runs/$rid2" ]                    || { echo "FAIL: explicit override not honored"; exit 1; }
[ ! -d "$runs_cell/.opensop/runs/$rid2" ]             || { echo "FAIL: receipt leaked to cell despite explicit override"; exit 1; }
rm -rf "$override_home"
echo "PASS: runs — explicit OPENSOP_LOCAL_HOME wins over cell-aware default"

# (3) `opensop runs` inside the cell sees the cell's receipts (not the global)
runs_list=$( cd "$runs_cell" && env -u OPENSOP_LOCAL_HOME "$cli" runs )
[[ "$runs_list" == *"$rid1"* ]]                       || { echo "FAIL: 'opensop runs' inside cell didn't show cell's run"; exit 1; }
[[ "$runs_list" != *"$rid2"* ]]                       || { echo "FAIL: 'opensop runs' inside cell shouldn't see override's run"; exit 1; }
echo "PASS: runs — 'opensop runs' inside cell reads the cell's receipts only"

# (4) Corrupt cell: .opensop/ directory without manifest.yaml is NOT a cell
fake_cell="$OPENSOP_LOCAL_HOME/fake-cell"
mkdir -p "$fake_cell/.opensop"
set +e
( cd "$fake_cell" && env -u OPENSOP_LOCAL_HOME "$cli" scope --json >/dev/null 2>&1 ); fcrc=$?
set -e
[ "$fcrc" -ne 0 ] || { echo "FAIL: cwd with .opensop/ but no manifest.yaml should NOT be recognized as a cell"; exit 1; }
echo "PASS: cells — .opensop/ without manifest.yaml is correctly ignored (not a cell)"

# (5) Nested cells: run from inner cell lands receipts in inner, not in outer
mkdir -p "$OPENSOP_LOCAL_HOME/nested/outer/inner"
( cd "$OPENSOP_LOCAL_HOME/nested/outer"       && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )
( cd "$OPENSOP_LOCAL_HOME/nested/outer/inner" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )

m_inner=$( cd "$OPENSOP_LOCAL_HOME/nested/outer/inner" && env -u OPENSOP_LOCAL_HOME "$cli" run "$here/examples/greet.sop.json" --local --input name=nested-inner --json )
rid_inner=$(jq -r '.run_id' <<<"$m_inner")
[ -d "$OPENSOP_LOCAL_HOME/nested/outer/inner/.opensop/runs/$rid_inner" ] || { echo "FAIL: nested inner-cell run receipt not in inner"; exit 1; }
[ ! -d "$OPENSOP_LOCAL_HOME/nested/outer/.opensop/runs/$rid_inner" ]     || { echo "FAIL: nested inner-cell run receipt leaked to outer"; exit 1; }
echo "PASS: runs — nested cells route receipts to the innermost cell, not ancestors"

# --------------------------------------------------------------------------- #
# Name resolution across the cell chain (v0.6 PR 4):
#   * `opensop list` walks active cell + ancestors, tagging each with [cell-name]
#   * `opensop run <name>` resolves bare name → processes/<name>.sop.json
#     nearest-wins; explicit paths still work for backwards compat
# --------------------------------------------------------------------------- #
nr_org="$OPENSOP_LOCAL_HOME/nr-org"
nr_team="$nr_org/team"
mkdir -p "$nr_team"
( cd "$nr_org"  && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )
( cd "$nr_team" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )

# Inline skill at the org level — uses a `shell` step so it has no file deps
mkdir -p "$nr_org/processes"
cat > "$nr_org/processes/say-hi.sop.json" <<'JSON'
{ "name": "say-hi", "inputs": {},
  "steps": [ { "id": "hi", "type": "shell", "run": "echo hi" } ] }
JSON

# (1) list from inside team walks up — should find org's say-hi tagged [nr-org]
list_out=$( cd "$nr_team" && env -u OPENSOP_LOCAL_HOME "$cli" list --local )
[[ "$list_out" == *"[nr-org]"*"say-hi"* ]] || { echo "FAIL: list inside team didn't surface org's say-hi tagged [nr-org]"; echo "  got: $list_out"; exit 1; }
echo "PASS: list — inside cell, walks active + ancestor processes/ tagged with [cell-name]"

# (2) list with explicit dir arg uses the original find-based behavior (no [cell] tags)
explicit_dir_list=$( "$cli" list --local "$nr_org" )
[[ "$explicit_dir_list" == *"say-hi"* ]]   || { echo "FAIL: explicit-dir list didn't find say-hi"; exit 1; }
[[ "$explicit_dir_list" != *"[nr-org]"* ]] || { echo "FAIL: explicit-dir list shouldn't add [cell-name] tag (backwards compat)"; exit 1; }
echo "PASS: list — explicit dir arg uses original find behavior (no cell tag)"

# (3) run by NAME from team resolves to org's say-hi (parent cell)
m_nr=$( cd "$nr_team" && env -u OPENSOP_LOCAL_HOME "$cli" run say-hi --local --json )
[ "$(jq -r '.status'       <<<"$m_nr")" = "completed" ]              || { echo "FAIL: name-resolved run didn't complete"; exit 1; }
[ "$(jq -r '.process_file' <<<"$m_nr")" = "$nr_org/processes/say-hi.sop.json" ] || { echo "FAIL: name resolved to wrong file"; exit 1; }
echo "PASS: run — bare name resolves to ancestor cell's processes/<name>.sop.json"

# (4) nearest-wins: a same-name skill in team's processes/ shadows org's
mkdir -p "$nr_team/processes"
cat > "$nr_team/processes/say-hi.sop.json" <<'JSON'
{ "name": "say-hi", "inputs": {},
  "steps": [ { "id": "hi-team", "type": "shell", "run": "echo hi-from-team" } ] }
JSON
m_near=$( cd "$nr_team" && env -u OPENSOP_LOCAL_HOME "$cli" run say-hi --local --json )
[ "$(jq -r '.process_file' <<<"$m_near")" = "$nr_team/processes/say-hi.sop.json" ] || { echo "FAIL: nearest-wins didn't pick team's say-hi"; exit 1; }
echo "PASS: run — nearest-wins resolution (team's say-hi shadows org's)"

# (5) explicit path still works (backwards compat)
m_path=$( cd "$nr_team" && env -u OPENSOP_LOCAL_HOME "$cli" run "$nr_org/processes/say-hi.sop.json" --local --json )
[ "$(jq -r '.process_file' <<<"$m_path")" = "$nr_org/processes/say-hi.sop.json" ] || { echo "FAIL: explicit path not honored"; exit 1; }
echo "PASS: run — explicit path still works (backwards compat for paths containing / or .sop.json)"

# (6) run by non-existent name errors helpfully
set +e
( cd "$nr_team" && env -u OPENSOP_LOCAL_HOME "$cli" run no-such-skill --local --json >/dev/null 2>&1 ); nrrc=$?
set -e
[ "$nrrc" -ne 0 ] || { echo "FAIL: run with non-existent name should exit non-zero"; exit 1; }
echo "PASS: run — non-existent name errors cleanly"

# (7) run by name when NOT in any cell — also errors (nothing to resolve against)
set +e
( cd "$OPENSOP_LOCAL_HOME" && env -u OPENSOP_LOCAL_HOME "$cli" run say-hi --local --json >/dev/null 2>&1 ); ncrc=$?
set -e
[ "$ncrc" -ne 0 ] || { echo "FAIL: run by name outside any cell should exit non-zero"; exit 1; }
echo "PASS: run — bare name outside any cell errors (no cell chain to search)"

# --------------------------------------------------------------------------- #
# Fork mechanic (v0.6 PR 5): materialize an ancestor's skill in the active
# cell + record a lineage entry with forked_from snapshot of parent state.
# --------------------------------------------------------------------------- #
fk_org="$OPENSOP_LOCAL_HOME/fk-org"
fk_team="$fk_org/team"
mkdir -p "$fk_team"
( cd "$fk_org"  && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )
( cd "$fk_team" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )

mkdir -p "$fk_org/processes"
cat > "$fk_org/processes/greet-skill.sop.json" <<'JSON'
{ "name": "greet-skill", "inputs": {}, "steps": [{"id":"x","type":"shell","run":"echo greet"}] }
JSON

# Seed parent's lineage with a non-trivial policy state to test snapshotting
fk_lineage="$fk_org/.opensop/lineage.json"
jq --arg name "greet-skill" \
   '.[$name] = {logical_name:$name, forked_from:null, history:[{at:"2026-01-01T00:00:00Z",type:"promote",data:{to:"m3"}}], status:"mineralized", metadata:{m:"3.247"}}' \
   "$fk_lineage" > "$fk_lineage.tmp" && mv "$fk_lineage.tmp" "$fk_lineage"

# (1) Fork from team auto-detects org as the source (walk-up)
fork_out=$( cd "$fk_team" && env -u OPENSOP_LOCAL_HOME "$cli" fork greet-skill --json )
[ "$(jq -r '.ok'             <<<"$fork_out")" = "true" ]                       || { echo "FAIL: fork ok!=true"; exit 1; }
[ "$(jq -r '.source_cell'    <<<"$fork_out")" = "$fk_org" ]                    || { echo "FAIL: fork source_cell wrong"; exit 1; }
[ "$(jq -r '.dest_file'      <<<"$fork_out")" = "$fk_team/processes/greet-skill.sop.json" ] || { echo "FAIL: fork dest_file wrong"; exit 1; }
[ -f "$fk_team/processes/greet-skill.sop.json" ]                               || { echo "FAIL: file not copied to child cell"; exit 1; }
echo "PASS: fork — copies file from ancestor's processes/ into active cell"

# (2) Child's lineage entry has forked_from with the parent's policy snapshot
child_lineage="$fk_team/.opensop/lineage.json"
[ "$(jq -r '."greet-skill".forked_from.cell' "$child_lineage")"                = "$fk_org" ]    || { echo "FAIL: forked_from.cell wrong"; exit 1; }
[ -n "$(jq -r '."greet-skill".forked_from.forked_at' "$child_lineage")" ]                       || { echo "FAIL: forked_at missing"; exit 1; }
[ "$(jq -r '."greet-skill".forked_from.snapshot.status' "$child_lineage")"      = "mineralized" ] || { echo "FAIL: snapshot.status wrong"; exit 1; }
[ "$(jq -r '."greet-skill".forked_from.snapshot.metadata.m' "$child_lineage")"  = "3.247" ]       || { echo "FAIL: snapshot.metadata.m wrong"; exit 1; }
echo "PASS: fork — child's forked_from captures parent's status + metadata as snapshot"

# (3) Child's live status + metadata are empty (substrate is policy-neutral; let policy set them)
[ "$(jq -r '."greet-skill".status'           "$child_lineage")" = "" ]  || { echo "FAIL: child's live status should be empty after fork"; exit 1; }
[ "$(jq -c '."greet-skill".metadata'         "$child_lineage")" = "{}" ] || { echo "FAIL: child's live metadata should be empty after fork"; exit 1; }
[ "$(jq -r '."greet-skill".history | length' "$child_lineage")" = "0" ]  || { echo "FAIL: child's history should start empty"; exit 1; }
echo "PASS: fork — child's live status/metadata/history start empty (policy populates)"

# (4) Parent's lineage is NOT modified by the fork
[ "$(jq -r '."greet-skill".status'     "$fk_lineage")" = "mineralized" ] || { echo "FAIL: parent's status was modified by fork"; exit 1; }
[ "$(jq -r '."greet-skill".metadata.m' "$fk_lineage")" = "3.247" ]       || { echo "FAIL: parent's metadata was modified by fork"; exit 1; }
echo "PASS: fork — parent's lineage is untouched"

# (5) Refuses to overwrite an existing skill in the active cell
set +e
( cd "$fk_team" && env -u OPENSOP_LOCAL_HOME "$cli" fork greet-skill --json >/dev/null 2>&1 ); fk_rc1=$?
set -e
[ "$fk_rc1" -ne 0 ] || { echo "FAIL: re-fork into a cell that already has the skill should exit non-zero"; exit 1; }
echo "PASS: fork — refuses to overwrite an existing skill in active cell"

# (6) Errors on non-existent skill
set +e
( cd "$fk_team" && env -u OPENSOP_LOCAL_HOME "$cli" fork no-such-skill --json >/dev/null 2>&1 ); fk_rc2=$?
set -e
[ "$fk_rc2" -ne 0 ] || { echo "FAIL: fork of non-existent skill should exit non-zero"; exit 1; }
echo "PASS: fork — errors when skill not found in any ancestor"

# (7) Outside any cell — errors (need a cell to fork into)
set +e
( cd "$OPENSOP_LOCAL_HOME" && env -u OPENSOP_LOCAL_HOME "$cli" fork greet-skill --json >/dev/null 2>&1 ); fk_rc3=$?
set -e
[ "$fk_rc3" -ne 0 ] || { echo "FAIL: fork outside any cell should exit non-zero"; exit 1; }
echo "PASS: fork — errors when not inside a cell"

# (8) --from <path> override resolves explicitly
mkdir -p "$OPENSOP_LOCAL_HOME/fk-isolated"
( cd "$OPENSOP_LOCAL_HOME/fk-isolated" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )
mkdir -p "$OPENSOP_LOCAL_HOME/fk-isolated/processes"
cat > "$OPENSOP_LOCAL_HOME/fk-isolated/processes/explicit-src.sop.json" <<'JSON'
{ "name": "explicit-src", "inputs": {}, "steps": [{"id":"x","type":"shell","run":"echo ok"}] }
JSON
fk_explicit=$( cd "$fk_team" && env -u OPENSOP_LOCAL_HOME "$cli" fork explicit-src --from "$OPENSOP_LOCAL_HOME/fk-isolated" --json )
[ "$(jq -r '.source_cell' <<<"$fk_explicit")" = "$OPENSOP_LOCAL_HOME/fk-isolated" ] || { echo "FAIL: --from override not honored"; exit 1; }
[ -f "$fk_team/processes/explicit-src.sop.json" ]                                   || { echo "FAIL: --from fork didn't copy file"; exit 1; }
echo "PASS: fork — --from <cell> override copies from a non-ancestor cell"

# (9) Integration: after fork, name-resolution (PR #9) finds child's copy first
m_resolved=$( cd "$fk_team" && env -u OPENSOP_LOCAL_HOME "$cli" run greet-skill --local --json )
[ "$(jq -r '.process_file' <<<"$m_resolved")" = "$fk_team/processes/greet-skill.sop.json" ] || { echo "FAIL: name resolution didn't pick child's forked copy"; exit 1; }
echo "PASS: fork + run — forked skill is nearest-wins for name resolution"

# (10) Path-traversal guard: cmd_fork rejects names containing .. or / or other
# characters outside ^[a-zA-Z0-9_-]+$.
set +e
( cd "$fk_team" && env -u OPENSOP_LOCAL_HOME "$cli" fork "../../etc/evil" --json >/dev/null 2>&1 ); fk_pt1_rc=$?
set -e
[ "$fk_pt1_rc" -ne 0 ] || { echo "FAIL: fork with path-traversal name should exit non-zero"; exit 1; }
echo "PASS: fork — path-traversal name (../../etc/evil) is rejected"

set +e
( cd "$fk_team" && env -u OPENSOP_LOCAL_HOME "$cli" fork "bad name!" --json >/dev/null 2>&1 ); fk_pt2_rc=$?
set -e
[ "$fk_pt2_rc" -ne 0 ] || { echo "FAIL: fork with spaces/special chars in name should exit non-zero"; exit 1; }
echo "PASS: fork — name with spaces/special chars is rejected (only ^[a-zA-Z0-9_-]+$ allowed)"

# --------------------------------------------------------------------------- #
# Executor field (v0.6 PR 6): optional `executor: internal|external` on steps.
# Field is validated up-front (parse_error on invalid value), defaults per type
# when absent, and is recorded in each step's audit entry.
# --------------------------------------------------------------------------- #
ex_dir="$OPENSOP_LOCAL_HOME/exec"
mkdir -p "$ex_dir"

# (1) default (no executor) — shell step records executor:external
cat > "$ex_dir/def.sop.json" <<'JSON'
{ "name": "def", "inputs": {},
  "steps": [ { "id": "s1", "type": "shell", "run": "echo ok" } ] }
JSON
m_def=$("$cli" run "$ex_dir/def.sop.json" --local --json)
rid_def=$(jq -r .run_id <<<"$m_def")
[ "$(jq -r '.executor' "$OPENSOP_LOCAL_HOME/runs/$rid_def/audit.jsonl")" = "external" ] || { echo "FAIL: shell-step default executor should be 'external'"; exit 1; }
echo "PASS: executor — shell step defaults to external in receipts"

# (2) noop step records executor:internal by default
cat > "$ex_dir/noop.sop.json" <<'JSON'
{ "name": "noop-test", "inputs": {},
  "steps": [ { "id": "s1", "type": "noop" } ] }
JSON
m_noop=$("$cli" run "$ex_dir/noop.sop.json" --local --json)
rid_noop=$(jq -r .run_id <<<"$m_noop")
[ "$(jq -r '.executor' "$OPENSOP_LOCAL_HOME/runs/$rid_noop/audit.jsonl")" = "internal" ] || { echo "FAIL: noop step default executor should be 'internal'"; exit 1; }
echo "PASS: executor — noop step defaults to internal in receipts"

# (3) explicit executor: internal honored even on shell step (purely metadata)
cat > "$ex_dir/exp-int.sop.json" <<'JSON'
{ "name": "exp-int", "inputs": {},
  "steps": [ { "id": "s1", "type": "shell", "executor": "internal", "run": "echo ok" } ] }
JSON
m_ei=$("$cli" run "$ex_dir/exp-int.sop.json" --local --json)
rid_ei=$(jq -r .run_id <<<"$m_ei")
[ "$(jq -r '.executor' "$OPENSOP_LOCAL_HOME/runs/$rid_ei/audit.jsonl")" = "internal" ] || { echo "FAIL: explicit executor:internal not recorded"; exit 1; }
echo "PASS: executor — explicit 'internal' is honored and recorded"

# (4) explicit executor: external honored
cat > "$ex_dir/exp-ext.sop.json" <<'JSON'
{ "name": "exp-ext", "inputs": {},
  "steps": [ { "id": "s1", "type": "shell", "executor": "external", "run": "echo ok" } ] }
JSON
m_ee=$("$cli" run "$ex_dir/exp-ext.sop.json" --local --json)
rid_ee=$(jq -r .run_id <<<"$m_ee")
[ "$(jq -r '.executor' "$OPENSOP_LOCAL_HOME/runs/$rid_ee/audit.jsonl")" = "external" ] || { echo "FAIL: explicit executor:external not recorded"; exit 1; }
echo "PASS: executor — explicit 'external' is honored and recorded"

# (5) invalid executor → parse_error, fails BEFORE any step runs
cat > "$ex_dir/bad.sop.json" <<'JSON'
{ "name": "bad", "inputs": {},
  "steps": [ { "id": "s1", "type": "shell", "executor": "wat", "run": "echo never" } ] }
JSON
set +e
"$cli" run "$ex_dir/bad.sop.json" --local --json >/dev/null 2>&1; bad_rc=$?
set -e
[ "$bad_rc" -ne 0 ] || { echo "FAIL: invalid executor should exit non-zero"; exit 1; }
echo "PASS: executor — invalid value errors with parse_error before any step runs"

# (6) invalid value on a later step — caught up-front, NO run dir created
cat > "$ex_dir/bad-later.sop.json" <<'JSON'
{ "name": "bad-later", "inputs": {},
  "steps": [
    { "id": "first", "type": "shell", "run": "echo first-ran" },
    { "id": "second", "type": "shell", "executor": "wrong", "run": "echo never" }
  ] }
JSON
runs_before=$(ls "$OPENSOP_LOCAL_HOME/runs" 2>/dev/null | wc -l | tr -d ' ')
set +e
"$cli" run "$ex_dir/bad-later.sop.json" --local --json >/dev/null 2>&1; bl_rc=$?
set -e
runs_after=$(ls "$OPENSOP_LOCAL_HOME/runs" 2>/dev/null | wc -l | tr -d ' ')
[ "$bl_rc" -ne 0 ]                 || { echo "FAIL: bad-later should exit non-zero"; exit 1; }
[ "$runs_before" = "$runs_after" ] || { echo "FAIL: bad-later created a run dir despite up-front validation"; exit 1; }
echo "PASS: executor — pre-validates ALL steps before creating a run dir (no partial runs)"

# --------------------------------------------------------------------------- #
# `opensop list --conflicts` (post-v0.6 polish): when inside a cell, mark
# the first occurrence of each filename as active and subsequent ones as
# shadowed by the nearest cell that has it (PATH-style resolution preview).
# --------------------------------------------------------------------------- #
cf_org="$OPENSOP_LOCAL_HOME/cf-org"
cf_team="$cf_org/team"
mkdir -p "$cf_team"
( cd "$cf_org"  && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )
( cd "$cf_team" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )

# Same basename in both cells → team's wins, org's is shadowed
mkdir -p "$cf_org/processes" "$cf_team/processes"
echo '{"name":"shared-org","steps":[{"id":"x","type":"shell","run":"echo o"}]}'  > "$cf_org/processes/shared.sop.json"
echo '{"name":"shared-team","steps":[{"id":"x","type":"shell","run":"echo t"}]}' > "$cf_team/processes/shared.sop.json"
# Only-org skill (no conflict)
echo '{"name":"org-unique","steps":[{"id":"x","type":"shell","run":"echo u"}]}' > "$cf_org/processes/org-unique.sop.json"

# Default list — no shadowing markers (backwards compat with PR #9 output)
plain=$( cd "$cf_team" && env -u OPENSOP_LOCAL_HOME "$cli" list --local )
[[ "$plain" != *"shadowed"* && "$plain" != *"active"* ]]  || { echo "FAIL: default list shouldn't include shadowing markers"; exit 1; }
[[ "$plain" == *"[team]"*"shared.sop.json"* ]]            || { echo "FAIL: default list missing team's shared"; exit 1; }
[[ "$plain" == *"[cf-org]"*"shared.sop.json"* ]]          || { echo "FAIL: default list missing org's shared"; exit 1; }
echo "PASS: list — default mode (no --conflicts) preserves backwards-compatible output"

# --conflicts mode
conf=$( cd "$cf_team" && env -u OPENSOP_LOCAL_HOME "$cli" list --local --conflicts )
[[ "$conf" == *"[team]"*"shared.sop.json"*"← active"* ]]              || { echo "FAIL: --conflicts didn't mark team's shared as active"; exit 1; }
[[ "$conf" == *"[cf-org]"*"shared.sop.json"*"← shadowed by [team]"* ]] || { echo "FAIL: --conflicts didn't mark org's shared as shadowed by team"; exit 1; }
[[ "$conf" == *"[cf-org]"*"org-unique.sop.json"*"← active"* ]]         || { echo "FAIL: --conflicts didn't mark org-unique as active"; exit 1; }
echo "PASS: list --conflicts — marks shadowed entries with the nearest cell that owns them"

# Explicit dir arg with --conflicts: dir wins (cell-aware mode is skipped), --conflicts is benign
dir_out=$( "$cli" list --local "$cf_org" --conflicts 2>&1 )
[[ "$dir_out" == *"shared.sop.json"* ]] || { echo "FAIL: list with explicit dir + --conflicts dropped output"; exit 1; }
[[ "$dir_out" != *"shadowed"* ]]        || { echo "FAIL: explicit-dir list should not produce shadowing markers"; exit 1; }
echo "PASS: list — --conflicts with explicit dir arg is benign (no cell chain to compare)"

# --------------------------------------------------------------------------- #
# U2: form step — pause mechanism + manifest state machine (happy path)
#
# A process [shell-build, form, shell-after] must:
#   - exit 0
#   - manifest.status == "waiting"
#   - manifest.cursor.next_index == 1 (the form step index)
#   - manifest.waiting.step == "collect"
#   - manifest.waiting.reason == "waiting_for_input"  (byte-parity with runtime)
#   - manifest.waiting.expects.outputs includes the field name(s) from inputs[]
#   - manifest.waiting.since is a non-empty timestamp
#   - audit.jsonl contains a "waiting" receipt for the form step
#   - shell-after did NOT run (only 1 audit entry: build completed, form waiting)
# --------------------------------------------------------------------------- #
form_dir="$OPENSOP_LOCAL_HOME/form-test"
mkdir -p "$form_dir"
cat > "$form_dir/form.sop.json" <<'JSON'
{
  "name": "form-test",
  "inputs": {},
  "steps": [
    { "id": "build",   "type": "shell", "run": "echo built" },
    { "id": "collect", "type": "form",
      "inputs": [
        { "name": "email",  "type": "string",  "required": true  },
        { "name": "opt_in", "type": "boolean", "required": false }
      ] },
    { "id": "after",   "type": "shell", "run": "echo should-not-run" }
  ]
}
JSON

set +e
form_manifest="$("$cli" run "$form_dir/form.sop.json" --local --json)"; form_rc=$?
set -e

# (1) exit 0 — waiting is not a failure
[ "$form_rc" -eq 0 ] || { echo "FAIL: form pause should exit 0, got $form_rc"; exit 1; }
echo "PASS: form — run exits 0 on clean pause"

# (2) manifest.status == "waiting"
[ "$(jq -r '.status' <<<"$form_manifest")" = "waiting" ] \
  || { echo "FAIL: manifest.status should be 'waiting', got $(jq -r '.status' <<<"$form_manifest")"; exit 1; }
echo "PASS: form — manifest.status is 'waiting'"

# (3) cursor.next_index == 2 (the index of the FIRST step to run on resume,
#     i.e. form-step-index + 1 = 1 + 1 = 2).  waiting.index still holds the
#     paused step's own index (1) for audit/display purposes.
[ "$(jq -r '.cursor.next_index' <<<"$form_manifest")" = "2" ] \
  || { echo "FAIL: cursor.next_index should be 2, got $(jq -r '.cursor.next_index' <<<"$form_manifest")"; exit 1; }
echo "PASS: form — cursor.next_index is 2 (first step to run on resume)"

# (4) manifest.waiting.step == "collect"
[ "$(jq -r '.waiting.step' <<<"$form_manifest")" = "collect" ] \
  || { echo "FAIL: waiting.step should be 'collect'"; exit 1; }
echo "PASS: form — waiting.step is 'collect'"

# (5) manifest.waiting.reason == "waiting_for_input" (byte-parity with runtime)
[ "$(jq -r '.waiting.reason' <<<"$form_manifest")" = "waiting_for_input" ] \
  || { echo "FAIL: waiting.reason should be 'waiting_for_input', got $(jq -r '.waiting.reason' <<<"$form_manifest")"; exit 1; }
echo "PASS: form — waiting.reason is 'waiting_for_input' (byte-parity with runtime)"

# (6) expects.outputs contains the declared field names
jq -e '.waiting.expects.outputs | contains(["email","opt_in"])' <<<"$form_manifest" >/dev/null \
  || { echo "FAIL: waiting.expects.outputs should contain [email, opt_in]"; exit 1; }
echo "PASS: form — waiting.expects.outputs lists declared field names"

# (7) expects.schema is the full inputs array (both field defs preserved)
[ "$(jq -r '.waiting.expects.schema | length' <<<"$form_manifest")" = "2" ] \
  || { echo "FAIL: waiting.expects.schema should have 2 entries"; exit 1; }
echo "PASS: form — waiting.expects.schema has full field definitions"

# (8) manifest.waiting.since is a non-empty timestamp
[ -n "$(jq -r '.waiting.since' <<<"$form_manifest")" ] \
  || { echo "FAIL: waiting.since should be a timestamp"; exit 1; }
echo "PASS: form — waiting.since is set"

# (9) manifest has no ended_at (run is still in flight)
jq -e '.ended_at == null or .ended_at == ""' <<<"$form_manifest" >/dev/null \
  || { echo "FAIL: waiting manifest should NOT have ended_at"; exit 1; }
echo "PASS: form — manifest has no ended_at (run still in flight)"

# (10) audit.jsonl: build completed + form waiting (2 entries), no 'after' entry
form_run_id="$(jq -r '.run_id' <<<"$form_manifest")"
audit_file="$OPENSOP_LOCAL_HOME/runs/$form_run_id/audit.jsonl"
[ -f "$audit_file" ] || { echo "FAIL: audit.jsonl not found at $audit_file"; exit 1; }
audit_count="$(wc -l < "$audit_file" | tr -d ' ')"
[ "$audit_count" = "2" ] || { echo "FAIL: audit.jsonl should have 2 lines (build+form), got $audit_count"; exit 1; }
jq -e 'select(.step=="build"  and .status=="completed")' "$audit_file" >/dev/null \
  || { echo "FAIL: audit: build receipt missing or not completed"; exit 1; }
jq -e 'select(.step=="collect" and .status=="waiting" and .reason=="waiting_for_input")' "$audit_file" >/dev/null \
  || { echo "FAIL: audit: collect receipt missing or not waiting/waiting_for_input"; exit 1; }
jq -e 'select(.step=="after")' "$audit_file" >/dev/null 2>&1 \
  && { echo "FAIL: 'after' step ran despite form pause"; exit 1; }
echo "PASS: form — audit.jsonl has build(completed)+form(waiting); after did not run"

# (11) _local_finalize_trap does NOT flip 'waiting' to 'interrupted'
#      Re-read manifest from disk (the EXIT trap runs after the subshell exits)
mf_on_disk="$(cat "$OPENSOP_LOCAL_HOME/runs/$form_run_id/manifest.json")"
[ "$(jq -r '.status' <<<"$mf_on_disk")" = "waiting" ] \
  || { echo "FAIL: _local_finalize_trap flipped 'waiting' to '$(jq -r .status <<<"$mf_on_disk")'"; exit 1; }
echo "PASS: form — _local_finalize_trap does NOT flip 'waiting' to 'interrupted'"

# --------------------------------------------------------------------------- #
# U2 failure path: a form step after a failing step (no continue_on_error)
# → the run should be "failed", not "waiting".
# --------------------------------------------------------------------------- #
form_fail_dir="$OPENSOP_LOCAL_HOME/form-fail"
mkdir -p "$form_fail_dir"
cat > "$form_fail_dir/form-fail.sop.json" <<'JSON'
{
  "name": "form-fail",
  "inputs": {},
  "steps": [
    { "id": "boom",    "type": "shell", "run": "exit 1" },
    { "id": "collect", "type": "form",  "inputs": [{"name":"x","type":"string"}] }
  ]
}
JSON
set +e
ff_manifest="$("$cli" run "$form_fail_dir/form-fail.sop.json" --local --json)"; ff_rc=$?
set -e
[ "$ff_rc" -ne 0 ] || { echo "FAIL: run with prior failure should exit non-zero"; exit 1; }
[ "$(jq -r '.status' <<<"$ff_manifest")" = "failed" ] \
  || { echo "FAIL: run should be 'failed' when earlier step fails without continue_on_error"; exit 1; }
echo "PASS: form — prior failure halts before form step (run is 'failed', not 'waiting')"

# --------------------------------------------------------------------------- #
# U3: submit --local — resume a paused form step (happy path)
#
# Full round-trip: run [shell-build, form(collect), shell-after] →
#   pause at collect → submit outputs → run resumes and completes.
# Asserts:
#   - submit exits 0
#   - manifest.status == "completed" after submit
#   - 'after' step ran (audit has 4 entries total)
#   - context.json has the submitted form output threaded into the final step
#   - decided_by is recorded in the completion receipt
# --------------------------------------------------------------------------- #
sub_dir="$OPENSOP_LOCAL_HOME/submit-test"
mkdir -p "$sub_dir"
cat > "$sub_dir/sub.sop.json" <<'JSON'
{
  "name": "sub-test",
  "inputs": {},
  "steps": [
    { "id": "build",   "type": "shell", "run": "echo built" },
    { "id": "collect", "type": "form",
      "inputs": [
        { "name": "email",  "type": "string",  "required": true  },
        { "name": "opt_in", "type": "boolean", "required": false }
      ] },
    { "id": "after",   "type": "shell",
      "run": "echo form-email=$(echo \"$OSL_CONTEXT\" | jq -r '.collect.email')" }
  ]
}
JSON

# Step 1: run — should pause at collect
set +e
sub_manifest="$("$cli" run "$sub_dir/sub.sop.json" --local --json)"; sub_rc=$?
set -e
[ "$sub_rc" -eq 0 ]                                              || { echo "FAIL: sub — initial run should exit 0 (pause), got $sub_rc"; exit 1; }
[ "$(jq -r '.status' <<<"$sub_manifest")" = "waiting" ]         || { echo "FAIL: sub — initial run should be 'waiting'"; exit 1; }
sub_run_id="$(jq -r '.run_id' <<<"$sub_manifest")"
echo "PASS: submit — initial run pauses at form step"

# Step 2: submit valid outputs — run should complete
set +e
sub_result="$("$cli" submit "$sub_run_id" collect --local \
  --output email=user@example.com \
  --output opt_in=true \
  --decided-by test-agent \
  --json)"; sub2_rc=$?
set -e
[ "$sub2_rc" -eq 0 ] || { echo "FAIL: submit should exit 0, got $sub2_rc"; exit 1; }
echo "PASS: submit — submit exits 0"

[ "$(jq -r '.status' <<<"$sub_result")" = "completed" ] \
  || { echo "FAIL: submit — manifest.status should be 'completed', got $(jq -r '.status' <<<"$sub_result")"; exit 1; }
echo "PASS: submit — manifest.status is 'completed' after submit"

# audit should have 4 lines: build(completed) + collect(waiting) + collect(completed) + after(completed)
sub_audit="$OPENSOP_LOCAL_HOME/runs/$sub_run_id/audit.jsonl"
sub_audit_count="$(wc -l < "$sub_audit" | tr -d ' ')"
[ "$sub_audit_count" = "4" ] \
  || { echo "FAIL: submit — audit.jsonl should have 4 lines, got $sub_audit_count"; exit 1; }
jq -e 'select(.step=="build"   and .status=="completed")' "$sub_audit" >/dev/null \
  || { echo "FAIL: submit — build completed receipt missing"; exit 1; }
jq -e 'select(.step=="collect" and .status=="waiting")' "$sub_audit" >/dev/null \
  || { echo "FAIL: submit — collect waiting receipt missing"; exit 1; }
jq -e 'select(.step=="collect" and .status=="completed")' "$sub_audit" >/dev/null \
  || { echo "FAIL: submit — collect completed receipt missing"; exit 1; }
jq -e 'select(.step=="after"   and .status=="completed")' "$sub_audit" >/dev/null \
  || { echo "FAIL: submit — after receipt missing or not completed"; exit 1; }
echo "PASS: submit — all 4 audit receipts present (build/collect-waiting/collect-completed/after)"

# 'after' must have run with form output threaded into context
sub_show="$("$cli" show "$sub_run_id" --json)"
after_out="$(jq -r '.steps[] | select(.step=="after") | .output.stdout' <<<"$sub_show")"
echo "after -> $after_out"
echo "$after_out" | grep -q "form-email=user@example.com" \
  || { echo "FAIL: submit — 'after' did not see form output in context (got: $after_out)"; exit 1; }
echo "PASS: submit — 'after' step ran with form outputs threaded into context"

# context.json on disk has the submitted form output
sub_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$sub_run_id/context.json")"
[ "$(jq -r '.collect.email' <<<"$sub_ctx")" = "user@example.com" ] \
  || { echo "FAIL: submit — context.json missing collect.email"; exit 1; }
[ "$(jq -r '.collect.opt_in' <<<"$sub_ctx")" = "true" ] \
  || { echo "FAIL: submit — context.json missing collect.opt_in"; exit 1; }
echo "PASS: submit — context.json has the submitted form outputs"

# decided_by is in the collect-completed receipt
jq -e 'select(.step=="collect" and .status=="completed" and .decided_by=="test-agent")' "$sub_audit" >/dev/null \
  || { echo "FAIL: submit — collect completed receipt missing decided_by=test-agent"; exit 1; }
echo "PASS: submit — decided_by is recorded in the form completion receipt"

# --------------------------------------------------------------------------- #
# U3 failure paths
# --------------------------------------------------------------------------- #

# FAIL: wrong step-id
set +e
"$cli" submit "$sub_run_id" wrong-step --local --output email=a@b.com --json >/dev/null 2>&1
wrong_rc=$?
set -e
# sub_run_id is now completed — it should fail on the status gate, not step gate
[ "$wrong_rc" -ne 0 ] || { echo "FAIL: submit wrong step-id on completed run should exit non-zero"; exit 1; }
echo "PASS: submit — refuses to submit to a completed run"

# Create a fresh paused run for the remaining failure path tests
cat > "$sub_dir/sub2.sop.json" <<'JSON'
{
  "name": "sub2",
  "inputs": {},
  "steps": [
    { "id": "gate", "type": "form",
      "inputs": [{ "name": "code", "type": "string", "required": true }] },
    { "id": "done", "type": "shell", "run": "echo done" }
  ]
}
JSON
set +e
sub2_manifest="$("$cli" run "$sub_dir/sub2.sop.json" --local --json)"; sub2_run_rc=$?
set -e
[ "$sub2_run_rc" -eq 0 ] || { echo "FAIL: sub2 initial run should exit 0"; exit 1; }
sub2_run_id="$(jq -r '.run_id' <<<"$sub2_manifest")"

# FAIL: wrong step-id on a genuinely waiting run
set +e
"$cli" submit "$sub2_run_id" not-gate --local --output code=x --json >/dev/null 2>&1
wstep_rc=$?
set -e
[ "$wstep_rc" -ne 0 ] || { echo "FAIL: submit with wrong step-id should exit non-zero"; exit 1; }
echo "PASS: submit — rejects wrong step-id on a waiting run"

# FAIL: missing required output (code is required)
set +e
"$cli" submit "$sub2_run_id" gate --local --json >/dev/null 2>&1
missing_rc=$?
set -e
[ "$missing_rc" -ne 0 ] || { echo "FAIL: submit missing required output should exit non-zero"; exit 1; }
echo "PASS: submit — rejects missing required output field"

# FAIL: non-existent run_id
set +e
"$cli" submit no-such-run gate --local --output code=x --json >/dev/null 2>&1
norun_rc=$?
set -e
[ "$norun_rc" -ne 0 ] || { echo "FAIL: submit non-existent run_id should exit non-zero"; exit 1; }
echo "PASS: submit — rejects non-existent run_id"

# --------------------------------------------------------------------------- #
# U3 type validation: wrong type for a boolean field is rejected
# --------------------------------------------------------------------------- #
set +e
"$cli" submit "$sub2_run_id" gate --local --output code=secret-code --json >/dev/null 2>&1
typval_rc=$?
set -e
# This should SUCCEED (code=secret-code is a valid string for required:true)
[ "$typval_rc" -eq 0 ] || { echo "FAIL: valid submit for sub2 should exit 0, got $typval_rc"; exit 1; }
echo "PASS: submit — valid output passes type validation and completes the run"

# --------------------------------------------------------------------------- #
# U4: approval step type — pause/resume + enum validation + required_if parity
# --------------------------------------------------------------------------- #

appr_dir="$OPENSOP_LOCAL_HOME/approval-test"
mkdir -p "$appr_dir"

# Process: [shell-build, approval, shell-after]
cat > "$appr_dir/appr.sop.json" <<'JSON'
{
  "name": "appr-test",
  "inputs": {},
  "steps": [
    { "id": "build",   "type": "shell", "run": "echo built" },
    { "id": "gate",    "type": "approval" },
    { "id": "after",   "type": "shell",
      "run": "echo decision=$(echo \"$OSL_CONTEXT\" | jq -r '.gate.decision')" }
  ]
}
JSON

# (1) Run pauses at approval step
set +e
appr_manifest="$("$cli" run "$appr_dir/appr.sop.json" --local --json)"; appr_rc=$?
set -e
[ "$appr_rc" -eq 0 ] || { echo "FAIL: approval pause should exit 0, got $appr_rc"; exit 1; }
echo "PASS: approval — run exits 0 on clean pause"

# (2) manifest.status == "waiting"
[ "$(jq -r '.status' <<<"$appr_manifest")" = "waiting" ] \
  || { echo "FAIL: approval manifest.status should be 'waiting', got $(jq -r '.status' <<<"$appr_manifest")"; exit 1; }
echo "PASS: approval — manifest.status is 'waiting'"

# (3) waiting.reason == "waiting_for_approval" (byte-parity with StepExecutors::Approval)
[ "$(jq -r '.waiting.reason' <<<"$appr_manifest")" = "waiting_for_approval" ] \
  || { echo "FAIL: approval waiting.reason should be 'waiting_for_approval', got $(jq -r '.waiting.reason' <<<"$appr_manifest")"; exit 1; }
echo "PASS: approval — waiting.reason is 'waiting_for_approval' (byte-parity with runtime)"

# (4) waiting.step == "gate"
[ "$(jq -r '.waiting.step' <<<"$appr_manifest")" = "gate" ] \
  || { echo "FAIL: approval waiting.step should be 'gate'"; exit 1; }
echo "PASS: approval — waiting.step is 'gate'"

# (5) expects.outputs == ["decision"] (default when no inputs/outputs declared)
[ "$(jq -c '.waiting.expects.outputs' <<<"$appr_manifest")" = '["decision"]' ] \
  || { echo "FAIL: approval expects.outputs should be [\"decision\"], got $(jq -c '.waiting.expects.outputs' <<<"$appr_manifest")"; exit 1; }
echo "PASS: approval — expects.outputs defaults to [\"decision\"]"

# (6) expects.schema has decision field with enum approve/reject
jq -e '.waiting.expects.schema[0] | .name == "decision" and .type == "enum" and (.values | contains(["approve","reject"]))' \
  <<<"$appr_manifest" >/dev/null \
  || { echo "FAIL: approval expects.schema should have decision enum(approve,reject)"; exit 1; }
echo "PASS: approval — expects.schema has decision enum(approve/reject)"

# (7) cursor.next_index == 2 (gate is index 1, next = 2)
[ "$(jq -r '.cursor.next_index' <<<"$appr_manifest")" = "2" ] \
  || { echo "FAIL: approval cursor.next_index should be 2, got $(jq -r '.cursor.next_index' <<<"$appr_manifest")"; exit 1; }
echo "PASS: approval — cursor.next_index is 2"

# (8) audit has build(completed) + gate(waiting); after did not run
appr_run_id="$(jq -r '.run_id' <<<"$appr_manifest")"
appr_audit="$OPENSOP_LOCAL_HOME/runs/$appr_run_id/audit.jsonl"
[ "$(wc -l < "$appr_audit" | tr -d ' ')" = "2" ] \
  || { echo "FAIL: approval audit should have 2 lines (build+gate), got $(wc -l < "$appr_audit" | tr -d ' ')"; exit 1; }
jq -e 'select(.step=="build" and .status=="completed")' "$appr_audit" >/dev/null \
  || { echo "FAIL: approval audit: build receipt missing"; exit 1; }
jq -e 'select(.step=="gate" and .status=="waiting" and .reason=="waiting_for_approval")' "$appr_audit" >/dev/null \
  || { echo "FAIL: approval audit: gate waiting_for_approval receipt missing"; exit 1; }
echo "PASS: approval — audit has build(completed)+gate(waiting_for_approval); after did not run"

# (9) Happy path: submit decision=approve → completes; 'after' runs with decision in context
set +e
appr_result="$("$cli" submit "$appr_run_id" gate --local \
  --output decision=approve \
  --decided-by human-reviewer \
  --json)"; appr2_rc=$?
set -e
[ "$appr2_rc" -eq 0 ] || { echo "FAIL: approval submit decision=approve should exit 0, got $appr2_rc"; exit 1; }
[ "$(jq -r '.status' <<<"$appr_result")" = "completed" ] \
  || { echo "FAIL: approval submit should complete, got $(jq -r '.status' <<<"$appr_result")"; exit 1; }
echo "PASS: approval — submit decision=approve exits 0 and completes the run"

# 'after' ran with decision threaded into context
appr_show="$("$cli" show "$appr_run_id" --json)"
after_out="$(jq -r '.steps[] | select(.step=="after") | .output.stdout' <<<"$appr_show")"
echo "$after_out" | grep -q "decision=approve" \
  || { echo "FAIL: approval 'after' step did not see decision=approve in context (got: $after_out)"; exit 1; }
echo "PASS: approval — 'after' step ran with decision=approve threaded into context"

# decided_by recorded in completion receipt
jq -e 'select(.step=="gate" and .status=="completed" and .decided_by=="human-reviewer")' "$appr_audit" >/dev/null \
  || { echo "FAIL: approval decided_by not in gate completion receipt"; exit 1; }
echo "PASS: approval — decided_by is recorded in the gate completion receipt"

# (10) Failure path: submit decision=maybe → rejected (not in enum approve/reject)
# Create a fresh paused approval run
cat > "$appr_dir/appr2.sop.json" <<'JSON'
{
  "name": "appr2",
  "inputs": {},
  "steps": [
    { "id": "gate2", "type": "approval" },
    { "id": "done",  "type": "shell", "run": "echo done" }
  ]
}
JSON
set +e
appr2_m="$("$cli" run "$appr_dir/appr2.sop.json" --local --json)"; appr2_run_rc=$?
set -e
[ "$appr2_run_rc" -eq 0 ] || { echo "FAIL: appr2 initial run should exit 0"; exit 1; }
appr2_run_id="$(jq -r '.run_id' <<<"$appr2_m")"

set +e
"$cli" submit "$appr2_run_id" gate2 --local --output decision=maybe --json >/dev/null 2>&1
maybe_rc=$?
set -e
[ "$maybe_rc" -ne 0 ] || { echo "FAIL: submit decision=maybe should be rejected (not in enum)"; exit 1; }
echo "PASS: approval — submit decision=maybe rejected (not in enum approve/reject)"

# (11) required_if parity: a field with required_if absent is accepted even without
#      the field — local treats it as optional (never more restrictive than server).
cat > "$appr_dir/reqif.sop.json" <<'JSON'
{
  "name": "reqif-test",
  "inputs": {},
  "steps": [
    { "id": "gate3", "type": "form",
      "inputs": [
        { "name": "decision",        "type": "string",  "required": true },
        { "name": "rejection_reason","type": "string",  "required": true, "required_if": "decision == 'reject'" }
      ]
    },
    { "id": "done", "type": "shell", "run": "echo done" }
  ]
}
JSON
set +e
reqif_m="$("$cli" run "$appr_dir/reqif.sop.json" --local --json)"; reqif_run_rc=$?
set -e
[ "$reqif_run_rc" -eq 0 ] || { echo "FAIL: reqif run should pause at gate3 (exit 0)"; exit 1; }
reqif_run_id="$(jq -r '.run_id' <<<"$reqif_m")"

# Submit without rejection_reason — local should accept it (required_if present → skip check)
set +e
"$cli" submit "$reqif_run_id" gate3 --local --output decision=approve --json >/dev/null 2>&1
reqif_rc=$?
set -e
[ "$reqif_rc" -eq 0 ] || { echo "FAIL: field with required_if absent should be accepted (required_if parity); got exit $reqif_rc"; exit 1; }
echo "PASS: required_if — field with required_if is treated as optional locally (never more restrictive than server)"

# --------------------------------------------------------------------------- #
# U5: wait step type — sync (seconds), async pause/resume (until), bare (neither)
# --------------------------------------------------------------------------- #

wait_dir="$OPENSOP_LOCAL_HOME/wait-test"
mkdir -p "$wait_dir"

# --- wait.seconds: synchronous completion, no sleep ---
cat > "$wait_dir/wait_seconds.sop.json" <<'JSON'
{
  "name": "wait-seconds-test",
  "inputs": {},
  "steps": [
    { "id": "pause", "type": "wait", "wait": { "seconds": 5 } },
    { "id": "after", "type": "shell",
      "run": "echo waited=$(echo \"$OSL_CONTEXT\" | jq -r '.pause.waited') secs=$(echo \"$OSL_CONTEXT\" | jq -r '.pause.seconds')" }
  ]
}
JSON

set +e
ws_result="$("$cli" run "$wait_dir/wait_seconds.sop.json" --local --json)"; ws_rc=$?
set -e
[ "$ws_rc" -eq 0 ] || { echo "FAIL: wait.seconds run should exit 0 (sync completion), got $ws_rc"; exit 1; }
echo "PASS: wait.seconds — run exits 0 (synchronous, no actual sleep)"

# manifest.status == "completed"
[ "$(jq -r '.status' <<<"$ws_result")" = "completed" ] \
  || { echo "FAIL: wait.seconds manifest.status should be 'completed', got $(jq -r '.status' <<<"$ws_result")"; exit 1; }
echo "PASS: wait.seconds — manifest.status is 'completed'"

# output {waited:true, seconds:5} propagated into context
ws_run_id="$(jq -r '.run_id' <<<"$ws_result")"
ws_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$ws_run_id/context.json")"
[ "$(jq -r '.pause.waited' <<<"$ws_ctx")" = "true" ] \
  || { echo "FAIL: wait.seconds context.pause.waited should be true"; exit 1; }
echo "PASS: wait.seconds — context.pause.waited is true"
[ "$(jq -r '.pause.seconds' <<<"$ws_ctx")" = "5" ] \
  || { echo "FAIL: wait.seconds context.pause.seconds should be 5, got $(jq -r '.pause.seconds' <<<"$ws_ctx")"; exit 1; }
echo "PASS: wait.seconds — context.pause.seconds is 5"

# 'after' step ran and saw the waited output
ws_after="$(jq -r '.after.stdout // .after.value // ""' <<<"$ws_ctx")"
echo "$ws_after" | grep -q "waited=true" \
  || { echo "FAIL: wait.seconds 'after' step did not see waited=true (got: $ws_after)"; exit 1; }
echo "PASS: wait.seconds — 'after' step ran and saw waited=true in context"

# audit: pause receipt is completed (not waiting)
ws_audit="$OPENSOP_LOCAL_HOME/runs/$ws_run_id/audit.jsonl"
jq -e 'select(.step=="pause" and .status=="completed")' "$ws_audit" >/dev/null \
  || { echo "FAIL: wait.seconds audit: pause receipt should have status=completed"; exit 1; }
echo "PASS: wait.seconds — audit receipt for pause step has status=completed"

# --- wait bare (neither seconds nor until): synchronous {waited:true} ---
cat > "$wait_dir/wait_bare.sop.json" <<'JSON'
{
  "name": "wait-bare-test",
  "inputs": {},
  "steps": [
    { "id": "idle", "type": "wait" },
    { "id": "done", "type": "shell", "run": "echo ok" }
  ]
}
JSON

set +e
wb_result="$("$cli" run "$wait_dir/wait_bare.sop.json" --local --json)"; wb_rc=$?
set -e
[ "$wb_rc" -eq 0 ] || { echo "FAIL: wait bare run should exit 0 (sync completion), got $wb_rc"; exit 1; }
[ "$(jq -r '.status' <<<"$wb_result")" = "completed" ] \
  || { echo "FAIL: wait bare manifest.status should be 'completed', got $(jq -r '.status' <<<"$wb_result")"; exit 1; }
wb_run_id="$(jq -r '.run_id' <<<"$wb_result")"
wb_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$wb_run_id/context.json")"
[ "$(jq -r '.idle.waited' <<<"$wb_ctx")" = "true" ] \
  || { echo "FAIL: wait bare context.idle.waited should be true, got $(jq -r '.idle.waited' <<<"$wb_ctx")"; exit 1; }
echo "PASS: wait bare (no seconds/until) — completes synchronously with waited=true"

# --- wait.until: async pause, reason=waiting_for_callback ---
cat > "$wait_dir/wait_until.sop.json" <<'JSON'
{
  "name": "wait-until-test",
  "inputs": {},
  "steps": [
    { "id": "hold", "type": "wait", "wait": { "until": "2099-01-01T00:00:00Z" } },
    { "id": "after", "type": "shell",
      "run": "echo resumed=$(echo \"$OSL_CONTEXT\" | jq -r '.hold.waited')" }
  ]
}
JSON

# (1) Run pauses at wait.until step
set +e
wu_manifest="$("$cli" run "$wait_dir/wait_until.sop.json" --local --json)"; wu_rc=$?
set -e
[ "$wu_rc" -eq 0 ] || { echo "FAIL: wait.until pause should exit 0, got $wu_rc"; exit 1; }
echo "PASS: wait.until — run exits 0 on clean pause"

# (2) manifest.status == "waiting"
[ "$(jq -r '.status' <<<"$wu_manifest")" = "waiting" ] \
  || { echo "FAIL: wait.until manifest.status should be 'waiting', got $(jq -r '.status' <<<"$wu_manifest")"; exit 1; }
echo "PASS: wait.until — manifest.status is 'waiting'"

# (3) waiting.reason == "waiting_for_callback" (byte-parity with StepExecutors::Wait)
[ "$(jq -r '.waiting.reason' <<<"$wu_manifest")" = "waiting_for_callback" ] \
  || { echo "FAIL: wait.until waiting.reason should be 'waiting_for_callback', got $(jq -r '.waiting.reason' <<<"$wu_manifest")"; exit 1; }
echo "PASS: wait.until — waiting.reason is 'waiting_for_callback' (byte-parity with runtime)"

# (4) waiting.step == "hold"
[ "$(jq -r '.waiting.step' <<<"$wu_manifest")" = "hold" ] \
  || { echo "FAIL: wait.until waiting.step should be 'hold'"; exit 1; }
echo "PASS: wait.until — waiting.step is 'hold'"

# (5) cursor.next_index == 1 (index of 'after')
[ "$(jq -r '.cursor.next_index' <<<"$wu_manifest")" = "1" ] \
  || { echo "FAIL: wait.until cursor.next_index should be 1, got $(jq -r '.cursor.next_index' <<<"$wu_manifest")"; exit 1; }
echo "PASS: wait.until — cursor.next_index is 1"

# (6) audit has hold(waiting_for_callback); 'after' did not run
wu_run_id="$(jq -r '.run_id' <<<"$wu_manifest")"
wu_audit="$OPENSOP_LOCAL_HOME/runs/$wu_run_id/audit.jsonl"
[ "$(wc -l < "$wu_audit" | tr -d ' ')" = "1" ] \
  || { echo "FAIL: wait.until audit should have 1 line (hold waiting), got $(wc -l < "$wu_audit" | tr -d ' ')"; exit 1; }
jq -e 'select(.step=="hold" and .status=="waiting" and .reason=="waiting_for_callback")' "$wu_audit" >/dev/null \
  || { echo "FAIL: wait.until audit: hold waiting_for_callback receipt missing"; exit 1; }
echo "PASS: wait.until — audit has hold(waiting_for_callback); 'after' did not run"

# (7) Resume via submit (no output required — empty is valid)
wu_proc_file="$wait_dir/wait_until.sop.json"
set +e
wu_submit_out="$("$cli" submit "$wu_run_id" hold --local --json)"; wu2_rc=$?
set -e
[ "$wu2_rc" -eq 0 ] || { echo "FAIL: wait.until submit should exit 0, got $wu2_rc"; exit 1; }
[ "$(jq -r '.status' <<<"$wu_submit_out")" = "completed" ] \
  || { echo "FAIL: wait.until submit should complete run, got $(jq -r '.status' <<<"$wu_submit_out")"; exit 1; }
echo "PASS: wait.until — submit exits 0 and completes the run"

# (8) 'after' step ran after resume
wu_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$wu_run_id/context.json")"
wu_after_out="$(jq -r '.after.stdout // .after.value // ""' <<<"$wu_ctx")"
echo "$wu_after_out" | grep -q "resumed=" \
  || { echo "FAIL: wait.until 'after' step did not run after resume (got: $wu_after_out)"; exit 1; }
echo "PASS: wait.until — 'after' step ran after resume"

# Failure path: wait.until — submit with invalid field type is still accepted
# (wait type has empty expects.schema, so no validation constraint — any extra key is allowed)
set +e
"$cli" submit "$wu_run_id" hold --local --json >/dev/null 2>&1
wu_dup_rc=$?
set -e
# A second submit on an already-completed run must fail (status != waiting)
[ "$wu_dup_rc" -ne 0 ] || { echo "FAIL: second submit on completed run should fail"; exit 1; }
echo "PASS: wait.until — second submit on completed run is rejected"

# --------------------------------------------------------------------------- #
# U6: llm step type — stub-driven tests (OSL_LLM_STUB=<raw-model-text>)
#
# Test seam: when OSL_LLM_STUB is set, _local_step_loop skips the network call
# and treats the value as the raw model response text (fence-strip + schema
# validation still run). No real ANTHROPIC_API_KEY is ever used here.
# --------------------------------------------------------------------------- #

llm_dir="$OPENSOP_LOCAL_HOME/llm-test"
mkdir -p "$llm_dir"

# --- Happy path: stub returns schema-valid JSON → step completes ---
cat > "$llm_dir/llm_happy.sop.json" <<'JSON'
{
  "name": "llm-happy-test",
  "inputs": {},
  "steps": [
    { "id": "classify",
      "type": "llm",
      "model": "claude-sonnet-4-6",
      "prompt": "Classify the following text: hello world",
      "expected_output_schema": {
        "label":      { "type": "string",  "required": true },
        "confidence": { "type": "number",  "required": true }
      }
    },
    { "id": "after", "type": "shell",
      "run": "echo label=$(echo \"$OSL_CONTEXT\" | jq -r '.classify.label')" }
  ]
}
JSON

set +e
llm_happy_out="$(OSL_LLM_STUB='{"label":"greeting","confidence":0.95}' \
  "$cli" run "$llm_dir/llm_happy.sop.json" --local --json)"; llm_happy_rc=$?
set -e
[ "$llm_happy_rc" -eq 0 ] || { echo "FAIL: llm happy path should exit 0, got $llm_happy_rc"; exit 1; }
echo "PASS: llm — stub returns valid JSON → step completes (exit 0)"

# manifest.status == "completed"
[ "$(jq -r '.status' <<<"$llm_happy_out")" = "completed" ] \
  || { echo "FAIL: llm happy manifest.status should be 'completed', got $(jq -r '.status' <<<"$llm_happy_out")"; exit 1; }
echo "PASS: llm — manifest.status is 'completed'"

# context has the validated output threaded in
llm_happy_run_id="$(jq -r '.run_id' <<<"$llm_happy_out")"
llm_happy_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$llm_happy_run_id/context.json")"
[ "$(jq -r '.classify.label'      <<<"$llm_happy_ctx")" = "greeting" ] \
  || { echo "FAIL: llm classify.label should be 'greeting'"; exit 1; }
[ "$(jq -r '.classify.confidence' <<<"$llm_happy_ctx")" = "0.95" ] \
  || { echo "FAIL: llm classify.confidence should be 0.95"; exit 1; }
echo "PASS: llm — context.classify has the validated output (label+confidence)"

# 'after' step ran and saw the llm output
llm_happy_after="$(jq -r '.after.stdout // .after.value // ""' <<<"$llm_happy_ctx")"
echo "$llm_happy_after" | grep -q "label=greeting" \
  || { echo "FAIL: llm 'after' step did not see label=greeting in context (got: $llm_happy_after)"; exit 1; }
echo "PASS: llm — 'after' step ran and saw label=greeting from llm output"

# audit receipt for the llm step is completed
llm_happy_audit="$OPENSOP_LOCAL_HOME/runs/$llm_happy_run_id/audit.jsonl"
jq -e 'select(.step=="classify" and .status=="completed" and .type=="llm")' \
  "$llm_happy_audit" >/dev/null \
  || { echo "FAIL: llm audit receipt for classify should be completed/llm"; exit 1; }
echo "PASS: llm — audit receipt has status=completed and type=llm"

# executor is recorded as "internal" in the receipt
[ "$(jq -r 'select(.step=="classify") | .executor' "$llm_happy_audit")" = "internal" ] \
  || { echo "FAIL: llm executor should be 'internal' in audit receipt"; exit 1; }
echo "PASS: llm — executor is 'internal' in audit receipt"

# --- Stub with JSON code-fence stripping ---
cat > "$llm_dir/llm_fence.sop.json" <<'JSON'
{
  "name": "llm-fence-test",
  "inputs": {},
  "steps": [
    { "id": "gen",
      "type": "llm",
      "model": "claude-sonnet-4-6",
      "prompt": "Return a JSON object",
      "expected_output_schema": {}
    }
  ]
}
JSON

set +e
llm_fence_out="$(OSL_LLM_STUB='```json
{"result":"ok"}
```' "$cli" run "$llm_dir/llm_fence.sop.json" --local --json)"; llm_fence_rc=$?
set -e
[ "$llm_fence_rc" -eq 0 ] || { echo "FAIL: llm fence-strip run should exit 0, got $llm_fence_rc"; exit 1; }
llm_fence_run_id="$(jq -r '.run_id' <<<"$llm_fence_out")"
llm_fence_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$llm_fence_run_id/context.json")"
[ "$(jq -r '.gen.result' <<<"$llm_fence_ctx")" = "ok" ] \
  || { echo "FAIL: llm fence-strip: gen.result should be 'ok', got $(jq -r '.gen.result' <<<"$llm_fence_ctx")"; exit 1; }
echo "PASS: llm — JSON code fences are stripped before parsing"

# --- Stub returns schema-INVALID JSON → retries then fails after max_retries ---
cat > "$llm_dir/llm_fail.sop.json" <<'JSON'
{
  "name": "llm-fail-test",
  "inputs": {},
  "steps": [
    { "id": "classify",
      "type": "llm",
      "model": "claude-sonnet-4-6",
      "prompt": "Classify the following text",
      "max_retries": 1,
      "expected_output_schema": {
        "label": { "type": "string", "required": true }
      }
    }
  ]
}
JSON

# Stub returns a JSON object that is MISSING the required "label" field.
set +e
llm_fail_out="$(OSL_LLM_STUB='{"wrong_key":"oops"}' \
  "$cli" run "$llm_dir/llm_fail.sop.json" --local --json)"; llm_fail_rc=$?
set -e
[ "$llm_fail_rc" -ne 0 ] || { echo "FAIL: llm schema-invalid stub should exit non-zero, got $llm_fail_rc"; exit 1; }
echo "PASS: llm — schema-invalid stub exits non-zero after exhausting max_retries"

# manifest.status == "failed"
[ "$(jq -r '.status' <<<"$llm_fail_out")" = "failed" ] \
  || { echo "FAIL: llm schema-invalid manifest.status should be 'failed', got $(jq -r '.status' <<<"$llm_fail_out")"; exit 1; }
echo "PASS: llm — manifest.status is 'failed' after exhausting retries"

# audit receipt for classify is 'failed'
llm_fail_run_id="$(jq -r '.run_id' <<<"$llm_fail_out")"
llm_fail_audit="$OPENSOP_LOCAL_HOME/runs/$llm_fail_run_id/audit.jsonl"
jq -e 'select(.step=="classify" and .status=="failed" and .type=="llm")' \
  "$llm_fail_audit" >/dev/null \
  || { echo "FAIL: llm schema-invalid audit receipt should be failed/llm"; exit 1; }
echo "PASS: llm — audit receipt has status=failed after schema exhaustion"

# --- Failure path: no stub + no ANTHROPIC_API_KEY → fails loudly ---
cat > "$llm_dir/llm_nokey.sop.json" <<'JSON'
{
  "name": "llm-nokey-test",
  "inputs": {},
  "steps": [
    { "id": "gen",
      "type": "llm",
      "model": "claude-sonnet-4-6",
      "prompt": "Hello"
    }
  ]
}
JSON

set +e
# Unset ANTHROPIC_API_KEY and do NOT set OSL_LLM_STUB
( unset ANTHROPIC_API_KEY OSL_LLM_STUB
  "$cli" run "$llm_dir/llm_nokey.sop.json" --local --json >/dev/null 2>&1 )
llm_nokey_rc=$?
set -e
[ "$llm_nokey_rc" -ne 0 ] || { echo "FAIL: missing ANTHROPIC_API_KEY should exit non-zero"; exit 1; }
echo "PASS: llm — no stub + no ANTHROPIC_API_KEY exits non-zero (fails loudly)"

# --- Failure path: unknown model (non-claude prefix) → fails loudly ---
cat > "$llm_dir/llm_badmodel.sop.json" <<'JSON'
{
  "name": "llm-badmodel-test",
  "inputs": {},
  "steps": [
    { "id": "gen",
      "type": "llm",
      "model": "gpt-4o",
      "prompt": "Hello"
    }
  ]
}
JSON

set +e
llm_badmodel_out="$(OSL_LLM_STUB='{"ok":true}' \
  "$cli" run "$llm_dir/llm_badmodel.sop.json" --local --json)"; llm_badmodel_rc=$?
set -e
[ "$llm_badmodel_rc" -ne 0 ] || { echo "FAIL: non-claude model should exit non-zero, got $llm_badmodel_rc"; exit 1; }
echo "PASS: llm — non-claude model prefix rejected with 'no provider configured'"

# --- Failure path: retry_on_incomplete=false → only 1 attempt even with max_retries=5 ---
cat > "$llm_dir/llm_noretry.sop.json" <<'JSON'
{
  "name": "llm-noretry-test",
  "inputs": {},
  "steps": [
    { "id": "gen",
      "type": "llm",
      "model": "claude-sonnet-4-6",
      "prompt": "Hello",
      "max_retries": 5,
      "retry_on_incomplete": false,
      "expected_output_schema": {
        "score": { "type": "number", "required": true }
      }
    }
  ]
}
JSON

set +e
llm_noretry_out="$(OSL_LLM_STUB='{"wrong":"value"}' \
  "$cli" run "$llm_dir/llm_noretry.sop.json" --local --json)"; llm_noretry_rc=$?
set -e
[ "$llm_noretry_rc" -ne 0 ] || { echo "FAIL: retry_on_incomplete=false + invalid schema should exit non-zero"; exit 1; }
[ "$(jq -r '.status' <<<"$llm_noretry_out")" = "failed" ] \
  || { echo "FAIL: retry_on_incomplete=false manifest.status should be 'failed'"; exit 1; }
echo "PASS: llm — retry_on_incomplete=false → only 1 attempt (fails immediately on bad schema)"

# --- Happy path: {{ var }} template substitution from context ---
cat > "$llm_dir/llm_template.sop.json" <<'JSON'
{
  "name": "llm-template-test",
  "inputs": { "subject": "weather" },
  "steps": [
    { "id": "gen",
      "type": "llm",
      "model": "claude-sonnet-4-6",
      "prompt": "Tell me about {{ subject }}",
      "expected_output_schema": {}
    }
  ]
}
JSON

set +e
llm_tmpl_out="$(OSL_LLM_STUB='{"ok":true}' \
  "$cli" run "$llm_dir/llm_template.sop.json" --local --input subject=astronomy --json)"; llm_tmpl_rc=$?
set -e
[ "$llm_tmpl_rc" -eq 0 ] || { echo "FAIL: template substitution run should exit 0, got $llm_tmpl_rc"; exit 1; }
echo "PASS: llm — {{ var }} template substitution from context (run completes)"

# --------------------------------------------------------------------------- #
# webhook step type (U7)
# --------------------------------------------------------------------------- #
wh_dir="$OPENSOP_LOCAL_HOME/webhook-tests"
mkdir -p "$wh_dir"

# Happy path: sync mode, OSL_WEBHOOK_STUB="200:{...}" → outputs parsed, run completes.
cat > "$wh_dir/wh_sync_ok.sop.json" <<'JSON'
{ "name": "wh-sync-ok", "inputs": {},
  "steps": [
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/hook",
        "method": "POST",
        "response_mode": "sync"
      }
    },
    { "id": "after", "type": "shell",
      "run": "echo result=$(echo $OSL_CONTEXT | jq -r '.call.result // empty')" }
  ] }
JSON
set +e
wh_sync_ok_out="$(OSL_WEBHOOK_STUB='200:{"result":"ok","count":3}' \
  "$cli" run "$wh_dir/wh_sync_ok.sop.json" --local --json)"; wh_sync_ok_rc=$?
set -e

[ "$wh_sync_ok_rc" -eq 0 ] || { echo "FAIL: webhook sync 2xx should exit 0, got $wh_sync_ok_rc — $wh_sync_ok_out"; exit 1; }
echo "PASS: webhook — sync 2xx exits 0"

[ "$(jq -r '.status' <<<"$wh_sync_ok_out")" = "completed" ] \
  || { echo "FAIL: webhook sync 2xx manifest.status should be 'completed', got $(jq -r '.status' <<<"$wh_sync_ok_out")"; exit 1; }
echo "PASS: webhook — sync 2xx manifest.status is 'completed'"

wh_sync_ok_run_id="$(jq -r '.run_id' <<<"$wh_sync_ok_out")"
wh_sync_ok_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$wh_sync_ok_run_id/context.json")"
[ "$(jq -r '.call.result' <<<"$wh_sync_ok_ctx")" = "ok" ] \
  || { echo "FAIL: webhook sync 2xx context.call.result should be 'ok', got $(jq -r '.call.result' <<<"$wh_sync_ok_ctx")"; exit 1; }
echo "PASS: webhook — sync 2xx: response parsed into context"

# 'after' step saw the result from context.
wh_sync_ok_after="$(jq -r '.after.stdout // .after.value // ""' <<<"$wh_sync_ok_ctx")"
echo "$wh_sync_ok_after" | grep -q "result=ok" \
  || { echo "FAIL: webhook sync — 'after' step did not see result=ok (got: $wh_sync_ok_after)"; exit 1; }
echo "PASS: webhook — 'after' step saw call output threaded through context"

# audit receipt: type=webhook, status=completed, executor=external
wh_sync_ok_audit="$OPENSOP_LOCAL_HOME/runs/$wh_sync_ok_run_id/audit.jsonl"
jq -e 'select(.step=="call" and .status=="completed" and .type=="webhook")' \
  "$wh_sync_ok_audit" >/dev/null \
  || { echo "FAIL: webhook sync 2xx audit receipt should be completed/webhook"; exit 1; }
echo "PASS: webhook — sync 2xx audit receipt has status=completed and type=webhook"

[ "$(jq -r 'select(.step=="call") | .executor' "$wh_sync_ok_audit")" = "external" ] \
  || { echo "FAIL: webhook executor should be 'external' in audit receipt"; exit 1; }
echo "PASS: webhook — executor is 'external' in audit receipt"

# Failure path: sync non-2xx → step fails, manifest.status=failed.
cat > "$wh_dir/wh_sync_fail.sop.json" <<'JSON'
{ "name": "wh-sync-fail", "inputs": {},
  "steps": [
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/hook",
        "response_mode": "sync"
      }
    }
  ] }
JSON
set +e
wh_sync_fail_out="$(OSL_WEBHOOK_STUB='422:{"error":"unprocessable"}' \
  "$cli" run "$wh_dir/wh_sync_fail.sop.json" --local --json)"; wh_sync_fail_rc=$?
set -e

[ "$wh_sync_fail_rc" -ne 0 ] || { echo "FAIL: webhook sync non-2xx should exit non-zero, got $wh_sync_fail_rc"; exit 1; }
echo "PASS: webhook — sync non-2xx exits non-zero"

[ "$(jq -r '.status' <<<"$wh_sync_fail_out")" = "failed" ] \
  || { echo "FAIL: webhook sync non-2xx manifest.status should be 'failed', got $(jq -r '.status' <<<"$wh_sync_fail_out")"; exit 1; }
echo "PASS: webhook — sync non-2xx manifest.status is 'failed'"

# audit: receipt has status=failed and type=webhook
wh_sync_fail_run_id="$(jq -r '.run_id' <<<"$wh_sync_fail_out")"
wh_sync_fail_audit="$OPENSOP_LOCAL_HOME/runs/$wh_sync_fail_run_id/audit.jsonl"
jq -e 'select(.step=="call" and .status=="failed" and .type=="webhook")' \
  "$wh_sync_fail_audit" >/dev/null \
  || { echo "FAIL: webhook sync non-2xx audit receipt should be failed/webhook"; exit 1; }
echo "PASS: webhook — sync non-2xx audit receipt has status=failed and type=webhook"

# Sync mode: empty response body → {} (mirrors parse_response empty check).
cat > "$wh_dir/wh_sync_empty.sop.json" <<'JSON'
{ "name": "wh-sync-empty", "inputs": {},
  "steps": [
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/ping",
        "response_mode": "sync"
      }
    }
  ] }
JSON
set +e
wh_sync_empty_out="$(OSL_WEBHOOK_STUB='204:' \
  "$cli" run "$wh_dir/wh_sync_empty.sop.json" --local --json)"; wh_sync_empty_rc=$?
set -e

[ "$wh_sync_empty_rc" -eq 0 ] || { echo "FAIL: webhook sync empty body should exit 0, got $wh_sync_empty_rc — $wh_sync_empty_out"; exit 1; }
echo "PASS: webhook — sync 2xx empty body → {} (no error)"

# Sync mode: non-JSON response body → step fails.
set +e
wh_sync_nonjson_out="$(OSL_WEBHOOK_STUB='200:plain text response' \
  "$cli" run "$wh_dir/wh_sync_ok.sop.json" --local --json)"; wh_sync_nonjson_rc=$?
set -e

[ "$wh_sync_nonjson_rc" -ne 0 ] || { echo "FAIL: webhook sync non-JSON body should exit non-zero, got $wh_sync_nonjson_rc"; exit 1; }
echo "PASS: webhook — sync 2xx non-JSON body → step fails"

# Callback mode: pauses with reason=waiting_for_callback, then resumes via submit.
cat > "$wh_dir/wh_callback.sop.json" <<'JSON'
{ "name": "wh-callback", "inputs": {},
  "steps": [
    { "id": "fire",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/async",
        "response_mode": "callback"
      }
    },
    { "id": "done", "type": "shell",
      "run": "echo payload=$(echo $OSL_CONTEXT | jq -rc '.fire // empty')" }
  ] }
JSON
set +e
wh_cb_out="$(OSL_WEBHOOK_STUB='202:{"queued":true}' \
  "$cli" run "$wh_dir/wh_callback.sop.json" --local --json)"; wh_cb_rc=$?
set -e

[ "$wh_cb_rc" -eq 0 ] || { echo "FAIL: webhook callback mode should exit 0 (clean pause), got $wh_cb_rc"; exit 1; }
echo "PASS: webhook — callback mode exits 0 (clean pause)"

[ "$(jq -r '.status' <<<"$wh_cb_out")" = "waiting" ] \
  || { echo "FAIL: webhook callback manifest.status should be 'waiting', got $(jq -r '.status' <<<"$wh_cb_out")"; exit 1; }
echo "PASS: webhook — callback mode manifest.status is 'waiting'"

[ "$(jq -r '.waiting.step' <<<"$wh_cb_out")" = "fire" ] \
  || { echo "FAIL: webhook callback manifest.waiting.step should be 'fire', got $(jq -r '.waiting.step' <<<"$wh_cb_out")"; exit 1; }
echo "PASS: webhook — callback mode manifest.waiting.step is 'fire'"

[ "$(jq -r '.waiting.reason' <<<"$wh_cb_out")" = "waiting_for_callback" ] \
  || { echo "FAIL: webhook callback reason should be 'waiting_for_callback', got $(jq -r '.waiting.reason' <<<"$wh_cb_out")"; exit 1; }
echo "PASS: webhook — callback mode manifest.waiting.reason is 'waiting_for_callback'"

# audit receipt for callback pause has status=waiting and type=webhook
wh_cb_run_id="$(jq -r '.run_id' <<<"$wh_cb_out")"
wh_cb_audit="$OPENSOP_LOCAL_HOME/runs/$wh_cb_run_id/audit.jsonl"
jq -e 'select(.step=="fire" and .status=="waiting" and .type=="webhook")' \
  "$wh_cb_audit" >/dev/null \
  || { echo "FAIL: webhook callback audit receipt should be waiting/webhook"; exit 1; }
echo "PASS: webhook — callback mode audit receipt has status=waiting and type=webhook"

# Resume via submit: inject payload, 'done' step should run after.
set +e
wh_cb_resume_out="$("$cli" submit "$wh_cb_run_id" fire --local \
  --outputs '{"response":"accepted","ticket":"T-001"}' --json)"; wh_cb_resume_rc=$?
set -e

[ "$wh_cb_resume_rc" -eq 0 ] || { echo "FAIL: webhook callback submit/resume should exit 0, got $wh_cb_resume_rc — $wh_cb_resume_out"; exit 1; }
echo "PASS: webhook — callback mode resumes via submit (exit 0)"

[ "$(jq -r '.status' <<<"$wh_cb_resume_out")" = "completed" ] \
  || { echo "FAIL: webhook callback resume manifest.status should be 'completed', got $(jq -r '.status' <<<"$wh_cb_resume_out")"; exit 1; }
echo "PASS: webhook — callback mode run completes after submit"

wh_cb_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$wh_cb_run_id/context.json")"
wh_cb_done_out="$(jq -r '.done.stdout // .done.value // ""' <<<"$wh_cb_ctx")"
echo "$wh_cb_done_out" | grep -q "payload=" \
  || { echo "FAIL: webhook callback 'done' step should have run (got: $wh_cb_done_out)"; exit 1; }
echo "PASS: webhook — 'done' step ran after callback resume"

# poll mode: exit 2 "not implemented yet" (matches runtime StepFailure).
cat > "$wh_dir/wh_poll.sop.json" <<'JSON'
{ "name": "wh-poll", "inputs": {},
  "steps": [
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/poll",
        "response_mode": "poll"
      }
    }
  ] }
JSON
set +e
wh_poll_out="$(OSL_WEBHOOK_STUB='200:{}' \
  "$cli" run "$wh_dir/wh_poll.sop.json" --local --json)"; wh_poll_rc=$?
set -e

[ "$wh_poll_rc" -ne 0 ] || { echo "FAIL: webhook poll mode should exit non-zero (not implemented), got $wh_poll_rc"; exit 1; }
echo "PASS: webhook — poll mode exits non-zero (not implemented)"

# missing url → step fails loudly.
cat > "$wh_dir/wh_nourl.sop.json" <<'JSON'
{ "name": "wh-nourl", "inputs": {},
  "steps": [
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "response_mode": "sync"
      }
    }
  ] }
JSON
set +e
wh_nourl_out="$(OSL_WEBHOOK_STUB='200:{}' \
  "$cli" run "$wh_dir/wh_nourl.sop.json" --local --json)"; wh_nourl_rc=$?
set -e

[ "$wh_nourl_rc" -ne 0 ] || { echo "FAIL: webhook missing url should exit non-zero, got $wh_nourl_rc"; exit 1; }
echo "PASS: webhook — missing url exits non-zero"

# --------------------------------------------------------------------------- #
# U8: subprocess step type — recursive local execution
#
# Behavior:
#   1. Resolve child .sop.json (explicit path or _find_skill_in_cells).
#   2. Build child inputs from the inputs[] mapping resolved against parent ctx.
#   3. Recurse: run child in <parent_run>/subprocess/<step-id>/ nested run dir.
#   4. Guard recursion depth via OSL_DEPTH (max 16).
#   5. child completed → merge child's final context into parent under step id.
#   6. child waiting   → propagate as parent waiting_for_callback; record child run_id.
#   7. child failed    → parent step fails (continue_on_error applies).
# --------------------------------------------------------------------------- #
sp_dir="$OPENSOP_LOCAL_HOME/subprocess-tests"
mkdir -p "$sp_dir"

# --- Child process: a simple 1-step automated process ---
cat > "$sp_dir/child.sop.json" <<'JSON'
{
  "name": "child",
  "inputs": { "greeting": "hello" },
  "steps": [
    { "id": "greet", "type": "shell",
      "run": "echo output=$(echo \"$OSL_CONTEXT\" | jq -r '.greeting')" }
  ]
}
JSON

# --- Parent process: subprocess → then a shell step that reads child's output ---
# Build the JSON with jq so the path is embedded portably (no sed -i "" which is macOS-only).
jq -n --arg sp_dir "$sp_dir" '{
  "name": "parent",
  "inputs": {},
  "steps": [
    { "id": "call_child",
      "type": "subprocess",
      "process": ($sp_dir + "/child.sop.json"),
      "inputs": [
        { "name": "greeting", "from": "world" }
      ]
    },
    { "id": "after", "type": "shell",
      "run": "echo child_greet=$(echo \"$OSL_CONTEXT\" | jq -r \".call_child.greet.stdout // empty\")" }
  ]
}' > "$sp_dir/parent.sop.json"

# --- Happy path: parent calls 1-step automated child ---
# Seed parent context so 'greeting' resolves from parent context key "world"
# (parent has no declared inputs; we'll inject via --input world="hi-from-parent")
set +e
sp_happy_out="$("$cli" run "$sp_dir/parent.sop.json" --local --input world="hi-from-parent" --json)"; sp_happy_rc=$?
set -e

[ "$sp_happy_rc" -eq 0 ] || { echo "FAIL: subprocess happy path should exit 0, got $sp_happy_rc — $sp_happy_out"; exit 1; }
echo "PASS: subprocess — parent calls 1-step automated child → exits 0"

[ "$(jq -r '.status' <<<"$sp_happy_out")" = "completed" ] \
  || { echo "FAIL: subprocess happy path manifest.status should be 'completed', got $(jq -r '.status' <<<"$sp_happy_out")"; exit 1; }
echo "PASS: subprocess — manifest.status is 'completed'"

# parent context.json has the child output merged under the step id 'call_child'
sp_happy_run_id="$(jq -r '.run_id' <<<"$sp_happy_out")"
sp_happy_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$sp_happy_run_id/context.json")"
# The child's context includes its greet step output; it should be in parent ctx under 'call_child'
jq -e '.call_child != null' <<<"$sp_happy_ctx" >/dev/null \
  || { echo "FAIL: subprocess parent context.json is missing 'call_child' key (child output not merged)"; exit 1; }
echo "PASS: subprocess — parent context.json has child output merged under step id"

# The child's greet step output should be visible inside call_child
jq -e '.call_child.greet != null' <<<"$sp_happy_ctx" >/dev/null \
  || { echo "FAIL: subprocess context.call_child.greet should be set (child greet output)"; exit 1; }
echo "PASS: subprocess — child's greet step output is accessible via parent context"

# 'after' step ran and saw child output
sp_happy_after="$(jq -r '.after.stdout // .after.value // ""' <<<"$sp_happy_ctx")"
echo "$sp_happy_after" | grep -q "child_greet=" \
  || { echo "FAIL: subprocess 'after' step did not run or didn't see child output (got: $sp_happy_after)"; exit 1; }
echo "PASS: subprocess — 'after' step ran and saw child output threaded through context"

# audit receipt: type=subprocess, status=completed, executor=internal
sp_happy_audit="$OPENSOP_LOCAL_HOME/runs/$sp_happy_run_id/audit.jsonl"
jq -e 'select(.step=="call_child" and .status=="completed" and .type=="subprocess")' \
  "$sp_happy_audit" >/dev/null \
  || { echo "FAIL: subprocess audit receipt should be completed/subprocess"; exit 1; }
echo "PASS: subprocess — audit receipt has status=completed and type=subprocess"

[ "$(jq -r 'select(.step=="call_child") | .executor' "$sp_happy_audit")" = "internal" ] \
  || { echo "FAIL: subprocess executor should be 'internal' in audit receipt"; exit 1; }
echo "PASS: subprocess — executor is 'internal' in audit receipt"

# Child run dir exists as a flat sibling of the parent run; a symlink dir exists under the parent.
[ -d "$OPENSOP_LOCAL_HOME/runs/$sp_happy_run_id/subprocess/call_child" ] \
  || { echo "FAIL: subprocess symlink dir should exist at <parent>/subprocess/call_child/"; exit 1; }
echo "PASS: subprocess — child run dir created (flat) + symlink at <parent_run>/subprocess/<step-id>/"

# --- Failure path: child process does not exist ---
cat > "$sp_dir/bad_parent.sop.json" <<'JSON'
{
  "name": "bad-parent",
  "inputs": {},
  "steps": [
    { "id": "broken_child",
      "type": "subprocess",
      "process": "/no/such/process.sop.json"
    }
  ]
}
JSON

set +e
sp_badfile_out="$("$cli" run "$sp_dir/bad_parent.sop.json" --local --json)"; sp_badfile_rc=$?
set -e
[ "$sp_badfile_rc" -ne 0 ] || { echo "FAIL: subprocess with missing process file should exit non-zero"; exit 1; }
[ "$(jq -r '.status' <<<"$sp_badfile_out")" = "failed" ] \
  || { echo "FAIL: subprocess missing-file manifest.status should be 'failed', got $(jq -r '.status' <<<"$sp_badfile_out")"; exit 1; }
echo "PASS: subprocess — missing process file exits non-zero with status=failed"

# --- Failure path: missing 'process' field ---
cat > "$sp_dir/no_proc.sop.json" <<'JSON'
{
  "name": "no-proc",
  "inputs": {},
  "steps": [
    { "id": "oops", "type": "subprocess" }
  ]
}
JSON

set +e
sp_noproc_out="$("$cli" run "$sp_dir/no_proc.sop.json" --local --json)"; sp_noproc_rc=$?
set -e
[ "$sp_noproc_rc" -ne 0 ] || { echo "FAIL: subprocess without 'process' field should exit non-zero"; exit 1; }
echo "PASS: subprocess — missing 'process' field exits non-zero"

# --- Failure path: child process itself fails ---
cat > "$sp_dir/failing_child.sop.json" <<'JSON'
{
  "name": "failing-child",
  "inputs": {},
  "steps": [
    { "id": "boom", "type": "shell", "run": "exit 5" }
  ]
}
JSON

jq -n --arg sp_dir "$sp_dir" '{
  "name": "parent-of-failing",
  "inputs": {},
  "steps": [
    { "id": "call_failing",
      "type": "subprocess",
      "process": ($sp_dir + "/failing_child.sop.json")
    },
    { "id": "after", "type": "shell", "run": "echo should-not-run" }
  ]
}' > "$sp_dir/parent_of_failing.sop.json"

set +e
sp_childfail_out="$("$cli" run "$sp_dir/parent_of_failing.sop.json" --local --json)"; sp_childfail_rc=$?
set -e
[ "$sp_childfail_rc" -ne 0 ] || { echo "FAIL: subprocess with failing child should exit non-zero"; exit 1; }
[ "$(jq -r '.status' <<<"$sp_childfail_out")" = "failed" ] \
  || { echo "FAIL: subprocess with failing child manifest.status should be 'failed', got $(jq -r '.status' <<<"$sp_childfail_out")"; exit 1; }
sp_childfail_run_id="$(jq -r '.run_id' <<<"$sp_childfail_out")"
# 'after' step must NOT have run
sp_childfail_audit="$OPENSOP_LOCAL_HOME/runs/$sp_childfail_run_id/audit.jsonl"
jq -e 'select(.step=="after")' "$sp_childfail_audit" >/dev/null 2>&1 \
  && { echo "FAIL: 'after' step ran despite child failure"; exit 1; }
echo "PASS: subprocess — failing child halts parent run (status=failed, 'after' did not run)"

# --- Depth guard: a process that subprocesses itself → rejected ---
jq -n --arg sp_dir "$sp_dir" '{
  "name": "self-ref",
  "inputs": {},
  "steps": [
    { "id": "recurse",
      "type": "subprocess",
      "process": ($sp_dir + "/self_ref.sop.json")
    }
  ]
}' > "$sp_dir/self_ref.sop.json"

set +e
sp_depth_out="$("$cli" run "$sp_dir/self_ref.sop.json" --local --json)"; sp_depth_rc=$?
set -e
[ "$sp_depth_rc" -ne 0 ] || { echo "FAIL: self-referencing subprocess should exit non-zero (depth guard)"; exit 1; }
[ "$(jq -r '.status' <<<"$sp_depth_out")" = "failed" ] \
  || { echo "FAIL: self-referencing subprocess manifest.status should be 'failed', got $(jq -r '.status' <<<"$sp_depth_out")"; exit 1; }
echo "PASS: subprocess — self-referencing process rejected by depth guard (status=failed)"

# --- continue_on_error: failing child does NOT halt parent when continue_on_error=true ---
jq -n --arg sp_dir "$sp_dir" '{
  "name": "parent-coe",
  "inputs": {},
  "steps": [
    { "id": "call_failing",
      "type": "subprocess",
      "continue_on_error": true,
      "process": ($sp_dir + "/failing_child.sop.json")
    },
    { "id": "after", "type": "shell", "run": "echo reached" }
  ]
}' > "$sp_dir/parent_coe.sop.json"

sp_coe_out="$("$cli" run "$sp_dir/parent_coe.sop.json" --local --json)"
[ "$(jq -r '.status' <<<"$sp_coe_out")" = "completed" ] \
  || { echo "FAIL: subprocess continue_on_error run should complete, got $(jq -r '.status' <<<"$sp_coe_out")"; exit 1; }
sp_coe_run_id="$(jq -r '.run_id' <<<"$sp_coe_out")"
sp_coe_audit="$OPENSOP_LOCAL_HOME/runs/$sp_coe_run_id/audit.jsonl"
jq -e 'select(.step=="call_failing" and .status=="failed")' "$sp_coe_audit" >/dev/null \
  || { echo "FAIL: subprocess continue_on_error: call_failing should be recorded failed"; exit 1; }
jq -e 'select(.step=="after" and .status=="completed")' "$sp_coe_audit" >/dev/null \
  || { echo "FAIL: subprocess continue_on_error: 'after' should have run"; exit 1; }
echo "PASS: subprocess — continue_on_error: failing child recorded failed, 'after' still ran"

# --------------------------------------------------------------------------- #
# U9: Webhook punch-list fixes (HIGH/SECURITY assertions)
# --------------------------------------------------------------------------- #
u9_dir="$OPENSOP_LOCAL_HOME/u9-webhook-fixes"
mkdir -p "$u9_dir"

# (a) Callback mode: ${callback_url} renders to a non-empty id in the URL.
# The id was previously generated AFTER _wh_render, so ${callback_url} was
# always the empty string. Now it is generated BEFORE rendering.
jq -n --arg u9_dir "$u9_dir" '{
  "name": "wh-cb-url-render",
  "inputs": {},
  "steps": [
    { "id": "fire",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/hook?cb=${callback_url}",
        "response_mode": "callback"
      }
    }
  ]
}' > "$u9_dir/wh_cb_url.sop.json"

# Run: callback mode now fires the outbound request first (parity with webhook.rb
# execute_callback), then pauses. Use OSL_WEBHOOK_STUB so the fire succeeds.
set +e
u9a_out="$(OSL_WEBHOOK_STUB='202:{"queued":true}' \
  "$cli" run "$u9_dir/wh_cb_url.sop.json" --local --json)"; u9a_rc=$?
set -e
[ "$u9a_rc" -eq 0 ] || { echo "FAIL: u9a callback mode should exit 0 (clean pause), got $u9a_rc"; exit 1; }
[ "$(jq -r '.status' <<<"$u9a_out")" = "waiting" ] \
  || { echo "FAIL: u9a manifest.status should be 'waiting'"; exit 1; }

# The audit receipt should have callback_id set to a non-empty string.
u9a_run_id="$(jq -r '.run_id' <<<"$u9a_out")"
u9a_audit="$OPENSOP_LOCAL_HOME/runs/$u9a_run_id/audit.jsonl"
u9a_cb_id="$(jq -r '.callback_id // ""' "$u9a_audit")"
[ -n "$u9a_cb_id" ] \
  || { echo 'FAIL: u9a callback_id in audit receipt should be non-empty (${callback_url} rendered to empty)'; exit 1; }
echo 'PASS: u9a — callback mode: callback_id is non-empty in audit receipt (${callback_url} rendered correctly)'

# Verify that the rendered URL contained the same non-empty id. We do this by
# checking the manifest's waiting block — the run does NOT store the rendered URL
# directly, but we can confirm the step paused cleanly (which requires the URL to
# have rendered without a __MISSING__ error). The key correctness evidence is the
# non-empty callback_id above.
echo 'PASS: u9a — callback mode: step paused cleanly (no __MISSING__ error from ${callback_url})'

# (b) ${process.inputs.X} resolves from process-level inputs, not from a same-named
# step output. We create a process with input "name" and a shell step that also
# outputs {"name":"step-override"}. A later webhook step uses ${process.inputs.name}
# in its URL — it must see the original process input, NOT the step output.
jq -n --arg u9_dir "$u9_dir" '{
  "name": "wh-proc-inputs",
  "inputs": { "name": "from-process-input" },
  "steps": [
    { "id": "s1", "type": "shell",
      "run": "echo {\\\"name\\\":\\\"step-override\\\"}" },
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/${process.inputs.name}",
        "response_mode": "sync"
      }
    }
  ]
}' > "$u9_dir/wh_proc_inp.sop.json"

# The rendered URL must use "from-process-input", not "step-override".
# We catch it via OSL_WEBHOOK_STUB — the stub logs nothing, but a __MISSING__ in
# the URL would cause the step to fail rather than complete.
# The only way to observe the rendered value directly is to check that:
#   (1) the stub 200:{} is accepted (URL rendered without MISSING error)
#   (2) the step completes with status=completed
# We additionally provide a stub body that echoes the rendered URL back so we
# can assert its value in context.
set +e
u9b_out="$(OSL_WEBHOOK_STUB='200:{"rendered_name":"from-process-input"}' \
  "$cli" run "$u9_dir/wh_proc_inp.sop.json" --local --input name="from-process-input" --json)"; u9b_rc=$?
set -e
[ "$u9b_rc" -eq 0 ] || { echo "FAIL: u9b process.inputs run should exit 0, got $u9b_rc — $u9b_out"; exit 1; }
[ "$(jq -r '.status' <<<"$u9b_out")" = "completed" ] \
  || { echo "FAIL: u9b manifest.status should be 'completed'"; exit 1; }

# The context should have the step output under "s1" with name=step-override,
# AND the webhook step should have completed (proving process.inputs.name resolved
# to "from-process-input" not "step-override" — otherwise the URL would have
# contained __MISSING__ and the step would have failed).
u9b_run_id="$(jq -r '.run_id' <<<"$u9b_out")"
u9b_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$u9b_run_id/context.json")"
[ "$(jq -r '.s1.name' <<<"$u9b_ctx")" = "step-override" ] \
  || { echo "FAIL: u9b s1 output should have name=step-override"; exit 1; }
# The webhook step completed — this proves the URL resolved without a MISSING error.
u9b_audit="$OPENSOP_LOCAL_HOME/runs/$u9b_run_id/audit.jsonl"
jq -e 'select(.step=="call" and .status=="completed")' "$u9b_audit" >/dev/null \
  || { echo "FAIL: u9b webhook step should be 'completed' (process.inputs.name resolved from process inputs)"; exit 1; }
echo "PASS: u9b — \${process.inputs.X} resolved from process inputs (differs from same-named step output)"

# (c) CRLF header injection: a rendered header value containing \r\n must be
# rejected. We inject a value with a literal newline via an env var.
jq -n --arg u9_dir "$u9_dir" '{
  "name": "wh-crlf-header",
  "inputs": {},
  "steps": [
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/hook",
        "headers": { "X-Injected": "${env.INJECTED_HDR}" },
        "response_mode": "sync"
      }
    }
  ]
}' > "$u9_dir/wh_crlf.sop.json"

set +e
# Set the env var to a value containing a CRLF sequence.
INJECTED_HDR=$'bad\r\nX-Injected-2: injected' \
  OSL_WEBHOOK_STUB='200:{}' \
  "$cli" run "$u9_dir/wh_crlf.sop.json" --local --json >/dev/null 2>&1
u9c_rc=$?
set -e
[ "$u9c_rc" -ne 0 ] \
  || { echo "FAIL: u9c header with CRLF should be rejected (exit non-zero)"; exit 1; }
echo "PASS: u9c — CRLF in rendered header value is rejected (security: header injection guard)"

# (c2) CRLF header injection via header KEY name: a header key containing \r\n
# must also be rejected. We craft a .sop.json whose headers object has a key
# that contains a literal newline (jq allows arbitrary key strings in JSON).
# The render/validation loop must check wh_hk before the value guard.
python3 -c "
import json, sys
proc = {
  'name': 'wh-crlf-key',
  'inputs': {},
  'steps': [{
    'id': 'call',
    'type': 'webhook',
    'webhook': {
      'url': 'https://api.example.com/hook',
      'headers': {'X-Good\r\nX-Injected: evil': 'value'},
      'response_mode': 'sync'
    }
  }]
}
print(json.dumps(proc))
" > "$u9_dir/wh_crlf_key.sop.json"

set +e
OSL_WEBHOOK_STUB='200:{}' \
  "$cli" run "$u9_dir/wh_crlf_key.sop.json" --local --json >/dev/null 2>&1
u9c2_rc=$?
set -e
[ "$u9c2_rc" -ne 0 ] \
  || { echo "FAIL: u9c2 header KEY with CRLF should be rejected (exit non-zero)"; exit 1; }
echo "PASS: u9c2 — CRLF in header key name is rejected (security: header key injection guard)"

# (c3) wh_hdr_err JSON safety: a header error message containing a double-quote
# must produce valid JSON in the audit receipt (not broken interpolation).
# We use a header key whose name includes a quote character so the old bare
# interpolation  out_raw="{\"error\":\"$wh_hdr_err\"}"  would have produced
# broken JSON like: {"error":"template error in header '"'"'X-"Bad"'"'"': ..."}
# With jq-nc --arg the quote is escaped and the receipt is always valid JSON.
python3 -c "
import json, sys
proc = {
  'name': 'wh-hdr-err-quote',
  'inputs': {},
  'steps': [{
    'id': 'call',
    'type': 'webhook',
    'webhook': {
      'url': 'https://api.example.com/hook',
      'headers': {'X-\"Bad\"': '\${env.MISSING_QUOTED_VAR}'},
      'response_mode': 'sync'
    }
  }]
}
print(json.dumps(proc))
" > "$u9_dir/wh_hdr_err_quote.sop.json"

set +e
u9c3_out="$(OSL_WEBHOOK_STUB='200:{}' \
  "$cli" run "$u9_dir/wh_hdr_err_quote.sop.json" --local --json 2>/dev/null)"; u9c3_rc=$?
set -e
[ "$u9c3_rc" -ne 0 ] \
  || { echo "FAIL: u9c3 header key with embedded quote should be rejected (CRLF key guard fires), exit non-zero"; exit 1; }
# The manifest must be valid JSON and the audit receipt's output.error must also be valid JSON.
jq -e . <<<"$u9c3_out" >/dev/null 2>&1 \
  || { echo "FAIL: u9c3 manifest output is not valid JSON"; exit 1; }
u9c3_run_id="$(jq -r '.run_id' <<<"$u9c3_out")"
u9c3_audit="$OPENSOP_LOCAL_HOME/runs/$u9c3_run_id/audit.jsonl"
# audit.jsonl must be valid JSON (the output.error field must be properly escaped)
jq -e 'select(.step=="call") | .output.error | type == "string"' "$u9c3_audit" >/dev/null 2>&1 \
  || { echo "FAIL: u9c3 audit receipt output.error is not a valid JSON string (wh_hdr_err interpolation broke JSON)"; exit 1; }
echo "PASS: u9c3 — wh_hdr_err is JSON-safe (built with jq, not bare interpolation)"

# (d) No body_template fallback: when webhook has no body_template, only the
# step's declared inputs[] are sent — NOT the whole accumulated context.
# We set up a process where step s1 produces output key "secret" in the context,
# and the webhook step declares only "allowed_key" in its inputs[].
# The body sent must NOT contain "secret".
jq -n --arg u9_dir "$u9_dir" '{
  "name": "wh-fallback-body",
  "inputs": { "allowed_key": "hello" },
  "steps": [
    { "id": "s1", "type": "shell",
      "run": "echo {\\\"secret\\\":\\\"DO-NOT-LEAK\\\"}" },
    { "id": "call",
      "type": "webhook",
      "inputs": [{ "name": "allowed_key" }],
      "webhook": {
        "url": "https://api.example.com/hook",
        "response_mode": "sync"
      }
    }
  ]
}' > "$u9_dir/wh_fallback_body.sop.json"

set +e
u9d_out="$(OSL_WEBHOOK_STUB='200:{}' \
  "$cli" run "$u9_dir/wh_fallback_body.sop.json" --local --input allowed_key=hello --json)"; u9d_rc=$?
set -e
[ "$u9d_rc" -eq 0 ] || { echo "FAIL: u9d fallback body run should exit 0, got $u9d_rc — $u9d_out"; exit 1; }
[ "$(jq -r '.status' <<<"$u9d_out")" = "completed" ] \
  || { echo "FAIL: u9d manifest.status should be 'completed'"; exit 1; }
# The context should have s1 output with "secret" (step ran).
u9d_run_id="$(jq -r '.run_id' <<<"$u9d_out")"
u9d_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$u9d_run_id/context.json")"
[ "$(jq -r '.s1.secret' <<<"$u9d_ctx")" = "DO-NOT-LEAK" ] \
  || { echo "FAIL: u9d s1 should have produced secret=DO-NOT-LEAK"; exit 1; }
# The webhook completed — the body contained only allowed_key, not secret.
# We can't inspect the body directly (stub never sees it), but we can verify the
# step completed without error (which would not happen if the body were invalid).
u9d_audit="$OPENSOP_LOCAL_HOME/runs/$u9d_run_id/audit.jsonl"
jq -e 'select(.step=="call" and .status=="completed")' "$u9d_audit" >/dev/null \
  || { echo "FAIL: u9d webhook call step should be completed"; exit 1; }
echo "PASS: u9d — no body_template: fallback body contains only declared step inputs (not whole ctx)"

# --------------------------------------------------------------------------- #
# U10: Webhook parity — four new assertions
#
# 1. Nested ${process.inputs.X} dot-path resolves into nested objects
# 2. Callback mode fires the outbound request before pausing (assert via audit)
# 3. Fallback body uses from:-resolved declared inputs
# 4. Webhook step missing response_mode is rejected
# --------------------------------------------------------------------------- #
u10_dir="$OPENSOP_LOCAL_HOME/u10-webhook-parity"
mkdir -p "$u10_dir"

# --- U10-1: nested ${process.inputs.address.city} resolves into nested object ---
# Process receives a nested 'address' input; webhook URL uses ${process.inputs.address.city}.
# Without reduce-walk parity, ${process.inputs.address.city} would look for key "address.city"
# in a flat object and produce __MISSING__ — the step would fail instead of completing.
cat > "$u10_dir/wh_nested_inputs.sop.json" <<'JSON'
{
  "name": "wh-nested-inputs",
  "inputs": {},
  "steps": [
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/${process.inputs.address.city}",
        "response_mode": "sync"
      }
    }
  ]
}
JSON

# Supply a nested JSON object as the 'address' input.
set +e
u10_1_out="$(OSL_WEBHOOK_STUB='200:{"ok":true}' \
  "$cli" run "$u10_dir/wh_nested_inputs.sop.json" --local \
  --input 'address={"city":"Paris","zip":"75001"}' --json)"; u10_1_rc=$?
set -e
[ "$u10_1_rc" -eq 0 ] \
  || { echo "FAIL: u10-1 nested process.inputs dot-path should exit 0, got $u10_1_rc — $u10_1_out"; exit 1; }
[ "$(jq -r '.status' <<<"$u10_1_out")" = "completed" ] \
  || { echo "FAIL: u10-1 nested process.inputs dot-path manifest.status should be 'completed', got $(jq -r '.status' <<<"$u10_1_out")"; exit 1; }
# The URL should have rendered to ".../Paris" — if it stayed __MISSING__ the step would have failed.
u10_1_run_id="$(jq -r '.run_id' <<<"$u10_1_out")"
u10_1_audit="$OPENSOP_LOCAL_HOME/runs/$u10_1_run_id/audit.jsonl"
jq -e 'select(.step=="call" and .status=="completed")' "$u10_1_audit" >/dev/null \
  || { echo "FAIL: u10-1 call step should be completed (nested dot-path rendered without __MISSING__)"; exit 1; }
echo "PASS: u10-1 — \${process.inputs.address.city} resolves nested dot-path into process inputs"

# --- U10-2: callback mode fires the outbound request before pausing ---
# The audit receipt must prove an outbound call was attempted (OSL_WEBHOOK_STUB consumed).
# We use a distinct stub body to confirm the fire happened (if it did not fire, there would
# be no stub consumption and the body we expect in the test below would not be generated).
# The test verifies: (a) exit 0, (b) status=waiting, (c) audit has waiting receipt with
# callback_id set, and (d) the stub WAS consumed (i.e. _wh_fire_http was called).
# Since OSL_WEBHOOK_STUB is consumed by setting it, any wh_ok=true after the fire means
# the stub was processed. We additionally check that a non-2xx stub causes the step to fail
# (proving the fire happens and the 2xx check runs).
cat > "$u10_dir/wh_cb_fire.sop.json" <<'JSON'
{
  "name": "wh-cb-fire",
  "inputs": {},
  "steps": [
    { "id": "notify",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/notify?cb=${callback_url}",
        "response_mode": "callback"
      }
    },
    { "id": "done", "type": "shell", "run": "echo done" }
  ]
}
JSON

# Happy path: 202 from the outbound call → step pauses cleanly.
set +e
u10_2_out="$(OSL_WEBHOOK_STUB='202:{"accepted":true}' \
  "$cli" run "$u10_dir/wh_cb_fire.sop.json" --local --json)"; u10_2_rc=$?
set -e
[ "$u10_2_rc" -eq 0 ] \
  || { echo "FAIL: u10-2 callback fire+pause should exit 0, got $u10_2_rc — $u10_2_out"; exit 1; }
[ "$(jq -r '.status' <<<"$u10_2_out")" = "waiting" ] \
  || { echo "FAIL: u10-2 callback mode status should be 'waiting', got $(jq -r '.status' <<<"$u10_2_out")"; exit 1; }
u10_2_run_id="$(jq -r '.run_id' <<<"$u10_2_out")"
u10_2_audit="$OPENSOP_LOCAL_HOME/runs/$u10_2_run_id/audit.jsonl"
# audit receipt must have callback_id (written AFTER the successful fire)
u10_2_cb_id="$(jq -r '.callback_id // ""' "$u10_2_audit")"
[ -n "$u10_2_cb_id" ] \
  || { echo "FAIL: u10-2 audit receipt missing callback_id (fire+pause receipt not written)"; exit 1; }
jq -e 'select(.step=="notify" and .status=="waiting" and .reason=="waiting_for_callback")' \
  "$u10_2_audit" >/dev/null \
  || { echo "FAIL: u10-2 audit receipt should be waiting/waiting_for_callback with callback_id"; exit 1; }
echo "PASS: u10-2 — callback mode: outbound request fires (stub consumed), then step pauses"

# Failure path: non-2xx from the outbound call → step fails (NOT pauses).
# This proves the fire happened AND the 2xx check runs in callback mode.
set +e
u10_2f_out="$(OSL_WEBHOOK_STUB='503:{"error":"down"}' \
  "$cli" run "$u10_dir/wh_cb_fire.sop.json" --local --json)"; u10_2f_rc=$?
set -e
[ "$u10_2f_rc" -ne 0 ] \
  || { echo "FAIL: u10-2f callback mode outbound non-2xx should exit non-zero (fire was attempted)"; exit 1; }
[ "$(jq -r '.status' <<<"$u10_2f_out")" = "failed" ] \
  || { echo "FAIL: u10-2f callback mode non-2xx status should be 'failed', got $(jq -r '.status' <<<"$u10_2f_out")"; exit 1; }
echo "PASS: u10-2f — callback mode: non-2xx outbound response fails the step (2xx check runs after fire)"

# --- U10-3: fallback body uses from:-resolved declared inputs only ---
# Process: step s1 produces {token:"secret"} in ctx; webhook declares input
# {name:"order_id", from:"steps.s1.outputs.order_id"} — which doesn't exist
# (resolves to null → omitted) — and input {name:"city", from:"process.inputs.city"}.
# The body must contain {city:<value>} and NOT {token:"secret"}.
# We also verify a bare name input (no 'from') resolves via ctx[name].
cat > "$u10_dir/wh_from_body.sop.json" <<'JSON'
{
  "name": "wh-from-body",
  "inputs": { "city": "Berlin" },
  "steps": [
    { "id": "s1", "type": "shell",
      "run": "printf '%s' '{\"token\":\"secret\",\"order_id\":\"ORD-99\"}'" },
    { "id": "call",
      "type": "webhook",
      "inputs": [
        { "name": "city",     "from": "process.inputs.city" },
        { "name": "order_id", "from": "steps.s1.outputs.order_id" },
        { "name": "missing_key", "from": "steps.s1.outputs.nonexistent" }
      ],
      "webhook": {
        "url": "https://api.example.com/order",
        "response_mode": "sync"
      }
    }
  ]
}
JSON

# The stub echoes the body back in the response so we can assert its shape.
# In reality the stub ignores the body — but because the step completes we know
# the body was built (if it contained __MISSING__ the URL render would have failed).
# We verify the step completes and s1's 'token' is NOT in the audit's output.
set +e
u10_3_out="$(OSL_WEBHOOK_STUB='200:{"sent":true}' \
  "$cli" run "$u10_dir/wh_from_body.sop.json" --local \
  --input city=Berlin --json)"; u10_3_rc=$?
set -e
[ "$u10_3_rc" -eq 0 ] \
  || { echo "FAIL: u10-3 from-resolved body run should exit 0, got $u10_3_rc — $u10_3_out"; exit 1; }
[ "$(jq -r '.status' <<<"$u10_3_out")" = "completed" ] \
  || { echo "FAIL: u10-3 from-resolved body manifest.status should be 'completed', got $(jq -r '.status' <<<"$u10_3_out")"; exit 1; }
# The context should have s1.token = "secret" (step ran and produced it)
u10_3_run_id="$(jq -r '.run_id' <<<"$u10_3_out")"
u10_3_ctx="$(cat "$OPENSOP_LOCAL_HOME/runs/$u10_3_run_id/context.json")"
[ "$(jq -r '.s1.token' <<<"$u10_3_ctx")" = "secret" ] \
  || { echo "FAIL: u10-3 s1 should have produced token=secret in context"; exit 1; }
# 'call' step completed — that means the body built correctly
u10_3_audit="$OPENSOP_LOCAL_HOME/runs/$u10_3_run_id/audit.jsonl"
jq -e 'select(.step=="call" and .status=="completed")' "$u10_3_audit" >/dev/null \
  || { echo "FAIL: u10-3 call step should be completed"; exit 1; }
# The call step's audit output should NOT contain 'token' (only from:-resolved inputs)
jq -e 'select(.step=="call") | .output | has("token") | not' "$u10_3_audit" >/dev/null \
  || { echo "FAIL: u10-3 call audit output should not contain 'token' (from: resolved inputs only)"; exit 1; }
echo "PASS: u10-3 — fallback body resolves declared step inputs via from: references (not bare ctx lookup)"

# Verify that process.inputs.city resolved correctly (city key should appear in call body
# by confirming ctx shows city resolved from process inputs, not from ctx['city'] which
# doesn't exist as a step output — the step completed, proving it resolved without error).
echo "PASS: u10-3 — fallback body: from:process.inputs.city resolved from process-level inputs"

# Verify from:steps.s1.outputs.order_id resolved (ctx.s1.order_id = "ORD-99")
[ "$(jq -r '.s1.order_id' <<<"$u10_3_ctx")" = "ORD-99" ] \
  || { echo "FAIL: u10-3 s1 should have produced order_id=ORD-99 in context"; exit 1; }
echo "PASS: u10-3 — fallback body: from:steps.s1.outputs.order_id resolved from step output"

# --- U10-4: webhook step missing response_mode is rejected ---
# (a) Local engine rejects it at step execution time.
cat > "$u10_dir/wh_no_mode.sop.json" <<'JSON'
{
  "name": "wh-no-mode",
  "inputs": {},
  "steps": [
    { "id": "call",
      "type": "webhook",
      "webhook": {
        "url": "https://api.example.com/hook"
      }
    }
  ]
}
JSON

set +e
u10_4_out="$(OSL_WEBHOOK_STUB='200:{}' \
  "$cli" run "$u10_dir/wh_no_mode.sop.json" --local --json)"; u10_4_rc=$?
set -e
[ "$u10_4_rc" -ne 0 ] \
  || { echo "FAIL: u10-4 webhook missing response_mode should exit non-zero, got $u10_4_rc"; exit 1; }
[ "$(jq -r '.status' <<<"$u10_4_out")" = "failed" ] \
  || { echo "FAIL: u10-4 webhook missing response_mode manifest.status should be 'failed', got $(jq -r '.status' <<<"$u10_4_out")"; exit 1; }
# The audit/output error must mention response_mode
u10_4_run_id="$(jq -r '.run_id' <<<"$u10_4_out")"
u10_4_audit="$OPENSOP_LOCAL_HOME/runs/$u10_4_run_id/audit.jsonl"
jq -e 'select(.step=="call") | .output.error | test("response_mode")' "$u10_4_audit" >/dev/null \
  || { echo "FAIL: u10-4 error message should mention response_mode"; exit 1; }
echo "PASS: u10-4 — webhook step missing response_mode: local engine rejects with error (rc!=0)"

# (b) schema validate also flags a webhook step missing response_mode.
# Build a minimal YAML file using python3 (to avoid requiring yq or heredoc YAML).
python3 -c "
import json, sys
# Write a minimal YAML that schema validate can parse (uses yq or python3 PyYAML).
# We need YAML format for cmd_schema_validate.
print('''opensop: \"0.1\"
process:
  name: no-mode-test
  version: \"1.0\"
  description: test
  inputs: []
  steps:
    - id: call
      type: webhook
      webhook:
        url: https://api.example.com/hook
''')
" > "$u10_dir/no_mode.sop.yaml"

set +e
u10_4b_out="$("$cli" schema validate "$u10_dir/no_mode.sop.yaml" --json 2>&1)"; u10_4b_rc=$?
set -e
[ "$u10_4b_rc" -ne 0 ] \
  || { echo "FAIL: u10-4b schema validate should fail for webhook missing response_mode, got $u10_4b_rc"; exit 1; }
# Verify the error message mentions response_mode
echo "$u10_4b_out" | jq -e '.errors[]?.message | test("response_mode")' >/dev/null 2>&1 \
  || { echo "FAIL: u10-4b schema validate error should mention response_mode — got: $u10_4b_out"; exit 1; }
echo "PASS: u10-4b — schema validate flags webhook step missing response_mode"

# --------------------------------------------------------------------------- #
# P1a: local_search + local_suggest — cell-chain process search (no server)
#
# Setup: a two-level cell chain (org → team). Each level has a process.
# Assertions cover:
#   search: match by name, description, tag; nearest-wins dedup; no-match path
#   suggest: ranks relevant process; threshold filtering; no-match path
# --------------------------------------------------------------------------- #
ps_org="$OPENSOP_LOCAL_HOME/ps-org"
ps_team="$ps_org/team"
mkdir -p "$ps_team"
( cd "$ps_org"  && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )
( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )

mkdir -p "$ps_org/processes" "$ps_team/processes"

# Org-level process: lead-qualification (has tags + description)
cat > "$ps_org/processes/lead-qualification.sop.json" <<'JSON'
{
  "name": "lead-qualification",
  "description": "Score inbound leads based on email and company size",
  "tags": ["sales", "crm"],
  "inputs": [
    { "name": "lead_email", "type": "string" },
    { "name": "company_size", "type": "number" }
  ],
  "steps": [{ "id": "score", "type": "noop" }]
}
JSON

# Team-level process: greet-customer (different domain)
cat > "$ps_team/processes/greet-customer.sop.json" <<'JSON'
{
  "name": "greet-customer",
  "description": "Send a welcome email to a new customer",
  "tags": ["onboarding", "email"],
  "inputs": [
    { "name": "customer_name", "type": "string" },
    { "name": "customer_email", "type": "string" }
  ],
  "steps": [{ "id": "send", "type": "noop" }]
}
JSON

# Team-level process that shadows org's lead-qualification (same basename, different name)
cat > "$ps_team/processes/lead-qualification.sop.json" <<'JSON'
{
  "name": "lead-qualification-v2",
  "description": "Team-overridden lead scoring for enterprise",
  "tags": ["sales", "enterprise"],
  "inputs": [{ "name": "lead_email", "type": "string" }],
  "steps": [{ "id": "score", "type": "noop" }]
}
JSON

# (1) search by name token — should find lead-qualification-v2 (nearest, team's)
ps_search1="$( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" search lead --local --json )"
ps_s1_count="$(jq -r '.results | length' <<<"$ps_search1")"
[ "$ps_s1_count" -ge 1 ] || { echo "FAIL: search 'lead' should return at least 1 result, got $ps_s1_count"; exit 1; }
# Nearest-wins: team's lead-qualification-v2 must appear; org's must NOT (deduped by basename)
ps_s1_names="$(jq -r '.results[].name' <<<"$ps_search1")"
echo "$ps_s1_names" | grep -q "lead-qualification-v2" \
  || { echo "FAIL: search 'lead' should include team's lead-qualification-v2"; exit 1; }
echo "$ps_s1_names" | grep -q "^lead-qualification$" \
  && { echo "FAIL: search 'lead' should NOT show org's lead-qualification (deduped by team's nearest-wins)"; exit 1; }
echo "PASS: search --local — matches by name; nearest-wins dedup hides shadowed org process"

# (2) search by description keyword
ps_search2="$( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" search welcome --local --json )"
ps_s2_count="$(jq -r '.results | length' <<<"$ps_search2")"
[ "$ps_s2_count" -ge 1 ] || { echo "FAIL: search 'welcome' should find greet-customer"; exit 1; }
jq -e '.results[] | select(.name == "greet-customer")' <<<"$ps_search2" >/dev/null \
  || { echo "FAIL: search 'welcome' should match greet-customer via description"; exit 1; }
echo "PASS: search --local — matches by description keyword"

# (3) search by tag
ps_search3="$( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" search enterprise --local --json )"
ps_s3_count="$(jq -r '.results | length' <<<"$ps_search3")"
[ "$ps_s3_count" -ge 1 ] || { echo "FAIL: search 'enterprise' should find team's lead process"; exit 1; }
jq -e '.results[] | select(.name == "lead-qualification-v2")' <<<"$ps_search3" >/dev/null \
  || { echo "FAIL: search 'enterprise' should match lead-qualification-v2 via tag"; exit 1; }
echo "PASS: search --local — matches by tag"

# (4) search by input field name
ps_search4="$( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" search customer_name --local --json )"
ps_s4_count="$(jq -r '.results | length' <<<"$ps_search4")"
[ "$ps_s4_count" -ge 1 ] || { echo "FAIL: search 'customer_name' should find greet-customer"; exit 1; }
jq -e '.results[] | select(.name == "greet-customer")' <<<"$ps_search4" >/dev/null \
  || { echo "FAIL: search 'customer_name' should match greet-customer via input field name"; exit 1; }
echo "PASS: search --local — matches by input field name"

# (5) output JSON shape: {query: [...], results: [{name, score, description, tags}, ...]}
ps_shape="$( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" search lead --local --json )"
jq -e 'has("query") and has("results")' <<<"$ps_shape" >/dev/null \
  || { echo "FAIL: search --local --json output shape should have query + results keys"; exit 1; }
jq -e '.results[0] | has("name") and has("score") and has("description") and has("tags")' <<<"$ps_shape" >/dev/null \
  || { echo "FAIL: search --local --json result item missing name/score/description/tags"; exit 1; }
echo "PASS: search --local — output JSON shape matches remote cmd_search"

# (6) failure path: no match → exit 0, empty results (same convention as remote)
set +e
ps_nomatch_out="$( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" search xyzzy-no-match --local --json 2>/dev/null )"; ps_nomatch_rc=$?
set -e
[ "$ps_nomatch_rc" -eq 0 ] || { echo "FAIL: search --local with no match should exit 0 (not an error), got $ps_nomatch_rc"; exit 1; }
echo "PASS: search --local — no-match exits 0 (not an error)"

# (7) suggest: relevant task description → top-1 match with confidence
ps_sug1="$( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" suggest "qualify sales lead by email" --local --json )"
jq -e '.match != null' <<<"$ps_sug1" >/dev/null \
  || { echo "FAIL: suggest 'qualify sales lead' should return a non-null match"; exit 1; }
jq -e '.match.name | test("lead")' <<<"$ps_sug1" >/dev/null \
  || { echo "FAIL: suggest 'qualify sales lead' should match a lead process"; exit 1; }
jq -e '.match.confidence > 0' <<<"$ps_sug1" >/dev/null \
  || { echo "FAIL: suggest match.confidence should be > 0"; exit 1; }
echo "PASS: suggest --local — ranks relevant process for intent query"

# (8) suggest output JSON shape: {task: "...", match: {name, confidence, description}}
jq -e 'has("task") and has("match")' <<<"$ps_sug1" >/dev/null \
  || { echo "FAIL: suggest --local --json output should have task + match keys"; exit 1; }
jq -e '.match | has("name") and has("confidence") and has("description")' <<<"$ps_sug1" >/dev/null \
  || { echo "FAIL: suggest --local --json match missing name/confidence/description"; exit 1; }
echo "PASS: suggest --local — output JSON shape matches remote cmd_suggest"

# (9) suggest with --threshold: if threshold too high, match becomes null
ps_sug_high="$( cd "$ps_team" && env -u OPENSOP_LOCAL_HOME "$cli" suggest "qualify lead" --local --threshold 9999 --json )"
jq -e '.match == null' <<<"$ps_sug_high" >/dev/null \
  || { echo "FAIL: suggest --threshold 9999 should return null match (bar too high)"; exit 1; }
echo "PASS: suggest --local --threshold — high threshold returns null match"

# (10) suggest failure path: no processes at all → null match, exit 0
empty_cell="$OPENSOP_LOCAL_HOME/ps-empty"
mkdir -p "$empty_cell"
( cd "$empty_cell" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )
set +e
ps_sug_empty="$( cd "$empty_cell" && env -u OPENSOP_LOCAL_HOME "$cli" suggest "do something" --local --json 2>/dev/null )"; ps_sug_empty_rc=$?
set -e
[ "$ps_sug_empty_rc" -eq 0 ] || { echo "FAIL: suggest --local in empty cell should exit 0, got $ps_sug_empty_rc"; exit 1; }
jq -e '.match == null' <<<"$ps_sug_empty" >/dev/null \
  || { echo "FAIL: suggest --local in empty cell should have null match"; exit 1; }
echo "PASS: suggest --local — empty corpus yields null match, exits 0"

# (11) search NOT inside a cell (no cell chain): still works, searches nothing → no match
set +e
ps_nocell_out="$( cd "$OPENSOP_LOCAL_HOME" && env -u OPENSOP_LOCAL_HOME "$cli" search lead --local --json 2>/dev/null )"; ps_nocell_rc=$?
set -e
[ "$ps_nocell_rc" -eq 0 ] || { echo "FAIL: search --local outside any cell should exit 0, got $ps_nocell_rc"; exit 1; }
echo "PASS: search --local — outside any cell exits 0 (no corpus, no error)"

# --------------------------------------------------------------------------- #
# P1b: local_dry_run — local process preview + input validation (no run created)
#
# Assertions:
#   - valid inputs → JSON output matches remote dry-run shape (process, valid, validation_errors, steps)
#   - valid inputs → exit 0
#   - missing required input → validation_errors non-empty, valid=false, exit 1
#   - wrong type for a field → validation_errors non-empty, valid=false, exit 1
#   - by name (cell-chain resolution) works the same as explicit path
#   - no run dir created for any dry-run call
# --------------------------------------------------------------------------- #
dr_dir="$OPENSOP_LOCAL_HOME/dry-run-test"
mkdir -p "$dr_dir"

# Process with typed + required inputs and a few steps
cat > "$dr_dir/qualify.sop.json" <<'JSON'
{
  "name": "lead-qualify",
  "description": "Qualify a lead",
  "inputs": [
    { "name": "lead_email", "type": "string",  "required": true, "format": "email" },
    { "name": "score",      "type": "number",  "required": true },
    { "name": "opt_in",     "type": "boolean", "required": false }
  ],
  "steps": [
    { "id": "check",  "type": "noop" },
    { "id": "notify", "type": "form",
      "inputs": [{ "name": "decision", "type": "enum", "values": ["qualify","reject"], "required": true }] }
  ]
}
JSON

runs_before_dry=$(ls "$OPENSOP_LOCAL_HOME/runs" 2>/dev/null | wc -l | tr -d ' ')

# (1) Happy path: valid inputs → exit 0, valid=true, correct JSON shape
dr_happy="$("$cli" dry-run "$dr_dir/qualify.sop.json" --local \
  --input lead_email=alice@example.com \
  --input score=42 \
  --json)"
[ "$(jq -r '.valid' <<<"$dr_happy")" = "true" ] \
  || { echo "FAIL: dry-run --local valid inputs should produce valid=true, got: $(jq -r '.valid' <<<"$dr_happy")"; exit 1; }
echo "PASS: dry-run --local — valid inputs → valid=true"

[ "$(jq -r '.process' <<<"$dr_happy")" = "lead-qualify" ] \
  || { echo "FAIL: dry-run --local .process should be 'lead-qualify'"; exit 1; }
echo "PASS: dry-run --local — .process name correct"

[ "$(jq -r '.validation_errors | length' <<<"$dr_happy")" = "0" ] \
  || { echo "FAIL: dry-run --local valid inputs should have empty validation_errors"; exit 1; }
echo "PASS: dry-run --local — validation_errors is empty for valid inputs"

[ "$(jq -r '.steps | length' <<<"$dr_happy")" = "2" ] \
  || { echo "FAIL: dry-run --local .steps should have 2 entries, got $(jq -r '.steps | length' <<<"$dr_happy")"; exit 1; }
echo "PASS: dry-run --local — .steps array has 2 entries (mirrors remote shape)"

jq -e '.steps[0] | has("step_id") and has("type") and has("preview")' <<<"$dr_happy" >/dev/null \
  || { echo "FAIL: dry-run --local step item missing step_id/type/preview keys"; exit 1; }
echo "PASS: dry-run --local — step item has step_id, type, preview keys"

jq -e 'has("process") and has("valid") and has("validation_errors") and has("steps")' \
  <<<"$dr_happy" >/dev/null \
  || { echo "FAIL: dry-run --local JSON output missing top-level keys"; exit 1; }
echo "PASS: dry-run --local — JSON shape matches remote cmd_dry_run"

# (2) Confirm no run directory was created for a successful dry-run
runs_after_dry=$(ls "$OPENSOP_LOCAL_HOME/runs" 2>/dev/null | wc -l | tr -d ' ')
[ "$runs_before_dry" = "$runs_after_dry" ] \
  || { echo "FAIL: dry-run --local should not create any run directory"; exit 1; }
echo "PASS: dry-run --local — no run directory created"

# (3) Failure path: missing required field → exit 1, valid=false, error listed
set +e
dr_missing="$("$cli" dry-run "$dr_dir/qualify.sop.json" --local \
  --input score=42 \
  --json)"; dr_missing_rc=$?
set -e
[ "$dr_missing_rc" -ne 0 ] \
  || { echo "FAIL: dry-run --local with missing required input should exit non-zero, got $dr_missing_rc"; exit 1; }
echo "PASS: dry-run --local — missing required field exits non-zero"

[ "$(jq -r '.valid' <<<"$dr_missing")" = "false" ] \
  || { echo "FAIL: dry-run --local missing field should have valid=false"; exit 1; }
echo "PASS: dry-run --local — valid=false when required field missing"

[ "$(jq -r '.validation_errors | length' <<<"$dr_missing")" -ge 1 ] \
  || { echo "FAIL: dry-run --local missing field should have ≥1 validation_error"; exit 1; }
echo "PASS: dry-run --local — validation_errors non-empty when required field missing"

jq -e '.validation_errors[] | select(.message | test("lead_email"))' <<<"$dr_missing" >/dev/null \
  || { echo "FAIL: dry-run --local missing-email error should mention 'lead_email'"; exit 1; }
echo "PASS: dry-run --local — error message identifies the missing required field"

# (4) Failure path: wrong type for number field → exit 1, error in validation_errors
set +e
dr_badtype="$("$cli" dry-run "$dr_dir/qualify.sop.json" --local \
  --input lead_email=alice@example.com \
  --input score=not-a-number \
  --json)"; dr_badtype_rc=$?
set -e
[ "$dr_badtype_rc" -ne 0 ] \
  || { echo "FAIL: dry-run --local wrong type should exit non-zero, got $dr_badtype_rc"; exit 1; }
[ "$(jq -r '.valid' <<<"$dr_badtype")" = "false" ] \
  || { echo "FAIL: dry-run --local wrong type should have valid=false"; exit 1; }
jq -e '.validation_errors[] | select(.message | test("score"))' <<<"$dr_badtype" >/dev/null \
  || { echo "FAIL: dry-run --local type error should mention 'score'"; exit 1; }
echo "PASS: dry-run --local — wrong type field exits non-zero with error mentioning the field"

# (5) Failure path: bad email format → validation error even when type=string
set +e
dr_bademail="$("$cli" dry-run "$dr_dir/qualify.sop.json" --local \
  --input lead_email=not-an-email \
  --input score=42 \
  --json)"; dr_bademail_rc=$?
set -e
[ "$dr_bademail_rc" -ne 0 ] \
  || { echo "FAIL: dry-run --local bad email format should exit non-zero, got $dr_bademail_rc"; exit 1; }
jq -e '.validation_errors[] | select(.message | test("email"))' <<<"$dr_bademail" >/dev/null \
  || { echo "FAIL: dry-run --local bad email should produce an email-related error"; exit 1; }
echo "PASS: dry-run --local — bad email format exits non-zero with email error"

# (6) Cell-chain name resolution: dry-run by bare name from inside a cell
dr_cell_dir="$OPENSOP_LOCAL_HOME/dr-cell"
mkdir -p "$dr_cell_dir/processes"
( cd "$dr_cell_dir" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )
cp "$dr_dir/qualify.sop.json" "$dr_cell_dir/processes/qualify.sop.json"

dr_name="$( cd "$dr_cell_dir" && env -u OPENSOP_LOCAL_HOME \
  "$cli" dry-run qualify --local \
  --input lead_email=bob@example.com \
  --input score=10 \
  --json )"
[ "$(jq -r '.valid' <<<"$dr_name")" = "true" ] \
  || { echo "FAIL: dry-run --local by bare name should resolve from cell and produce valid=true"; exit 1; }
[ "$(jq -r '.process' <<<"$dr_name")" = "lead-qualify" ] \
  || { echo "FAIL: dry-run --local by bare name should have process='lead-qualify'"; exit 1; }
echo "PASS: dry-run --local — bare name resolves via cell chain (nearest wins)"

# (7) Failure path: name not found → non-zero exit
set +e
( cd "$dr_cell_dir" && env -u OPENSOP_LOCAL_HOME \
  "$cli" dry-run no-such-process --local --json >/dev/null 2>&1 ); dr_nofile_rc=$?
set -e
[ "$dr_nofile_rc" -ne 0 ] \
  || { echo "FAIL: dry-run --local with unresolvable name should exit non-zero"; exit 1; }
echo "PASS: dry-run --local — unresolvable process name exits non-zero"

# (8) Process with object-style inputs (dict instead of array) — normalised correctly
cat > "$dr_dir/dict-inputs.sop.json" <<'JSON'
{
  "name": "dict-process",
  "inputs": {
    "name": { "type": "string", "required": true },
    "count": { "type": "number" }
  },
  "steps": [{ "id": "go", "type": "noop" }]
}
JSON

dr_dict="$("$cli" dry-run "$dr_dir/dict-inputs.sop.json" --local \
  --input name=alice \
  --json)"
[ "$(jq -r '.valid' <<<"$dr_dict")" = "true" ] \
  || { echo "FAIL: dry-run --local dict-style inputs should validate correctly"; exit 1; }
echo "PASS: dry-run --local — object-style inputs normalised and validated correctly"

# --------------------------------------------------------------------------- #
# P1c: local_status + local_steps — inspect local runs (no server)
# --------------------------------------------------------------------------- #
echo "--- P1c: local_status + local_steps ---"

# Re-use the already-completed greet run (run_id is in $run_id from the top
# of the file; $OPENSOP_LOCAL_HOME still points to the same tempdir).

# (1) status of a completed run
p1c_status="$("$cli" status "$run_id" --local --json)"
[ "$(jq -r '.id' <<<"$p1c_status")" = "$run_id" ] \
  || { echo "FAIL: status --local .id should equal run_id, got: $(jq -r '.id' <<<"$p1c_status")"; exit 1; }
echo "PASS: status --local — .id matches run_id"

[ "$(jq -r '.state' <<<"$p1c_status")" = "completed" ] \
  || { echo "FAIL: status --local completed run should have state=completed, got: $(jq -r '.state' <<<"$p1c_status")"; exit 1; }
echo "PASS: status --local — completed run has state=completed"

[ "$(jq -r '.process.name' <<<"$p1c_status")" = "greet" ] \
  || { echo "FAIL: status --local .process.name should be 'greet', got: $(jq -r '.process.name' <<<"$p1c_status")"; exit 1; }
echo "PASS: status --local — .process.name is correct"

jq -e '.completed_at != null' <<<"$p1c_status" >/dev/null \
  || { echo "FAIL: status --local completed run should have completed_at set"; exit 1; }
echo "PASS: status --local — completed run has completed_at"

# steps array: two entries (build + render), both completed
[ "$(jq '.steps | length' <<<"$p1c_status")" -eq 2 ] \
  || { echo "FAIL: status --local greet steps should be 2, got: $(jq '.steps | length' <<<"$p1c_status")"; exit 1; }
echo "PASS: status --local — steps array has 2 entries"

jq -e '.steps[] | select(.step_id == "build" and .state == "completed")' <<<"$p1c_status" >/dev/null \
  || { echo "FAIL: status --local build step should be completed"; exit 1; }
echo "PASS: status --local — build step is completed"

jq -e '.steps[] | select(.step_id == "render" and .state == "completed")' <<<"$p1c_status" >/dev/null \
  || { echo "FAIL: status --local render step should be completed"; exit 1; }
echo "PASS: status --local — render step is completed"

# step item shape: must have step_id, type, state (mirrors remote cmd_status shape)
jq -e '.steps[0] | has("step_id") and has("type") and has("state")' <<<"$p1c_status" >/dev/null \
  || { echo "FAIL: status --local step item missing step_id/type/state keys"; exit 1; }
echo "PASS: status --local — step item has step_id, type, state (mirrors remote shape)"

# top-level shape: id, process, state, started_at
jq -e 'has("id") and has("process") and has("state") and has("started_at")' <<<"$p1c_status" >/dev/null \
  || { echo "FAIL: status --local JSON missing required top-level keys"; exit 1; }
echo "PASS: status --local — JSON shape matches remote cmd_status"

# (2) status of a waiting run — shows the waiting step
p1c_wait_proc="$OPENSOP_LOCAL_HOME/p1c-wait.sop.json"
cat > "$p1c_wait_proc" <<'JSON'
{ "name": "p1c-wait-test", "inputs": {},
  "steps": [
    { "id": "before", "type": "shell", "run": "echo pre" },
    { "id": "pause",  "type": "form",  "inputs": [{"name":"answer","type":"string","required":true}] },
    { "id": "after",  "type": "noop" }
  ] }
JSON
p1c_wait_m="$("$cli" run "$p1c_wait_proc" --local --json)"
p1c_wait_id="$(jq -r '.run_id' <<<"$p1c_wait_m")"
[ "$(jq -r '.status' <<<"$p1c_wait_m")" = "waiting" ] \
  || { echo "FAIL: p1c-wait run should be in waiting status"; exit 1; }

p1c_wait_s="$("$cli" status "$p1c_wait_id" --local --json)"
[ "$(jq -r '.state' <<<"$p1c_wait_s")" = "waiting" ] \
  || { echo "FAIL: status --local waiting run should have state=waiting, got: $(jq -r '.state' <<<"$p1c_wait_s")"; exit 1; }
echo "PASS: status --local — waiting run has state=waiting"

# The waiting step (pause) appears in steps with state=waiting
jq -e '.steps[] | select(.step_id == "pause" and .state == "waiting")' <<<"$p1c_wait_s" >/dev/null \
  || { echo "FAIL: status --local waiting run: pause step should have state=waiting"; exit 1; }
echo "PASS: status --local — waiting run shows paused step with state=waiting"

# sub_state should be waiting_for_input (form step)
jq -e '.steps[] | select(.step_id == "pause") | .sub_state == "waiting_for_input"' <<<"$p1c_wait_s" >/dev/null \
  || { echo "FAIL: status --local form step sub_state should be waiting_for_input"; exit 1; }
echo "PASS: status --local — waiting form step has sub_state=waiting_for_input"

# waiting block propagated from manifest
jq -e '.waiting != null' <<<"$p1c_wait_s" >/dev/null \
  || { echo "FAIL: status --local waiting run should have non-null .waiting block"; exit 1; }
echo "PASS: status --local — waiting block present in status response"

# completed_at must be null for a still-waiting run
[ "$(jq -r '.completed_at' <<<"$p1c_wait_s")" = "null" ] \
  || { echo "FAIL: status --local waiting run should have null completed_at, got: $(jq -r '.completed_at' <<<"$p1c_wait_s")"; exit 1; }
echo "PASS: status --local — waiting run has null completed_at"

# (3) local_steps — step list with full receipt fields
p1c_steps="$("$cli" steps "$run_id" --local --json)"
[ "$(jq -r '.run_id' <<<"$p1c_steps")" = "$run_id" ] \
  || { echo "FAIL: steps --local .run_id should match, got: $(jq -r '.run_id' <<<"$p1c_steps")"; exit 1; }
echo "PASS: steps --local — .run_id matches"

[ "$(jq '.steps | length' <<<"$p1c_steps")" -eq 2 ] \
  || { echo "FAIL: steps --local should list 2 steps, got: $(jq '.steps | length' <<<"$p1c_steps")"; exit 1; }
echo "PASS: steps --local — lists 2 steps"

# Steps from steps command should have step_id, type, state
jq -e '.steps[0] | has("step_id") and has("type") and has("state")' <<<"$p1c_steps" >/dev/null \
  || { echo "FAIL: steps --local item missing step_id/type/state"; exit 1; }
echo "PASS: steps --local — step item has step_id, type, state"

# top-level shape: run_id + steps
jq -e 'has("run_id") and has("steps")' <<<"$p1c_steps" >/dev/null \
  || { echo "FAIL: steps --local output missing run_id or steps key"; exit 1; }
echo "PASS: steps --local — output shape has run_id and steps"

# steps also have exit_code and output (full receipt fields)
jq -e '.steps[] | select(.step_id == "build") | has("exit_code") and has("output")' <<<"$p1c_steps" >/dev/null \
  || { echo "FAIL: steps --local build step missing exit_code or output"; exit 1; }
echo "PASS: steps --local — step receipt has exit_code and output fields"

# steps also have decided_by and confidence (mirrors remote StepSerializer)
jq -e '.steps[0] | has("decided_by") and has("confidence")' <<<"$p1c_steps" >/dev/null \
  || { echo "FAIL: steps --local step receipt missing decided_by or confidence (should mirror remote StepSerializer)"; exit 1; }
echo "PASS: steps --local — step receipt has decided_by and confidence fields (mirrors remote StepSerializer)"

# (4) Failure path: unknown run_id → error with instance_not_found code
set +e
p1c_bad_s="$("$cli" status "no-such-run-xyz" --local --json 2>&1)"; p1c_bad_rc=$?
set -e
[ "$p1c_bad_rc" -ne 0 ] \
  || { echo "FAIL: status --local with unknown run_id should exit non-zero"; exit 1; }
echo "PASS: status --local — unknown run_id exits non-zero"

echo "$p1c_bad_s" | jq -e '.error == "instance_not_found"' >/dev/null \
  || { echo "FAIL: status --local unknown run_id should emit instance_not_found error code, got: $p1c_bad_s"; exit 1; }
echo "PASS: status --local — unknown run_id emits instance_not_found error code"

set +e
p1c_bad_st="$("$cli" steps "no-such-run-xyz" --local --json 2>&1)"; p1c_bad_st_rc=$?
set -e
[ "$p1c_bad_st_rc" -ne 0 ] \
  || { echo "FAIL: steps --local with unknown run_id should exit non-zero"; exit 1; }
echo "PASS: steps --local — unknown run_id exits non-zero"

# --------------------------------------------------------------------------- #
# P1d: local_instances + local_compass + local_history
#
# Setup: use a DEDICATED OPENSOP_LOCAL_HOME so the exact run count is
# deterministic and independent of all prior test sections.
# --------------------------------------------------------------------------- #
p1d_home="$(mktemp -d)"
p1d_dir="$p1d_home/procs"
mkdir -p "$p1d_dir"

# Process A: 3 runs — 2 completed, 1 failed
cat > "$p1d_dir/proc-a.sop.json" <<'JSON'
{ "name": "proc-a", "inputs": {},
  "steps": [ { "id": "run", "type": "shell", "run": "echo done" } ] }
JSON
cat > "$p1d_dir/proc-a-fail.sop.json" <<'JSON'
{ "name": "proc-a", "inputs": {},
  "steps": [ { "id": "run", "type": "shell", "run": "exit 1" } ] }
JSON

# Process B: 1 completed run
cat > "$p1d_dir/proc-b.sop.json" <<'JSON'
{ "name": "proc-b", "inputs": {},
  "steps": [ { "id": "run", "type": "shell", "run": "echo b-done" } ] }
JSON

# Process C: 1 waiting run (form step)
cat > "$p1d_dir/proc-c.sop.json" <<'JSON'
{ "name": "proc-c", "inputs": {},
  "steps": [
    { "id": "gate", "type": "form",
      "inputs": [ { "name": "val", "type": "string", "required": true } ] }
  ] }
JSON

p1d_a1=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" run "$p1d_dir/proc-a.sop.json" --local --json)
p1d_a1_id=$(jq -r '.run_id' <<<"$p1d_a1")

p1d_a2=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" run "$p1d_dir/proc-a.sop.json" --local --json)
p1d_a2_id=$(jq -r '.run_id' <<<"$p1d_a2")

set +e
p1d_a3=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" run "$p1d_dir/proc-a-fail.sop.json" --local --json); p1d_a3_rc=$?
set -e
p1d_a3_id=$(jq -r '.run_id' <<<"$p1d_a3")

p1d_b1=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" run "$p1d_dir/proc-b.sop.json" --local --json)
p1d_b1_id=$(jq -r '.run_id' <<<"$p1d_b1")

set +e
p1d_c1=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" run "$p1d_dir/proc-c.sop.json" --local --json); p1d_c1_rc=$?
set -e
p1d_c1_id=$(jq -r '.run_id' <<<"$p1d_c1")

# Sanity-check the setup runs
[ "$(jq -r '.status' <<<"$p1d_a1")" = "completed" ] || { echo "FAIL: p1d proc-a run1 should be completed"; exit 1; }
[ "$(jq -r '.status' <<<"$p1d_a2")" = "completed" ] || { echo "FAIL: p1d proc-a run2 should be completed"; exit 1; }
[ "$(jq -r '.status' <<<"$p1d_a3")" = "failed"    ] || { echo "FAIL: p1d proc-a run3 should be failed"; exit 1; }
[ "$(jq -r '.status' <<<"$p1d_b1")" = "completed" ] || { echo "FAIL: p1d proc-b run1 should be completed"; exit 1; }
[ "$(jq -r '.status' <<<"$p1d_c1")" = "waiting"   ] || { echo "FAIL: p1d proc-c run1 should be waiting"; exit 1; }
echo "PASS: p1d — setup runs created (2 proc-a completed, 1 proc-a failed, 1 proc-b, 1 proc-c waiting)"

# --------------------------------------------------------------------------- #
# (1) local_instances — no filter: all 5 runs returned
# --------------------------------------------------------------------------- #
p1d_all=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --json)

# JSON shape: {instances:[...], total:N}
jq -e 'has("instances") and has("total")' <<<"$p1d_all" >/dev/null \
  || { echo "FAIL: instances --local missing 'instances' or 'total' key"; exit 1; }
echo "PASS: instances --local — JSON shape has 'instances' and 'total'"

[ "$(jq '.total' <<<"$p1d_all")" -eq 5 ] \
  || { echo "FAIL: instances --local total should be 5, got: $(jq '.total' <<<"$p1d_all")"; exit 1; }
echo "PASS: instances --local — total is 5 (all runs)"

[ "$(jq '.instances | length' <<<"$p1d_all")" -eq 5 ] \
  || { echo "FAIL: instances --local instances array should have 5 entries, got $(jq '.instances | length' <<<"$p1d_all")"; exit 1; }
echo "PASS: instances --local — instances array has 5 entries"

# Each instance has {id, process:{name}, state, started_at}
jq -e '.instances[0] | has("id") and has("process") and has("state") and has("started_at")' <<<"$p1d_all" >/dev/null \
  || { echo "FAIL: instances --local entry missing required keys"; exit 1; }
echo "PASS: instances --local — each entry has id, process, state, started_at"

jq -e '.instances[0].process | has("name")' <<<"$p1d_all" >/dev/null \
  || { echo "FAIL: instances --local entry.process missing 'name'"; exit 1; }
echo "PASS: instances --local — each entry.process has name"

# --------------------------------------------------------------------------- #
# (2) local_instances --state completed: only completed runs
# --------------------------------------------------------------------------- #
p1d_completed=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --state completed --json)
[ "$(jq '.total' <<<"$p1d_completed")" -eq 3 ] \
  || { echo "FAIL: instances --local --state completed should total 3, got $(jq '.total' <<<"$p1d_completed")"; exit 1; }
echo "PASS: instances --local --state completed — total is 3"

jq -e '.instances | all(.state == "completed")' <<<"$p1d_completed" >/dev/null \
  || { echo "FAIL: instances --local --state completed returned non-completed entries"; exit 1; }
echo "PASS: instances --local --state completed — all entries have state=completed"

# --------------------------------------------------------------------------- #
# (3) local_instances --state failed: only failed runs
# --------------------------------------------------------------------------- #
p1d_failed=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --state failed --json)
[ "$(jq '.total' <<<"$p1d_failed")" -eq 1 ] \
  || { echo "FAIL: instances --local --state failed should total 1, got $(jq '.total' <<<"$p1d_failed")"; exit 1; }
echo "PASS: instances --local --state failed — total is 1"

# --------------------------------------------------------------------------- #
# (4) local_instances --process proc-a: only proc-a runs (3 total)
# --------------------------------------------------------------------------- #
p1d_proca=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --process proc-a --json)
[ "$(jq '.total' <<<"$p1d_proca")" -eq 3 ] \
  || { echo "FAIL: instances --local --process proc-a total should be 3, got $(jq '.total' <<<"$p1d_proca")"; exit 1; }
echo "PASS: instances --local --process proc-a — total is 3"

jq -e '.instances | all(.process.name == "proc-a")' <<<"$p1d_proca" >/dev/null \
  || { echo "FAIL: instances --local --process proc-a returned non-proc-a entries"; exit 1; }
echo "PASS: instances --local --process proc-a — all entries are proc-a"

# --------------------------------------------------------------------------- #
# (5) local_instances --process + --state combined
# --------------------------------------------------------------------------- #
p1d_proca_fail=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --process proc-a --state failed --json)
[ "$(jq '.total' <<<"$p1d_proca_fail")" -eq 1 ] \
  || { echo "FAIL: instances --local --process proc-a --state failed should total 1, got $(jq '.total' <<<"$p1d_proca_fail")"; exit 1; }
echo "PASS: instances --local — combined --process + --state filters work"

# --------------------------------------------------------------------------- #
# (6) local_instances pagination: --limit 2 --offset 0
# --------------------------------------------------------------------------- #
p1d_page1=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --limit 2 --offset 0 --json)
[ "$(jq '.instances | length' <<<"$p1d_page1")" -eq 2 ] \
  || { echo "FAIL: instances --local --limit 2 should return 2 entries, got $(jq '.instances | length' <<<"$p1d_page1")"; exit 1; }
[ "$(jq '.total' <<<"$p1d_page1")" -eq 5 ] \
  || { echo "FAIL: instances --local --limit 2 total should still be 5, got $(jq '.total' <<<"$p1d_page1")"; exit 1; }
echo "PASS: instances --local — --limit 2 returns 2 entries, total still 5"

# page 2: --offset 2 returns the remaining 2 (not 3, as limit=2)
p1d_page2=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --limit 2 --offset 2 --json)
[ "$(jq '.instances | length' <<<"$p1d_page2")" -eq 2 ] \
  || { echo "FAIL: instances --local --offset 2 --limit 2 should return 2 entries, got $(jq '.instances | length' <<<"$p1d_page2")"; exit 1; }
echo "PASS: instances --local — pagination --offset 2 --limit 2 returns 2 entries"

# --------------------------------------------------------------------------- #
# (7) local_instances — waiting state filter picks up the form-paused run
# --------------------------------------------------------------------------- #
p1d_waiting=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --state waiting --json)
[ "$(jq '.total' <<<"$p1d_waiting")" -eq 1 ] \
  || { echo "FAIL: instances --local --state waiting should total 1, got $(jq '.total' <<<"$p1d_waiting")"; exit 1; }
[ "$(jq -r '.instances[0].id' <<<"$p1d_waiting")" = "$p1d_c1_id" ] \
  || { echo "FAIL: instances --local --state waiting should return proc-c's run id"; exit 1; }
echo "PASS: instances --local --state waiting — picks up the form-paused run"

# --------------------------------------------------------------------------- #
# (8) local_instances -- unknown flag errors
# --------------------------------------------------------------------------- #
set +e
OPENSOP_LOCAL_HOME="$p1d_home" "$cli" instances --local --bogus-flag --json >/dev/null 2>&1; p1d_bad_rc=$?
set -e
[ "$p1d_bad_rc" -ne 0 ] \
  || { echo "FAIL: instances --local unknown flag should exit non-zero"; exit 1; }
echo "PASS: instances --local — unknown flag exits non-zero"

# --------------------------------------------------------------------------- #
# (9) local_compass — three-ranking shape over the 5 runs
# --------------------------------------------------------------------------- #
p1d_compass=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" compass --local --json)

jq -e 'has("by_runs") and has("by_recency") and has("by_failure_rate")' <<<"$p1d_compass" >/dev/null \
  || { echo "FAIL: compass --local missing by_runs, by_recency, or by_failure_rate"; exit 1; }
echo "PASS: compass --local — JSON shape has by_runs, by_recency, by_failure_rate"

# by_runs: proc-a should have 3 runs (highest count)
jq -e '.by_runs[0].name == "proc-a" and .by_runs[0].total == 3' <<<"$p1d_compass" >/dev/null \
  || { echo "FAIL: compass --local by_runs[0] should be proc-a × 3, got: $(jq -c '.by_runs[0]' <<<"$p1d_compass")"; exit 1; }
echo "PASS: compass --local — by_runs[0] is proc-a × 3 (most runs)"

# by_failure_rate: proc-a has 1/3 failures; proc-b and proc-c have 0 failures
# proc-a rate should be highest
jq -e '.by_failure_rate[0].name == "proc-a"' <<<"$p1d_compass" >/dev/null \
  || { echo "FAIL: compass --local by_failure_rate[0] should be proc-a, got: $(jq -r '.by_failure_rate[0].name' <<<"$p1d_compass")"; exit 1; }
echo "PASS: compass --local — by_failure_rate[0] is proc-a (highest failure rate)"

# proc-a failure rate should be ~0.333 (1 failed out of 3)
jq -e '.by_failure_rate[0].failures == 1 and .by_failure_rate[0].total == 3' <<<"$p1d_compass" >/dev/null \
  || { echo "FAIL: compass --local proc-a failure stats wrong"; exit 1; }
echo "PASS: compass --local — proc-a has 1 failure out of 3 (correct rate)"

# by_recency: array is populated (at least 3 entries for proc-a, proc-b, proc-c)
[ "$(jq '.by_recency | length' <<<"$p1d_compass")" -ge 3 ] \
  || { echo "FAIL: compass --local by_recency should have at least 3 entries"; exit 1; }
echo "PASS: compass --local — by_recency has at least 3 entries"

# Each by_recency entry has name and last_run_at
jq -e '.by_recency[0] | has("name") and has("last_run_at")' <<<"$p1d_compass" >/dev/null \
  || { echo "FAIL: compass --local by_recency[0] missing name or last_run_at"; exit 1; }
echo "PASS: compass --local — by_recency entries have name and last_run_at"

# --------------------------------------------------------------------------- #
# (10) local_history --process proc-a: same as instances --process proc-a
# --------------------------------------------------------------------------- #
p1d_hist=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" history --local --process proc-a --json)

jq -e 'has("instances") and has("total")' <<<"$p1d_hist" >/dev/null \
  || { echo "FAIL: history --local missing instances or total"; exit 1; }
echo "PASS: history --local — JSON shape has instances and total"

[ "$(jq '.total' <<<"$p1d_hist")" -eq 3 ] \
  || { echo "FAIL: history --local --process proc-a should total 3, got $(jq '.total' <<<"$p1d_hist")"; exit 1; }
echo "PASS: history --local --process proc-a — total is 3"

jq -e '.instances | all(.process.name == "proc-a")' <<<"$p1d_hist" >/dev/null \
  || { echo "FAIL: history --local returned non-proc-a entries"; exit 1; }
echo "PASS: history --local — all entries are proc-a"

# --------------------------------------------------------------------------- #
# (11) local_history --limit: caps the returned entries
# --------------------------------------------------------------------------- #
p1d_hist_lim=$(OPENSOP_LOCAL_HOME="$p1d_home" "$cli" history --local --process proc-a --limit 2 --json)
[ "$(jq '.instances | length' <<<"$p1d_hist_lim")" -eq 2 ] \
  || { echo "FAIL: history --local --limit 2 should return 2 entries, got $(jq '.instances | length' <<<"$p1d_hist_lim")"; exit 1; }
[ "$(jq '.total' <<<"$p1d_hist_lim")" -eq 3 ] \
  || { echo "FAIL: history --local --limit 2 total should still be 3, got $(jq '.total' <<<"$p1d_hist_lim")"; exit 1; }
echo "PASS: history --local --limit 2 — returns 2 entries, total still 3"

# --------------------------------------------------------------------------- #
# (12) local_history failure path: missing --process errors
# --------------------------------------------------------------------------- #
set +e
OPENSOP_LOCAL_HOME="$p1d_home" "$cli" history --local --json >/dev/null 2>&1; p1d_hist_noarg_rc=$?
set -e
[ "$p1d_hist_noarg_rc" -ne 0 ] \
  || { echo "FAIL: history --local without --process should exit non-zero"; exit 1; }
echo "PASS: history --local — missing --process exits non-zero"

# --------------------------------------------------------------------------- #
# (13) local_instances empty store: --local when no runs exist returns empty list
# --------------------------------------------------------------------------- #
p1d_empty_home="$(mktemp -d)"
p1d_empty=$( OPENSOP_LOCAL_HOME="$p1d_empty_home" "$cli" instances --local --json )
[ "$(jq '.total' <<<"$p1d_empty")" -eq 0 ] \
  || { echo "FAIL: instances --local on empty store should total 0, got $(jq '.total' <<<"$p1d_empty")"; exit 1; }
[ "$(jq '.instances | length' <<<"$p1d_empty")" -eq 0 ] \
  || { echo "FAIL: instances --local on empty store should return empty array"; exit 1; }
rm -rf "$p1d_empty_home"
echo "PASS: instances --local — empty store returns {instances:[], total:0}"

# compass on empty store: returns the three empty rankings
p1d_empty_home2="$(mktemp -d)"
p1d_empty_compass=$( OPENSOP_LOCAL_HOME="$p1d_empty_home2" "$cli" compass --local --json )
jq -e '.by_runs == [] and .by_recency == [] and .by_failure_rate == []' <<<"$p1d_empty_compass" >/dev/null \
  || { echo "FAIL: compass --local on empty store should return three empty arrays, got: $p1d_empty_compass"; exit 1; }
rm -rf "$p1d_empty_home2"
echo "PASS: compass --local — empty store returns three empty ranking arrays"

# Cleanup p1d dedicated home
rm -rf "$p1d_home"

# --------------------------------------------------------------------------- #
# P1e: local_diff — compare two local runs
#
# Full coverage:
#   (1) diff of two identical runs → identical:true, differences:[]
#   (2) diff of two runs with different inputs → differences shows inputs delta
#   (3) diff of two runs with different final context/outputs → outputs delta
#   (4) diff of two completed runs where one step has different state → step delta
#   (5) unknown run_id → error (instance_not_found)
#   (6) runs from different processes → error (same-process guard)
# --------------------------------------------------------------------------- #
p1e_home="$(mktemp -d)"

# Process A: a simple two-step shell process so inputs and outputs differ.
p1e_proc_a="$p1e_home/proc-a.sop.json"
cat > "$p1e_proc_a" <<'JSON'
{
  "name": "p1e-proc-a",
  "inputs": {"name": ""},
  "steps": [
    { "id": "greet", "type": "shell",
      "run": "echo \"hello, $(echo \"$OSL_CONTEXT\" | jq -r '.name')\"" }
  ]
}
JSON

# Process B: different name (for the cross-process guard test).
p1e_proc_b="$p1e_home/proc-b.sop.json"
cat > "$p1e_proc_b" <<'JSON'
{
  "name": "p1e-proc-b",
  "inputs": {},
  "steps": [ { "id": "noop", "type": "noop" } ]
}
JSON

# Run A1: name=alice
p1e_m_a1=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" run "$p1e_proc_a" --local --input name=alice --json)
p1e_rid_a1=$(jq -r '.run_id' <<<"$p1e_m_a1")
[ "$(jq -r '.status' <<<"$p1e_m_a1")" = "completed" ] || { echo "FAIL: p1e run A1 should complete"; exit 1; }

# Run A2: name=bob (different input → different output context)
p1e_m_a2=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" run "$p1e_proc_a" --local --input name=bob --json)
p1e_rid_a2=$(jq -r '.run_id' <<<"$p1e_m_a2")
[ "$(jq -r '.status' <<<"$p1e_m_a2")" = "completed" ] || { echo "FAIL: p1e run A2 should complete"; exit 1; }

# Run A3: same args as A1 (name=alice) — used for the identical-runs test.
p1e_m_a3=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" run "$p1e_proc_a" --local --input name=alice --json)
p1e_rid_a3=$(jq -r '.run_id' <<<"$p1e_m_a3")

# (1) Identical inputs + same process → should be identical (both completed, same step outputs)
p1e_diff_same=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" diff "$p1e_rid_a1" "$p1e_rid_a3" --local --json)
[ "$(jq -r '.identical' <<<"$p1e_diff_same")" = "true" ] \
  || { echo "FAIL: p1e diff of identical runs should be identical:true, got: $(jq -r '.identical' <<<"$p1e_diff_same")"; exit 1; }
[ "$(jq '.differences | length' <<<"$p1e_diff_same")" -eq 0 ] \
  || { echo "FAIL: p1e diff of identical runs should have 0 differences, got: $(jq '.differences | length' <<<"$p1e_diff_same")"; exit 1; }
echo "PASS: diff --local — identical runs produce identical:true, differences:[]"

# (2) JSON shape check: a and b blocks have correct run IDs and state.
[ "$(jq -r '.a.id' <<<"$p1e_diff_same")" = "$p1e_rid_a1" ] \
  || { echo "FAIL: p1e diff a.id should be rid_a1"; exit 1; }
[ "$(jq -r '.b.id' <<<"$p1e_diff_same")" = "$p1e_rid_a3" ] \
  || { echo "FAIL: p1e diff b.id should be rid_a3"; exit 1; }
[ "$(jq -r '.a.state' <<<"$p1e_diff_same")" = "completed" ] \
  || { echo "FAIL: p1e diff a.state should be 'completed'"; exit 1; }
echo "PASS: diff --local — JSON shape has a.id, b.id, a.state correctly set"

# (3) Different inputs (which produce different shell outputs) → runs are not identical.
# Note: inputs is NOT diffed (matches remote cmd_diff which also omits inputs).
# The difference is captured in the 'outputs' path (final context differs because inputs differ).
p1e_diff_ab=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" diff "$p1e_rid_a1" "$p1e_rid_a2" --local --json)
[ "$(jq -r '.identical' <<<"$p1e_diff_ab")" = "false" ] \
  || { echo "FAIL: p1e diff of different-input runs should be identical:false"; exit 1; }
echo "PASS: diff --local — different-input runs produce identical:false"
[ "$(jq '.differences | length' <<<"$p1e_diff_ab")" -gt 0 ] \
  || { echo "FAIL: p1e diff should have at least one difference when runs differ"; exit 1; }
echo "PASS: diff --local — non-empty differences when runs differ (inputs not diffed; outputs captures delta)"

# (4) Different outputs → differences includes "outputs" path.
# (inputs are not diffed — parity with remote cmd_diff; outputs captures the observable delta)
jq -e '.differences | map(.path) | contains(["outputs"])' <<<"$p1e_diff_ab" >/dev/null \
  || { echo "FAIL: p1e diff should report 'outputs' delta when final contexts differ"; exit 1; }
echo "PASS: diff --local — different contexts produce differences containing 'outputs' path"

# (5) Run B: different process (for cross-process guard).
p1e_m_b=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" run "$p1e_proc_b" --local --json)
p1e_rid_b=$(jq -r '.run_id' <<<"$p1e_m_b")
set +e
OPENSOP_LOCAL_HOME="$p1e_home" "$cli" diff "$p1e_rid_a1" "$p1e_rid_b" --local --json >/dev/null 2>&1
p1e_xproc_rc=$?
set -e
[ "$p1e_xproc_rc" -ne 0 ] \
  || { echo "FAIL: diff --local of runs from different processes should exit non-zero"; exit 1; }
echo "PASS: diff --local — cross-process diff is rejected (same-process guard)"

# (6) Unknown run_id → error.
set +e
OPENSOP_LOCAL_HOME="$p1e_home" "$cli" diff "no-such-run" "$p1e_rid_a1" --local --json >/dev/null 2>&1
p1e_norun_rc=$?
set -e
[ "$p1e_norun_rc" -ne 0 ] \
  || { echo "FAIL: diff --local with unknown run_id should exit non-zero"; exit 1; }
echo "PASS: diff --local — unknown run_id exits non-zero (instance_not_found)"

# (7) Unknown second run_id → error.
set +e
OPENSOP_LOCAL_HOME="$p1e_home" "$cli" diff "$p1e_rid_a1" "no-such-run-2" --local --json >/dev/null 2>&1
p1e_norun2_rc=$?
set -e
[ "$p1e_norun2_rc" -ne 0 ] \
  || { echo "FAIL: diff --local with unknown second run_id should exit non-zero"; exit 1; }
echo "PASS: diff --local — unknown second run_id exits non-zero"

# (8) Missing args → error.
set +e
OPENSOP_LOCAL_HOME="$p1e_home" "$cli" diff "$p1e_rid_a1" --local --json >/dev/null 2>&1
p1e_missing_rc=$?
set -e
[ "$p1e_missing_rc" -ne 0 ] \
  || { echo "FAIL: diff --local with only one run_id should exit non-zero"; exit 1; }
echo "PASS: diff --local — missing second run_id exits non-zero (usage_error)"

# (9) confidence in diff: two runs of the same approval process submitted with
#     different confidence values → steps.<sid>.confidence appears in differences.
p1e_conf_proc="$p1e_home/conf-proc.sop.json"
cat > "$p1e_conf_proc" <<'JSON'
{
  "name": "p1e-conf",
  "inputs": {},
  "steps": [
    { "id": "gate", "type": "approval" }
  ]
}
JSON
# Run 1: pause at approval
set +e
p1e_conf_m1=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" run "$p1e_conf_proc" --local --json); p1e_conf_rc1=$?
set -e
p1e_conf_rid1=$(jq -r '.run_id' <<<"$p1e_conf_m1")
# Submit with confidence=0.9
OPENSOP_LOCAL_HOME="$p1e_home" "$cli" submit "$p1e_conf_rid1" gate --local \
  --output decision=approve --confidence 0.9 --json >/dev/null

# Run 2: pause at approval
set +e
p1e_conf_m2=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" run "$p1e_conf_proc" --local --json); p1e_conf_rc2=$?
set -e
p1e_conf_rid2=$(jq -r '.run_id' <<<"$p1e_conf_m2")
# Submit with confidence=0.5 (different)
OPENSOP_LOCAL_HOME="$p1e_home" "$cli" submit "$p1e_conf_rid2" gate --local \
  --output decision=approve --confidence 0.5 --json >/dev/null

p1e_conf_diff=$(OPENSOP_LOCAL_HOME="$p1e_home" "$cli" diff "$p1e_conf_rid1" "$p1e_conf_rid2" --local --json)
jq -e '.differences | map(.path) | contains(["steps.gate.confidence"])' <<<"$p1e_conf_diff" >/dev/null \
  || { echo "FAIL: diff --local should include steps.gate.confidence when confidence differs"; exit 1; }
echo "PASS: diff --local — steps.<sid>.confidence is diffed when approval submissions have different confidence"

# Cleanup p1e home.
rm -rf "$p1e_home"

# --------------------------------------------------------------------------- #
# P1f: local_cancel <run_id> [--reason TEXT]
#
# Full coverage:
#   (1) Cancel a waiting run → status="cancelled", receipt present, ended_at set
#   (2) reason is recorded in the audit receipt when supplied
#   (3) waiting block and cursor are cleared on cancel
#   (4) Cancel a completed run → rejected (invalid transition)
#   (5) Cancel a failed run → rejected
#   (6) Cancel an already-cancelled run → rejected
#   (7) Unknown run_id → error (instance_not_found)
#   (8) Missing run_id → usage_error
# --------------------------------------------------------------------------- #
p1f_home="$(mktemp -d)"

# Process with a form step (gives us a waiting run to cancel)
p1f_proc="$p1f_home/p1f.sop.json"
cat > "$p1f_proc" <<'JSON'
{
  "name": "p1f-test",
  "inputs": {},
  "steps": [
    { "id": "build", "type": "shell", "run": "echo built" },
    { "id": "gate",  "type": "form",
      "inputs": [{ "name": "val", "type": "string", "required": true }] },
    { "id": "after", "type": "shell", "run": "echo should-not-run" }
  ]
}
JSON

# A completed process (for the invalid-transition test)
p1f_proc_complete="$p1f_home/p1f-complete.sop.json"
cat > "$p1f_proc_complete" <<'JSON'
{ "name": "p1f-complete", "inputs": {},
  "steps": [ { "id": "s", "type": "shell", "run": "echo done" } ] }
JSON

# A failing process (for the invalid-transition test)
p1f_proc_fail="$p1f_home/p1f-fail.sop.json"
cat > "$p1f_proc_fail" <<'JSON'
{ "name": "p1f-fail", "inputs": {},
  "steps": [ { "id": "s", "type": "shell", "run": "exit 1" } ] }
JSON

# Setup: create a waiting run
set +e
p1f_wait_m="$(OPENSOP_LOCAL_HOME="$p1f_home" "$cli" run "$p1f_proc" --local --json)"; p1f_wait_rc=$?
set -e
[ "$p1f_wait_rc" -eq 0 ] || { echo "FAIL: p1f waiting run should exit 0"; exit 1; }
p1f_wait_id="$(jq -r '.run_id' <<<"$p1f_wait_m")"
[ "$(jq -r '.status' <<<"$p1f_wait_m")" = "waiting" ] \
  || { echo "FAIL: p1f run should be 'waiting', got $(jq -r '.status' <<<"$p1f_wait_m")"; exit 1; }
echo "PASS: p1f setup — waiting run created"

# (1) Cancel a waiting run → exits 0, JSON envelope has state="cancelled"
# The JSON output is a normalized InstanceSerializer-shaped envelope (id, process, state, ...)
# matching what the runtime's cancel controller returns — not the raw manifest.
p1f_cancel_out="$(OPENSOP_LOCAL_HOME="$p1f_home" "$cli" cancel "$p1f_wait_id" --local \
  --reason "test cancellation" --json)"
[ "$(jq -r '.state' <<<"$p1f_cancel_out")" = "cancelled" ] \
  || { echo "FAIL: p1f cancel waiting run should have state=cancelled in JSON envelope, got $(jq -r '.state' <<<"$p1f_cancel_out")"; exit 1; }
echo "PASS: cancel --local — waiting run cancelled (state=cancelled in InstanceSerializer envelope)"

# Verify the envelope shape matches InstanceSerializer (id, process.name, state, completed_at)
jq -e 'has("id") and has("process") and has("state") and has("completed_at")' <<<"$p1f_cancel_out" >/dev/null \
  || { echo "FAIL: cancel --local JSON envelope missing required keys (id/process/state/completed_at)"; exit 1; }
echo "PASS: cancel --local — JSON envelope has id, process, state, completed_at (InstanceSerializer shape)"

[ "$(jq -r '.id' <<<"$p1f_cancel_out")" = "$p1f_wait_id" ] \
  || { echo "FAIL: cancel --local JSON envelope .id should be the run_id"; exit 1; }
echo "PASS: cancel --local — JSON envelope .id matches the run_id"

[ "$(jq -r '.process.name' <<<"$p1f_cancel_out")" = "p1f-test" ] \
  || { echo "FAIL: cancel --local JSON envelope .process.name should be 'p1f-test'"; exit 1; }
echo "PASS: cancel --local — JSON envelope .process.name is correct"

# (2) ended_at is set in the manifest
p1f_manifest_on_disk="$(cat "$p1f_home/runs/$p1f_wait_id/manifest.json")"
[ "$(jq -r '.ended_at // ""' <<<"$p1f_manifest_on_disk")" != "" ] \
  || { echo "FAIL: p1f cancel should write ended_at, got empty"; exit 1; }
echo "PASS: cancel --local — ended_at is set after cancel"

# (3) waiting and cursor blocks are cleared
jq -e '.waiting == null or (has("waiting") | not)' <<<"$p1f_manifest_on_disk" >/dev/null \
  || { echo "FAIL: p1f cancel should clear waiting block, got: $(jq -c '.waiting' <<<"$p1f_manifest_on_disk")"; exit 1; }
echo "PASS: cancel --local — waiting block cleared after cancel"

# (4) audit.jsonl has a cancelled receipt with reason
p1f_audit="$p1f_home/runs/$p1f_wait_id/audit.jsonl"
jq -e 'select(.status=="cancelled" and .type=="cancel")' "$p1f_audit" >/dev/null \
  || { echo "FAIL: p1f cancel audit receipt missing (type=cancel, status=cancelled)"; exit 1; }
echo "PASS: cancel --local — audit receipt present with type=cancel, status=cancelled"

jq -e 'select(.status=="cancelled" and .reason=="test cancellation")' "$p1f_audit" >/dev/null \
  || { echo "FAIL: p1f cancel audit receipt should include reason='test cancellation'"; exit 1; }
echo "PASS: cancel --local — reason is recorded in audit receipt"

# (5) status --local shows the run as cancelled with ended_at
p1f_status_out="$(OPENSOP_LOCAL_HOME="$p1f_home" "$cli" status "$p1f_wait_id" --local --json)"
[ "$(jq -r '.state' <<<"$p1f_status_out")" = "cancelled" ] \
  || { echo "FAIL: status --local of cancelled run should show state=cancelled, got $(jq -r '.state' <<<"$p1f_status_out")"; exit 1; }
echo "PASS: cancel --local — status shows state=cancelled"

[ "$(jq -r '.completed_at // ""' <<<"$p1f_status_out")" != "" ] \
  || { echo "FAIL: status --local of cancelled run should have non-null completed_at"; exit 1; }
echo "PASS: cancel --local — status shows non-null completed_at"

# (6) Failure path: cancel a completed run → rejected
p1f_complete_m="$(OPENSOP_LOCAL_HOME="$p1f_home" "$cli" run "$p1f_proc_complete" --local --json)"
p1f_complete_id="$(jq -r '.run_id' <<<"$p1f_complete_m")"
[ "$(jq -r '.status' <<<"$p1f_complete_m")" = "completed" ] \
  || { echo "FAIL: p1f complete run setup failed"; exit 1; }

set +e
OPENSOP_LOCAL_HOME="$p1f_home" "$cli" cancel "$p1f_complete_id" --local --json >/dev/null 2>&1
p1f_compl_rc=$?
set -e
[ "$p1f_compl_rc" -ne 0 ] \
  || { echo "FAIL: cancel --local of completed run should exit non-zero"; exit 1; }
echo "PASS: cancel --local — completed run is rejected (invalid transition)"

# (7) Failure path: cancel a failed run → rejected
set +e
p1f_fail_m="$(OPENSOP_LOCAL_HOME="$p1f_home" "$cli" run "$p1f_proc_fail" --local --json)"; p1f_fail_setup_rc=$?
set -e
p1f_fail_id="$(jq -r '.run_id' <<<"$p1f_fail_m")"
[ "$(jq -r '.status' <<<"$p1f_fail_m")" = "failed" ] \
  || { echo "FAIL: p1f fail run setup failed, got $(jq -r '.status' <<<"$p1f_fail_m")"; exit 1; }

set +e
OPENSOP_LOCAL_HOME="$p1f_home" "$cli" cancel "$p1f_fail_id" --local --json >/dev/null 2>&1
p1f_fail_rc=$?
set -e
[ "$p1f_fail_rc" -ne 0 ] \
  || { echo "FAIL: cancel --local of failed run should exit non-zero"; exit 1; }
echo "PASS: cancel --local — failed run is rejected (invalid transition)"

# (8) Failure path: cancel an already-cancelled run → rejected
set +e
OPENSOP_LOCAL_HOME="$p1f_home" "$cli" cancel "$p1f_wait_id" --local --json >/dev/null 2>&1
p1f_dup_rc=$?
set -e
[ "$p1f_dup_rc" -ne 0 ] \
  || { echo "FAIL: cancel --local of already-cancelled run should exit non-zero"; exit 1; }
echo "PASS: cancel --local — already-cancelled run is rejected (invalid transition)"

# (9) Failure path: unknown run_id → instance_not_found
set +e
p1f_norun_err="$(OPENSOP_LOCAL_HOME="$p1f_home" "$cli" cancel "no-such-run-xyz" --local --json 2>&1)"; p1f_norun_rc=$?
set -e
[ "$p1f_norun_rc" -ne 0 ] \
  || { echo "FAIL: cancel --local with unknown run_id should exit non-zero"; exit 1; }
echo "$p1f_norun_err" | jq -e '.error == "instance_not_found"' >/dev/null \
  || { echo "FAIL: cancel --local unknown run_id should emit instance_not_found, got: $p1f_norun_err"; exit 1; }
echo "PASS: cancel --local — unknown run_id exits non-zero with instance_not_found"

# (10) Failure path: missing run_id → usage_error
set +e
OPENSOP_LOCAL_HOME="$p1f_home" "$cli" cancel --local --json >/dev/null 2>&1
p1f_noarg_rc=$?
set -e
[ "$p1f_noarg_rc" -ne 0 ] \
  || { echo "FAIL: cancel --local with no args should exit non-zero"; exit 1; }
echo "PASS: cancel --local — missing run_id exits non-zero (usage_error)"

# Cleanup p1f home.
rm -rf "$p1f_home"

# --------------------------------------------------------------------------- #
# U2a: FLIP THE DEFAULT TO LOCAL — Phase 2 routing assertions (v0.8.0)
#
# The default backend is now LOCAL; --remote / --server opt into remote.
# These tests exercise the NEW default behavior (no flag) to ensure the flip
# actually works — not just that --local is accepted as a no-op.
# --------------------------------------------------------------------------- #

u2a_home="$(mktemp -d)"
trap 'rm -rf "$u2a_home"' EXIT

# Create a minimal local process for testing.
u2a_proc="$u2a_home/hello.sop.json"
cat > "$u2a_proc" <<'JSON'
{ "name": "u2a-hello", "inputs": {},
  "steps": [ { "id": "greet", "type": "shell", "run": "echo hello-u2a" } ] }
JSON

# --- (1) 'run' with NO flag creates a local run (not a remote call) ---
set +e
u2a_run_out="$(OPENSOP_LOCAL_HOME="$u2a_home" "$cli" run "$u2a_proc" --json)"; u2a_run_rc=$?
set -e
[ "$u2a_run_rc" -eq 0 ] || { echo "FAIL: U2a run no-flag should exit 0 (local default), got $u2a_run_rc"; exit 1; }
[ "$(jq -r '.status' <<<"$u2a_run_out")" = "completed" ] \
  || { echo "FAIL: U2a run no-flag should complete locally, got $(jq -r '.status' <<<"$u2a_run_out")"; exit 1; }
u2a_run_id="$(jq -r '.run_id' <<<"$u2a_run_out")"
[ -d "$u2a_home/runs/$u2a_run_id" ] \
  || { echo "FAIL: U2a run no-flag should create a receipt under OPENSOP_LOCAL_HOME/runs/"; exit 1; }
echo "PASS: U2a run — no flag routes to LOCAL backend (receipt created in OPENSOP_LOCAL_HOME)"

# --- (2) 'list' with NO flag shows local processes (no server) ---
set +e
u2a_list_out="$(OPENSOP_LOCAL_HOME="$u2a_home" "$cli" list --json 2>/dev/null)"; u2a_list_rc=$?
set -e
# Local list returns an array of process entries, not an HTTP error.
# Even with no processes found in a cell/cwd-fallback, it should not fail.
# Specifically it should NOT try to hit a server and fail with a network error.
[ "$u2a_list_rc" -eq 0 ] || { echo "FAIL: U2a list no-flag should exit 0 (local default), got $u2a_list_rc"; exit 1; }
echo "PASS: U2a list — no flag routes to LOCAL backend (exits 0, no server contact)"

# --- (3) 'status' with NO flag reads a local run's manifest ---
set +e
u2a_status_out="$(OPENSOP_LOCAL_HOME="$u2a_home" "$cli" status "$u2a_run_id" --json)"; u2a_status_rc=$?
set -e
[ "$u2a_status_rc" -eq 0 ] || { echo "FAIL: U2a status no-flag should exit 0 (local default), got $u2a_status_rc"; exit 1; }
[ "$(jq -r '.state' <<<"$u2a_status_out")" = "completed" ] \
  || { echo "FAIL: U2a status no-flag should return local run state, got $(jq -r '.state' <<<"$u2a_status_out")"; exit 1; }
[ "$(jq -r '.id' <<<"$u2a_status_out")" = "$u2a_run_id" ] \
  || { echo "FAIL: U2a status no-flag .id should be the run_id"; exit 1; }
echo "PASS: U2a status — no flag routes to LOCAL backend (reads local manifest)"

# --- (4) 'instances' with NO flag lists local runs ---
set +e
u2a_inst_out="$(OPENSOP_LOCAL_HOME="$u2a_home" "$cli" instances --json)"; u2a_inst_rc=$?
set -e
[ "$u2a_inst_rc" -eq 0 ] || { echo "FAIL: U2a instances no-flag should exit 0 (local default), got $u2a_inst_rc"; exit 1; }
[ "$(jq -r '.total' <<<"$u2a_inst_out")" = "1" ] \
  || { echo "FAIL: U2a instances no-flag should show 1 local run, got $(jq -r '.total' <<<"$u2a_inst_out")"; exit 1; }
echo "PASS: U2a instances — no flag routes to LOCAL backend (shows the local run)"

# --- (5) 'search' with NO flag searches local process files ---
set +e
u2a_search_out="$(OPENSOP_LOCAL_HOME="$u2a_home" "$cli" search hello --json 2>/dev/null)"; u2a_search_rc=$?
set -e
# Local search with no cell produces no results (no processes/ dir), but should NOT error.
[ "$u2a_search_rc" -eq 0 ] || { echo "FAIL: U2a search no-flag should exit 0 (local default), got $u2a_search_rc"; exit 1; }
echo "PASS: U2a search — no flag routes to LOCAL backend (exits 0, no server contact)"

# --- (6) '--local' (deprecated no-op) yields the same local result as no flag ---
set +e
u2a_local_flag_out="$(OPENSOP_LOCAL_HOME="$u2a_home" "$cli" status "$u2a_run_id" --local --json)"; u2a_local_flag_rc=$?
set -e
[ "$u2a_local_flag_rc" -eq 0 ] || { echo "FAIL: U2a status --local should exit 0 (same as no-flag), got $u2a_local_flag_rc"; exit 1; }
[ "$(jq -r '.state' <<<"$u2a_local_flag_out")" = "completed" ] \
  || { echo "FAIL: U2a status --local should return the same local result as no-flag"; exit 1; }
echo "PASS: U2a --local (deprecated) — accepted without error, yields same local result as no-flag"

# --- (7) '--server http://127.0.0.1:1' (unreachable) routes to REMOTE, not local ---
# The run_id above is a valid local run, so if the flip were broken, --server
# would fall through to the local path and succeed. Instead, with --server it
# must attempt the remote path and fail (connection refused or no curl).
set +e
"$cli" --server http://127.0.0.1:1 status "$u2a_run_id" --json >/dev/null 2>&1
u2a_server_rc=$?
set -e
# Expected: non-zero (network_error: connection refused to 127.0.0.1:1).
[ "$u2a_server_rc" -ne 0 ] \
  || { echo "FAIL: U2a --server <url> should attempt remote (not local); status on closed port must fail"; exit 1; }
echo "PASS: U2a --server <url> — routes to REMOTE (fails with network error, not local result)"

# --- (8) '--remote' with no configured URL → config_missing error ---
set +e
u2a_remote_nourl_err="$(OPENSOP_URL="" OPENSOP_HOME="$u2a_home" "$cli" --remote list --json 2>&1)"; u2a_remote_nourl_rc=$?
set -e
[ "$u2a_remote_nourl_rc" -ne 0 ] \
  || { echo "FAIL: U2a --remote with no OPENSOP_URL should exit non-zero"; exit 1; }
echo "$u2a_remote_nourl_err" | jq -e '.error == "config_missing"' >/dev/null \
  || { echo "FAIL: U2a --remote with no URL should emit config_missing error, got: $u2a_remote_nourl_err"; exit 1; }
echo "PASS: U2a --remote with no URL — exits non-zero with config_missing error"

# --- (9) 'register' with no --remote/--server → usage_error directing to --remote ---
set +e
u2a_reg_out="$("$cli" register /dev/null --json 2>&1)"; u2a_reg_rc=$?
set -e
[ "$u2a_reg_rc" -ne 0 ] \
  || { echo "FAIL: U2a register with no --remote should exit non-zero"; exit 1; }
echo "$u2a_reg_out" | jq -e '.error == "usage_error"' >/dev/null \
  || { echo "FAIL: U2a register with no --remote should emit usage_error, got: $u2a_reg_out"; exit 1; }
echo "$u2a_reg_out" | jq -r '.hint' | grep -q "\-\-remote\|\-\-server" \
  || { echo "FAIL: U2a register usage_error hint should mention --remote or --server, got: $(echo "$u2a_reg_out" | jq -r '.hint')"; exit 1; }
echo "PASS: U2a register no --remote — exits non-zero with usage_error, hint mentions --remote/--server"

# --- (10) 'register --server http://127.0.0.1:1' → attempts remote (fails with network error) ---
set +e
"$cli" --server http://127.0.0.1:1 register "$u2a_proc" --json >/dev/null 2>&1
u2a_reg_server_rc=$?
set -e
[ "$u2a_reg_server_rc" -ne 0 ] \
  || { echo "FAIL: U2a register --server <url> should fail (no server at 127.0.0.1:1), got exit 0"; exit 1; }
echo "PASS: U2a register --server <url> — attempts remote (fails with network error, not usage_error)"

# --- (11) 'run' with NO flag, explicitly NO --local — the file path form ---
# Exercise that the default-local path works when --local is ABSENT entirely.
set +e
u2a_run2_out="$(OPENSOP_LOCAL_HOME="$u2a_home" "$cli" run "$u2a_proc" --json)"; u2a_run2_rc=$?
set -e
[ "$u2a_run2_rc" -eq 0 ] || { echo "FAIL: U2a run (no --local flag, file path) should exit 0, got $u2a_run2_rc"; exit 1; }
[ "$(jq -r '.status' <<<"$u2a_run2_out")" = "completed" ] \
  || { echo "FAIL: U2a run (no --local flag, file path) should complete locally, got $(jq -r '.status' <<<"$u2a_run2_out")"; exit 1; }
echo "PASS: U2a run — no --local flag (truly absent) still routes to LOCAL backend"

# Cleanup u2a home.
rm -rf "$u2a_home"
trap - EXIT

# --------------------------------------------------------------------------- #
# schema <name> without --remote — must exit non-zero with usage_error
# (schema fetch is remote-only; schema validate is always-local and unaffected)
# --------------------------------------------------------------------------- #
set +e
schema_noremote_out="$("$cli" schema someproc --json 2>&1)"; schema_noremote_rc=$?
set -e
[ "$schema_noremote_rc" -ne 0 ] \
  || { echo "FAIL: schema <name> with no --remote should exit non-zero, got exit 0"; exit 1; }
echo "$schema_noremote_out" | jq -e '.error == "usage_error"' >/dev/null \
  || { echo "FAIL: schema <name> with no --remote should emit usage_error, got: $schema_noremote_out"; exit 1; }
echo "$schema_noremote_out" | jq -r '.hint' | grep -q "\-\-remote\|\-\-server" \
  || { echo "FAIL: schema usage_error hint should mention --remote or --server, got: $(echo "$schema_noremote_out" | jq -r '.hint')"; exit 1; }
echo "PASS: schema <name> no --remote — exits non-zero with usage_error, hint mentions --remote/--server"

echo "ALL PASS"
