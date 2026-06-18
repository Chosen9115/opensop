#!/usr/bin/env bash
# =============================================================================
# Golden test for the opensop-mcp stdio server.
#
# Drives `mcp/opensop-mcp` by piping newline-delimited JSON-RPC 2.0 lines into
# it and asserting on the response lines (parsed with jq). The server reads
# until EOF then exits, so each scenario is one fresh process fed its own
# stream; responses are filtered by `.id`.
#
# Style mirrors cli/test/test.sh: plain bash under `set -e`, PASS:/FAIL: lines,
# exits non-zero on first failed assertion, ends with ALL PASS. Needs only
# bash + jq (the server shells out to the local CLI; no server, no curl).
# =============================================================================
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"          # mcp/
root="$(cd "$here/.." && pwd)"                     # repo root
server="$here/opensop-mcp"
cli="$root/cli/bin/opensop"
greet="$root/cli/examples/greet.sop.json"

[ -x "$server" ] || { echo "FAIL: server not found/executable at $server"; exit 1; }
[ -x "$cli" ]    || { echo "FAIL: CLI not found/executable at $cli"; exit 1; }
[ -f "$greet" ]  || { echo "FAIL: greet example not found at $greet"; exit 1; }

# The server resolves the CLI via OPENSOP_BIN; receipts land in a temp home.
export OPENSOP_BIN="$cli"
export OPENSOP_LOCAL_HOME="$(mktemp -d)"
work="$(mktemp -d)"
trap 'rm -rf "$OPENSOP_LOCAL_HOME" "$work"' EXIT

# --------------------------------------------------------------------------- #
# Fixture corpus: a cell with two object-form processes for discovery, plus
# the committed greet example (object-form inputs) for the run/submit loop.
# (Array-form inputs currently break the run engine, so we keep object-form.)
# --------------------------------------------------------------------------- #
cell="$work/cell"
mkdir -p "$cell/processes"
( cd "$cell" && env -u OPENSOP_LOCAL_HOME "$cli" init --json >/dev/null )

cat > "$cell/processes/onboard.sop.json" <<'JSON'
{ "name": "onboard-customer",
  "description": "Onboard a new customer account and send a welcome email",
  "tags": ["sales", "onboarding"],
  "inputs": { "name": { "type": "string" } },
  "steps": [ { "id": "greet", "type": "shell", "run": "echo welcome" } ] }
JSON
cat > "$cell/processes/deploy.sop.json" <<'JSON'
{ "name": "deploy-release",
  "description": "Deploy a tagged release to production",
  "tags": ["ops", "deploy"],
  "inputs": { "tag": { "type": "string" } },
  "steps": [ { "id": "ship", "type": "shell", "run": "echo shipped" } ] }
JSON
# A "lead" process so the glob-safe search case (keywords "* lead") matches at
# least one result and the CLI emits its JSON {query,results} envelope.
cat > "$cell/processes/lead.sop.json" <<'JSON'
{ "name": "qualify-lead",
  "description": "Qualify a new inbound sales lead",
  "tags": ["sales", "lead"],
  "inputs": { "email": { "type": "string" } },
  "steps": [ { "id": "score", "type": "shell", "run": "echo scored" } ] }
JSON

# --------------------------------------------------------------------------- #
# Helpers: feed a stream of JSON-RPC lines into a fresh server and capture the
# response lines (stdout only — diagnostics go to stderr, which we drop).
# `drive` runs the server in default mode; `drive_ro` in readonly mode.
# Each argument is one line of input.
# --------------------------------------------------------------------------- #
drive() {
  printf '%s\n' "$@" | "$server" 2>/dev/null
}
drive_ro() {
  printf '%s\n' "$@" | OPENSOP_MCP_READONLY=1 "$server" 2>/dev/null
}

# Pull the single response object whose .id matches, from a captured stream.
by_id() {  # <stream> <id>
  jq -c --argjson want "$2" 'select(.id == $want)' <<<"$1"
}

# --------------------------------------------------------------------------- #
# 1. initialize
# --------------------------------------------------------------------------- #
init_line='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{}}}'
out="$(drive "$init_line")"
r="$(by_id "$out" 1)"
[ "$(jq -r '.result.serverInfo.name' <<<"$r")" = "opensop" ] \
  || { echo "FAIL: initialize serverInfo.name should be 'opensop'"; exit 1; }
[ "$(jq -r '.result.protocolVersion' <<<"$r")" = "2025-03-26" ] \
  || { echo "FAIL: initialize should echo client protocolVersion '2025-03-26', got $(jq -r '.result.protocolVersion' <<<"$r")"; exit 1; }
