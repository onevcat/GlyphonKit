# GlyphonKit

Natural language → SF Symbol, fully on-device.

Describe what you need — in any language — and get the right SF Symbol
back, with alternates and a one-line reason. All AI runs locally via
Apple's FoundationModels; no server, no API keys.

GlyphonKit is the recommendation engine extracted from the
[Glyphon](https://glyphon.onevcat.com/) app, where the pipeline was
tuned and evaluated against a weighted multilingual dataset (see
[`eval/`](eval/)).

```swift
import GlyphonKit

let glyphon = try Glyphon()

// Fast keyword search (no AI)
let matches = glyphon.search("weather cloud rain")

// AI recommendation from natural language, any language
let pick = try await glyphon.recommend(from: "一个记账应用，帮助管理每月开销")
pick.symbol.name   // "chart.pie"
pick.alternates    // 4 runner-up SymbolEntry values
pick.reason        // one sentence, in the request's language
pick.usedAI        // false when the retrieval-only fallback answered

// Empty input → whimsical lucky draw
let lucky = try await glyphon.recommend(from: "")

// Validate a symbol name against the bundled database
glyphon.isValid("cloud.rain")  // true
```

## Requirements

- Swift 6.2, macOS 26+ / iOS 26+
- AI recommendations need Apple Intelligence (on-device
  `SystemLanguageModel`). Check `AIAvailability.current` for a pre-flight
  answer; when the model is unavailable, `recommend(from:)` degrades to
  pure retrieval instead of failing — inspect
  `SymbolRecommendation.usedAI` to label such results honestly.

## Installation

```swift
.package(url: "https://github.com/onevcat/GlyphonKit.git", from: "0.1.0")
```

## How it works

Two-stage pipeline on top of a root-deduplicated retrieval index:

1. **Guided keyword extraction** — any input language → weighted English
   keywords (`@Generable` structured output).
2. **Retrieval** — ~9k symbols deduped to ~2.5k semantic roots, ranked
   with a hand-curated alias map, IDF damping, and a complexity penalty.
3. **Constrained pick** — a `DynamicGenerationSchema` restricted to the
   candidate list, so the model cannot hallucinate a symbol name; the
   reason is written in the request's detected language.

Every failure mode degrades gracefully (schema refusal → plain-text
retry → retrieval-only → `sparkles`); the pipeline never throws to the
caller except for `CancellationError`. `recommend(from:)` is
cooperatively cancellable — cancelling the surrounding `Task` aborts the
model calls promptly.

Latency is roughly 3 s per query on an M-series Mac; budget UI
accordingly (the call is safe to run concurrently with user interaction
and to cancel when the UI goes away).

## Symbol database

`Sources/GlyphonKit/Resources/symbols.json` holds symbol names, release
years, categories, and search terms (SF Symbols 2025.1, 9184 symbols).
It is generated from the SF Symbols data present on the local macOS
installation by the bundled CLI:

```sh
swift run glyphon-extract Sources/GlyphonKit/Resources/symbols.json
```

Regenerate after a new SF Symbols release (and bump the version constant
in `Sources/GlyphonExtract/main.swift`), then re-run the eval suite.

SF Symbols themselves are © Apple Inc. This package redistributes no
glyph artwork — only name and metadata strings, for interoperability
with Apple's symbol APIs. Use of SF Symbols in your app is governed by
Apple's agreements (Xcode and Apple SDKs / SF Symbols license); this
package is intended solely for building software for Apple platforms.

## Evaluation

The pipeline is guarded by the eval harness in [`eval/`](eval/) — a
weighted multilingual dataset plus a CLI that scores the shipping code
path. Anything touching prompts, the alias map, or retrieval weights
must keep the `prod` variant green; see [`eval/README.md`](eval/README.md)
for the baseline and the tuning playbook. The eval needs a Mac with
Apple Intelligence and is therefore not part of CI.

## License

MIT. Extracted from the Glyphon app repository; the research log behind
the pipeline design lives there.
