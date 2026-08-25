#!/usr/bin/env bash
# demo.sh — C2 comparison video driver for OpenSOP v2
# Replays recorded data from cli/bench/results/bulletproof-3arm.jsonl
# Total runtime: ~60s at natural pacing
# HONEST: outputs below are RECORDED from 10 measured runs per arm (3-arm bench)

set -euo pipefail

# ─── ANSI helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'

# ─── Timing helpers ───────────────────────────────────────────────────────────
pause() { sleep "${1:-0.5}"; }

# Print character by character for "typing" effect
type_line() {
  local line="$1"
  local delay="${2:-0.03}"
  printf '%s' "$line" | while IFS= read -r -n1 ch; do
    printf '%s' "$ch"
    sleep "$delay"
  done
  printf '\n'
}

# Print a line instantly
println() { printf '%s\n' "$1"; }

# Print colored line instantly
cprintln() { printf "${1}%s${RESET}\n" "$2"; }

# Print a separator
sep() { printf "${DIM}%s${RESET}\n" "$(printf '─%.0s' {1..90})"; }

# Clear screen
cls() { printf '\033[2J\033[H'; }

# ─── Act 0: Title card (~4s) ─────────────────────────────────────────────────
cls
pause 0.3
printf '\n\n'
cprintln "$WHITE" "  OpenSOP — same model, same meeting notes."
cprintln "$WHITE" "  Extract the action items."
printf '\n'
cprintln "$DIM" "  Model: Claude Haiku · 10 runs each arm · recorded from measured runs, not simulated"
cprintln "$DIM" "  Source: cli/bench/results/bulletproof-3arm.jsonl (60 runs total: 3 arms × 2 models × 10)"
printf '\n'
sep
pause 3.5

# ─── Act 1: skill-only (~22s) ─────────────────────────────────────────────────
cls
printf '\n'
cprintln "$YELLOW" "  ▶ ACT 1  —  Skill-only (naive prompt)"
printf '\n'
cprintln "$DIM" "  Prompt (abbreviated from cli/bench/prompts/raw.txt):"
printf '\n'
cprintln "$CYAN" '  $ cat raw.txt'
pause 0.4
printf "${DIM}"
println '  Read the following meeting notes and extract all action items.'
println '  For each action item, identify the person responsible (owner)'
println '  and what they need to do (task).'
println '  ...'
println '  List the action items you found.'
printf "${RESET}"
pause 0.8

printf '\n'
sep
printf '\n'
cprintln "$YELLOW" "  Running 3× (recorded from 10 measured haiku runs)..."
pause 0.6

# --- Run 1: 6 items ---
printf '\n'
cprintln "$DIM" "  Run 1/3  ·  haiku  ·  2.85s  ·  result:"
pause 0.4
println  "  Action Items:"
println  "  1. Bob Navarro — Fix the CSV export race condition"
println  "  2. Carol Singh — Complete the WCAG 2.1 AA accessibility audit"
println  "  3. Dave Wu — Write integration tests for payments-flow edge cases"
printf "${RED}"
println  "  4. Alice Chen — Raise staging environment as P1 in infrastructure backlog"
println  "  5. Bob Navarro — File a planning ticket for the data-grid library upgrade"
println  "  6. Alice Chen — Follow up with customers on batch-import escalations"
printf "${RESET}"
pause 0.5
printf "${RED}${DIM}    ^^^^ phantom items — not in ACTION ITEMS section${RESET}\n"
pause 0.9

# --- Run 2: 8 items ---
printf '\n'
cprintln "$DIM" "  Run 2/3  ·  haiku  ·  2.96s  ·  result:"
pause 0.4
println  "  Action Items:"
println  "  1. Bob Navarro — Fix the CSV export race condition before August 12"
println  "  2. Carol Singh — Complete the WCAG 2.1 AA accessibility audit by August 15"
println  "  3. Dave Wu — Write additional integration tests for payments-flow"
printf "${RED}"
println  "  4. Alice Chen — Raise the staging environment reliability as a P1 issue"
println  "  5. Bob Navarro — File a ticket for the data-grid library upgrade sprint"
println  "  6. Carol Singh — Review the UX flow for batch-import edge cases"
println  "  7. Alice Chen — Follow up with the two customers on escalations"
println  "  8. Carol Chen — Review PRs within 24 hours going forward"
printf "${RESET}"
pause 0.5
printf "${RED}${DIM}    ^^^^ 5 phantom items — different set from Run 1${RESET}\n"
pause 0.9

