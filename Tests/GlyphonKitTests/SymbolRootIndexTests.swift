import Foundation
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

  @Test func wordShareExponentKeepsMoreWeightForEachWordOfAPhrase() {
    // "memo" is half of a two-word keyword. With an equal share it loses
    // against the second keyword; with the square-root share it wins.
    let keywords = [("memo qqqq", 1.0), ("tasks", 0.4)]
    #expect(names(keywords).first == "checklist")
    #expect(names(keywords, options: .init(wordShareExponent: 0.5)).first == "text.pad.header")
  }

  @Test func additionalNoiseWordsAreIgnored() {
    #expect(names([("memo", 1.0)]) == ["text.pad.header"])
    #expect(names([("memo", 1.0)], options: .init(additionalNoiseWords: ["memo"])).isEmpty)
  }

  @Test func hyphenatedWordIsOneWordWhenItIsKnown() {
    // "todo" has an alias entry; "to" and "do" do not name a to-do list.
    #expect(names([("to-do", 1.0)]).isEmpty)
    #expect(names([("to-do", 1.0)], options: .init(joinsHyphenatedWords: true)).first == "checklist")
  }

  @Test func exactNameGetsABonus() {
    let keywords = [("tasks", 0.5), ("airpods", 0.45)]
    #expect(names(keywords).first == "checklist")
    #expect(names(keywords, options: .init(exactNameBonus: 0.3)).first == "airpods")
  }

  @Test func rootWithOnlyCrossedOutSymbolsIsLeftOutWhenDuplicatesAreMerged() {
    let database = SymbolDatabase(symbols: [
      SymbolEntry(name: "torch.slash", year: "2019", categories: [], terms: []),
      SymbolEntry(name: "torch.slash.fill", year: "2019", categories: [], terms: []),
      SymbolEntry(name: "torch.on.fill", year: "2019", categories: [], terms: []),
      SymbolEntry(name: "lamp", year: "2019", categories: [], terms: []),
      SymbolEntry(name: "lamp.slash", year: "2019", categories: [], terms: []),
    ])
    #expect(SymbolRootIndex(database: database).roots.map(\.name) == ["lamp", "torch", "torch.on"])
    #expect(SymbolRootIndex(database: database, mergesDuplicates: true).roots.map(\.name) == ["lamp", "torch.on"])
  }

  @Test func rootNamedSlashStays() {
    // Here the slash is the subject, not a crossed-out form.
    let database = SymbolDatabase(symbols: [
      SymbolEntry(name: "slash.circle", year: "2019", categories: [], terms: ["divide"]),
      SymbolEntry(name: "slash.circle.fill", year: "2019", categories: [], terms: ["divide"]),
    ])
    #expect(SymbolRootIndex(database: database, mergesDuplicates: true).roots.map(\.name) == ["slash"])
  }

  @Test func everyAdditionalAliasTargetIsAWordOfTheSymbolData() {
    let index = SymbolRootIndex(database: SymbolRootIndexTests.database, mergesDuplicates: true)
    for (word, targets) in SymbolRootIndex.aliasAdditionsOS27 {
      for target in targets {
        let hits = index.search(keywords: [.init(text: target, weight: 1.0)], limit: 1)
        #expect(!hits.isEmpty, "alias \(word) -> \(target) matches no symbol")
      }
    }
  }

  @Test func conceptWordsFindTheirRootOnlyWithAWeight() {
    let index = SymbolRootIndex(database: Self.renamed, concepts: ["airpods": ["earphones", "wireless"]])
    let keywords = [SymbolRootIndex.WeightedKeyword(text: "earphones", weight: 1.0)]
    #expect(index.search(keywords: keywords, limit: 5).isEmpty)
    #expect(index.search(keywords: keywords, limit: 5, options: .init(conceptWeight: 0.5)).map(\.name) == ["airpods"])
    #expect(index.roots.first { $0.name == "airpods" }?.concepts == ["earphones", "wireless"])
  }

  @Test func conceptMatchCountsLessThanANameMatch() {
    // `speaker` has the concept word; `message` has it as its name.
    let index = SymbolRootIndex(database: Self.renamed, concepts: ["speaker": ["message"]])
    let keywords = [SymbolRootIndex.WeightedKeyword(text: "message", weight: 1.0)]
    #expect(index.search(keywords: keywords, limit: 5, options: .init(conceptWeight: 0.5)).map(\.name) == ["message", "speaker"])
  }

  @Test func twoWordKeywordFindsAOneWordConcept() {
    // "smart" is a noise word, but "smart home" is the concept `smarthome`.
    let index = SymbolRootIndex(database: Self.renamed, concepts: ["speaker": ["smarthome", "filmstrip"]])
    let options = SymbolRootIndex.SearchOptions(joinsCompounds: true, joinsHyphenatedWords: true, conceptWeight: 0.5)
    func search(_ text: String) -> [String] {
      index.search(keywords: [.init(text: text, weight: 1.0)], limit: 5, options: options).map(\.name)
    }
    #expect(search("smart home") == ["speaker"])
    #expect(search("film strip") == ["speaker"])
    #expect(search("film-strip") == ["speaker"])
  }

  @Test func noiseWordIsNotAConceptWord() {
    // The search drops "library" before any lookup, so it must not be a
    // concept word either: it would only take a hint slot.
    let index = SymbolRootIndex(database: Self.renamed, concepts: ["speaker": ["library"]])
    let options = SymbolRootIndex.SearchOptions(conceptWeight: 0.5)
    #expect(index.search(keywords: [.init(text: "library", weight: 1.0)], limit: 5, options: options).isEmpty)
  }

  @Test func commonNameWordDampsTheConceptWordToo() {
    // "audio" is a term of four roots and a concept word of one. The
    // concept match must not count more than a name match.
    let index = SymbolRootIndex(database: Self.renamed, concepts: ["message": ["audio"]])
    let scored = index.scoredSearch(
      keywords: [.init(text: "audio", weight: 1.0)], limit: 10, options: .init(conceptWeight: 0.5))
    let message = scored.first { $0.root.name == "message" }?.score ?? 0
    let speaker = scored.first { $0.root.name == "speaker" }?.score ?? 0
    #expect(message > 0)
    #expect(message < speaker)
  }

  @Test func scoredSearchGivesTheScoresInOrder() {
    let index = SymbolRootIndex(database: Self.renamed)
    let scored = index.scoredSearch(keywords: [.init(text: "audio", weight: 1.0)], limit: 5)
    #expect(scored.map(\.root.name) == index.search(keywords: [.init(text: "audio", weight: 1.0)], limit: 5).map(\.name))
    #expect(scored.map(\.score) == scored.map(\.score).sorted(by: >))
    #expect(scored.allSatisfy { $0.score > 0 })
  }

  @Test func stopWordFilterKeepsLoneStopWords() {
    let database = SymbolDatabase(symbols: [
      SymbolEntry(name: "at", year: "2019", categories: [], terms: []),
    ])
    let index = SymbolRootIndex(database: database)
    let options = SymbolRootIndex.SearchOptions(ignoresStopWords: true)
    #expect(index.search(keywords: [.init(text: "at", weight: 1.0)], limit: 5, options: options).map(\.name) == ["at"])
  }

  @Test func nonPositiveLimitGivesNoResult() {
    let index = SymbolRootIndex(database: Self.renamed)
    let keywords = [SymbolRootIndex.WeightedKeyword(text: "audio", weight: 1.0)]
    #expect(index.search(keywords: keywords, limit: 4).count == 4)
    #expect(index.search(keywords: keywords, limit: 0).isEmpty)
    #expect(index.search(keywords: keywords, limit: -1).isEmpty)
  }

  @Test func rootKeepsItsBaseWhenOnlyAVariantWasRenamed() {
    // Only the diamond variant has a new name. The base symbol and its
    // other variants must stay findable under their root.
    let database = SymbolDatabase(
      symbols: [
        SymbolEntry(name: "arrow.up.right", year: "2019", categories: [], terms: []),
        SymbolEntry(name: "arrow.up.right.circle", year: "2019", categories: [], terms: []),
        SymbolEntry(name: "arrow.up.right.diamond", year: "2019", categories: [], terms: []),
        SymbolEntry(name: "arrow.turn.up.right.diamond", year: "2024", categories: [], terms: []),
      ],
      replacements: ["arrow.up.right.diamond": "arrow.turn.up.right.diamond"]
    )
    let index = SymbolRootIndex(database: database, mergesDuplicates: true)
    #expect(index.roots.map(\.name) == ["arrow.turn.up.right", "arrow.up.right"])
    #expect(index.roots[1].displayEntry.name == "arrow.up.right")
    #expect(index.roots[1].terms.isEmpty)
  }

  @Test func mergedRootDisplaysACurrentName() {
    // The root name `window.on` is not a symbol. The old name is shorter
    // than the new one, but it must not be the displayed symbol.
    let database = SymbolDatabase(
      symbols: [
        SymbolEntry(name: "win.on.rectangle", year: "2019", categories: [], terms: []),
        SymbolEntry(name: "window.on.rectangle", year: "2024", categories: [], terms: ["display"]),
      ],
      replacements: ["win.on.rectangle": "window.on.rectangle"]
    )
    let index = SymbolRootIndex(database: database, mergesDuplicates: true)
    #expect(index.roots.map(\.name) == ["window.on"])
    #expect(index.roots[0].displayEntry.name == "window.on.rectangle")
  }

  @Test func rootDoesNotHintItsOwnName() {
    let database = SymbolDatabase(
      symbols: [
        SymbolEntry(name: "ring.fill.square.fill", year: "2019", categories: [], terms: []),
        SymbolEntry(name: "ring.square.fill", year: "2024", categories: [], terms: []),
        SymbolEntry(name: "ring", year: "2019", categories: [], terms: ["band"]),
      ],
      replacements: ["ring.fill.square.fill": "ring.square.fill"]
    )
    let index = SymbolRootIndex(database: database, mergesDuplicates: true)
    #expect(index.roots.first { $0.name == "ring" }?.terms == ["band"])
  }
}