jq -e '.result.capabilities | has("tools")' <<<"$r" >/dev/null \
  || { echo "FAIL: initialize result.capabilities should advertise tools"; exit 1; }
echo "PASS: initialize — serverInfo.name=opensop, protocolVersion echoed, capabilities.tools present"

# --------------------------------------------------------------------------- #
# 2. notification produces no response line
#    Stream: initialize (id 1) + notifications/initialized (no id) + tools/list
#    (id 2). Exactly 2 response lines expected — the notification yields none.
# --------------------------------------------------------------------------- #
out="$(drive \
  "$init_line" \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
nlines="$(grep -c . <<<"$out")"
[ "$nlines" = "2" ] \
  || { echo "FAIL: expected 2 response lines (notification gets none), got $nlines"; exit 1; }
jq -e 'select(.id == 1)' <<<"$out" >/dev/null || { echo "FAIL: missing initialize response"; exit 1; }
jq -e 'select(.id == 2)' <<<"$out" >/dev/null || { echo "FAIL: missing tools/list response"; exit 1; }
echo "PASS: notification — notifications/initialized produces no response line (2 of 3 messages answered)"

# --------------------------------------------------------------------------- #
# 3. tools/list — 9 tools by default; specific names present
# --------------------------------------------------------------------------- #
out="$(drive '{"jsonrpc":"2.0","id":3,"method":"tools/list"}')"
r="$(by_id "$out" 3)"
[ "$(jq -r '.result.tools | length' <<<"$r")" = "9" ] \
  || { echo "FAIL: default tools/list should expose 9 tools, got $(jq -r '.result.tools | length' <<<"$r")"; exit 1; }
for t in opensop_list opensop_search opensop_suggest opensop_dry_run \
         opensop_run opensop_status opensop_submit opensop_show opensop_runs; do
  jq -e --arg n "$t" '.result.tools | map(.name) | index($n)' <<<"$r" >/dev/null \
    || { echo "FAIL: tools/list missing tool '$t'"; exit 1; }
done
echo "PASS: tools/list — 9 tools present (all expected names)"

# --------------------------------------------------------------------------- #
# 4. readonly mode — 7 tools, no run/submit, and a run call is refused
# --------------------------------------------------------------------------- #
out="$(drive_ro '{"jsonrpc":"2.0","id":4,"method":"tools/list"}')"
r="$(by_id "$out" 4)"
[ "$(jq -r '.result.tools | length' <<<"$r")" = "7" ] \
  || { echo "FAIL: readonly tools/list should expose 7 tools, got $(jq -r '.result.tools | length' <<<"$r")"; exit 1; }
jq -e '.result.tools | map(.name) | index("opensop_run")' <<<"$r" >/dev/null \
  && { echo "FAIL: readonly mode should hide opensop_run"; exit 1; }
jq -e '.result.tools | map(.name) | index("opensop_submit")' <<<"$r" >/dev/null \
  && { echo "FAIL: readonly mode should hide opensop_submit"; exit 1; }
echo "PASS: readonly — tools/list has 7 tools, opensop_run and opensop_submit hidden"

out="$(drive_ro '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"opensop_run","arguments":{"process":"'"$greet"'"}}}')"
r="$(by_id "$out" 5)"
[ "$(jq -r '.result.isError' <<<"$r")" = "true" ] \
  || { echo "FAIL: readonly opensop_run call should be isError:true"; exit 1; }
jq -e '.result.content[0].text | test("readonly|disabled")' <<<"$r" >/dev/null \
  || { echo "FAIL: readonly refusal text should mention readonly/disabled"; exit 1; }
echo "PASS: readonly — tools/call opensop_run refused with isError:true mentioning readonly"

# --------------------------------------------------------------------------- #
# 5. happy-path discovery — suggest + search against the fixture corpus.
#    Run from inside the cell so the cell-chain resolution sees the corpus.
# --------------------------------------------------------------------------- #
out="$(cd "$cell" && drive '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"opensop_suggest","arguments":{"task":"onboard a new customer"}}}')"
r="$(by_id "$out" 6)"
[ "$(jq -r '.result.isError' <<<"$r")" = "false" ] \
  || { echo "FAIL: suggest should be isError:false"; exit 1; }
text="$(jq -r '.result.content[0].text' <<<"$r")"
jq -e '. as $o | (has("task") and has("match"))' <<<"$text" >/dev/null \
  || { echo "FAIL: suggest text should parse as JSON with keys {task,match}"; exit 1; }
[ "$(jq -r '.match.name' <<<"$text")" = "onboard-customer" ] \
  || { echo "FAIL: suggest should match onboard-customer, got $(jq -r '.match.name' <<<"$text")"; exit 1; }
echo "PASS: discovery — opensop_suggest returns isError:false, text parses as {task,match}"

