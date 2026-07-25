import Foundation

public enum SymbolMatchSortMode: String, CaseIterable, Identifiable, Sendable {
  case relevance
  case prefixMatch
  case name
  case newest

  public var id: Self { self }

  public var displayName: String {
    switch self {
    case .relevance:
      "Relevance"
    case .prefixMatch:
      "Prefix Match"
    case .name:
      "Name"
    case .newest:
      "Newest"
    }
  }

  public var description: String {
    switch self {
    case .relevance:
      "Keyword match score"
    case .prefixMatch:
      "Symbol name prefix"
    case .name:
      "Alphabetical"
    case .newest:
      "Introduction year"
    }
  }
}

public extension Array where Element == SymbolMatch {
  func sorted(using mode: SymbolMatchSortMode, query: String) -> [SymbolMatch] {
    switch mode {
    case .relevance:
      sortedByRelevance()
    case .prefixMatch:
      sortedByPrefixMatch(query: query)
    case .name:
      sortedByName()
    case .newest:
      sortedByNewest()
    }
  }

  private func sortedByRelevance() -> [SymbolMatch] {
    sorted { lhs, rhs in
      if lhs.score != rhs.score {
        return lhs.score > rhs.score
      }

      return lhs.symbol.name.localizedStandardCompare(rhs.symbol.name) == .orderedAscending
    }
  }

  private func sortedByPrefixMatch(query: String) -> [SymbolMatch] {
    let prefix = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !prefix.isEmpty else {
      return sortedByRelevance()
    }

    return sorted { lhs, rhs in
      let lhsMatches = lhs.symbol.name.lowercased().hasPrefix(prefix)
      let rhsMatches = rhs.symbol.name.lowercased().hasPrefix(prefix)

      if lhsMatches != rhsMatches {
        return lhsMatches
      }

      if lhsMatches {
        return lhs.symbol.name.localizedStandardCompare(rhs.symbol.name) == .orderedAscending
      }

      return relevanceComesBefore(lhs, rhs)
    }
  }

  private func sortedByName() -> [SymbolMatch] {
    sorted { lhs, rhs in
      lhs.symbol.name.localizedStandardCompare(rhs.symbol.name) == .orderedAscending
    }
  }

  private func sortedByNewest() -> [SymbolMatch] {
    sorted { lhs, rhs in
      switch SymbolYear.compare(lhs.symbol.year, rhs.symbol.year) {
      case .orderedAscending:
        return false
      case .orderedDescending:
        return true
      case .orderedSame:
        return lhs.symbol.name.localizedStandardCompare(rhs.symbol.name) == .orderedAscending
      }
    }
  }

  private func relevanceComesBefore(_ lhs: SymbolMatch, _ rhs: SymbolMatch) -> Bool {
    if lhs.score != rhs.score {
      return lhs.score > rhs.score
    }

    return lhs.symbol.name.localizedStandardCompare(rhs.symbol.name) == .orderedAscending
  }
}

public enum SymbolYear {
  public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let lhsComponents = components(from: lhs)
    let rhsComponents = components(from: rhs)
    let count = max(lhsComponents.count, rhsComponents.count)

    for index in 0..<count {
      let lhsValue = lhsComponents[safe: index] ?? 0
      let rhsValue = rhsComponents[safe: index] ?? 0

      if lhsValue < rhsValue {
        return .orderedAscending
      }
      if lhsValue > rhsValue {
        return .orderedDescending
      }
    }

    return .orderedSame
  }

  private static func components(from year: String) -> [Int] {
    year.split(separator: ".").map { Int($0) ?? 0 }
  }
}

private extension Array {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