@Suite("Model generation settings")
struct ModelGenerationSettingsTests {
  /// The macOS 26 model cannot be measured again, so its settings must
  /// stay as they were when its prompts were tuned.
  @Test func macOS26KeepsTheSettingsItWasTunedWith() {
    #expect(SymbolRecommender.searchOptions(for: .os26) == SymbolRootIndex.SearchOptions())
    #expect(SymbolRecommender.pickListLength(for: .os26) == nil)
    #expect(SymbolRecommender.pickListScoreShare(for: .os26) == nil)
    #expect(SymbolRecommender.searchOptions(for: .os26).conceptWeight == 0)
    let options = SymbolRootIndex.SearchOptions()
    #expect(options.maxPerFamily == nil)
    #expect(!options.joinsCompounds)
    #expect(!options.ignoresStopWords)
    #expect(options.wordShareExponent == 1.0)
    #expect(options.exactNameBonus == 0)
    #expect(!options.joinsHyphenatedWords)
    #expect(options.additionalNoiseWords.isEmpty)
    #expect(options.additionalAliases.isEmpty)
  }

  @Test func macOS27UsesItsOwnSettings() {
    let options = SymbolRecommender.searchOptions(for: .os27)
    #expect(options.maxPerFamily == 3)
    #expect(options.joinsCompounds)
    #expect(options.ignoresStopWords)
    #expect(options.wordShareExponent == 0.5)
    #expect(options.exactNameBonus == 0.3)
    #expect(options.joinsHyphenatedWords)
    #expect(options.additionalNoiseWords.contains("icon"))
    #expect(options.additionalAliases == SymbolRootIndex.aliasAdditionsOS27)
    #expect(options.conceptWeight == 0.5)
    #expect(SymbolRecommender.pickListLength(for: .os27) == 6)
    #expect(SymbolRecommender.pickListScoreShare(for: .os27) == 0.7)
  }