# --- Run 3: 7 items ---
printf '\n'
cprintln "$DIM" "  Run 3/3  ·  haiku  ·  2.69s  ·  result:"
pause 0.4
println  "  Action Items:"
println  "  1. Bob Navarro — Fix the CSV export race condition"
println  "  2. Carol Singh — Complete the WCAG 2.1 AA accessibility audit"
println  "  3. Dave Wu — Write integration tests for payments-flow edge cases"
printf "${RED}"
println  "  4. Alice Chen — Follow up with escalation customers"
println  "  5. Alice Chen — Raise staging P1 in infrastructure backlog"
println  "  6. Bob Navarro — File data-grid upgrade ticket"
println  "  7. Carol Singh — Review batch-import UX flow"
printf "${RESET}"
pause 0.5
printf "${RED}${DIM}    ^^^^ 4 phantom items — yet another different set${RESET}\n"
pause 0.8

printf '\n'
sep
printf '\n'
printf "${RED}${BOLD}"
println  "  3 runs → 3 different answers · unstructured prose · invents 3–5 phantom action items"
printf "${RESET}"
printf "${DIM}"
println  "  (json_only arm: 10/10 valid JSON — but STILL 0/10 exact. Format alone doesn't fix scope.)"
printf "${RESET}"
pause 3.0

# ─── Act 2: openSOP (~22s) ───────────────────────────────────────────────────
cls
printf '\n'
cprintln "$GREEN" "  ▶ ACT 2  —  openSOP (process file)"
printf '\n'
cprintln "$DIM" "  Process: cli/bench/processes/extract-action-items.sop.json"
cprintln "$DIM" "  Key additions: scope rule (ACTION ITEMS heading only) + strict JSON schema"
printf '\n'
cprintln "$CYAN" '  $ opensop run extract-action-items.sop.json'
pause 0.8

printf '\n'
sep
printf '\n'
cprintln "$YELLOW" "  Running 3× (recorded from 10 measured haiku runs)..."
pause 0.6

# --- openSOP Run 1 ---
printf '\n'
cprintln "$DIM" "  Run 1/3  ·  haiku  ·  1.56s  ·  result:"
pause 0.4
printf "${GREEN}"
println  '  {"action_items":[{"owner":"Bob Navarro","task":"Fix the CSV export race condition"},'
println  '   {"owner":"Carol Singh","task":"Complete the WCAG 2.1 AA accessibility audit"},'
println  '   {"owner":"Dave Wu","task":"Write integration tests for payments-flow edge cases"}]}'
printf "${RESET}"
pause 1.0

# --- openSOP Run 2 ---
printf '\n'
cprintln "$DIM" "  Run 2/3  ·  haiku  ·  1.49s  ·  result:"
pause 0.4
printf "${GREEN}"
println  '  {"action_items":[{"owner":"Bob Navarro","task":"Fix the CSV export race condition"},'
println  '   {"owner":"Carol Singh","task":"Complete the WCAG 2.1 AA accessibility audit"},'
println  '   {"owner":"Dave Wu","task":"Write integration tests for payments-flow edge cases"}]}'
printf "${RESET}"
pause 0.5
printf "${DIM}  (byte-identical to Run 1)${RESET}\n"
pause 1.0

# --- openSOP Run 3 ---
printf '\n'
cprintln "$DIM" "  Run 3/3  ·  haiku  ·  1.63s  ·  result:"
pause 0.4
printf "${GREEN}"
println  '  {"action_items":[{"owner":"Bob Navarro","task":"Fix the CSV export race condition"},'
println  '   {"owner":"Carol Singh","task":"Complete the WCAG 2.1 AA accessibility audit"},'
println  '   {"owner":"Dave Wu","task":"Write integration tests for payments-flow edge cases"}]}'
printf "${RESET}"
pause 0.5
printf "${DIM}  (byte-identical to Runs 1–2)${RESET}\n"
pause 0.8

