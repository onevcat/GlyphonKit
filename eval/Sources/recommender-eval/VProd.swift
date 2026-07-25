import Foundation
import GlyphonKit

/// Evaluates the shipping SymbolRecommender in Sources/GlyphonKit — run this
/// after porting changes so the production pipeline never drifts from the
/// tuned harness variants.
struct VProd: Variant {
  let name = "prod"

  func recommend(query: String, database: SymbolDatabase, engine: SymbolSearchEngine) async throws -> VariantResult {
    let recommender = SymbolRecommender(database: database)
    let recommendation = try await recommender.recommend(from: query)
    return VariantResult(
      pickName: recommendation.symbol.name,
      alternates: recommendation.alternates.map(\.name),
      reason: recommendation.reason,
      candidateCount: recommendation.consideredCount
    )
  }
}
