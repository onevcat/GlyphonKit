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

@Suite("SymbolRootIndex search options")
struct SymbolRootIndexSearchOptionsTests {
  private static let renamed = SymbolDatabase(
    symbols: [
      SymbolEntry(name: "note.text", year: "2020", categories: [], terms: []),
      SymbolEntry(name: "text.pad.header", year: "2024", categories: ["editing"], terms: ["memo"]),
      SymbolEntry(name: "headphones", year: "2019", categories: [], terms: ["audio"]),
      SymbolEntry(name: "headphones.dots", year: "2019", categories: [], terms: ["audio"]),
      SymbolEntry(name: "headphones.over.ear", year: "2019", categories: [], terms: ["audio"]),
      SymbolEntry(name: "speaker", year: "2019", categories: [], terms: ["audio"]),
      SymbolEntry(name: "checklist", year: "2019", categories: [], terms: ["tasks"]),
      SymbolEntry(name: "checklist.rtl", year: "2019", categories: [], terms: ["tasks"]),
      SymbolEntry(name: "airpods", year: "2019", categories: [], terms: []),
      SymbolEntry(name: "message", year: "2019", categories: [], terms: []),
    ],
    replacements: ["note.text": "text.pad.header"]
  )

  private func names(
    _ keywords: [(String, Double)],
    mergesDuplicates: Bool = false,
    options: SymbolRootIndex.SearchOptions = .init()
  ) -> [String] {
    let index = SymbolRootIndex(database: Self.renamed, mergesDuplicates: mergesDuplicates)
    let weighted = keywords.map { SymbolRootIndex.WeightedKeyword(text: $0.0, weight: $0.1) }
    return index.search(keywords: weighted, limit: 25, options: options).map(\.name)
  }

  @Test func defaultKeepsARenamedSymbolAsTwoRoots() {
    #expect(Set(names([("note", 1.0), ("memo", 1.0)])) == ["note.text", "text.pad.header"])
  }

  @Test func oldNameFindsTheNewNameWhenRenamedSymbolsAreMerged() {
    // "note" is a word of the old name only.
    #expect(names([("note", 1.0)], mergesDuplicates: true) == ["text.pad.header"])
  }

  @Test func mergedRootShowsTheOldNameAsItsFirstHint() {
    let index = SymbolRootIndex(database: Self.renamed, mergesDuplicates: true)
    let root = index.roots.first { $0.name == "text.pad.header" }
    #expect(root?.terms == ["note.text", "memo"])
    #expect(root?.displayEntry.name == "text.pad.header")
  }

  @Test func familyLimitKeepsRoomForOtherConcepts() {
    #expect(names([("audio", 1.0)]).count == 4)
    let limited = names([("audio", 1.0)], options: .init(maxPerFamily: 2))
    #expect(limited.filter { $0.hasPrefix("headphones") }.count == 2)
    #expect(limited.contains("speaker"))
  }

  @Test func scriptVariantsGetNoRootWhenDuplicatesAreMerged() {
    #expect(names([("tasks", 1.0)]) == ["checklist", "checklist.rtl"])
    #expect(names([("tasks", 1.0)], mergesDuplicates: true) == ["checklist"])
  }

  @Test func variantWithoutARenameEntryFollowsItsRoot() {
    // The rename table lists `old.thing` only; `old.thing.circle.fill` is
    // the same root and must not stay behind as a root of its own.
    let database = SymbolDatabase(
      symbols: [
        SymbolEntry(name: "old.thing", year: "2019", categories: [], terms: []),
        SymbolEntry(name: "old.thing.circle.fill", year: "2019", categories: [], terms: []),
        SymbolEntry(name: "new.thing", year: "2024", categories: [], terms: []),
      ],
      replacements: ["old.thing": "new.thing"]
    )
    let index = SymbolRootIndex(database: database, mergesDuplicates: true)
    #expect(index.roots.map(\.name) == ["new.thing"])
  }

  @Test func renameToALocaleVariantIsNotMerged() {
    let database = SymbolDatabase(
      symbols: [
        SymbolEntry(name: "help.video.rtl", year: "2019", categories: [], terms: []),
        SymbolEntry(name: "help.video.ar", year: "2024", categories: [], terms: []),
        SymbolEntry(name: "help.video", year: "2019", categories: [], terms: []),
      ],
      replacements: ["help.video.rtl": "help.video.ar"]
    )
    let index = SymbolRootIndex(database: database, mergesDuplicates: true)
    #expect(index.roots.map(\.name) == ["help.video"])
  }

  @Test func additionalAliasesApplyOnlyOnRequest() {
    #expect(names([("crypto", 1.0)]).isEmpty)
    let options = SymbolRootIndex.SearchOptions(additionalAliases: ["crypto": ["speaker"]])
    #expect(names([("crypto", 1.0)], options: options) == ["speaker"])
    #expect(SymbolRootIndex.aliasAdditionsOS27.keys.allSatisfy { SymbolRootIndex.aliasMap[$0] == nil })
  }

  @Test func stopWordFilterKeepsTermPhrasesAndLoneStopWords() {
    let database = SymbolDatabase(symbols: [
      SymbolEntry(name: "plus.magnifyingglass", year: "2019", categories: [], terms: ["zoom in"]),
      SymbolEntry(name: "at", year: "2019", categories: [], terms: []),
    ])
    let index = SymbolRootIndex(database: database)
    let options = SymbolRootIndex.SearchOptions(ignoresStopWords: true)
    func search(_ text: String) -> [String] {
      index.search(keywords: [.init(text: text, weight: 1.0)], limit: 5, options: options).map(\.name)
    }
    #expect(search("zoom in") == ["plus.magnifyingglass"])
    #expect(search("at") == ["at"])
  }

  @Test func nonPositiveLimitGivesNoResult() {
    #expect(names([("audio", 1.0)]).count == 4)
    let index = SymbolRootIndex(database: Self.renamed)
    #expect(index.search(keywords: [.init(text: "audio", weight: 1.0)], limit: 0).isEmpty)
  }

  @Test func compoundWordsMatchAsOneToken() {
    #expect(names([("air pods", 1.0)]).isEmpty)
    #expect(names([("air pods", 1.0)], options: .init(joinsCompounds: true)) == ["airpods"])
  }

  @Test func stopWordsDoNotTakeAShareOfTheWeight() {
    // "chat" reaches `message` through the alias map. With "and" in the
    // split, "chat" has a third of the phrase weight and loses against the
    // weaker second keyword; without it, "chat" has half and wins.
    let keywords = [("chat and messaging", 1.0), ("memo", 0.37)]
    #expect(names(keywords).first == "text.pad.header")
    #expect(names(keywords, options: .init(ignoresStopWords: true)).first == "message")
  }

  @Test func equalScoresHaveAStableOrder() {
    // The two roots get the same score and have names of the same length.
    let database = SymbolDatabase(symbols: [
      SymbolEntry(name: "bbb", year: "2019", categories: [], terms: ["same"]),
      SymbolEntry(name: "aaa", year: "2019", categories: [], terms: ["same"]),
    ])
    let index = SymbolRootIndex(database: database)
    let keywords = [SymbolRootIndex.WeightedKeyword(text: "same", weight: 1.0)]
    for _ in 0..<5 {
      #expect(index.search(keywords: keywords, limit: 5).map(\.name) == ["aaa", "bbb"])
    }
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
