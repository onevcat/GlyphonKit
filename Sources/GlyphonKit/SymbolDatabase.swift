import Foundation

/// In-memory database of SF Symbols with an inverted index for fast search.
public final class SymbolDatabase: Sendable {
  public let symbols: [SymbolEntry]
  private let byName: [String: SymbolEntry]
  private let invertedIndex: [String: [Int]]
  /// Old name -> new name, for renamed symbols whose new name is in the
  /// database.
  private let replacements: [String: String]

  public var count: Int { symbols.count }

  public convenience init(symbols: [SymbolEntry]) {
    self.init(symbols: symbols, replacements: [:])
  }

  init(symbols: [SymbolEntry], replacements: [String: String]) {
    self.symbols = symbols
    self.replacements = replacements
    self.byName = Dictionary(uniqueKeysWithValues: symbols.map { ($0.name, $0) })
    self.invertedIndex = Self.buildIndex(symbols)
  }

  public func symbol(named name: String) -> SymbolEntry? {
    byName[name]
  }

  /// The name that the running system uses for a symbol.
  ///
  /// SF Symbols releases rename symbols and keep the old names as aliases.
  /// For an old name whose new name is in the database, this is the new
  /// name. For all other names it is the name itself.
  public func currentName(for name: String) -> String {
    replacements[name] ?? name
  }

  /// Returns symbol indices matching the given term via the inverted index.
  func indices(for term: String) -> [Int] {
    invertedIndex[term.lowercased()] ?? []
  }

  // MARK: - Loading

  static var bundledURL: URL? {
    Bundle.module.url(forResource: "symbols", withExtension: "json")
  }

  /// Load from the bundled symbols.json resource.
  ///
  /// Symbols that the running system does not have are left out, so every
  /// symbol in the database can be drawn.
  public static func bundled() throws -> SymbolDatabase {
    guard let url = bundledURL else {
      throw GlyphonError.resourceNotFound
    }
    return try load(from: url)
  }

  /// Load from a JSON file at the given URL.
  ///
  /// If the file has release data, symbols that the running system does
  /// not have are left out.
  public static func load(from url: URL) throws -> SymbolDatabase {
    try load(from: url, systemVersion: ProcessInfo.processInfo.operatingSystemVersion)
  }

  static func load(
    from url: URL,
    platform: String = SymbolAvailability.currentPlatform,
    systemVersion: OperatingSystemVersion
  ) throws -> SymbolDatabase {
    let data = try Data(contentsOf: url)
    let file = try JSONDecoder().decode(SymbolsFile.self, from: data)
    let unavailableYears = file.releases.map {
      SymbolAvailability(releases: $0).unavailableYears(platform: platform, version: systemVersion)
    } ?? []
    return file.database(withoutYears: unavailableYears)
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

    // Equal scores are common; order them by name so the result does not
    // depend on dictionary order and stays the same between calls.
    return scores
      .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
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
  /// Release year -> platform name -> the first system version with the
  /// symbols of that year. Files from before SF Symbols 2026 do not have it.
  let releases: [String: [String: String]]?
  /// Old name -> new name of the renamed symbols. An old name stays a
  /// symbol of its own, but the data has no terms or categories for it.
  let aliases: [String: String]?
  let symbols: [SymbolEntry]

  private static let whatsNew = "whatsnew"

  /// The database of a system that does not have the symbols of
  /// `unavailableYears`.
  func database(withoutYears unavailableYears: Set<String>) -> SymbolDatabase {
    guard !unavailableYears.isEmpty else {
      return SymbolDatabase(symbols: symbols, replacements: aliases ?? [:])
    }

    let unavailable = Dictionary(
      uniqueKeysWithValues: symbols.lazy.filter { unavailableYears.contains($0.year) }.map { ($0.name, $0) })
    var available = symbols.filter { !unavailableYears.contains($0.year) }
    var replacements: [String: String] = [:]

    // On this system, an old name whose new name is not available is the
    // only name of the symbol. Give it the metadata that moved to the new
    // name, or it cannot be found by term or category.
    var inherited: [String: SymbolEntry] = [:]
    for (old, new) in aliases ?? [:] {
      if let target = unavailable[new] {
        inherited[old] = target
      } else {
        replacements[old] = new
      }
    }
    if !inherited.isEmpty {
      available = available.map { symbol in
        guard let target = inherited[symbol.name], symbol.terms.isEmpty, symbol.categories.isEmpty else {
          return symbol
        }
        return SymbolEntry(
          name: symbol.name,
          year: symbol.year,
          categories: target.categories.filter { $0 != Self.whatsNew },
          terms: target.terms
        )
      }
    }

    // The data marks only its own newest release as "whatsnew". A system
    // without that release still has a newest release of its own.
    if !available.contains(where: { $0.categories.contains(Self.whatsNew) }),
       let newest = available.map(\.year).max(by: { SymbolYear.compare($0, $1) == .orderedAscending }) {
      let major = newest.prefix { $0 != "." }
      available = available.map { symbol in
        guard symbol.year.prefix(while: { $0 != "." }) == major else { return symbol }
        return SymbolEntry(
          name: symbol.name,
          year: symbol.year,
          categories: symbol.categories + [Self.whatsNew],
          terms: symbol.terms
        )
      }
    }

    return SymbolDatabase(symbols: available, replacements: replacements)
  }
}
