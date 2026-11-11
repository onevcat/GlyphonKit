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

  /// Retrieval only, from the keywords and weights of an earlier `prod`
  /// report: no model call, so a retrieval setting can be compared in
  /// seconds. Experimental options come from `--set key=value,...`.
  static func replay(_ args: [String]) throws {
    guard let reportPath = option("report", in: args), let datasetPath = option("dataset", in: args) else {
      printUsage()
      return
    }
    var settings: [String: String] = [:]
    for pair in (option("set", in: args) ?? "").split(separator: ",") {
      let parts = pair.split(separator: "=", maxSplits: 1)
      guard let key = parts.first else { continue }
      settings[String(key)] = parts.count > 1 ? String(parts[1]) : "1"
    }
    func number(_ key: String, _ fallback: Double) throws -> Double {
      guard let text = settings[key] else { return fallback }
      guard let value = Double(text), value.isFinite else {
        throw GlyphonError.recommendationFailed("setting \(key) is not a number: \(text)")
      }
      return value
    }

    let database = try SymbolDatabase.bundled()
    let dataset = try EvalDataset.load(from: datasetPath)
    let report = try JSONDecoder().decode(EvalReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
    let cases = Dictionary(report.cases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let index = SymbolRootIndex(database: database, mergesDuplicates: true)

    var options = SymbolRecommender.searchOptions(for: .os27)
    options.maxPerFamily = Int(try number("cap", Double(options.maxPerFamily ?? 3)))
    if settings["nocompounds"] != nil { options.joinsCompounds = false }
    if settings["nostopwords"] != nil { options.ignoresStopWords = false }
    if settings["nohyphens"] != nil { options.joinsHyphenatedWords = false }
    if settings["noaliases"] != nil { options.additionalAliases = [:] }

    let counts = [1, 2, 3, 6, 25]
    var sums = Dictionary(uniqueKeysWithValues: counts.map { ($0, 0.0) })
    var replayed = 0
    var lines: [String] = []
    for evalCase in dataset.cases {
      guard
        let reported = cases[evalCase.id],
        let weights = reported.keywordWeights,
        weights.count == reported.keywords.count,
        !weights.isEmpty
      else { continue }
      let weighted = zip(reported.keywords, weights).map { SymbolRootIndex.WeightedKeyword(text: $0, weight: $1) }
      let names = index.search(keywords: weighted, limit: 25, options: options).map(\.name)
      let scores = names.map { matchScore(name: $0, expected: evalCase.expected, database: database) }
      for count in counts {
        sums[count]! += scores.prefix(count).max() ?? 0
      }
      replayed += 1
      lines.append("\(evalCase.id) \(String(format: "%.1f", scores.first ?? 0)) \(names.prefix(6).joined(separator: " "))")
    }
    guard replayed > 0 else {
      throw GlyphonError.recommendationFailed(
        "no case of the dataset has keywords and weights in the report (wrong report, or a report from before `keywordWeights`)")
    }
    print(counts.map { "top\($0) \(String(format: "%.3f", sums[$0]! / Double(replayed)))" }.joined(separator: " | "))
    if replayed < dataset.cases.count {
      print("replayed \(replayed) of \(dataset.cases.count) cases; the others have no keywords in the report")
    }
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
        recommender-eval replay --report <prod report> --dataset <path> [--set cap=3,nocompounds,nostopwords,nohyphens,noaliases,v]
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
