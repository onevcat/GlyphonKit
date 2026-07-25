/// Glyphon — Natural language to SF Symbol mapping.
///
/// ```swift
/// let glyphon = try Glyphon()
///
/// // Keyword search (fast, no AI)
/// let results = glyphon.search("weather cloud rain")
///
/// // AI-powered recommendation (requires macOS 26+ / iOS 26+)
/// let pick = try await glyphon.recommend(from: readmeText)
/// ```
public struct Glyphon: Sendable {
  public let database: SymbolDatabase

  private let engine: SymbolSearchEngine
  private let recommender: SymbolRecommender

  /// Initialize with the bundled symbol database.
  public init() throws {
    try self.init(database: .bundled())
  }

  /// Initialize with a custom symbol database.
  public init(database: SymbolDatabase) {
    self.database = database
    self.engine = SymbolSearchEngine(database: database)
    self.recommender = SymbolRecommender(database: database)
  }

  /// Search for symbols matching a keyword query.
  public func search(_ query: String, limit: Int = 20) -> [SymbolMatch] {
    engine.search(query, limit: limit)
  }

  /// Recommend a symbol from a natural language description using Foundation Models.
  ///
  /// Falls back to keyword search when Foundation Models are unavailable.
  public func recommend(from text: String) async throws -> SymbolRecommendation {
    try await recommender.recommend(from: text)
  }

  /// Validate whether a symbol name exists in the database.
  public func isValid(_ name: String) -> Bool {
    database.symbol(named: name) != nil
  }

  /// Total number of symbols in the database.
  public var symbolCount: Int {
    database.count
  }
}

public enum GlyphonError: Error, Sendable {
  case resourceNotFound
  case recommendationFailed(String)
}
