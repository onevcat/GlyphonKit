import Foundation
import FoundationModels
import GlyphonKit

/// Faithful port of the shipping two-step pipeline in
/// Sources/GlyphonKit/SymbolRecommender.swift. Alternates reproduce the UI's
/// "OTHER CONTENDERS" row (raw-query keyword search, drop first, take 5).
struct V0Baseline: Variant {
  let name = "v0"

  func recommend(query: String, database: SymbolDatabase, engine: SymbolSearchEngine) async throws -> VariantResult {
    var result = VariantResult(pickName: "", alternates: [], reason: "")
    result.alternates = engine.search(query, limit: 60).dropFirst().prefix(5).map(\.symbol.name)

    let keywordStart = Date()
    let keywords = try await extractKeywords(from: query)
    result.stageSeconds["keywords"] = Date().timeIntervalSince(keywordStart)
    result.keywords = [keywords]

    let candidates = engine.search(keywords, limit: 60).map(\.symbol)
    result.candidateCount = candidates.count

    guard !candidates.isEmpty else {
      applySearchFallback(query: query, database: database, engine: engine, to: &result)
      return result
    }

    let candidateList = candidates
      .map { entry in
        let tags = entry.terms.isEmpty ? "" : " — \(entry.terms.joined(separator: ", "))"
        return "  \(entry.name)\(tags)"
      }
      .joined(separator: "\n")

    let prompt = """
      You are an icon selector for a code editor's project sidebar.

      Given the software project description below, pick the single best SF Symbol \
      from the candidate list. Prefer concrete, recognizable symbols over abstract ones. \
      Avoid overly generic symbols like "folder" or "doc".

      ## Project Description
      \(String(query.prefix(1000)))

      ## Candidate SF Symbols
      \(candidateList)

      Respond in exactly two lines:
      Line 1: the SF Symbol name (nothing else)
      Line 2: a brief reason (one sentence)
      """

    let pickStart = Date()
    let session = LanguageModelSession()
    let response = try await session.respond(to: prompt)
    result.stageSeconds["pick"] = Date().timeIntervalSince(pickStart)

    let lines = response.content.split(separator: "\n", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    let symbolName = lines.first ?? ""
    let reason = lines.count > 1 ? lines[1] : ""

    if let entry = database.symbol(named: symbolName) {
      result.pickName = entry.name
      result.reason = reason
      return result
    }

    let cleaned = symbolName.replacing("\"", with: "").trimmingCharacters(in: .punctuationCharacters)
    if let entry = database.symbol(named: cleaned) {
      result.pickName = entry.name
      result.reason = reason
      return result
    }

    applySearchFallback(query: query, database: database, engine: engine, to: &result)
    return result
  }

  private func extractKeywords(from text: String) async throws -> String {
    let prompt = """
      Extract 5-10 English keywords from the following text that best describe \
      what this software project does. Return only the keywords separated by spaces, \
      nothing else.

      \(String(text.prefix(1000)))
      """
    let session = LanguageModelSession()
    let response = try await session.respond(to: prompt)
    return response.content
  }
}

/// The pure keyword-search fallback path (no FM at all) — measures how much
/// the model actually adds over plain retrieval.
struct V0KeywordOnly: Variant {
  let name = "v0-nofm"

  func recommend(query: String, database: SymbolDatabase, engine: SymbolSearchEngine) async throws -> VariantResult {
    var result = VariantResult(pickName: "", alternates: [], reason: "")
    result.alternates = engine.search(query, limit: 60).dropFirst().prefix(5).map(\.symbol.name)
    applySearchFallback(query: query, database: database, engine: engine, to: &result)
    return result
  }
}

func applySearchFallback(query: String, database: SymbolDatabase, engine: SymbolSearchEngine, to result: inout VariantResult) {
  result.usedFallback = true
  let tokens = query.lowercased()
    .split { !$0.isLetter && !$0.isNumber }
    .map(String.init)
    .prefix(20)
  let joined = tokens.joined(separator: " ")
  if let best = engine.search(joined, limit: 1).first {
    result.pickName = best.symbol.name
    result.reason = "Best keyword match"
    return
  }
  let fallback = database.symbol(named: "app") ?? database.symbols.first!
  result.pickName = fallback.name
  result.reason = "Default fallback"
}
