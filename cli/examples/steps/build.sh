#!/usr/bin/env bash
# Example automated step for opensop-local.
# Input: the accumulated run context arrives on stdin AND in $OSL_CONTEXT (JSON).
# Output: print a JSON object to stdout — opensop-local merges it into the run
#         context under this step's id ("build"). Non-JSON stdout is stored as
#         {"stdout": "..."}. A non-zero exit fails the step.
set -uo pipefail
ctx="${OSL_CONTEXT:-$(cat)}"
name="$(jq -r '.name // "world"' <<<"$ctx")"
jq -nc --arg g "hello, $name" --arg w "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{greeting:$g, when:$w}'
