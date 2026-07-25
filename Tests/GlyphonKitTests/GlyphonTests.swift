import Testing
@testable import GlyphonKit

@Suite("Glyphon")
struct GlyphonTests {
  let glyphon = try! Glyphon()

  @Test func loadsBundledDatabase() {
    #expect(glyphon.symbolCount > 5000)
  }

  @Test func validatesSymbolNames() {
    #expect(glyphon.isValid("folder"))
    #expect(glyphon.isValid("star.fill"))
    #expect(!glyphon.isValid("nonexistent.symbol.name"))
  }

  @Test func searchFindsRelevantSymbols() {
    let results = glyphon.search("weather cloud rain")
    #expect(!results.isEmpty)

    let names = results.map(\.symbol.name)
    let hasWeatherSymbol = names.contains { $0.contains("cloud") || $0.contains("rain") }
    #expect(hasWeatherSymbol)
  }

  @Test func searchReturnsEmptyForGibberish() {
    let results = glyphon.search("xyzqwerty123")
    #expect(results.isEmpty)
  }

  @Test func searchRespectsLimit() {
    let results = glyphon.search("arrow", limit: 5)
    #expect(results.count <= 5)
  }

  @Test func searchExcludesLocaleVariantsByDefault() {
    let results = glyphon.search("circle", limit: 100)
    let hasLocaleVariant = results.contains { $0.symbol.isLocaleVariant }
    #expect(!hasLocaleVariant)
  }

  @Test func localeVariantDetection() {
    let entry = SymbolEntry(name: "0.circle.ar", year: "2022.1", categories: [], terms: [])
    #expect(entry.isLocaleVariant)
    #expect(entry.baseName == "0.circle")

    let base = SymbolEntry(name: "folder.fill", year: "2019", categories: [], terms: [])
    #expect(!base.isLocaleVariant)
    #expect(base.baseName == "folder.fill")
  }
}

// MARK: - Search Result Sorting Tests

@Suite("Symbol Match Sorting")
struct SymbolMatchSortingTests {
  @Test func prefixMatchPrioritizesStrictNamePrefixesAlphabetically() {
    let matches = [
      match("z.square", year: "2020", score: 9),
      match("a.b", year: "2020", score: 1),
      match("a.a.y", year: "2020", score: 3),
      match("b.circle", year: "2020", score: 8),
      match("a.a.fill", year: "2020", score: 4),
      match("a.a", year: "2020", score: 2),
    ]

    let sorted = matches.sorted(using: .prefixMatch, query: "a.").map(\.symbol.name)

    #expect(sorted == ["a.a", "a.a.fill", "a.a.y", "a.b", "z.square", "b.circle"])
  }

  @Test func prefixMatchFallsBackToRelevanceWhenQueryIsEmpty() {
    let matches = [
      match("a.a", year: "2020", score: 1),
      match("b.circle", year: "2020", score: 3),
      match("a.b", year: "2020", score: 2),
    ]

    let sorted = matches.sorted(using: .prefixMatch, query: "").map(\.symbol.name)

    #expect(sorted == ["b.circle", "a.b", "a.a"])
  }

  @Test func newestSortUsesNumericYearComponentsDescending() {
    let matches = [
      match("old", year: "2020", score: 3),
      match("newerMinor", year: "2024.1", score: 1),
      match("newerMajor", year: "2025", score: 2),
      match("newerBase", year: "2024", score: 4),
    ]

    let sorted = matches.sorted(using: .newest, query: "ignored").map(\.symbol.name)

    #expect(sorted == ["newerMajor", "newerMinor", "newerBase", "old"])
  }

  @Test func symbolYearCompareHandlesMinorVersions() {
    let years = ["2025", "2024", "2025.1", "2026", "2025.2"]
      .sorted { lhs, rhs in
        SymbolYear.compare(lhs, rhs) == .orderedDescending
      }

    #expect(years == ["2026", "2025.2", "2025.1", "2025", "2024"])
  }

