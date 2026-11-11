import Foundation
import GlyphonKit

/// Output of one pipeline run for one query.
struct VariantResult {
  var pickName: String
  var alternates: [String]
  var reason: String
  var keywords: [String] = []
  /// The retrieved candidate roots, best first (empty if the variant does
  /// not report them).
  var candidates: [String] = []
  /// The part of `candidates` that the model could choose from (empty if
  /// it is all of them).
  var pickList: [String] = []
  /// The retrieval scores of `candidates` (empty if not reported).
  var candidateScores: [Double] = []
  var candidateCount: Int = 0
  var usedFallback: Bool = false
  var stageSeconds: [String: Double] = [:]
}

protocol Variant: Sendable {
  var name: String { get }
  func recommend(query: String, database: SymbolDatabase, engine: SymbolSearchEngine) async throws -> VariantResult
}

func makeVariant(named name: String) -> Variant? {
  switch name {
  case "v0": V0Baseline()
  case "v0-nofm": V0KeywordOnly()
  case "v1": V1Guided()
  case "v1-reason-first": V1Guided(reasonFirst: true)
  case "v1-c40": V1Guided(candidateLimit: 40)
  case "v1-c15": V1Guided(candidateLimit: 15)
  case "prod": VProd()
  case "prod-retrieval": VProdRetrieval()
  default: nil
  }
}
