import Foundation

/// In-memory database of SF Symbols with an inverted index for fast search.
public final class SymbolDatabase: Sendable {
  public let symbols: [SymbolEntry]
  private let byName: [String: SymbolEntry]
  private let invertedIndex: [String: [Int]]

  public var count: Int { symbols.count }

  public init(symbols: [SymbolEntry]) {
    self.symbols = symbols
    self.byName = Dictionary(uniqueKeysWithValues: symbols.map { ($0.name, $0) })
    self.invertedIndex = Self.buildIndex(symbols)
  }

  public func symbol(named name: String) -> SymbolEntry? {
    byName[name]
  }

  /// Returns symbol indices matching the given term via the inverted index.
  func indices(for term: String) -> [Int] {
    invertedIndex[term.lowercased()] ?? []
  }

  // MARK: - Loading

  /// Load from the bundled symbols.json resource.
  public static func bundled() throws -> SymbolDatabase {
    guard let url = Bundle.module.url(forResource: "symbols", withExtension: "json") else {
      throw GlyphonError.resourceNotFound
    }
    return try load(from: url)
  }

  /// Load from a JSON file at the given URL.
  public static func load(from url: URL) throws -> SymbolDatabase {
    let data = try Data(contentsOf: url)
    let wrapper = try JSONDecoder().decode(SymbolsFile.self, from: data)
    return SymbolDatabase(symbols: wrapper.symbols)
  }

  // MARK: - Indexing

  private static func buildIndex(_ symbols: [SymbolEntry]) -> [String: [Int]] {
    var index: [String: [Int]] = [:]
    for (i, symbol) in symbols.enumerated() {
      let nameTokens = tokenize(symbol.name)
      let allTokens = nameTokens + symbol.terms.map { $0.lowercased() } + symbol.categories
      for token in Set(allTokens) {
        index[token, default: []].append(i)
      }
    }
    return index
  }

  /// Split a symbol name like `"arrow.up.circle.fill"` into `["arrow", "up", "circle", "fill"]`.
  static func tokenize(_ name: String) -> [String] {
    name.lowercased().split(separator: ".").map(String.init)
  }

  // MARK: - Categories

  /// Returns all unique category keys sorted alphabetically.
  public func allCategoryKeys() -> [String] {
    var keys = Set<String>()
    for symbol in symbols {
      for cat in symbol.categories {
        keys.insert(cat)
      }
    }
    return keys.sorted()
  }

  /// Returns the number of non-locale-variant symbols in each category.
  public func categorySymbolCounts() -> [String: Int] {
    var counts: [String: Int] = [:]
    for symbol in symbols where !symbol.isLocaleVariant {
      for cat in symbol.categories {
        counts[cat, default: 0] += 1
      }
    }
    return counts
  }

  /// Returns all non-locale-variant symbols belonging to the given category.
  public func symbols(inCategory category: String) -> [SymbolEntry] {
    symbols.filter { !$0.isLocaleVariant && $0.categories.contains(category) }
  }

  // MARK: - Variants

  private static let renderingModifiers: Set<String> = [
    "fill", "circle", "square", "rectangle", "diamond", "hexagon",
    "shield", "slash",
  ]

  /// Derives the semantic root by stripping trailing rendering modifiers.
  public static func semanticRoot(of name: String) -> String {
    var segments = name.split(separator: ".").map(String.init)
    while segments.count > 1, renderingModifiers.contains(segments.last!) {
      segments.removeLast()
    }
    return segments.joined(separator: ".")
  }

  /// Returns rendering variants (fill, circle, square, etc.) for the given symbol.
  public func variants(for symbol: SymbolEntry) -> [SymbolEntry] {
    let root = Self.semanticRoot(of: symbol.name)
    return symbols.filter { entry in
      entry.name != symbol.name
        && !entry.isLocaleVariant
        && Self.semanticRoot(of: entry.name) == root
    }
  }

  // MARK: - Related Symbols

  /// Returns related symbols using a priority cascade:
  /// 1. Same first-segment prefix
  /// 2. Matching secondary segments
  /// 3. Same category
  public func relatedSymbols(for symbol: SymbolEntry, limit: Int = 60) -> [SymbolEntry] {
    let root = Self.semanticRoot(of: symbol.name)
    let segments = symbol.name.split(separator: ".").map { $0.lowercased() }
    let firstSegment = segments.first ?? ""
    let secondarySegments = Set(segments.dropFirst())

    var scores: [String: Double] = [:]
    let variantNames = Set(variants(for: symbol).map(\.name)).union([symbol.name])

    for entry in symbols {
      guard !entry.isLocaleVariant, !variantNames.contains(entry.name) else { continue }
      let entryRoot = Self.semanticRoot(of: entry.name)
      guard entryRoot != root else { continue }

      var score = 0.0
      let entrySegments = entry.name.split(separator: ".").map { $0.lowercased() }

      if entrySegments.first == firstSegment {
        score += 3.0
      }

      let entrySecondary = Set(entrySegments.dropFirst())
      let overlap = secondarySegments.intersection(entrySecondary).count
      score += Double(overlap) * 1.5

      let commonCategories = Set(symbol.categories).intersection(Set(entry.categories))
      score += Double(commonCategories.count) * 0.5

      if score > 0 {
        scores[entry.name] = score
      }
    }

    return scores
      .sorted { $0.value > $1.value }
      .prefix(limit)
      .compactMap { byName[$0.key] }
  }

  // MARK: - Year Filtering

  /// Returns all unique introduction years, sorted.
  public func availableYears() -> [String] {
    var years = Set<String>()
    for symbol in symbols {
      years.insert(symbol.year)
    }
    return years.sorted()
  }

  /// Returns symbols introduced in the given year.
  public func symbols(introducedIn year: String) -> [SymbolEntry] {
    symbols.filter { $0.year == year && !$0.isLocaleVariant }
  }

  /// Returns symbols from the source list that match the given year.
  public static func filterByYear(_ year: String, from source: [SymbolEntry]) -> [SymbolEntry] {
    source.filter { $0.year == year }
  }

  /// Returns symbols from the source list matching any of the given years.
  public static func filterByYears(_ years: Set<String>, from source: [SymbolEntry]) -> [SymbolEntry] {
    source.filter { years.contains($0.year) }
  }
}

// MARK: - Internal Types

struct SymbolsFile: Codable {
  let version: String
  let count: Int
  let symbols: [SymbolEntry]
}