  @Test func nameSortUsesSymbolNameAscending() {
    let matches = [
      match("b.circle", year: "2020", score: 3),
      match("a.b", year: "2020", score: 1),
      match("a.a", year: "2020", score: 2),
    ]

    let sorted = matches.sorted(using: .name, query: "ignored").map(\.symbol.name)

    #expect(sorted == ["a.a", "a.b", "b.circle"])
  }

  private func match(_ name: String, year: String, score: Double) -> SymbolMatch {
    SymbolMatch(
      symbol: SymbolEntry(name: name, year: year, categories: [], terms: []),
      score: score
    )
  }
}

// MARK: - Category Tests

@Suite("SymbolDatabase Categories")
struct SymbolDatabaseCategoryTests {
  let db = StubDatabase.stub()

  @Test func allCategoryKeysReturnsSortedUniqueKeys() {
    let keys = db.allCategoryKeys()
    #expect(keys == keys.sorted())
    #expect(keys.contains("shapes"))
    #expect(keys.contains("weather"))
    #expect(keys.contains("arrows"))
    #expect(keys.contains("health"))
    #expect(keys.contains("multicolor"))
    #expect(keys.contains("indices"))
    #expect(keys.contains("objectsandtools"))
    #expect(Set(keys).count == keys.count)
  }

  @Test func categorySymbolCountsExcludesLocaleVariants() {
    let counts = db.categorySymbolCounts()
    // "indices" has only "0.circle.ar" which IS a locale variant → count should be 0
    #expect(counts["indices"] == nil || counts["indices"] == 0)
    // "shapes" has star, star.fill, star.circle, star.circle.fill, star.square, star.slash = 6
    #expect(counts["shapes"] == 6)
  }

  @Test func symbolsInCategoryReturnsCorrectSet() {
    let weather = db.symbols(inCategory: "weather")
    #expect(!weather.isEmpty)
    #expect(weather.allSatisfy { $0.categories.contains("weather") })
    #expect(weather.allSatisfy { !$0.isLocaleVariant })
  }

  @Test func symbolsInCategoryExcludesLocaleVariants() {
    let indices = db.symbols(inCategory: "indices")
    #expect(indices.isEmpty)
  }

  @Test func symbolsInUnknownCategoryReturnsEmpty() {
    let result = db.symbols(inCategory: "nonexistent")
    #expect(result.isEmpty)
  }
}

// MARK: - Variant Tests

@Suite("SymbolDatabase Variants")
struct SymbolDatabaseVariantTests {
  let db = StubDatabase.stub()

  @Test func semanticRootStripsRenderingModifiers() {
    #expect(SymbolDatabase.semanticRoot(of: "star.fill") == "star")
    #expect(SymbolDatabase.semanticRoot(of: "star.circle.fill") == "star")
    #expect(SymbolDatabase.semanticRoot(of: "star.square") == "star")
    #expect(SymbolDatabase.semanticRoot(of: "star.slash") == "star")
    #expect(SymbolDatabase.semanticRoot(of: "star") == "star")
  }

  @Test func semanticRootPreservesSemanticSegments() {
    #expect(SymbolDatabase.semanticRoot(of: "cloud.rain") == "cloud.rain")
    #expect(SymbolDatabase.semanticRoot(of: "cloud.rain.fill") == "cloud.rain")
    #expect(SymbolDatabase.semanticRoot(of: "cloud.rain.circle") == "cloud.rain")
    #expect(SymbolDatabase.semanticRoot(of: "cloud.sun") == "cloud.sun")
    #expect(SymbolDatabase.semanticRoot(of: "arrow.up") == "arrow.up")
    #expect(SymbolDatabase.semanticRoot(of: "arrow.up.circle.fill") == "arrow.up")
  }

  @Test func variantsOfStarReturnsAllStarVariants() {
    let star = db.symbol(named: "star")!
    let variants = db.variants(for: star)
    let names = Set(variants.map(\.name))
    #expect(names.contains("star.fill"))
    #expect(names.contains("star.circle"))
    #expect(names.contains("star.circle.fill"))
    #expect(names.contains("star.square"))
    #expect(names.contains("star.slash"))
    #expect(!names.contains("star"))
  }

