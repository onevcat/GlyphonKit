import Foundation
import FoundationModels
import GlyphonKit
import NaturalLanguage

@Generable
struct KeywordExtraction {
  @Guide(description: "English words naming the main subject: the concrete thing an icon should depict", .count(2))
  var subject: [String]
  @Guide(description: "More short English search keywords: synonyms, related concrete objects, broader concepts", .count(7))
  var related: [String]
}

/// V1: guided generation + root-deduplicated retrieval + constrained pick.
struct V1Guided: Variant {
  var name: String { "v1" }
  var candidateLimit = 25
  var reasonFirst = false

  func recommend(query: String, database: SymbolDatabase, engine: SymbolSearchEngine) async throws -> VariantResult {
    var result = VariantResult(pickName: "", alternates: [], reason: "")
    let index = RootIndex(database: database)

    // Step 1: extract weighted English keywords.
    let keywordStart = Date()
    let extraction: KeywordExtraction
    do {
      extraction = try await extractKeywords(from: query)
    } catch {
      print("    [extract error] \(error)")
      result.stageSeconds["keywords"] = Date().timeIntervalSince(keywordStart)
      applyRootIndexFallback(query: query, index: index, to: &result)
      return result
    }
    result.stageSeconds["keywords"] = Date().timeIntervalSince(keywordStart)
    result.keywords = extraction.subject + extraction.related

    var weighted: [RootIndex.WeightedKeyword] = []
    for (position, keyword) in extraction.subject.prefix(3).enumerated() {
      weighted.append(.init(text: keyword, weight: 2.0 / (1.0 + Double(position) * 0.3)))
    }
    for (position, keyword) in extraction.related.prefix(10).enumerated() {
      weighted.append(.init(text: keyword, weight: 1.0 / (1.0 + Double(position) * 0.15)))
    }

    let candidates = index.search(keywords: weighted, limit: candidateLimit)
    result.candidateCount = candidates.count

    guard candidates.count >= 2 else {
      applyRootIndexFallback(query: query, index: index, to: &result)
      return result
    }

    // Step 2: constrained pick — the model can only emit candidate names.
    let pickStart = Date()
    do {
      let pick: Pick
      do {
        pick = try await pickSymbol(query: query, candidates: candidates)
      } catch {
        // The guardrail sometimes refuses harmless queries (finance, health)
        // only on the schema-constrained path; the identical prompt passes as
        // plain text. Retry unconstrained and parse.
        print("    [pick retry after] \(error)")
        pick = try await pickSymbolPlainText(query: query, candidates: candidates)
      }
      result.stageSeconds["pick"] = Date().timeIntervalSince(pickStart)
      result.pickName = database.symbol(named: pick.best)?.name
        ?? candidates.first!.displayEntry.name
      result.reason = pick.reason
      result.alternates = pick.alternates.filter { $0 != pick.best }
      // Top up alternates from retrieval order if the model gave too few.
      for candidate in candidates where result.alternates.count < 4 {
        let name = candidate.name
        if name != pick.best && !result.alternates.contains(name) {
          result.alternates.append(name)
        }
      }
    } catch {
      print("    [pick error] \(error)")
      result.stageSeconds["pick"] = Date().timeIntervalSince(pickStart)
      // Retrieval already ranked candidates; degrade to its top hit.
      result.usedFallback = true
      result.pickName = candidates.first!.displayEntry.name
      result.reason = "Closest match to your description."
      result.alternates = candidates.dropFirst().prefix(4).map(\.name)
    }
    return result
  }

  /// No-FM degradation: rank with the root index directly from query words.
  private func applyRootIndexFallback(query: String, index: RootIndex, to result: inout VariantResult) {
    result.usedFallback = true
    let words = query.lowercased()
      .split { !$0.isLetter && !$0.isNumber }
      .prefix(12)
      .map { RootIndex.WeightedKeyword(text: String($0), weight: 1.0) }
    let hits = index.search(keywords: Array(words), limit: 5)
    if let best = hits.first {
      result.pickName = best.displayEntry.name
      result.reason = "Closest match to your description."
      result.alternates = hits.dropFirst().map(\.name)
    } else {
      result.pickName = "sparkles"
      result.reason = "A glyph drawn at random."
      result.alternates = []
    }
  }

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

  struct Pick {
    var best: String
    var alternates: [String]
    var reason: String
  }

  /// Unconstrained fallback for guardrail refusals on the schema path.
  private func pickSymbolPlainText(query: String, candidates: [RootIndex.Root]) async throws -> Pick {
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
    let names = Set(candidates.map(\.name))
    guard names.contains(rawName) else {
      throw GlyphonError.recommendationFailed("plain-text pick not in candidates: \(rawName)")
    }
    let reason = lines.count > 1 ? lines[1] : ""
    return Pick(best: rawName, alternates: [], reason: reason)
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

  private func pickSymbol(query: String, candidates: [RootIndex.Root]) async throws -> Pick {
    let candidateNames = candidates.map(\.name)
    let list = candidates
      .map { root in
        let terms = root.terms.prefix(5)
        return terms.isEmpty ? "- \(root.name)" : "- \(root.name) (\(terms.joined(separator: ", ")))"
      }
      .joined(separator: "\n")

    let nameSchema = DynamicGenerationSchema(name: "SymbolName", anyOf: candidateNames)
    let alternatesSchema = DynamicGenerationSchema(
      arrayOf: DynamicGenerationSchema(name: "AlternateName", anyOf: candidateNames),
      minimumElements: 4,
      maximumElements: 4
    )
    let reasonSchema = DynamicGenerationSchema(type: String.self)

    var properties: [DynamicGenerationSchema.Property] = [
      .init(name: "best", description: "The single icon that most directly depicts the request", schema: nameSchema),
      .init(name: "alternates", description: "4 other relevant icons, best first", schema: alternatesSchema),
      .init(name: "reason", description: "One short sentence (max 20 words) explaining why `best` fits", schema: reasonSchema),
    ]
    if reasonFirst {
      properties = [properties[2], properties[0], properties[1]]
    }
    let schema = try GenerationSchema(
      root: DynamicGenerationSchema(name: "IconPick", properties: properties),
      dependencies: []
    )

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
    return Pick(
      best: try content.value(String.self, forProperty: "best"),
      alternates: try content.value([String].self, forProperty: "alternates"),
      reason: try content.value(String.self, forProperty: "reason")
    )
  }
}
