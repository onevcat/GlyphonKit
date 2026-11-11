# GlyphonKit — Agent Guide

Natural language → SF Symbol engine for the Glyphon app
(github.com/onevcat/Glyphon). All AI runs on-device through
FoundationModels: no server, no API keys, no new dependencies. The
context window of the on-device model is 4096 tokens.

## Layout

| path | what it is |
|---|---|
| `Sources/GlyphonKit/SymbolDatabase.swift` | Symbol data, availability filter by running system, rename table |
| `Sources/GlyphonKit/SymbolRootIndex.swift` | Retrieval: semantic roots, alias map, search options |
| `Sources/GlyphonKit/SymbolRecommender.swift` | The pipeline: stage 1 (keywords), retrieval, stage 2 (pick) |
| `Sources/GlyphonKit/ModelGeneration.swift` | Which prompts and settings a system uses (`os26`, `os27`) |
| `Sources/GlyphonKit/Resources/symbols.json` | SF Symbols data, written by `glyphon-extract` |
| `Sources/GlyphonExtract/` | CLI that writes `symbols.json` from the SF Symbols app metadata |
| `Tests/GlyphonKitTests/` | Unit tests; no model needed, they run in CI |
| `eval/` | Eval harness for the recommender; needs a Mac with Apple Intelligence |

## Build and test

```sh
swift build --build-tests
swift test                      # no model needed
cd eval && swift build          # the harness needs a debug build
```

## Changing the recommender

Read `eval/README.md` first; its "Start here" section has the current
baseline and the commands. The rules:

1. **Each model generation has its own prompts and settings.** The
   on-device model changes with the major system release. Do not edit
   the prompts, the search options or `aliasMap` of a generation that
   can no longer be measured (now: macOS/iOS 26). A test states the
   settings of each generation.
2. **Judge a change on the held-out sets** (`dev2.json`, `test.json`),
   not on `train.json`. Train is about 0.15 above them. Tune on
   `train.json` and `dev.json` only; never tune on the cases of the
   held-out sets, and change `test.json` only to fix a wrong label.
3. **Run `prod` twice** on all four datasets before and after the
   change. On macOS 27 two runs give the same picks; if they differ,
   find out why first.
4. **Compare case by case**, not only the mean: count the cases that
   get better and worse on the held-out sets. A change that makes as
   many worse as better is not a gain.
5. **Look in the table of tried directions** in `eval/README.md` before
   you start a new one, and add your result to it, also when it did not
   help.
6. **After a system update**, run `prod` twice with the current
   generation before anything else. If the scores hold, keep the
   generation; if not, add a new one and tune it.

Record the new baseline in `eval/README.md` and put the raw reports in
`eval/results/`. Put the eval numbers in the PR.

## Updating the symbol data

After a new SF Symbols release, see "Symbol database" in `README.md`:
run `glyphon-extract` with the SF Symbols app as the source, run the
tests, then run the eval. The data can be newer than the running
system; `SymbolDatabase` leaves out what the system does not have.

## Release

The app pins a version tag of this package. After a merged change that
the app needs, onevcat makes the tag; then update the pin in the Glyphon
repository.
