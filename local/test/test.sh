#!/usr/bin/env bash
# Golden test for the local runtime: run the greet example, assert the rendered
# output, context threading, and per-step audit receipts. Requires bash + jq.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
export OPENSOP_LOCAL_HOME="$(mktemp -d)"
trap 'rm -rf "$OPENSOP_LOCAL_HOME"' EXIT

run_dir="$("$here/bin/opensop-local" run "$here/examples/greet.sop.json" --input name=opensop 2>/dev/null)"
ctx="$run_dir/context.json"; audit="$run_dir/audit.jsonl"

out="$(jq -r '.render.stdout' "$ctx")"
echo "render -> $out"
echo "$out" | grep -q "hello, opensop" || { echo "FAIL: expected greeting not rendered"; exit 1; }

jq -e 'select(.step=="build"  and .status=="completed")' "$audit" >/dev/null || { echo "FAIL: build receipt missing/failed"; exit 1; }
jq -e 'select(.step=="render" and .status=="completed")' "$audit" >/dev/null || { echo "FAIL: render receipt missing/failed"; exit 1; }
# render must NOT have leaked the build step's output (regression guard)
jq -e 'select(.step=="render") | .output | has("greeting")' "$audit" >/dev/null 2>&1 && { echo "FAIL: render leaked build output"; exit 1; }

echo "PASS: 2 steps ran, context threaded, receipts written, no step-output leak"
