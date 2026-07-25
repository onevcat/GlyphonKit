import Foundation

let bundlePath = [
  "/System/Library/PrivateFrameworks/SFSymbols.framework",
  "Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources",
].joined(separator: "/")

func loadPlist<T>(named name: String) throws -> T {
  let url = URL(fileURLWithPath: "\(bundlePath)/\(name)")
  let data = try Data(contentsOf: url)
  guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? T else {
    fatalError("Unexpected plist structure in \(name)")
  }
  return result
}

let availability: [String: Any] = try loadPlist(named: "name_availability.plist")
let searchTerms: [String: [String]] = try loadPlist(named: "symbol_search.plist")
let categories: [String: [String]] = try loadPlist(named: "symbol_categories.plist")

guard let symbolsDict = availability["symbols"] as? [String: String] else {
  fatalError("Missing 'symbols' key in name_availability.plist")
}

struct SymbolJSON: Codable {
  let name: String
  let year: String
  let categories: [String]
  let terms: [String]
}

struct OutputJSON: Codable {
  let version: String
  let count: Int
  let symbols: [SymbolJSON]
}

let symbols = symbolsDict.keys.sorted().map { name in
  SymbolJSON(
    name: name,
    year: symbolsDict[name] ?? "",
    categories: categories[name] ?? [],
    terms: searchTerms[name] ?? []
  )
}

let output = OutputJSON(version: "2025.1", count: symbols.count, symbols: symbols)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(output)

if CommandLine.arguments.count > 1 {
  let path = CommandLine.arguments[1]
  try data.write(to: URL(fileURLWithPath: path))
  print("Wrote \(symbols.count) symbols to \(path)")
} else {
  FileHandle.standardOutput.write(data)
}
