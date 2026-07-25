import Foundation
import GlyphonKit

struct CaseScore: Codable {
  let id: String
  let query: String
  let pick: String
  let pickScore: Double
  let alternates: [String]
  let alternateHitRatio: Double
  let reason: String
  let keywords: [String]
  let candidateCount: Int
  let usedFallback: Bool
  let totalSeconds: Double
}

struct EvalReport: Codable {
  let variant: String
  let dataset: String
  let meanPickScore: Double
  let perfectRate: Double
  let acceptableRate: Double
  let missRate: Double
  let fallbackRate: Double
  let meanAlternateHitRatio: Double
  let meanSeconds: Double
  let cases: [CaseScore]
}

func scoreCase(_ evalCase: EvalCase, result: VariantResult, seconds: Double) -> CaseScore {
  let pickScore = matchScore(name: result.pickName, expected: evalCase.expected)

  let pickRoot = SymbolDatabase.semanticRoot(of: result.pickName)
  var seenRoots: Set<String> = [pickRoot]
  var hits = 0
  var counted = 0
  for alternate in result.alternates {
    let root = SymbolDatabase.semanticRoot(of: alternate)
    guard !seenRoots.contains(root) else { continue }
    seenRoots.insert(root)
    counted += 1
    if matchScore(name: alternate, expected: evalCase.expected) > 0 {
      hits += 1
    }
  }
  let ratio = counted == 0 ? 0 : Double(hits) / Double(counted)

  return CaseScore(
    id: evalCase.id,
    query: evalCase.query,
    pick: result.pickName,
    pickScore: pickScore,
    alternates: result.alternates,
    alternateHitRatio: ratio,
    reason: result.reason,
    keywords: result.keywords,
    candidateCount: result.candidateCount,
    usedFallback: result.usedFallback,
    totalSeconds: seconds
  )
}

func matchScore(name: String, expected: [ExpectedSymbol]) -> Double {
  let root = SymbolDatabase.semanticRoot(of: name)
  var best = 0.0
  for candidate in expected {
    if candidate.root == name || candidate.root == root {
      best = max(best, candidate.weight)
    }
  }
  return best
}

func buildReport(variant: String, dataset: String, scores: [CaseScore]) -> EvalReport {
  let count = Double(scores.count)
  let mean = scores.map(\.pickScore).reduce(0, +) / max(count, 1)
  let perfect = Double(scores.filter { $0.pickScore >= 0.99 }.count) / max(count, 1)
  let acceptable = Double(scores.filter { $0.pickScore > 0 }.count) / max(count, 1)
  let fallback = Double(scores.filter(\.usedFallback).count) / max(count, 1)
  let altMean = scores.map(\.alternateHitRatio).reduce(0, +) / max(count, 1)
  let secMean = scores.map(\.totalSeconds).reduce(0, +) / max(count, 1)
  return EvalReport(
    variant: variant,
    dataset: dataset,
    meanPickScore: mean,
    perfectRate: perfect,
    acceptableRate: acceptable,
    missRate: 1 - acceptable,
    fallbackRate: fallback,
    meanAlternateHitRatio: altMean,
    meanSeconds: secMean,
    cases: scores
  )
}

private func pad(_ text: String, _ width: Int) -> String {
  text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
}

func printReport(_ report: EvalReport) {
  print("")
  print("\(pad("case", 28)) \(pad("score", 5))  \(pad("pick", 34)) alt-hit")
  print(String(repeating: "-", count: 84))
  for score in report.cases {
    let flag = score.usedFallback ? " [FB]" : ""
    let scoreText = String(format: "%5.2f", score.pickScore)
    let ratioText = String(format: "%4.2f", score.alternateHitRatio)
    print("\(pad(score.id, 28)) \(scoreText)  \(pad(score.pick, 34)) \(ratioText)\(flag)")
  }
  print(String(repeating: "-", count: 84))
  print("variant=\(report.variant) dataset=\(report.dataset)")
  print(String(format: "meanPickScore     %.3f", report.meanPickScore))
  print(String(format: "perfectRate       %.1f%%", report.perfectRate * 100))
  print(String(format: "acceptableRate    %.1f%%", report.acceptableRate * 100))
  print(String(format: "missRate          %.1f%%", report.missRate * 100))
  print(String(format: "fallbackRate      %.1f%%", report.fallbackRate * 100))
  print(String(format: "altHitRatio       %.3f", report.meanAlternateHitRatio))
  print(String(format: "meanSeconds       %.2f", report.meanSeconds))
}
