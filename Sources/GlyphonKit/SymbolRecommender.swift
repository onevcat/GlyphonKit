import Foundation
import FoundationModels
import NaturalLanguage

@Generable
struct KeywordExtraction {
  @Guide(description: "English words naming the main subject: the concrete thing an icon should depict", .count(2))
  var subject: [String]
  @Guide(description: "More short English search keywords: synonyms, related concrete objects, broader concepts", .count(7))
  var related: [String]
}

/// Recommends SF Symbols using a two-stage pipeline:
/// 1. Guided keyword extraction (any input language → weighted English
///    keywords), ranked against the root-deduplicated index.
/// 2. Constrained pick: the model chooses the best symbol and alternates
///    from the candidate list, and explains why in the request's language.
///
/// Empty input becomes a random "feeling lucky" draw. Every failure mode
/// degrades to pure retrieval, never to an error.
///
/// The pipeline is tuned by the eval harness in
/// eval/ — run it after changing prompts or
/// retrieval so regressions are caught by the datasets there.
public struct SymbolRecommender: Sendable {
  private let database: SymbolDatabase
  private let index: SymbolRootIndex

  public init(database: SymbolDatabase) {
    self.database = database
    self.index = SymbolRootIndex(database: database)
  }

  /// Recommend a symbol based on a natural language description.
  ///
  /// - Parameters:
  ///   - text: Any natural language text, in any language. Empty text
  ///     yields a random lucky pick.
  ///   - candidateLimit: Number of candidates for the model to choose from.
  /// - Returns: A recommendation with the chosen symbol, alternates, and reasoning.
  public func recommend(from text: String, candidateLimit: Int = 25) async throws -> SymbolRecommendation {
    try Task.checkCancellation()
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return await luckyPick()
    }

    guard case .available = SystemLanguageModel.default.availability else {
      return retrievalOnlyRecommendation(for: trimmed)
    }

    let extraction: KeywordExtraction
    do {
      extraction = try await extractKeywords(from: trimmed)
      debugLog("AI Step 1 - keywords: \(extraction.subject + extraction.related)")
    } catch let error where error is CancellationError {
      // Cancellation must escape the degradation ladder so hosts can
      // abort mid-generation instead of receiving a fallback result.
      throw error
    } catch {
      debugLog("AI Step 1 - extraction failed: \(error)")
      return retrievalOnlyRecommendation(for: trimmed)
    }

    try Task.checkCancellation()

    var weighted: [SymbolRootIndex.WeightedKeyword] = []
    for (position, keyword) in extraction.subject.prefix(3).enumerated() {
      weighted.append(.init(text: keyword, weight: 2.0 / (1.0 + Double(position) * 0.3)))
    }
    for (position, keyword) in extraction.related.prefix(10).enumerated() {
      weighted.append(.init(text: keyword, weight: 1.0 / (1.0 + Double(position) * 0.15)))
    }

    let candidates = index.search(keywords: weighted, limit: candidateLimit)
    debugLog("AI Step 1.5 - candidates: \(candidates.count)")

    guard candidates.count >= 2 else {
      return retrievalOnlyRecommendation(for: trimmed)
    }

    let pick: IconPick
    do {
      do {
        pick = try await pickSymbol(query: trimmed, candidates: candidates)
      } catch let error where error is CancellationError {
        throw error
      } catch {
        // The guardrail sometimes refuses harmless queries (finance, health)
        // only on the schema-constrained path; the identical prompt passes
        // as plain text. Retry unconstrained and parse.
        debugLog("AI Step 2 - constrained pick failed, retrying plain: \(error)")
        pick = try await pickSymbolPlainText(query: trimmed, candidates: candidates)
      }
    } catch let error where error is CancellationError {
      throw error
    } catch {
      debugLog("AI Step 2 - pick failed: \(error)")
      return recommendation(fromRanked: candidates, isLucky: false)
    }

    let bestEntry = database.symbol(named: pick.best) ?? candidates[0].displayEntry
    var alternateNames = pick.alternates.filter { $0 != pick.best }
    for candidate in candidates where alternateNames.count < 4 {
      if candidate.name != pick.best && !alternateNames.contains(candidate.name) {
        alternateNames.append(candidate.name)
      }
    }
    let alternates = alternateNames.compactMap { database.symbol(named: $0) }