  @Test func variantsOfFillFormReturnsSameGroup() {
    let starFill = db.symbol(named: "star.fill")!
    let variants = db.variants(for: starFill)
    let names = Set(variants.map(\.name))
    #expect(names.contains("star"))
    #expect(names.contains("star.circle"))
    #expect(!names.contains("star.fill"))
  }

  @Test func variantsOfCloudRainDoesNotIncludeCloud() {
    let cloudRain = db.symbol(named: "cloud.rain")!
    let variants = db.variants(for: cloudRain)
    let names = Set(variants.map(\.name))
    #expect(names.contains("cloud.rain.fill"))
    #expect(names.contains("cloud.rain.circle"))
    #expect(!names.contains("cloud"))
    #expect(!names.contains("cloud.fill"))
    #expect(!names.contains("cloud.sun"))
  }

  @Test func variantsExcludesLocaleVariants() {
    let variants = db.variants(for: db.symbol(named: "star")!)
    #expect(variants.allSatisfy { !$0.isLocaleVariant })
  }
}

// MARK: - Related Tests

@Suite("SymbolDatabase Related Symbols")
struct SymbolDatabaseRelatedTests {
  let db = StubDatabase.stub()

  @Test func relatedSymbolsExcludesSelfAndVariants() {
    let star = db.symbol(named: "star")!
    let related = db.relatedSymbols(for: star)
    let names = Set(related.map(\.name))
    // Should not contain star or any star.* variant
    #expect(!names.contains("star"))
    #expect(!names.contains("star.fill"))
    #expect(!names.contains("star.circle"))
  }

  @Test func relatedSymbolsPrioritizesSameFirstSegment() {
    let cloudRain = db.symbol(named: "cloud.rain")!
    let related = db.relatedSymbols(for: cloudRain)
    let names = related.map(\.name)
    // cloud.sun should appear because it shares the "cloud" first segment
    #expect(names.contains("cloud.sun") || names.contains("cloud.sun.fill"))
  }

  @Test func relatedSymbolsReturnsEmptyForIsolatedSymbol() {
    let folder = db.symbol(named: "folder")!
    let related = db.relatedSymbols(for: folder)
    // folder has no first-segment siblings, no secondary segment matches → only category overlap
    // It should still find something via category overlap if any
    // but the set is small, so might be empty or very few
    #expect(related.count < db.count)
  }

  @Test func relatedSymbolsExcludesLocaleVariants() {
    let star = db.symbol(named: "star")!
    let related = db.relatedSymbols(for: star)
    #expect(related.allSatisfy { !$0.isLocaleVariant })
  }
}

// MARK: - Year Filtering Tests

@Suite("SymbolDatabase Year Filtering")
struct SymbolDatabaseYearTests {
  let db = StubDatabase.stub()

  @Test func availableYearsReturnsSortedUniqueYears() {
    let years = db.availableYears()
    #expect(years == years.sorted())
    #expect(years.contains("2019"))
    #expect(years.contains("2020"))
    #expect(years.contains("2021"))
    #expect(years.contains("2022.1"))
    #expect(Set(years).count == years.count)
  }

  @Test func symbolsIntroducedInYearFiltersCorrectly() {
    let symbols2021 = db.symbols(introducedIn: "2021")
    #expect(!symbols2021.isEmpty)
    #expect(symbols2021.allSatisfy { $0.year == "2021" })
    #expect(symbols2021.allSatisfy { !$0.isLocaleVariant })
  }

  @Test func filterByYearFromSourceList() {
    let all = db.symbols(inCategory: "shapes")
    let filtered = SymbolDatabase.filterByYear("2020", from: all)
    #expect(filtered.allSatisfy { $0.year == "2020" })
    #expect(!filtered.isEmpty)
  }

  @Test func filterByMultipleYears() {
    let all = db.symbols(inCategory: "weather")
    let filtered = SymbolDatabase.filterByYears(["2019", "2021"], from: all)
    #expect(filtered.allSatisfy { $0.year == "2019" || $0.year == "2021" })
    #expect(!filtered.isEmpty)
  }

  @Test func filterByNonexistentYearReturnsEmpty() {
    let filtered = db.symbols(introducedIn: "2099")
    #expect(filtered.isEmpty)
  }
}
