/// A single SF Symbol with its metadata.
public struct SymbolEntry: Sendable, Hashable, Codable {
  /// The SF Symbol name, e.g. `"folder.fill"`.
  public let name: String
  /// The SF Symbols version year when this symbol was introduced, e.g. `"2019"`.
  public let year: String
  /// Category keys this symbol belongs to, e.g. `["objectsandtools"]`.
  public let categories: [String]
  /// Search terms associated with this symbol, e.g. `["directory", "file"]`.
  public let terms: [String]

  public init(name: String, year: String, categories: [String], terms: [String]) {
    self.name = name
    self.year = year
    self.categories = categories
    self.terms = terms
  }

  /// Whether this is a locale-specific variant (e.g. `.ar`, `.hi`, `.zh`).
  public var isLocaleVariant: Bool {
    let suffixes = [".ar", ".hi", ".th", ".zh", ".ja", ".ko", ".he", ".km", ".my", ".bn"]
    return suffixes.contains(where: { name.hasSuffix($0) })
  }

  /// The base symbol name without locale suffix.
  public var baseName: String {
    let suffixes = [".ar", ".hi", ".th", ".zh", ".ja", ".ko", ".he", ".km", ".my", ".bn"]
    for suffix in suffixes where name.hasSuffix(suffix) {
      return String(name.dropLast(suffix.count))
    }
    return name
  }
}

/// A search result with relevance score.
public struct SymbolMatch: Sendable {
  public let symbol: SymbolEntry
  public let score: Double
}

/// A recommendation result from the AI recommender.
public struct SymbolRecommendation: Sendable {
  /// The best-matching symbol.
  public let symbol: SymbolEntry
  /// A short human-readable explanation, in the language of the request.
  public let reason: String
  /// Other relevant symbols, best first.
  public let alternates: [SymbolEntry]
  /// How many candidate symbols were weighed for this pick.
  public let consideredCount: Int
  /// Whether this was a random "feeling lucky" draw (empty input).
  public let isLucky: Bool
  /// Whether the on-device model made this pick; false means the
  /// recommender degraded to keyword retrieval.
  public let usedAI: Bool

  public init(
    symbol: SymbolEntry,
    reason: String,
    alternates: [SymbolEntry] = [],
    consideredCount: Int = 0,
    isLucky: Bool = false,
    usedAI: Bool = true
  ) {
    self.symbol = symbol
    self.reason = reason
    self.alternates = alternates
    self.consideredCount = consideredCount
    self.isLucky = isLucky
    self.usedAI = usedAI
  }
}
