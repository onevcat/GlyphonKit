import Foundation

/// Everyday words for symbols: what a person says when a symbol is the
/// right icon ("package", "parcel", "delivery" for `shippingbox`).
///
/// The data from Apple has search terms for about a third of the symbols
/// and few synonyms, so a keyword like "package" finds nothing by name.
/// `concepts.json` adds such words on the symbol side, for every root that
/// has an everyday meaning. It was written once, offline; it is not
/// derived from the eval datasets.
enum SymbolConcepts {
  private struct File: Decodable {
    let concepts: [String: [String]]
  }

  /// Root name -> words. Empty if the resource cannot be read: retrieval
  /// then works from names, terms and aliases as before.
  static let bundled: [String: [String]] = {
    guard
      let url = Bundle.module.url(forResource: "concepts", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let file = try? JSONDecoder().decode(File.self, from: data)
    else { return [:] }
    return file.concepts
  }()
}
