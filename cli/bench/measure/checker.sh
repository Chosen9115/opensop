#!/usr/bin/env bash
# measure/checker.sh — field-level reliability checker for action-items output.
#
# Sourced (not executed) by run-bench.sh and test-bench.sh.
#
# Exports one function: check_output <raw_json_text> <expected_json_file>
# Prints a JSON result to stdout:
#   { "schema_valid": bool, "field_match": bool, "detail": "..." }
#
# Schema validity: output must be valid JSON with a top-level "action_items" array
# whose items each have non-empty string "owner" and "task" fields.
#
# Field-level match: the set of (owner, task) pairs (lowercased, jq -S sorted)
# must equal the set in expected.json. Order-insensitive. Case-insensitive on
# owner/task comparison via lowercase normalisation.
#
# No external deps beyond bash + jq.

check_output() {
  local raw_text="$1"
  local expected_file="$2"

  # --- Schema validity ---
  local parsed schema_valid=false schema_detail=""
  if ! parsed="$(jq -e 'type == "object"' <<<"$raw_text" >/dev/null 2>&1 && echo "$raw_text")"; then
    schema_detail="output is not a JSON object"
    jq -nc --arg d "$schema_detail" '{schema_valid:false,field_match:false,detail:$d}'
    return 0
  fi
  parsed="$raw_text"

  # Check top-level "action_items" key exists and is an array.
  local items_check
  items_check="$(jq -r '
    if .action_items == null then "missing action_items key"
    elif (.action_items | type) != "array" then "action_items is not an array"
    elif (.action_items | length) == 0 then "action_items array is empty"
    else
      [ .action_items[] |
        if (.owner | type) != "string" or (.owner | length) == 0 then "item missing owner string"
        elif (.task  | type) != "string" or (.task  | length) == 0 then "item missing task string"
        else empty end
      ] | if length == 0 then "ok" else .[0] end
    end
  ' <<<"$parsed" 2>/dev/null)"

  if [[ "$items_check" != "ok" ]]; then
    schema_detail="${items_check:-schema check failed}"
    jq -nc --arg d "$schema_detail" '{schema_valid:false,field_match:false,detail:$d}'
    return 0
  fi
  schema_valid=true

  # --- Field-level match ---
  # Normalise: lowercase owner+task, sort the set, compare canonical JSON.
  local got_set expected_set
  got_set="$(jq -c '
    [ .action_items[] | {owner:(.owner|ascii_downcase|ltrimstr(" ")|rtrimstr(" ")),
                         task:(.task|ascii_downcase|ltrimstr(" ")|rtrimstr(" "))} ]
    | sort_by(.owner)
  ' <<<"$parsed" 2>/dev/null)"

  expected_set="$(jq -c '
    [ .action_items[] | {owner:(.owner|ascii_downcase|ltrimstr(" ")|rtrimstr(" ")),
                         task:(.task|ascii_downcase|ltrimstr(" ")|rtrimstr(" "))} ]
    | sort_by(.owner)
  ' "$expected_file" 2>/dev/null)"

  if [[ "$got_set" == "$expected_set" ]]; then
    jq -nc '{schema_valid:true,field_match:true,detail:"all items match"}'
  else
    # Produce a diff summary: which owners are wrong or missing.
    local detail
    detail="$(jq -rn \
      --argjson got "$got_set" \
      --argjson exp "$expected_set" \
      '
        ($exp | map(.owner)) as $exp_owners |
        ($got | map(.owner)) as $got_owners |
        ([ $exp[] | select(. as $e | ($got_owners | map(select(. == $e.owner))) | length == 0) | "missing owner: \(.owner)" ]) as $missing |
        ([ $got[] | select(. as $g | ($exp_owners | map(select(. == $g.owner))) | length == 0) | "unexpected owner: \(.owner)" ]) as $extra |
        ([ $exp[] | . as $e |
           ($got[] | select(.owner == $e.owner)) | . as $g |
           select($g.task != $e.task) |
           "wrong task for \($e.owner): got \($g.task | @json)" ]) as $wrong_task |
        ($missing + $extra + $wrong_task) |
        if length == 0 then "count or order mismatch" else join("; ") end
      ' 2>/dev/null || echo "diff computation failed")"
    jq -nc --arg d "$detail" '{schema_valid:true,field_match:false,detail:$d}'
  fi
}
