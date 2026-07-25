import Foundation
import GlyphonKit

/// A weighted acceptable answer. `root` is a semantic root (rendering
/// modifiers like .fill/.circle stripped), so any variant of it counts.
struct ExpectedSymbol: Codable {
  let root: String
  let weight: Double
}

struct EvalCase: Codable {
  let id: String
  let query: String
  let lang: String
  let expected: [ExpectedSymbol]
  let notes: String?
}

struct EvalDataset: Codable {
  let name: String
  let cases: [EvalCase]

  static func load(from path: String) throws -> EvalDataset {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(EvalDataset.self, from: data)
  }

  /// Ensure every expected root resolves to at least one symbol in the DB.
  func validate(against database: SymbolDatabase) -> [String] {
    var problems: [String] = []
    var knownRoots = Set<String>()
    for symbol in database.symbols {
      knownRoots.insert(symbol.name)
      knownRoots.insert(SymbolDatabase.semanticRoot(of: symbol.name))
    }
    for evalCase in cases {
      for expected in evalCase.expected where !knownRoots.contains(expected.root) {
        problems.append("[\(evalCase.id)] unknown root: \(expected.root)")
      }
      let ids = cases.filter { $0.id == evalCase.id }
      if ids.count > 1 {
        problems.append("duplicate id: \(evalCase.id)")
      }
    }
    return problems
  }
}
