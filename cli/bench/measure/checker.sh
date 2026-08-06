#!/usr/bin/env bash
# measure/checker.sh — field-level reliability checker for action-items output.
#
# Sourced (not executed) by run-bench.sh and test-bench.sh.
#
# Exports one function: check_output <raw_json_text> <expected_json_file>
# Prints a JSON result to stdout:
#   { "schema_valid": bool, "field_match": bool, "recall": int, "detail": "..." }
#
# Schema validity: output must be valid JSON with a top-level "action_items" array
# whose items each have non-empty string "owner" and "task" fields.
# [FIX3] Additionally enforces additionalProperties:false from action-items.schema.json:
#   - no extra top-level keys beyond "action_items"
#   - no extra per-item keys beyond "owner" and "task"
#
# Field-level match: the set of (owner, task) pairs (lowercased, jq -S sorted)
# must equal the set in expected.json. Order-insensitive. Case-insensitive on
# owner/task comparison via lowercase normalisation.
#
# [FIX2] Recall: count of expected (owner,task) pairs found in the output,
# regardless of extras. Reported as an integer (0..N where N = expected count).
# Recall is computed from action_items whenever the array is parseable, BEFORE
# applying additionalProperties checks — so schema-invalid outputs that still
# contain all expected items report full recall.
#
# No external deps beyond bash + jq.

check_output() {
  local raw_text="$1"
  local expected_file="$2"

  # --- Must be a JSON object ---
  local parsed
  if ! parsed="$(jq -e 'type == "object"' <<<"$raw_text" >/dev/null 2>&1 && echo "$raw_text")"; then
    jq -nc '{schema_valid:false,field_match:false,recall:0,detail:"output is not a JSON object"}'
    return 0
  fi
  parsed="$raw_text"

  # --- Recall: compute FIRST, from action_items if it exists and is a valid array.
  # [FIX2] Recall is independent of additionalProperties checks — an output with
  # extra keys that still contains all expected (owner,task) pairs gets full recall.
  local recall=0
  local _items_type
  _items_type="$(jq -r '.action_items | type' <<<"$parsed" 2>/dev/null || echo "null")"
  if [[ "$_items_type" == "array" ]]; then
    recall="$(jq -rn \
      --argjson got "$(jq -c '[.action_items[] | {owner:(.owner|ascii_downcase|ltrimstr(" ")|rtrimstr(" ")), task:(.task|ascii_downcase|ltrimstr(" ")|rtrimstr(" "))}] // []' <<<"$parsed" 2>/dev/null || echo '[]')" \
      --slurpfile exp "$expected_file" \
      '($exp[0].action_items |
        map({owner:(.owner|ascii_downcase|ltrimstr(" ")|rtrimstr(" ")),
             task:(.task|ascii_downcase|ltrimstr(" ")|rtrimstr(" "))}) |
        map(. as $e | if ($got | any(.owner == $e.owner and .task == $e.task)) then 1 else 0 end) |
        add // 0)' 2>/dev/null || echo 0)"
  fi

  # --- Schema validity checks (do NOT zero recall on failure) ---

  # [FIX3] Check top-level additionalProperties:false — only "action_items" is allowed.
  local extra_top_keys
  extra_top_keys="$(jq -r '[ keys[] | select(. != "action_items") ] | if length == 0 then "" else "extra top-level keys: " + join(", ") end' <<<"$parsed" 2>/dev/null || echo "schema check failed")"
  if [[ -n "$extra_top_keys" ]]; then
    jq -nc --arg d "$extra_top_keys" --argjson recall "$recall" \
      '{schema_valid:false,field_match:false,recall:$recall,detail:$d}'
    return 0
  fi

  # Check top-level "action_items" key exists and is an array with valid items.
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
    local schema_detail="${items_check:-schema check failed}"
    jq -nc --arg d "$schema_detail" --argjson recall "$recall" \
      '{schema_valid:false,field_match:false,recall:$recall,detail:$d}'
    return 0
  fi

  # [FIX3] Check per-item additionalProperties:false — only "owner" and "task" allowed.
  local extra_item_keys
  extra_item_keys="$(jq -r '
    [ .action_items[] |
      (keys | map(select(. != "owner" and . != "task"))) |
      if length > 0 then "extra item keys: " + join(", ") else empty end
    ] | if length == 0 then "" else .[0] end
  ' <<<"$parsed" 2>/dev/null || echo "schema check failed")"
  if [[ -n "$extra_item_keys" ]]; then
    jq -nc --arg d "$extra_item_keys" --argjson recall "$recall" \
      '{schema_valid:false,field_match:false,recall:$recall,detail:$d}'
    return 0
  fi

  # Schema is valid. Compute field-level match.
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
    jq -nc --argjson recall "$recall" '{schema_valid:true,field_match:true,recall:$recall,detail:"all items match"}'
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
    jq -nc --arg d "$detail" --argjson recall "$recall" '{schema_valid:true,field_match:false,recall:$recall,detail:$d}'
  fi
}
