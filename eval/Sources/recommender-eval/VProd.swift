import Foundation
@testable import GlyphonKit

/// Evaluates the shipping SymbolRecommender in Sources/GlyphonKit — run this
/// after porting changes so the production pipeline never drifts from the
/// tuned harness variants.
struct VProd: Variant {
  let name = "prod"

  func recommend(query: String, database: SymbolDatabase, engine: SymbolSearchEngine) async throws -> VariantResult {
    let recommender = SymbolRecommender(database: database)
    let (recommendation, trace) = try await recommender.recommendWithTrace(from: query)
    return VariantResult(
      pickName: recommendation.symbol.name,
      alternates: recommendation.alternates.map(\.name),
      reason: recommendation.reason,
      keywords: trace.keywords,
      keywordWeights: trace.keywordWeights,
      candidates: trace.candidates,
      pickList: trace.pickList,
      candidateScores: trace.scores,
      candidateCount: recommendation.consideredCount,
      usedFallback: !recommendation.usedAI
    )
  }
}

/// Stage 1 and retrieval of the shipping pipeline, without the pick: the
/// "pick" is the top candidate. Use it to tune keyword extraction and
/// retrieval on their own; the number to read is `candidateCeiling`.
struct VProdRetrieval: Variant {
  let name = "prod-retrieval"

  func recommend(query: String, database: SymbolDatabase, engine: SymbolSearchEngine) async throws -> VariantResult {
    let recommender = SymbolRecommender(database: database)
    var trace = SymbolRecommender.Trace()
    let candidates = try await recommender.retrieveCandidates(for: query, trace: &trace).map(\.root)
    return VariantResult(
      pickName: candidates.first?.name ?? "<none>",
      alternates: candidates.dropFirst().prefix(4).map(\.name),
      reason: "",
      keywords: trace.keywords,
      keywordWeights: trace.keywordWeights,
      candidates: trace.candidates,
      candidateScores: trace.scores,
      candidateCount: candidates.count
    )
  }
}
