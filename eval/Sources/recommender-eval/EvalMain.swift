import Foundation
import FoundationModels
@testable import GlyphonKit

@main
struct EvalMain {
  static func main() async {
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else {
      printUsage()
      return
    }
    let command = args.removeFirst()
    do {
      switch command {
      case "check":
        checkAvailability()
      case "validate":
        try validateDataset(args)
      case "run":
        try await runEval(args)
      case "replay":
        try replay(args)
      case "query":
        try await runSingleQuery(args)
      default:
        printUsage()
      }
    } catch {
      print("error: \(error)")
      exit(1)
    }
  }

  /// Retrieval only, from the keywords of an earlier `prod` report: no
  /// model call, so a retrieval setting can be compared in seconds.
  /// Experimental options come from `--set key=value,...`.
  static func replay(_ args: [String]) throws {
    guard let reportPath = option("report", in: args), let datasetPath = option("dataset", in: args) else {
      printUsage()
      return
    }
    var settings: [String: String] = [:]
    for pair in (option("set", in: args) ?? "").split(separator: ",") {
      let parts = pair.split(separator: "=", maxSplits: 1)
      settings[String(parts[0])] = parts.count > 1 ? String(parts[1]) : "1"
    }
    func number(_ key: String, _ fallback: Double) -> Double { settings[key].flatMap(Double.init) ?? fallback }

    let database = try SymbolDatabase.bundled()
    let dataset = try EvalDataset.load(from: datasetPath)
    let report = try JSONDecoder().decode(EvalReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
    let keywords = Dictionary(uniqueKeysWithValues: report.cases.map { ($0.id, $0.keywords) })
    var concepts = SymbolConcepts.bundled
    if let path = settings["concepts"] {
      struct ConceptsFile: Decodable { let concepts: [String: [String]] }
      concepts = try JSONDecoder().decode(ConceptsFile.self, from: Data(contentsOf: URL(fileURLWithPath: path))).concepts
    }
    let index = SymbolRootIndex(database: database, mergesDuplicates: true, concepts: concepts)

    var options = SymbolRecommender.searchOptions(for: .os27)
    options.maxPerFamily = Int(number("cap", 3))
    options.wordShareExponent = number("exp", options.wordShareExponent)
    options.exactNameBonus = number("exact", options.exactNameBonus)
    options.conceptWeight = number("cw", options.conceptWeight)
    let topicWeight = number("wt", 2.0), iconWeight = number("wi", 1.5), decay = number("decay", 0.15)

    var sums = [1: 0.0, 2: 0.0, 3: 0.0, 6: 0.0, 25: 0.0]
    var lines: [String] = []
    for evalCase in dataset.cases {
      guard let words = keywords[evalCase.id], !words.isEmpty else { continue }
      var weighted = [SymbolRootIndex.WeightedKeyword(text: words[0], weight: topicWeight)]
      for (position, word) in words.dropFirst().enumerated() {
        weighted.append(.init(text: word, weight: iconWeight / (1.0 + Double(position) * decay)))
      }
      let names = index.search(keywords: weighted, limit: 25, options: options).map(\.name)
      let scores = names.map { matchScore(name: $0, expected: evalCase.expected, database: database) }
      for count in sums.keys {
        sums[count]! += scores.prefix(count).max() ?? 0
      }
      lines.append("\(evalCase.id) \(String(format: "%.1f", scores.first ?? 0)) \(names.prefix(6).joined(separator: " "))")
    }
    let count = Double(dataset.cases.count)
    print([1, 2, 3, 6, 25].map { "top\($0) \(String(format: "%.3f", sums[$0]! / count))" }.joined(separator: " | "))
    if settings["v"] != nil {
      lines.forEach { print($0) }
    }
  }

  static func printUsage() {
    print("""
      usage:
        recommender-eval check
        recommender-eval validate --dataset <path>
        recommender-eval run --variant <name> --dataset <path> [--only <id>] [--limit N] [--out <path>]
        recommender-eval query --variant <name> --text <query>
      """)
  }

  static func checkAvailability() {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
      print("Foundation model: available")
    case .unavailable(let reason):
      print("Foundation model: UNAVAILABLE — \(reason)")
    }
    print("Supported languages: \(model.supportedLanguages.count)")
  }

  static func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: "--\(name)"), index + 1 < args.count else { return nil }
    return args[index + 1]
  }

  static func validateDataset(_ args: [String]) throws {
    guard let path = option("dataset", in: args) else {
      printUsage()
      return
    }
    let database = try SymbolDatabase.bundled()
    let dataset = try EvalDataset.load(from: path)
    let problems = dataset.validate(against: database)
    if problems.isEmpty {
      print("dataset '\(dataset.name)' OK — \(dataset.cases.count) cases")
    } else {
      for problem in problems {
        print(problem)
      }
      exit(1)
    }
  }

  static func runEval(_ args: [String]) async throws {
    guard
      let variantName = option("variant", in: args),
      let datasetPath = option("dataset", in: args),
      let variant = makeVariant(named: variantName)
    else {
      printUsage()
      exit(1)
    }
    let database = try SymbolDatabase.bundled()
    let engine = SymbolSearchEngine(database: database)
    let dataset = try EvalDataset.load(from: datasetPath)

    var cases = dataset.cases
    if let only = option("only", in: args) {
      cases = cases.filter { $0.id == only }
    }
    if let limitText = option("limit", in: args), let limit = Int(limitText) {
      cases = Array(cases.prefix(limit))
    }

    var scores: [CaseScore] = []
    for (index, evalCase) in cases.enumerated() {
      let start = Date()
      do {
        let result = try await variant.recommend(query: evalCase.query, database: database, engine: engine)
        let seconds = Date().timeIntervalSince(start)
        let score = scoreCase(evalCase, result: result, seconds: seconds, database: database)
        scores.append(score)
        let mark = score.pickScore >= 0.99 ? "✓" : score.pickScore > 0 ? "~" : "✗"
        print("[\(index + 1)/\(cases.count)] \(mark) \(evalCase.id): \(result.pickName) (\(String(format: "%.2f", score.pickScore)))")
      } catch {
        print("[\(index + 1)/\(cases.count)] ✗ \(evalCase.id): ERROR \(error)")
        scores.append(scoreCase(
          evalCase,
          result: VariantResult(pickName: "<error>", alternates: [], reason: "\(error)"),
          seconds: Date().timeIntervalSince(start),
          database: database
        ))
      }
    }

    let report = buildReport(variant: variantName, dataset: dataset.name, scores: scores)
    printReport(report)

    if let outPath = option("out", in: args) {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(report).write(to: URL(fileURLWithPath: outPath))
      print("report written to \(outPath)")
    }
  }

  static func runSingleQuery(_ args: [String]) async throws {
    guard
      let variantName = option("variant", in: args),
      let text = option("text", in: args),
      let variant = makeVariant(named: variantName)
    else {
      printUsage()
      exit(1)
    }
    let database = try SymbolDatabase.bundled()
    let engine = SymbolSearchEngine(database: database)
    let result = try await variant.recommend(query: text, database: database, engine: engine)
    print("keywords:   \(result.keywords)")
    print("candidates: \(result.candidateCount) \(result.candidates)")
    print("pick:       \(result.pickName)")
    print("alternates: \(result.alternates)")
    print("reason:     \(result.reason)")
    print("fallback:   \(result.usedFallback)")
    print("stages:     \(result.stageSeconds.map { "\($0.key)=\(String(format: "%.2f", $0.value))s" }.joined(separator: " "))")
  }
}