    debugLog("AI Step 2 - pick: \(bestEntry.name) — \(pick.reason)")
    return SymbolRecommendation(
      symbol: bestEntry,
      reason: pick.reason,
      alternates: alternates,
      consideredCount: candidates.count,
      isLucky: false,
      usedAI: true
    )
  }

  // MARK: - Lucky pick

  /// Categories whose symbols read as concrete, recognizable pictures —
  /// good surprises for a random draw.
  private static let luckyCategories: Set<String> = [
    "nature", "weather", "objectsandtools", "transportation", "devices",
    "gaming", "commerce", "home", "fitness", "media", "maps", "health",
    "human", "communication", "cameraandphotos", "automotive",
  ]

  private func luckySymbolPool() -> [SymbolRootIndex.Root] {
    index.roots.filter { root in
      let segments = root.name.split(separator: ".")
      guard let first = segments.first else { return false }
      return segments.count <= 2
        && first.count > 2 // no letter/number badges like r.circle
        && !first.hasSuffix("sign") // currency signs are dull draws
        && root.displayEntry.categories.contains(where: Self.luckyCategories.contains)
    }
  }

  private func luckyPick() async -> SymbolRecommendation {
    let pool = luckySymbolPool()
    guard let chosen = pool.randomElement() else {
      let fallback = database.symbol(named: "sparkles") ?? database.symbols[0]
      return SymbolRecommendation(
        symbol: fallback, reason: luckyFallbackReason(), isLucky: true, usedAI: false)
    }
    let alternates = Array(pool.shuffled().prefix(6))
      .filter { $0.name != chosen.name }
      .prefix(4)
      .map(\.displayEntry)

    var reason = luckyFallbackReason()
    if case .available = SystemLanguageModel.default.availability {
      do {
        let session = LanguageModelSession(instructions: """
          You are a playful oracle who draws a random glyph for the user.
          Answer with a single whimsical English sentence (max 18 words) about the drawn symbol.
          Do not mention that it was random.
          """)
        let response = try await session.respond(to: "The drawn symbol is \"\(chosen.name)\".")
        let line = response.content
          .split(separator: "\n", omittingEmptySubsequences: true)
          .first
          .map { $0.trimmingCharacters(in: .whitespaces) }
        if let line, !line.isEmpty {
          reason = line
        }
      } catch {
        debugLog("Lucky reason generation failed: \(error)")
      }
    }

    debugLog("AI Lucky - pick: \(chosen.name)")
    return SymbolRecommendation(
      symbol: chosen.displayEntry,
      reason: reason,
      alternates: Array(alternates),
      consideredCount: pool.count,
      isLucky: true,
      usedAI: false
    )
  }

  private func luckyFallbackReason() -> String {
    [
      "The Oracle reached into the aether and drew this glyph for you.",
      "A glyph surfaced from the depths of the grimoire.",
      "The stars aligned on this one.",
      "Fortune favors this glyph today.",
    ].randomElement()!
  }

  // MARK: - Stage 1: keywords

  private func extractKeywords(from text: String) async throws -> KeywordExtraction {
    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    let session = LanguageModelSession(model: model, instructions: """
      You generate English search keywords used to look up an icon for the user's text.
      The text can be in any language; always answer with English keywords.
      Prefer single nouns naming concrete, drawable things (like: dog, money, cloud, book).
      Include useful synonyms (for example: money, wallet, coin, budget for a finance app).
      Never output generic software words such as: app, application, software, project, tool, system, platform, service, mobile, tracker, manager.
      """)
    let response = try await session.respond(
      to: String(text.prefix(600)),
      generating: KeywordExtraction.self,
      options: GenerationOptions(sampling: .greedy)
    )
    return response.content
  }

  // MARK: - Stage 2: pick

  private struct IconPick {
    var best: String
    var alternates: [String]
    var reason: String
  }

  private func pickSymbol(query: String, candidates: [SymbolRootIndex.Root]) async throws -> IconPick {
    let candidateNames = candidates.map(\.name)
    let nameSchema = DynamicGenerationSchema(name: "SymbolName", anyOf: candidateNames)
    let alternatesSchema = DynamicGenerationSchema(
      arrayOf: DynamicGenerationSchema(name: "AlternateName", anyOf: candidateNames),
      minimumElements: 4,
      maximumElements: 4
    )
    let schema = try GenerationSchema(
      root: DynamicGenerationSchema(name: "IconPick", properties: [
        .init(name: "best", description: "The single icon that most directly depicts the request", schema: nameSchema),
        .init(name: "alternates", description: "4 other relevant icons, best first", schema: alternatesSchema),
        .init(name: "reason", description: "One short sentence (max 20 words) explaining why `best` fits", schema: DynamicGenerationSchema(type: String.self)),
      ]),
      dependencies: []
    )

    let list = candidates
      .map { root in
        let terms = root.terms.prefix(5)
        return terms.isEmpty ? "- \(root.name)" : "- \(root.name) (\(terms.joined(separator: ", ")))"
      }
      .joined(separator: "\n")

    let prompt = """
      Choose the best icon for this user request.

      ## User request
      \(String(query.prefix(600)))

      ## Available icons (name, then hints), roughly ordered by relevance
      \(list)

      Rules: choose the icon whose picture most directly shows the request's main subject. \
      Prefer specific and concrete over generic or loosely related. \
      Prefer simple, iconic symbols; avoid names that combine many elements. \
      Write `reason` in \(reasonLanguage(for: query)).
      """

    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    let session = LanguageModelSession(model: model)
    let response = try await session.respond(
      to: prompt,
      schema: schema,
      options: GenerationOptions(sampling: .greedy)
    )
    let content = response.content
    return IconPick(
      best: try content.value(String.self, forProperty: "best"),
      alternates: try content.value([String].self, forProperty: "alternates"),
      reason: try content.value(String.self, forProperty: "reason")
    )
  }

  /// Unconstrained fallback for guardrail refusals on the schema path.
  private func pickSymbolPlainText(query: String, candidates: [SymbolRootIndex.Root]) async throws -> IconPick {
    let list = candidates.map { "- \($0.name)" }.joined(separator: "\n")
    let prompt = """
      Choose the best icon for this user request.

      ## User request
      \(String(query.prefix(600)))

      ## Available icons
      \(list)

      Respond in exactly two lines:
      Line 1: the icon name, exactly as written in the list (nothing else)
      Line 2: one short reason (max 20 words) in \(reasonLanguage(for: query))
      """
    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    let session = LanguageModelSession(model: model)
    let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy))
    let lines = response.content
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }
    let rawName = (lines.first ?? "")
      .replacing("\"", with: "")
      .replacing("`", with: "")
      .trimmingCharacters(in: .punctuationCharacters)
    guard candidates.contains(where: { $0.name == rawName }) else {
      throw GlyphonError.recommendationFailed("plain-text pick not in candidates: \(rawName)")
    }
    return IconPick(best: rawName, alternates: [], reason: lines.count > 1 ? lines[1] : "")
  }

  /// Name the query's language in English so the prompt can demand the
  /// reason in it. The model cannot reliably infer "same language as the
  /// request" on its own.
  private func reasonLanguage(for text: String) -> String {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard
      let language = recognizer.dominantLanguage,
      language != .undetermined,
      let name = Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue)
    else { return "English" }
    return name
  }

  // MARK: - No-FM degradation

  /// Rank with the root index directly from the query's own words.
  private func retrievalOnlyRecommendation(for query: String) -> SymbolRecommendation {
    let words = query.lowercased()
      .split { !$0.isLetter && !$0.isNumber }
      .prefix(12)
      .map { SymbolRootIndex.WeightedKeyword(text: String($0), weight: 1.0) }
    let hits = index.search(keywords: Array(words), limit: 5)
    guard !hits.isEmpty else {
      let fallback = database.symbol(named: "sparkles") ?? database.symbols[0]
      return SymbolRecommendation(symbol: fallback, reason: "", isLucky: false, usedAI: false)
    }
    return recommendation(fromRanked: hits, isLucky: false)
  }

  private func recommendation(fromRanked hits: [SymbolRootIndex.Root], isLucky: Bool) -> SymbolRecommendation {
    SymbolRecommendation(
      symbol: hits[0].displayEntry,
      reason: "Closest match to your description.",
      alternates: hits.dropFirst().prefix(4).map(\.displayEntry),
      consideredCount: hits.count,
      isLucky: isLucky,
      usedAI: false
    )
  }

  private func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
  }
}
