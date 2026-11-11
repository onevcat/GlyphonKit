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

### macOS 27 re-baseline (2026-11-10)

The on-device model changed with macOS 27. The `prod` scores dropped
well below the macOS 26 reference with the same code; treat these as
the current baseline, not as a regression of a change:

| item | value |
|---|---|
| macOS | 27.0.1 (build 26A434) |
| Xcode | 27.2 (27B52) |
| prod, master `22e6be5` | train 0.715 / acceptable 76.5% · test 0.456 / acceptable 56.2% · ~3.3 s/query |
| raw reports | `results/prod-macos27-train.json`, `results/prod-macos27-test.json` |

Recovering the macOS 26 quality needs its own tuning round on `train.json`.

### SF Symbols 2026.2 data (2026-11-11)

`symbols.json` is now version 2026.2: 9649 symbols (3362 with search
terms). The database leaves out the symbols that the running system does
not have, so the candidate set depends on the system: macOS 27.0.1 has
9524 of them. With the same recommender on macOS 27.0.1, two `prod` runs
each gave train 0.735 / 0.709 (acceptable 79.4% / 76.5%) and test
0.456 / 0.456 (acceptable 56.2%). Two runs with the 2025.1 data on the
same day gave train 0.724 / 0.685 and test 0.456 / 0.456: the data
update does not move the scores beyond the run noise.

### macOS 27 tuning (2026-11-11)

The macOS 27 model has its own prompts and retrieval settings
(`ModelGeneration.os27`); the macOS 26 ones are unchanged. All numbers
are `prod` on macOS 27.0.1 with the 2026.2 data, as
meanPickScore (acceptable):

| run | train, 34 cases, labels before | train, 34 cases, labels now | train, 42 cases | test, labels before | test, labels now |
|---|---|---|---|---|---|
| macOS 26 reference (2025.1 data) | 0.929 (100%) | 0.929 (100%) | - | 0.844 (100%) | 0.844 (100%) |
| macOS 27, macOS 26 prompts, run 1 | 0.735 (79.4%) | 0.800 (91.2%) | - | 0.456 (56.2%) | 0.569 (75.0%) |
| macOS 27, macOS 26 prompts, run 2 | 0.709 (76.5%) | 0.774 (88.2%) | - | 0.456 (56.2%) | 0.569 (75.0%) |
| macOS 27, tuned, run 1 and run 2 | 0.871 (94.1%) | 0.909 (100%) | 0.879 (100%) | 0.744 (93.8%) | 0.744 (93.8%) |

- "Labels before" and "labels now" separate the two effects. The label
  review added reasonable symbols that scored 0 (13 train cases, 3 test
  cases; the reason is in each case's `notes`). It is worth about 0.065
  on train and 0.113 on test for the macOS 26 prompts. The step from
  there to the tuned row is the change in quality.
- The 8 added train cases (ids `en-pomodoro` to `zh-podcast`) are new
  failure categories of the macOS 27 model; the 42-case column includes
  them.
- The macOS 26 row is the old report scored again, with renamed symbols
  matched (0.921 in the report itself).
- The tuned pipeline takes about 2.2 s per query (the macOS 26 prompts:
  3.3 s), and two runs give the same picks.
- Current baseline: train 0.879 / acceptable 100% · test 0.744 /
  acceptable 93.8%. Raw reports: `results/prod-macos27-tuned-train.json`,
  `results/prod-macos27-tuned-test.json`.
- Not recovered: test stays about 0.10 below macOS 26. The model could
  reach 0.931 on test with the candidates that it gets; the remaining
  misses are picks of a weaker candidate (`clock` for a kitchen timer
  with `timer` in the list).

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
shipping `SymbolRecommender` — run this after any production change),
`prod-retrieval` (stage 1 and retrieval of the shipping pipeline without
the pick). The harness variants `v0` and `v1` are the macOS 26 research
history; they do not follow the macOS 27 tuning.

`prod` reports the keywords and candidates of each case and two
ceilings. `retrievalCeiling` is the best score among all retrieved
candidates. `candidateCeiling` is the best score among the candidates
that the model could choose from (on macOS 27 the first 6). A low
`retrievalCeiling` is a keyword or vocabulary problem; a
`candidateCeiling` below it is a ranking problem; a high
`candidateCeiling` with a low score is a pick problem. The tuned
baseline has 0.964 / 0.971 on train and 0.931 / 0.944 on test.

`prod` and `prod-retrieval` read the pipeline's trace through
`@testable import`, so the harness needs a debug build. All timings are
debug-build timings.

On macOS 26, treat differences < ~0.04 meanPickScore as noise and run
twice before believing a regression. On macOS 27 two runs give the same
picks, so a difference is real; still run twice after a system update.

## Datasets

- `datasets/train.json` — 42 weighted cases (en/zh/ja/es/fr/de/ko,
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
  (`query --variant prod --text ...`, or the `candidates` and
  `candidateCeiling` of the case in a report); a fine list means a
  pick-prompt problem, a bad list means keywords or retrieval weights.
- **Tune stage 1 on its own** with `run --variant prod-retrieval`: read
  the ceilings and the score of the top candidate.
- **New vocabulary** → `SymbolRootIndex.aliasAdditionsOS27`, not
  `aliasMap`: the macOS 26 retrieval reads `aliasMap` and cannot be
  measured again.
- **A new system release** → first run `prod` twice with the previous
  generation's prompts. If the scores hold, map the new release to that
  generation in `ModelGeneration.current`. If not, add a generation and
  tune it; never edit the prompts of a generation that can no longer be
  measured.
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

## FoundationModels quirks (macOS 27.0, on-device FM)

1. **"Keywords" lose the text's own words.** With the macOS 26 keyword
   prompt, `dog` gives `animal, canine, pet, furry friend` without `dog`,
   and `music player app` gives no `music`. The example in the
   instructions (`money, wallet, coin, budget`) leaks into unrelated
   requests. Asking for icon suggestions, with the topic as its own
   field and no examples, keeps the subject.
2. **Long guided arrays repeat.** `.count(7)` with greedy sampling gives
   `list, tasks, object, object, object, ...`. Keep arrays short and
   drop repeated entries in code.
3. **The pick does not follow the list order.** The model takes weak
   candidates from the end of a 25-item list (`airpods` for a music
   player with `headphones` first). A 6-item list from a diverse
   retrieval (at most 3 roots per family) removes most of it; prompt
   wording alone moved the score by less than 0.04.
4. **A quotation mark in a guided string can run away.** One pick opened
   a quotation in `reason` and wrote until the 4096-token window was
   full, after 64 s. The pick prompt asks for no quotation marks, and
   `maximumResponseTokens` ends a response that goes wrong.
5. **Unstable order of equal scores looked like model noise.** Most of
   the run-to-run variance came from the candidate order of equal
   retrieval scores, which depended on dictionary order. With a name
   tiebreak, two runs give the same picks.
6. **Renamed symbols.** The well-known names `note.text`, `speedometer`
   or `doc.richtext` are now aliases without terms. The macOS 27 index
   merges an old name into its new name's root, so the old words still
   find the symbol and the model sees the old name as a hint.
