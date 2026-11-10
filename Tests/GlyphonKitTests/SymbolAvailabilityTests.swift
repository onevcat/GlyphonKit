import Foundation
import Testing
@testable import GlyphonKit

@Suite("SymbolAvailability")
struct SymbolAvailabilityTests {
  private let availability = SymbolAvailability(releases: [
    "2025": ["macOS": "26.0", "iOS": "26.0"],
    "2025.1": ["macOS": "26.1", "iOS": "26.1"],
    "2026": ["macOS": "27.0", "iOS": "27.0"],
  ])

  private func version(_ major: Int, _ minor: Int, _ patch: Int = 0) -> OperatingSystemVersion {
    OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
  }

  @Test func symbolsOfALaterSystemAreNotAvailable() {
    #expect(!availability.isAvailable(year: "2026", platform: "macOS", version: version(26, 5, 1)))
    #expect(!availability.isAvailable(year: "2025.1", platform: "iOS", version: version(26, 0, 2)))
  }

  @Test func symbolsOfTheSameOrAnEarlierSystemAreAvailable() {
    #expect(availability.isAvailable(year: "2026", platform: "macOS", version: version(27, 0)))
    #expect(availability.isAvailable(year: "2025.1", platform: "iOS", version: version(26, 1)))
    #expect(availability.isAvailable(year: "2025", platform: "iOS", version: version(27, 2)))
  }

  @Test func unknownYearsAndPlatformsStayAvailable() {
    // Without release data there is nothing to decide on; dropping the
    // symbol would hide it everywhere.
    #expect(availability.isAvailable(year: "2031", platform: "macOS", version: version(26, 0)))
    #expect(availability.isAvailable(year: "2026", platform: "tvOS", version: version(26, 0)))
    #expect(SymbolAvailability(releases: [:]).isAvailable(year: "2026", platform: "macOS", version: version(26, 0)))
  }

  @Test func loadingLeavesOutSymbolsTheSystemDoesNotHave() throws {
    let json = """
      {"version":"2026","count":2,
       "releases":{"2019":{"macOS":"10.15","iOS":"13.0"},"2026":{"macOS":"27.0","iOS":"27.0"}},
       "symbols":[
        {"name":"star","year":"2019","categories":[],"terms":[]},
        {"name":"star.new","year":"2026","categories":[],"terms":[]}]}
      """
    let url = FileManager.default.temporaryDirectory.appending(path: "glyphon-availability-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let older = try SymbolDatabase.load(from: url, systemVersion: version(26, 5))
    #expect(older.symbols.map(\.name) == ["star"])
    let newer = try SymbolDatabase.load(from: url, systemVersion: version(27, 0))
    #expect(newer.symbols.map(\.name) == ["star", "star.new"])
  }

  @Test func filesWithoutReleaseDataKeepAllSymbols() throws {
    let json = """
      {"version":"2025.1","count":1,"symbols":[{"name":"star.new","year":"2026","categories":[],"terms":[]}]}
      """
    let url = FileManager.default.temporaryDirectory.appending(path: "glyphon-availability-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(try SymbolDatabase.load(from: url, systemVersion: version(26, 0)).count == 1)
  }

  @Test func bundledDataHasAReleaseForEveryYear() throws {
    let url = try #require(SymbolDatabase.bundledURL)
    let file = try JSONDecoder().decode(SymbolsFile.self, from: Data(contentsOf: url))
    let releases = try #require(file.releases)
    for year in Set(file.symbols.map(\.year)) {
      #expect(releases[year]?["macOS"] != nil, "no macOS release for \(year)")
      #expect(releases[year]?["iOS"] != nil, "no iOS release for \(year)")
    }
  }

  @Test func bundledDatabaseDependsOnTheSystemVersion() throws {
    let url = try #require(SymbolDatabase.bundledURL)
    let onMacOS26 = try SymbolDatabase.load(from: url, platform: "macOS", systemVersion: version(26, 5, 1))
    let onMacOS27 = try SymbolDatabase.load(from: url, platform: "macOS", systemVersion: version(27, 0))
    #expect(onMacOS26.symbols.allSatisfy { !$0.year.hasPrefix("2026") })
    #expect(onMacOS27.symbol(named: "calendar.day")?.year == "2026")
    #expect(onMacOS27.count > onMacOS26.count)
  }
}
