import Foundation

/// Tells whether the symbols of a release year exist on a system version.
///
/// The bundled data can be newer than the running system (the package
/// supports the previous major release too). A symbol that the system does
/// not have draws as nothing, so it must not reach a search result or a
/// recommendation.
struct SymbolAvailability: Sendable {
  /// Release year -> platform name -> first system version, e.g.
  /// `["2026": ["macOS": "27.0", "iOS": "27.0"]]`.
  let releases: [String: [String: String]]

  /// The platform key of the running system in the release data.
  static var currentPlatform: String {
    #if os(macOS)
    "macOS"
    #elseif os(visionOS)
    "visionOS"
    #elseif os(tvOS)
    "tvOS"
    #elseif os(watchOS)
    "watchOS"
    #else
    "iOS"
    #endif
  }

  /// A year or platform without release data counts as available: there is
  /// nothing to decide on.
  func isAvailable(year: String, platform: String, version: OperatingSystemVersion) -> Bool {
    guard let release = releases[year]?[platform] else { return true }
    let parts = release.split(separator: ".").map { Int($0) ?? 0 }
    let required = [parts.first ?? 0, parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0]
    let current = [version.majorVersion, version.minorVersion, version.patchVersion]
    return !current.lexicographicallyPrecedes(required)
  }
}
