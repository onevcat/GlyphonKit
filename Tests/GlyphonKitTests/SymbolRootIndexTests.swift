import Testing
@testable import GlyphonKit

@Suite("SymbolRootIndex")
struct SymbolRootIndexTests {
  static let database = try! SymbolDatabase.bundled()
  let index = SymbolRootIndex(database: Self.database)

  private func topRoots(for keywords: [(String, Double)], limit: Int = 25) -> [String] {
    let weighted = keywords.map { SymbolRootIndex.WeightedKeyword(text: $0.0, weight: $0.1) }
    return index.search(keywords: weighted, limit: limit).map(\.name)
  }

  @Test func dedupesRenderingVariantsIntoRoots() {
    let names = topRoots(for: [("dog", 2.0), ("pet", 1.0)])
    #expect(names.contains("dog"))
    // Variants like dog.fill / dog.circle collapse into the "dog" root.
    #expect(!names.contains("dog.fill"))
    #expect(!names.contains("dog.circle"))
  }

  @Test func aliasBridgesMissingVocabulary() {
    // "money" appears nowhere in the symbol metadata; the alias map must
    // still surface finance symbols.
    let names = topRoots(for: [("money", 2.0), ("budget", 1.0)])
    #expect(names.contains("banknote"))
    #expect(names.contains("dollarsign"))
  }

  @Test func multiWordTermsAreReachable() {
    // "pet friendly" is stored as a single term phrase; the per-word
    // tokenization must make it reachable from "pet".
    let names = topRoots(for: [("pet", 2.0)])
    #expect(names.contains("pawprint"))
  }

  @Test func noiseWordsDoNotMatchGenericSymbols() {
    let names = topRoots(for: [("app", 2.0), ("dog", 1.0)], limit: 10)
    #expect(names.contains("dog"))
    #expect(!names.contains("app"))
  }

  @Test func simpleRootsOutrankComposedOnes() {
    let names = topRoots(for: [("money", 2.0), ("finance", 1.0)], limit: 8)
    let composite = "dollarsign.gauge.chart.lefthalf.righthalf"
    if let compositeRank = names.firstIndex(of: composite), let plainRank = names.firstIndex(of: "dollarsign") {
      #expect(plainRank < compositeRank)
    }
  }

  @Test func displayEntryPrefersBaseSymbol() {
    let weighted = [SymbolRootIndex.WeightedKeyword(text: "dog", weight: 1.0)]
    let roots = index.search(keywords: weighted, limit: 25)
    let dog = roots.first { $0.name == "dog" }
    #expect(dog?.displayEntry.name == "dog")
  }

  @Test func excludesLocaleVariants() {
    let weighted = [SymbolRootIndex.WeightedKeyword(text: "book", weight: 1.0)]
    let roots = index.search(keywords: weighted, limit: 50)
    #expect(roots.allSatisfy { !$0.displayEntry.isLocaleVariant })
  }
}

@Suite("SymbolRecommendation")
struct SymbolRecommendationTests {
  @Test func defaultsKeepBackwardCompatibleShape() {
    let entry = SymbolEntry(name: "star", year: "2019", categories: [], terms: [])
    let recommendation = SymbolRecommendation(symbol: entry, reason: "why")
    #expect(recommendation.alternates.isEmpty)
    #expect(recommendation.consideredCount == 0)
    #expect(!recommendation.isLucky)
  }
}