out="$(cd "$cell" && drive '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"opensop_search","arguments":{"keywords":"deploy release"}}}')"
r="$(by_id "$out" 7)"
[ "$(jq -r '.result.isError' <<<"$r")" = "false" ] \
  || { echo "FAIL: search should be isError:false"; exit 1; }
text="$(jq -r '.result.content[0].text' <<<"$r")"
jq -e '(has("query") and has("results"))' <<<"$text" >/dev/null \
  || { echo "FAIL: search text should parse as JSON with keys {query,results}"; exit 1; }
jq -e '.results | map(.name) | index("deploy-release")' <<<"$text" >/dev/null \
  || { echo "FAIL: search 'deploy release' should surface deploy-release"; exit 1; }
echo "PASS: discovery — opensop_search returns isError:false, text parses as {query,results}"

# --------------------------------------------------------------------------- #
# 6. run → status loop (non-readonly), plus runs + show.
#    Run the greet example, capture its run_id from the result text, then
#    status/show/runs against it.
# --------------------------------------------------------------------------- #
out="$(drive '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"opensop_run","arguments":{"process":"'"$greet"'","inputs":{"name":"alice"}}}}')"
r="$(by_id "$out" 8)"
[ "$(jq -r '.result.isError' <<<"$r")" = "false" ] \
  || { echo "FAIL: opensop_run greet should be isError:false"; exit 1; }
runtext="$(jq -r '.result.content[0].text' <<<"$r")"
[ "$(jq -r '.status' <<<"$runtext")" = "completed" ] \
  || { echo "FAIL: greet run status should be 'completed', got $(jq -r '.status' <<<"$runtext")"; exit 1; }
run_id="$(jq -r '.run_id' <<<"$runtext")"
[ -n "$run_id" ] && [ "$run_id" != "null" ] \
  || { echo "FAIL: opensop_run result text should carry a run_id"; exit 1; }
echo "PASS: run — opensop_run greet → isError:false, status 'completed', run_id captured"

out="$(drive '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"opensop_status","arguments":{"run_id":"'"$run_id"'"}}}')"
r="$(by_id "$out" 9)"
[ "$(jq -r '.result.isError' <<<"$r")" = "false" ] \
  || { echo "FAIL: opensop_status should be isError:false"; exit 1; }
text="$(jq -r '.result.content[0].text' <<<"$r")"
[ "$(jq -r '.state' <<<"$text")" = "completed" ] \
  || { echo "FAIL: status state should be 'completed', got $(jq -r '.state' <<<"$text")"; exit 1; }
[ "$(jq -r '.id' <<<"$text")" = "$run_id" ] \
  || { echo "FAIL: status .id should echo the run_id"; exit 1; }
echo "PASS: status — opensop_status on captured run_id → isError:false, state 'completed'"

out="$(drive '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"opensop_runs","arguments":{}}}')"
r="$(by_id "$out" 10)"
[ "$(jq -r '.result.isError' <<<"$r")" = "false" ] \
  || { echo "FAIL: opensop_runs should be isError:false"; exit 1; }
jq -e --arg rid "$run_id" '.result.content[0].text | test($rid)' <<<"$r" >/dev/null \
  || { echo "FAIL: opensop_runs output should list the run_id"; exit 1; }
echo "PASS: runs — opensop_runs lists the just-completed run"

out="$(drive '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"opensop_show","arguments":{"run_id":"'"$run_id"'"}}}')"
r="$(by_id "$out" 11)"
[ "$(jq -r '.result.isError' <<<"$r")" = "false" ] \
  || { echo "FAIL: opensop_show should be isError:false"; exit 1; }
text="$(jq -r '.result.content[0].text' <<<"$r")"
jq -e '.steps | length >= 2' <<<"$text" >/dev/null \
  || { echo "FAIL: show should return the run's step receipts"; exit 1; }
echo "PASS: show — opensop_show returns the run's audit trail with step receipts"

# --------------------------------------------------------------------------- #
# 7. error passthrough — status on a nonexistent run surfaces the CLI's
#    instance_not_found envelope through isError:true.
# --------------------------------------------------------------------------- #
out="$(drive '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"opensop_status","arguments":{"run_id":"no-such-run"}}}')"
r="$(by_id "$out" 12)"
[ "$(jq -r '.result.isError' <<<"$r")" = "true" ] \
  || { echo "FAIL: status on nonexistent run should be isError:true"; exit 1; }
jq -e '.result.content[0].text | test("instance_not_found")' <<<"$r" >/dev/null \
  || { echo "FAIL: status error text should contain 'instance_not_found'"; exit 1; }
echo "PASS: error passthrough — opensop_status nonexistent run → isError:true, text has instance_not_found"