printf '\n'
sep
printf '\n'
printf "${GREEN}${BOLD}"
println  "  3 runs → identical · valid JSON · exactly the 3 real items · 0 phantoms"
printf "${RESET}"
pause 3.0

# ─── Act 3: Scoreboard (~10s) ─────────────────────────────────────────────────
cls
printf '\n'
cprintln "$WHITE" "  ═══════════════════════════════════════════════════════════════"
cprintln "$WHITE" "  RESULTS  —  verified from bulletproof-3arm.jsonl (60 runs)"
cprintln "$WHITE" "  ═══════════════════════════════════════════════════════════════"
printf '\n'

# Table header
printf "${BOLD}%-18s  %-12s  %-14s  %-16s  %-10s  %-10s${RESET}\n" \
  "Metric" "skill" "json-only" "openSOP" "" ""
sep

# Row 1: reliability
printf "${BOLD}%-18s${RESET}  " "Reliability"
printf "${RED}%-12s${RESET}  " "0/10"
printf "${RED}%-14s${RESET}  " "0/10"
printf "${GREEN}%-16s${RESET}\n" "10/10  ✓"
pause 0.3

# Row 2: recall
printf "${BOLD}%-18s${RESET}  " "Recall (3 real)"
printf "${GREEN}%-12s${RESET}  " "3/3"
printf "${GREEN}%-14s${RESET}  " "3/3"
printf "${GREEN}%-16s${RESET}\n" "3/3"
pause 0.3

# Row 3: phantom items
printf "${BOLD}%-18s${RESET}  " "Phantom items"
printf "${RED}%-12s${RESET}  " "+4 median"
printf "${RED}%-14s${RESET}  " "+4 median"
printf "${GREEN}%-16s${RESET}\n" "+0  ✓"
pause 0.3

# Row 4: valid JSON
printf "${BOLD}%-18s${RESET}  " "Valid JSON"
printf "${RED}%-12s${RESET}  " "0/10"
printf "${GREEN}%-14s${RESET}  " "10/10"
printf "${GREEN}%-16s${RESET}\n" "10/10  ✓"
pause 0.3

# Row 5: output tokens (measured from real output size; input ~constant across arms)
printf "${BOLD}%-18s${RESET}  " "Output tokens ≈"
printf "${RED}%-12s${RESET}  " "~174"
printf "${RED}%-14s${RESET}  " "~190"
printf "${GREEN}%-16s${RESET}\n" "~69  (2.5× fewer)"
pause 0.3

# Row 6: speed
printf "${BOLD}%-18s${RESET}  " "Speed (median)"
printf "${DIM}%-12s${RESET}  " "2.69s"
printf "${DIM}%-14s${RESET}  " "2.51s"
printf "${GREEN}%-16s${RESET}\n" "1.56s  (1.7× faster)"
pause 0.3

# Row 6: models
printf "${BOLD}%-18s${RESET}  " "Consistent on"
printf "${DIM}%-12s${RESET}  " "Haiku+Sonnet"
printf "${DIM}%-14s${RESET}  " "Haiku+Sonnet"
printf "${GREEN}%-16s${RESET}\n" "Haiku+Sonnet  ✓"

sep
printf '\n'

printf "${DIM}  Recall is 3/3 in every arm — the model always finds the real items.${RESET}\n"
printf "${DIM}  The failure is scope-creep: naive prompts promote informal commitments to action items.${RESET}\n"
printf "${DIM}  json_only proves format alone doesn't fix it — only the encoded scope rule does.${RESET}\n"
pause 0.8

printf '\n'
sep
printf '\n'
printf "${CYAN}${BOLD}"
println  "  A process is a file."
println  "  Declare it, run it, get the same result every time."
println  "                                                — OpenSOP"
printf "${RESET}"
printf '\n'
cprintln "$DIM" "  opensop.ai  ·  github.com/opensop/opensop"
printf '\n'
pause 3.5
