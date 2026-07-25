import GlyphonKit

enum StubDatabase {

/// Creates a small deterministic database for testing.
static func stub() -> SymbolDatabase {
  SymbolDatabase(symbols: [
    SymbolEntry(name: "star", year: "2019", categories: ["shapes"], terms: ["favorite", "rating"]),
    SymbolEntry(name: "star.fill", year: "2019", categories: ["shapes", "multicolor"], terms: ["favorite", "rating"]),
    SymbolEntry(name: "star.circle", year: "2020", categories: ["shapes"], terms: ["favorite"]),
    SymbolEntry(name: "star.circle.fill", year: "2020", categories: ["shapes", "multicolor"], terms: ["favorite"]),
    SymbolEntry(name: "star.square", year: "2021", categories: ["shapes"], terms: []),
    SymbolEntry(name: "star.slash", year: "2020", categories: ["shapes"], terms: []),
    SymbolEntry(name: "cloud", year: "2019", categories: ["weather"], terms: ["sky", "overcast"]),
    SymbolEntry(name: "cloud.fill", year: "2019", categories: ["weather", "multicolor"], terms: ["sky"]),
    SymbolEntry(name: "cloud.rain", year: "2019", categories: ["weather"], terms: ["precipitation", "storm"]),
    SymbolEntry(name: "cloud.rain.fill", year: "2019", categories: ["weather", "multicolor"], terms: ["precipitation"]),
    SymbolEntry(name: "cloud.rain.circle", year: "2021", categories: ["weather"], terms: []),
    SymbolEntry(name: "cloud.sun", year: "2019", categories: ["weather"], terms: ["partly cloudy"]),
    SymbolEntry(name: "cloud.sun.fill", year: "2019", categories: ["weather", "multicolor"], terms: []),
    SymbolEntry(name: "arrow.up", year: "2019", categories: ["arrows"], terms: ["upload", "direction"]),
    SymbolEntry(name: "arrow.down", year: "2019", categories: ["arrows"], terms: ["download", "direction"]),
    SymbolEntry(name: "arrow.up.circle", year: "2019", categories: ["arrows"], terms: []),
    SymbolEntry(name: "arrow.up.circle.fill", year: "2020", categories: ["arrows", "multicolor"], terms: []),
    SymbolEntry(name: "heart", year: "2019", categories: ["health"], terms: ["love", "like", "favorite"]),
    SymbolEntry(name: "heart.fill", year: "2019", categories: ["health", "multicolor"], terms: ["love"]),
    SymbolEntry(name: "folder", year: "2019", categories: ["objectsandtools"], terms: ["directory", "file"]),
    SymbolEntry(name: "0.circle.ar", year: "2022.1", categories: ["indices"], terms: []),
  ])
}

}