# --------------------------------------------------------------------------- #
# 8. missing required arg — search with no keywords
# --------------------------------------------------------------------------- #
out="$(drive '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"opensop_search","arguments":{}}}')"
r="$(by_id "$out" 13)"
[ "$(jq -r '.result.isError' <<<"$r")" = "true" ] \
  || { echo "FAIL: search without keywords should be isError:true"; exit 1; }
jq -e '.result.content[0].text | test("missing required argument")' <<<"$r" >/dev/null \
  || { echo "FAIL: missing-arg text should say 'missing required argument'"; exit 1; }
echo "PASS: missing arg — opensop_search without keywords → isError:true 'missing required argument'"

# --------------------------------------------------------------------------- #
# 9. unknown tool
# --------------------------------------------------------------------------- #
out="$(drive '{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"opensop_nope","arguments":{}}}')"
r="$(by_id "$out" 14)"
[ "$(jq -r '.result.isError' <<<"$r")" = "true" ] \
  || { echo "FAIL: unknown tool should be isError:true"; exit 1; }
jq -e '.result.content[0].text | test("unknown tool")' <<<"$r" >/dev/null \
  || { echo "FAIL: unknown-tool text should say 'unknown tool'"; exit 1; }
echo "PASS: unknown tool — tools/call opensop_nope → isError:true 'unknown tool'"

# --------------------------------------------------------------------------- #
# 10. unknown JSON-RPC method (with id) → JSON-RPC error object, code -32601
# --------------------------------------------------------------------------- #
out="$(drive '{"jsonrpc":"2.0","id":15,"method":"does/not/exist"}')"
r="$(by_id "$out" 15)"
[ "$(jq -r '.error.code' <<<"$r")" = "-32601" ] \
  || { echo "FAIL: unknown method should return error.code -32601, got $(jq -r '.error.code' <<<"$r")"; exit 1; }
jq -e 'has("result") | not' <<<"$r" >/dev/null \
  || { echo "FAIL: unknown method response should carry no result"; exit 1; }
echo "PASS: unknown method — does/not/exist → error.code -32601"

# --------------------------------------------------------------------------- #
# 11. glob-safe search (HIGH-severity regression) — keywords containing `*`
#     must NOT pathname-expand against the CWD. Run from inside the cell (which
#     has a processes/ dir and files), so a regression would visibly turn `*`
#     into a list of CWD entries. Assert the parsed .query stays exactly
#     ["*","lead"] — the `*` survives as a literal token.
# --------------------------------------------------------------------------- #
out="$(cd "$cell" && drive '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"opensop_search","arguments":{"keywords":"* lead"}}}')"
r="$(by_id "$out" 16)"
[ "$(jq -r '.result.isError' <<<"$r")" = "false" ] \
  || { echo "FAIL: glob-safe search should be isError:false"; exit 1; }
text="$(jq -r '.result.content[0].text' <<<"$r")"
jq -e '.query == ["*","lead"]' <<<"$text" >/dev/null \
  || { echo "FAIL: search keywords '* lead' should yield .query == [\"*\",\"lead\"] (no glob expansion), got $(jq -c '.query' <<<"$text")"; exit 1; }
jq -e '.results | map(.name) | index("qualify-lead")' <<<"$text" >/dev/null \
  || { echo "FAIL: glob-safe search '* lead' should still surface qualify-lead"; exit 1; }
echo "PASS: glob-safe search — keywords '* lead' keep '*' literal, .query == [\"*\",\"lead\"]"

# --------------------------------------------------------------------------- #
# 12. notifications get no reply for KNOWN methods (JSON-RPC regression) —
#     stream: initialize (id 100) + an id-less tools/list NOTIFICATION + ping
#     (id 101). Exactly 2 response lines, with ids exactly {100,101}: the
#     id-less tools/list must produce NO response line, even though tools/list
#     is a known method (guards the regression where known methods replied to
#     notifications).
# --------------------------------------------------------------------------- #
out="$(drive \
  '{"jsonrpc":"2.0","id":100,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{}}}' \
  '{"jsonrpc":"2.0","method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":101,"method":"ping"}')"
nlines="$(grep -c . <<<"$out")"
[ "$nlines" = "2" ] \
  || { echo "FAIL: id-less tools/list must get no reply; expected 2 response lines, got $nlines"; exit 1; }
ids="$(jq -s -c 'map(.id) | sort' <<<"$out")"
[ "$ids" = "[100,101]" ] \
  || { echo "FAIL: response ids should be exactly [100,101] (notification yields none), got $ids"; exit 1; }
echo "PASS: notification (known method) — id-less tools/list yields no reply; ids == [100,101]"

echo "ALL PASS"