  private func roots(_ count: Int) -> [SymbolRootIndex.Root] {
    (0..<count).map { number in
      let entry = SymbolEntry(name: "symbol\(number)", year: "2019", categories: [], terms: [])
      return SymbolRootIndex.Root(name: entry.name, displayEntry: entry, terms: [], tokens: [], phrases: [])
    }
  }

  @Test func macOS27PickListHasOnlyTheCandidatesNearTheBestScore() {
    let candidates = roots(8)
    let close = SymbolRecommender.pickList(
      from: candidates, scores: [1.0, 0.8, 0.7, 0.69, 0.9, 0.2, 0.1, 0.1], generation: .os27)
    // The list stops at the first candidate below 70% of the best score.
    #expect(close.map(\.name) == ["symbol0", "symbol1", "symbol2"])

    let clear = SymbolRecommender.pickList(
      from: candidates, scores: [1.0, 0.5, 0.5, 0.4, 0.3, 0.2, 0.1, 0.1], generation: .os27)
    #expect(clear.map(\.name) == ["symbol0"])

    let equal = SymbolRecommender.pickList(
      from: candidates, scores: Array(repeating: 1.0, count: 8), generation: .os27)
    #expect(equal.count == 6)
  }

  @Test func macOS26PickListHasAllCandidates() {
    let candidates = roots(8)
    let list = SymbolRecommender.pickList(
      from: candidates, scores: [1.0, 0.5, 0.5, 0.4, 0.3, 0.2, 0.1, 0.1], generation: .os26)
    #expect(list.count == 8)
  }
}

@Suite("SymbolConcepts")
struct SymbolConceptsTests {
  @Test func bundledConceptsAreWordsOfKnownRoots() throws {
    let concepts = SymbolConcepts.bundled
    #expect(concepts.count > 1500)

    // All releases, so that the check does not depend on the test system.
    let url = try #require(SymbolDatabase.bundledURL)
    let database = try SymbolDatabase.load(
      from: url, platform: "macOS",
      systemVersion: OperatingSystemVersion(majorVersion: 99, minorVersion: 0, patchVersion: 0))
    // The index that reads the concepts: a key for an old name or for a
    // root that this index leaves out would have no effect.
    let roots = Set(SymbolRootIndex(database: database, mergesDuplicates: true).roots.map(\.name))
    for (name, words) in concepts {
      #expect(roots.contains(name), "\(name) is not a root")
      #expect(!words.isEmpty)
      for word in words {
        #expect(word.allSatisfy { $0.isLowercase && $0.isLetter && $0.isASCII }, "\(name): \(word)")
        #expect(!SymbolRootIndex.noiseWords.contains(word), "\(name): \(word) is a noise word")
      }
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
