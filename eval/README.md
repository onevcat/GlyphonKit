# Recommender eval harness

Scores the NL → SF Symbol pipeline against weighted multilingual
datasets. This is the drift detector for anything touching
`Sources/GlyphonKit/SymbolRecommender.swift` or
`Sources/GlyphonKit/SymbolRootIndex.swift` (prompts, alias map,
retrieval weights): the `prod` variant evaluates the shipping code and
must stay green.

The research log that produced this recipe (v0 → v1 experiments,
failure analyses) lives in the Glyphon app repository under
`docs/ai/002-ai-search-optimize/`.

## Environment snapshot (reference baseline)

All reference numbers were measured on this exact setup. The on-device
model changes with the OS — after an OS/Xcode update, re-establish the
baseline before trusting comparisons.

| item | value |
|---|---|
| date | 2026-07-03 |
| macOS | 26.5.1 (build 25F80) |
| Xcode | 26.6 (17F113), swift-tools 6.2 |
| model | on-device `SystemLanguageModel.default` (Apple Intelligence) |
| symbols.json | version 2025.1, 9184 symbols (3189 with search terms) |
| FM context window | 4096 tokens (hard limit) |
| reference scores (prod) | train 0.900 / acceptable 100% · test 0.769–0.844 / acceptable 93.8–100% · ~2.9 s/query |
| run-to-run noise | treat meanPickScore deltas < ~0.04 as noise (guardrail classifier is nondeterministic) |

Scores are weighted: 1.0 = ideal symbol, ~0.7 = good, ~0.4 = barely
acceptable, 0 = miss. "acceptable" = score > 0.

## How to run

Needs a Mac with Apple Intelligence available — not runnable in CI.

```sh
cd eval
swift build
.build/debug/recommender-eval check                          # FM availability
.build/debug/recommender-eval validate --dataset datasets/train.json
.build/debug/recommender-eval run --variant prod --dataset datasets/train.json --out results/xxx.json
.build/debug/recommender-eval run --variant prod --dataset datasets/test.json
.build/debug/recommender-eval query --variant prod --text "宠物狗的日常照顾"
.build/debug/recommender-eval query --variant prod --text ""   # lucky pick
```

Variants: `v0` (the pre-rewrite algorithm), `v0-nofm` (retrieval only),
`v1` (+`-c15`/`-c40`/`-reason-first` config spikes), `prod` (calls the
shipping `SymbolRecommender` — run this after any production change).

Because of run variance, treat differences < ~0.04 meanPickScore as
noise; run twice before believing a regression.

## Datasets

- `datasets/train.json` — 34 weighted cases (en/zh/ja/es/fr/de/ko,
  objects, project descriptions, abstract words). Tune on this; add new
  failure categories here with honest weighted labels.
- `datasets/test.json` — 16 held-out cases (incl. emoji-only). Never
  tune on it; only touch it to fix genuinely wrong labels.
- Labels list semantic roots (`cloud.rain`), not variants
  (`cloud.rain.fill`) — scoring matches by root.

`results/` keeps raw reports from the original tuning rounds (v0
baseline through the shipping port) for provenance.

## Tuning playbook

- **A query retrieves nothing relevant** → vocabulary gap. Add an alias
  entry in `SymbolRootIndex.aliasMap`; keep targets *discriminative*
  (prefer `meditate` over `figure`; check how many roots a token hits).
- **Model picks a weird candidate** → inspect the candidate list first
  (`query --variant v1 --text ...`); a fine list means a pick-prompt
  problem, a bad list means retrieval weights.
- Keep `prod` green: harness variants and production must not drift.

## FoundationModels quirks (macOS 26.5, on-device FM)

These cost the most debugging time; remember them:

1. **Schema-path-only refusals.** The guardrail refuses harmless
   finance/health prompts *only* via `respond(to:schema:)`; the same
   prompt passes as plain text. `permissiveContentTransformations`
   reduces but does not eliminate this — hence the plain-text retry in
   the pipeline.
2. **Unbounded `@Generable` arrays + greedy sampling can run away**,
   filling the 4096-token window and erroring. Always set
   `.count`/`.maximumCount` guides.
3. **Default sampling is nondeterministic** — eval scores drift ±0.05
   between runs with identical code. `GenerationOptions(sampling:
   .greedy)` restores reproducibility (refusals stay flaky; the
   guardrail classifier itself is nondeterministic).
4. Unsupported languages (e.g. Korean) can trigger runaway generation
   instead of a clean error; the degradation ladder covers it.
