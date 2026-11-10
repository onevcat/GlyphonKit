import Foundation

// usage: glyphon-extract [--source <metadata directory>] [<output path>]
//
// The default source is the symbol data of the running system. The
// SF Symbols app has its own, often newer, copy in
// "/Applications/SF Symbols.app/Contents/Resources/Metadata".

let systemSourcePath = [
  "/System/Library/PrivateFrameworks/SFSymbols.framework",
  "Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources",
].joined(separator: "/")

let (sourcePath, outputPath): (String, String?) = {
  var arguments = Array(CommandLine.arguments.dropFirst())
  var source = systemSourcePath
  if let index = arguments.firstIndex(of: "--source") {
    guard index + 1 < arguments.count else {
      fatalError("--source needs a directory")
    }
    source = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
  }
  return (source, arguments.first)
}()

func loadPlist<T>(named name: String) throws -> T {
  let url = URL(fileURLWithPath: "\(sourcePath)/\(name)")
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
guard let releases = availability["year_to_release"] as? [String: [String: String]] else {
  fatalError("Missing 'year_to_release' key in name_availability.plist")
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
  let releases: [String: [String: String]]
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

/// The data version is its newest release year ("2025.1" < "2026").
let version = Set(symbolsDict.values)
  .max { $0.compare($1, options: .numeric) == .orderedAscending } ?? ""

let output = OutputJSON(version: version, count: symbols.count, releases: releases, symbols: symbols)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(output)

if let path = outputPath {
  try data.write(to: URL(fileURLWithPath: path))
  print("Wrote \(symbols.count) symbols (version \(version)) to \(path)")
} else {
  FileHandle.standardOutput.write(data)
}
