# C0 bench — verified numbers (subagent measurement, 2026-08-05)

**Method:** measured Claude subagents as the LLM (no API key), one independent
subagent per run. **3 arms × 2 models × N=10 = 60 runs.** Same meeting-notes
fixture, same task, all arms. Raw per-run data lives on the `spike/c0-bench` branch
(`cli/bench/results/bulletproof-3arm.jsonl`, and the 40-run 2-arm pilot in
`results/subagent-bench.jsonl`). Every run's raw output was captured and scored;
aggregates recomputed with jq. The reproducer is `cli/bench/demo/demo.sh`; the
shipped `opensop bench` command (`--stub` for offline, `ANTHROPIC_API_KEY` for live)
re-runs the full benchmark against the same fixture and prompts.

## The three arms
- **skill** — the naive prompt a person writes: "extract all action items… list the action items you found" (`prompts/raw.txt`). No structure, no scope.
- **json_only** — same naive ask, but demands JSON output (schema in prompt). Isolates *format* from *scope*.
- **opensop** — the task *openSOP-ized*: strict JSON schema **+ an explicit scope rule** ("only items under the ACTION ITEMS heading") + field rules (`prompts/opensop.txt`).

## Results

| Model | Arm | Recall (found the 3 real) | Structured (valid JSON) | **Exact & usable** | Phantom items (median) | Reproducible | Median time |
|---|---|---|---|---|---|---|---|
| Haiku | skill | **3/3** | 0/10 | 0/10 | +4 | ✗ (6–8 items) | 2.69 s |
| Haiku | json_only | **3/3** | 10/10 | 0/10 | +4 | ✗ (7–8 items) | 2.51 s |
| Haiku | **openSOP** | **3/3** | **10/10** | **10/10** | **+0** | **✓ identical** | **1.56 s** |
| Sonnet | skill | **3/3** | 0/10 | 0/10 | +5 | ✗ (7–8 items) | 5.49 s |
| Sonnet | json_only | **3/3** | 10/10 | 0/10 | +3 | ✗ (6–7 items) | 3.85 s |
| Sonnet | **openSOP** | **3/3** | **10/10** | **10/10** | **+0** | **✓ identical** | **2.68 s** |

*Recall = how many of the 3 true action items (Bob/CSV, Carol/WCAG, Dave/integration) appeared. Exact = valid JSON AND exactly those 3, nothing else.*

## What this shows — honest, and why "0/10" is NOT a strawman

- **Recall is 3/3 in every cell.** The model always finds the 3 real action items.
  The naive arms are not "wrong because the model is dumb" — comprehension is perfect.
- **The failure is scope-creep, not reading.** Every naive run inflates the 3 formal
  action items into 6–8 by promoting informal commitments (Alice's P1, Bob's ticket,
  Alice's follow-up) to "action items" — a different set each run.
- **json_only is the decisive control:** asking for JSON gives 10/10 valid structure
  but **still 0/10 exact** — it keeps inventing 3–5 phantom items. **Format alone does
  not buy reliability.** Only the encoded scope rule (the openSOP process) does.
- **openSOP:** 10/10 exact, +0 phantom, byte-identical across all 10 runs, both models,
  and fastest (~1.7–2× faster than skill — tighter output).
- **Tokens — measured via OUTPUT size (honest method, no API key).** The raw
  `subagent_tokens` (~15k) is scaffold-dominated and useless, BUT output *generation*
  tokens — the variable, expensive part — are directly measurable from the real
  outputs (exact char counts, tokenizer-independent):

  | Arm | Output chars | ≈ output tokens (chars/3.7) |
  |---|---|---|
  | skill (Haiku prose) | 644 | ~174 |
  | skill (Sonnet, +tables) | 1429 | ~386 |
  | json_only | 703 | ~190 |
  | **openSOP** | **258** | **~69** |

  openSOP emits **~2.5–5.6× fewer output tokens** — exactly 3 scoped items in compact
  JSON vs. phantom items wrapped in prose. Input is ~constant (~500-token notes
  dominate; openSOP's instruction is slightly longer). This is why openSOP is also
  faster. (A keyed `opensop bench` would add exact input-token + cache accounting;
  not required for the output/generation story, which is the variable cost.)

## Headline for the video (data-driven, per the "whatever C0 shows" decision)

> Same model. All three approaches find the 3 real action items (100% recall). But a
> naive prompt — even one that demands JSON — invents 3–5 phantom tasks on every run,
> a different set each time. The openSOP process returns exactly the 3 real ones,
> identical every run, ~2× faster. **Reliability 0 → 10/10, on both Haiku and Sonnet.**
