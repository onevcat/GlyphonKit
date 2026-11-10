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

  // MARK: - Renamed symbols

  private func load(_ json: String, _ systemVersion: OperatingSystemVersion) throws -> SymbolDatabase {
    let url = FileManager.default.temporaryDirectory.appending(path: "glyphon-availability-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try SymbolDatabase.load(from: url, platform: "macOS", systemVersion: systemVersion)
  }

  /// `mic.old` was renamed to `mic.new` in 2026. As in the data from Apple,
  /// the old name has no terms or categories of its own.
  private let renamedJSON = """
    {"version":"2026","count":3,
     "releases":{"2019":{"macOS":"10.15"},"2025":{"macOS":"26.0"},"2026":{"macOS":"27.0"}},
     "aliases":{"mic.old":"mic.new"},
     "symbols":[
      {"name":"mic.new","year":"2026","categories":["media","whatsnew"],"terms":["microphone"]},
      {"name":"mic.old","year":"2019","categories":[],"terms":[]},
      {"name":"star","year":"2025","categories":["shapes"],"terms":[]}]}
    """

  @Test func oldNameKeepsTheMetadataWhenTheSystemDoesNotHaveTheNewName() throws {
    let database = try load(renamedJSON, version(26, 5))
    let old = try #require(database.symbol(named: "mic.old"))
    #expect(old.terms == ["microphone"])
    // "whatsnew" belongs to the new name's release, not to the old name.
    #expect(old.categories == ["media"])
    #expect(database.symbol(named: "mic.new") == nil)
    #expect(database.currentName(for: "mic.old") == "mic.old")
  }

  @Test func onlyTheNewestOldNameKeepsTheMetadata() throws {
    // `mic.first` became `mic.second` in 2024 and `mic.third` in 2026. The
    // rename table points both old names at the newest name. Before 2026
    // only `mic.second` had the metadata.
    let json = """
      {"version":"2026","count":3,
       "releases":{"2019":{"macOS":"10.15"},"2024":{"macOS":"15.0"},"2026":{"macOS":"27.0"}},
       "aliases":{"mic.first":"mic.third","mic.second":"mic.third"},
       "symbols":[
        {"name":"mic.first","year":"2019","categories":[],"terms":[]},
        {"name":"mic.second","year":"2024","categories":[],"terms":[]},
        {"name":"mic.third","year":"2026","categories":["media"],"terms":["microphone"]}]}
      """
    let database = try load(json, version(26, 5))
    #expect(database.symbol(named: "mic.second")?.terms == ["microphone"])
    #expect(database.symbol(named: "mic.first")?.terms == [])
  }

  @Test func oldNamePointsToTheNewNameWhenTheSystemHasIt() throws {
    let database = try load(renamedJSON, version(27, 0))
    #expect(database.symbol(named: "mic.old")?.terms == [])
    #expect(database.currentName(for: "mic.old") == "mic.new")
    #expect(database.currentName(for: "mic.new") == "mic.new")
    #expect(database.currentName(for: "star") == "star")
  }

  @Test func whatsNewIsTheNewestReleaseTheSystemHas() throws {
    // The data marks only its own newest release. An older system still
    // has a newest release of its own.
    let older = try load(renamedJSON, version(26, 5))
    #expect(older.symbols(inCategory: "whatsnew").map(\.name) == ["star"])
    let newer = try load(renamedJSON, version(27, 0))
    #expect(newer.symbols(inCategory: "whatsnew").map(\.name) == ["mic.new"])
  }

  @Test func bundledDataKeepsTheMacOS26Metadata() throws {
    let url = try #require(SymbolDatabase.bundledURL)
    let onMacOS26 = try SymbolDatabase.load(from: url, platform: "macOS", systemVersion: version(26, 5, 1))
    // Renamed in 2026 (to microphone.dynamic.on.stand, building.classical.columns).
    #expect(onMacOS26.symbol(named: "music.microphone")?.terms.contains("microphone") == true)
    #expect(onMacOS26.symbol(named: "building.columns")?.terms == ["library"])
    #expect(onMacOS26.symbol(named: "music.microphone")?.categories == ["objectsandtools"])
    // An older name of the same symbol had no metadata before the rename.
    #expect(onMacOS26.symbol(named: "music.mic")?.terms == [])
    let whatsNew = onMacOS26.symbols(inCategory: "whatsnew")
    #expect(!whatsNew.isEmpty)
    #expect(whatsNew.allSatisfy { $0.year.hasPrefix("2025") })
  }
}
