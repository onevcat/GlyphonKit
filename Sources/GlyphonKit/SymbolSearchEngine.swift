/// Keyword-based semantic search over the symbol database.
///
/// Tokenizes the query, matches against the inverted index (symbol name parts,
/// search terms, and categories), and returns results ranked by relevance.
public struct SymbolSearchEngine: Sendable {
  private let database: SymbolDatabase
  private let excludeLocaleVariants: Bool

  public init(database: SymbolDatabase, excludeLocaleVariants: Bool = true) {
    self.database = database
    self.excludeLocaleVariants = excludeLocaleVariants
  }

  /// Search for symbols matching the given query string.
  ///
  /// - Parameters:
  ///   - query: A natural language query, e.g. `"weather cloud rain"`.
  ///   - limit: Maximum number of results to return. Defaults to 20.
  /// - Returns: Ranked array of matches with relevance scores.
  public func search(_ query: String, limit: Int = 20) -> [SymbolMatch] {
    let queryTokens = query.lowercased()
      .split { $0.isWhitespace || $0 == "." || $0 == "," || $0 == "-" }
      .map(String.init)
    guard !queryTokens.isEmpty else { return [] }

    var scores: [Int: Double] = [:]

    for token in queryTokens {
      let exactHits = database.indices(for: token)
      for idx in exactHits {
        scores[idx, default: 0] += 1.0
      }

      if exactHits.isEmpty && token.count >= 3 {
        for (i, symbol) in database.symbols.enumerated() {
          let nameTokens = SymbolDatabase.tokenize(symbol.name)
          let allTokens = nameTokens + symbol.terms.map { $0.lowercased() }
          for t in allTokens where t.hasPrefix(token) && t.count <= token.count * 2 {
            scores[i, default: 0] += 0.5
          }
        }
      }
    }

    var matches = scores.compactMap { idx, score -> SymbolMatch? in
      let symbol = database.symbols[idx]
      if excludeLocaleVariants && symbol.isLocaleVariant { return nil }
      let normalized = score / Double(queryTokens.count)
      return SymbolMatch(symbol: symbol, score: normalized)
    }
    matches.sort { $0.score > $1.score }
    return Array(matches.prefix(limit))
  }

  /// Returns candidate symbols for a given query, formatted for LLM consumption.
  func candidates(for query: String, limit: Int = 80) -> [SymbolEntry] {
    search(query, limit: limit).map(\.symbol)
  }
}
