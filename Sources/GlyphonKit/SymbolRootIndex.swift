import Foundation

/// Retrieval layer rebuilt around semantic roots.
///
/// Differences from the shipping SymbolSearchEngine:
/// - Symbols are deduplicated by semantic root (fill/circle/... variants
///   collapse into one candidate), so a candidate list of N covers N distinct
///   concepts instead of N spellings of two concepts.
/// - Search terms are tokenized by whitespace, so multi-word terms like
///   "pet friendly" are reachable from the keyword "pet". The shipping index
///   stores the whole phrase as a single key, making it unreachable.
/// - Keywords are weighted (subject keywords > related keywords, earlier >
///   later) instead of every token counting equally.
struct SymbolRootIndex: Sendable {
  struct Root: Sendable {
    let name: String
    let displayEntry: SymbolEntry
    let terms: [String]
    let tokens: Set<String>
    let phrases: Set<String>
  }

  struct WeightedKeyword: Sendable {
    let text: String
    let weight: Double
  }

  let roots: [Root]
  private let tokenIndex: [String: [Int]]
  private let phraseIndex: [String: [Int]]
  private let tokenDamping: [String: Double]

  init(database: SymbolDatabase) {
    var byRoot: [String: [SymbolEntry]] = [:]
    for symbol in database.symbols where !symbol.isLocaleVariant {
      byRoot[SymbolDatabase.semanticRoot(of: symbol.name), default: []].append(symbol)
    }

    var roots: [Root] = []
    for (rootName, entries) in byRoot {
      // Prefer the entry whose name is exactly the root; else the shortest.
      let display = entries.first { $0.name == rootName }
        ?? entries.min { $0.name.count < $1.name.count }!
      var terms: [String] = []
      var seenTerms = Set<String>()
      for entry in entries {
        for term in entry.terms {
          let lowered = term.lowercased()
          if seenTerms.insert(lowered).inserted {
            terms.append(lowered)
          }
        }
      }
      var tokens = Set<String>()
      var phrases = Set<String>()
      for segment in rootName.split(separator: ".") {
        tokens.insert(String(segment))
      }
      for term in terms {
        let words = term.split(separator: " ").map(String.init)
        if words.count > 1 {
          phrases.insert(term)
        }
        for word in words {
          tokens.insert(word)
        }
      }
      for category in display.categories {
        tokens.insert(category)
      }
      roots.append(Root(name: rootName, displayEntry: display, terms: terms, tokens: tokens, phrases: phrases))
    }
    roots.sort { $0.name < $1.name }
    self.roots = roots

    var tokenIndex: [String: [Int]] = [:]
    var phraseIndex: [String: [Int]] = [:]
    for (index, root) in roots.enumerated() {
      for token in root.tokens {
        tokenIndex[token, default: []].append(index)
      }
      for phrase in root.phrases {
        phraseIndex[phrase, default: []].append(index)
      }
    }
    self.tokenIndex = tokenIndex
    self.phraseIndex = phraseIndex
    // IDF-style damping: a token shared by hundreds of roots ("arrow",
    // "figure", "chart") says little about any one of them.
    var damping: [String: Double] = [:]
    for (token, hits) in tokenIndex {
      damping[token] = 1.0 / (1.0 + log(Double(hits.count)) / 2.0)
    }
    self.tokenDamping = damping
  }

  /// Words that carry no icon signal — every software description contains
  /// them, and they only match generic symbols like `app`.
  static let noiseWords: Set<String> = [
    "app", "apps", "application", "applications", "software", "program",
    "project", "tool", "tools", "system", "systems", "platform", "service",
    "services", "mobile", "digital", "online", "smart", "personal", "daily",
    "monthly", "weekly", "manager", "management", "tracker", "tracking",
    "planner", "planning", "assistant", "helper", "utility", "utilities",
    "feature", "features", "simple", "easy", "modern", "best", "new",
    "user", "users", "interface", "framework", "library", "client",
  ]

  /// Query-time expansion: common concept words → tokens that actually occur
  /// in SF Symbol names. The symbol metadata has almost no synonyms (e.g. no
  /// symbol is findable via "money"), so this map bridges everyday vocabulary
  /// to the SF Symbols naming vocabulary. Keep entries generic — this is
  /// domain knowledge about SF Symbols, not tuning for specific queries.
  static let aliasMap: [String: [String]] = [
    // finance
    "money": ["banknote", "dollarsign", "wallet", "creditcard", "currency"],
    "cash": ["banknote", "dollarsign", "wallet"],
    "finance": ["banknote", "dollarsign", "chart", "wallet", "creditcard"],
    "financial": ["banknote", "dollarsign", "chart", "wallet"],
    "budget": ["banknote", "dollarsign", "wallet", "pie", "chart"],
    "expense": ["banknote", "dollarsign", "creditcard", "wallet"],
    "expenses": ["banknote", "dollarsign", "creditcard", "wallet"],
    "payment": ["creditcard", "banknote", "dollarsign", "wallet"],
    "coin": ["dollarsign", "banknote", "centsign"],
    "bank": ["building", "banknote", "dollarsign"],
    "banking": ["building", "banknote", "dollarsign"],
    "accounting": ["banknote", "dollarsign", "chart", "list"],
    "wealth": ["banknote", "dollarsign", "chart"],
    "invest": ["chart", "dollarsign"],
    "investment": ["chart", "dollarsign"],
    "stock": ["chart", "dollarsign"],
    "stocks": ["chart", "dollarsign"],
    // communication
    "email": ["envelope", "paperplane", "tray"],
    "mail": ["envelope", "tray"],
    "inbox": ["tray", "envelope"],
    "chat": ["message", "bubble"],
    "conversation": ["bubble", "message"],
    "talk": ["bubble", "message", "waveform"],
    "call": ["phone"],
    // tasks & notes
    "todo": ["checklist", "checkmark", "list"],
    "task": ["checklist", "checkmark", "list"],
    "tasks": ["checklist", "checkmark", "list"],
    "note": ["note", "pencil", "text"],
    "notes": ["note", "pencil", "text"],
    "journal": ["book", "pencil", "text", "note"],
    "diary": ["book", "pencil", "note"],
    "writing": ["pencil", "text", "note"],
    "markdown": ["note", "text", "doc"],
    // learning & language
    "language": ["translate", "character", "bubble", "globe"],
    "languages": ["translate", "character", "bubble", "globe"],
    "translation": ["translate", "character"],
    "vocabulary": ["character", "book", "text", "translate"],
    "dictionary": ["character", "book", "translate"],
    "learn": ["graduationcap", "book", "brain"],
    "learning": ["graduationcap", "book", "brain"],
    "study": ["graduationcap", "book", "pencil"],
    "education": ["graduationcap", "book", "pencil"],
    "school": ["graduationcap", "book", "backpack"],
    "course": ["graduationcap", "book"],
    // media
    "song": ["music", "waveform", "headphones"],
    "songs": ["music", "waveform", "headphones"],
    "audio": ["waveform", "speaker", "headphones", "music"],
    "podcast": ["mic", "waveform", "antenna", "headphones"],
    "movie": ["film", "video", "play", "popcorn"],
    "film": ["film", "video", "popcorn"],
    "gallery": ["photo", "square"],
    "picture": ["photo", "camera"],
    "pictures": ["photo", "camera"],
    "image": ["photo", "camera"],
    "images": ["photo", "camera"],
    "photography": ["camera", "photo"],
    // security
    "security": ["lock", "shield", "key"],
    "secure": ["lock", "shield", "key"],
    "privacy": ["lock", "shield", "eye", "hand"],
    "password": ["key", "lock", "asterisk"],
    "passwords": ["key", "lock", "asterisk"],
    "encryption": ["lock", "key", "shield"],
    "vault": ["lock", "shield", "key"],
    "vpn": ["lock", "shield", "network", "globe"],
    // health
    "health": ["heart", "cross", "stethoscope", "waveform"],
    "medical": ["cross", "stethoscope", "pills", "bandage"],
    "medicine": ["pills", "pill", "cross"],
    "medication": ["pills", "pill", "cross"],
    "doctor": ["stethoscope", "cross"],
    "hospital": ["cross", "building", "bed"],
    "workout": ["figure", "dumbbell", "flame"],
    "exercise": ["figure", "dumbbell", "flame"],
    "gym": ["dumbbell", "figure"],
    "fitness": ["figure", "dumbbell", "flame", "heart"],
    "running": ["figure", "shoe"],
    "yoga": ["yoga", "mind"],
    "meditation": ["meditate", "mind", "leaf", "brain"],
    "sleep": ["moon", "zzz", "bed", "powersleep"],
    "dream": ["moon", "zzz", "sparkles", "bed"],
    // weather & nature
    "weather": ["cloud", "sun", "rain", "snowflake", "wind", "thermometer"],
    "forecast": ["cloud", "sun", "rain"],
    "rain": ["rain", "cloud", "umbrella", "drop"],
    "plant": ["leaf", "tree", "macro"],
    "plants": ["leaf", "tree", "macro"],
    "garden": ["leaf", "tree", "sprinkler", "macro"],
    "gardening": ["leaf", "tree", "sprinkler"],
    "flower": ["macro", "leaf"],
    "nature": ["leaf", "tree", "mountain"],
    "animal": ["pawprint", "dog", "cat", "bird", "hare", "tortoise"],
    "animals": ["pawprint", "dog", "cat", "bird", "hare", "tortoise"],
    "pet": ["pawprint", "dog", "cat"],
    "pets": ["pawprint", "dog", "cat"],
    "puppy": ["dog", "pawprint"],
    "kitten": ["cat", "pawprint"],
    // food & drink
    "food": ["fork", "knife", "carrot", "takeoutbag"],
    "meal": ["fork", "knife", "frying"],
    "restaurant": ["fork", "knife", "storefront"],
    "cooking": ["frying", "stove", "oven", "fork", "knife"],
    "recipe": ["frying", "fork", "knife", "carrot", "book"],
    "recipes": ["frying", "fork", "knife", "carrot", "book"],
    "kitchen": ["stove", "oven", "frying", "refrigerator", "sink"],
    "coffee": ["cup", "mug", "takeoutbag"],
    "cafe": ["cup", "mug", "storefront"],
    "tea": ["cup", "mug"],
    "drink": ["cup", "mug", "wineglass", "waterbottle"],
    "beer": ["mug", "wineglass"],
    "wine": ["wineglass"],
    // travel & transport
    "travel": ["airplane", "suitcase", "globe", "map"],
    "trip": ["airplane", "suitcase", "map", "car"],
    "vacation": ["airplane", "suitcase", "beach", "sun"],
    "flight": ["airplane"],
    "flights": ["airplane"],
    "airport": ["airplane"],
    "hotel": ["bed", "building", "suitcase"],
    "navigation": ["map", "location", "mappin", "signpost", "arrow"],
    "directions": ["map", "signpost", "arrow", "location"],
    "route": ["map", "point", "location", "signpost"],
    "gps": ["location", "map", "mappin"],
    "commute": ["tram", "bus", "car", "bicycle"],
    "train": ["tram", "train", "cablecar"],
    "subway": ["tram", "train"],
    "metro": ["tram", "train"],
    "railway": ["tram", "train"],
    "bike": ["bicycle", "figure"],
    "cycling": ["bicycle", "figure"],
    "driving": ["car", "steeringwheel"],
    "taxi": ["car"],
    // shopping
    "shopping": ["cart", "bag", "basket", "storefront"],
    "shop": ["storefront", "cart", "bag"],
    "store": ["storefront", "cart", "bag"],
    "purchase": ["cart", "creditcard", "bag"],
    "buy": ["cart", "creditcard", "bag"],
    "ecommerce": ["cart", "creditcard", "shippingbox", "storefront"],
    "order": ["cart", "bag", "shippingbox", "list"],
    "delivery": ["shippingbox", "truck", "box"],
    "shipping": ["shippingbox", "truck", "box"],
    "invoice": ["doc", "text", "banknote", "list"],
    "receipt": ["doc", "text", "banknote", "list"],
    // time
    "time": ["clock", "timer", "hourglass"],
    "schedule": ["calendar", "clock", "list"],
    "reminder": ["bell", "alarm", "calendar", "checklist"],
    "reminders": ["bell", "alarm", "calendar", "checklist"],
    "event": ["calendar", "bell", "balloon"],
    "events": ["calendar", "bell", "balloon"],
    "notification": ["bell", "badge"],
    "notifications": ["bell", "badge"],
    "deadline": ["clock", "calendar", "hourglass", "timer"],
    "countdown": ["timer", "hourglass", "clock"],
    // tech
    "ai": ["brain", "sparkles", "cpu", "intelligence"],
    "intelligence": ["brain", "sparkles", "intelligence"],
    "neural": ["brain", "cpu", "point"],
    "robot": ["cpu", "gearshape", "faceid"],
    "code": ["curlybraces", "terminal", "chevron", "hammer"],
    "coding": ["curlybraces", "terminal", "chevron", "hammer"],
    "programming": ["curlybraces", "terminal", "chevron", "hammer"],
    "developer": ["curlybraces", "terminal", "hammer", "wrench"],
    "debug": ["ladybug", "ant", "terminal"],
    "bug": ["ladybug", "ant"],
    "api": ["network", "curlybraces", "arrow", "server"],
    "http": ["network", "globe", "arrow", "server"],
    "web": ["globe", "safari", "network"],
    "website": ["globe", "safari", "network"],
    "internet": ["globe", "wifi", "network"],
    "network": ["network", "wifi", "antenna", "server"],
    "server": ["server", "externaldrive", "network", "rack"],
    "database": ["cylinder", "externaldrive", "server", "tray"],
    "storage": ["externaldrive", "internaldrive", "archivebox", "shippingbox"],
    "sync": ["arrow", "icloud", "circlepath"],
    "backup": ["externaldrive", "icloud", "arrow", "clock"],
    "download": ["arrow", "tray", "square"],
    "upload": ["arrow", "tray", "square", "icloud"],
    "terminal": ["terminal", "apple"],
    "commandline": ["terminal", "apple"],
    "cli": ["terminal", "apple"],
    "analytics": ["chart", "gauge", "percent"],
    "statistics": ["chart", "percent", "sum"],
    "dashboard": ["gauge", "chart", "square", "speedometer"],
    "data": ["chart", "cylinder", "tablecells"],
    "report": ["chart", "doc", "text"],
    "graph": ["chart", "point"],
    // home & devices
    "home": ["house", "homekit", "lightbulb"],
    "smart": ["homekit", "lightbulb", "sensor"],
    "light": ["lightbulb", "lamp", "sun"],
    "energy": ["bolt", "battery", "leaf", "powerplug"],
    "power": ["bolt", "battery", "powerplug", "poweron"],
    "battery": ["battery", "bolt"],
    // misc
    "game": ["gamecontroller", "arcade", "dice", "trophy", "playstation", "xbox"],
    "games": ["gamecontroller", "arcade", "dice", "trophy"],
    "gaming": ["gamecontroller", "arcade", "dice"],
    "puzzle": ["puzzlepiece", "gamecontroller"],
    "speed": ["hare", "bolt", "gauge", "speedometer", "wind", "timer"],
    "fast": ["hare", "bolt", "gauge", "speedometer"],
    "performance": ["gauge", "bolt", "speedometer", "chart"],
    "slow": ["tortoise"],
    "love": ["heart", "sparkles"],
    "romance": ["heart", "sparkles"],
    "dating": ["heart", "person", "sparkles"],
    "favorite": ["star", "heart", "bookmark"],
    "favorites": ["star", "heart", "bookmark"],
    "rating": ["star", "hand"],
    "search": ["magnifyingglass", "binoculars", "sparkle"],
    "settings": ["gear", "gearshape", "slider", "switch"],
    "preferences": ["gear", "gearshape", "slider"],
    "profile": ["person", "circle"],
    "account": ["person", "circle", "key"],
    "team": ["person"],
    "social": ["person", "bubble", "heart", "hand"],
    "friends": ["person", "hand", "heart"],
    "family": ["figure", "person", "house"],
    "baby": ["stroller", "teddybear"],
    "child": ["teddybear", "stroller", "child"],
    "kids": ["teddybear", "stroller", "child"],
    "news": ["newspaper", "antenna"],
    "blog": ["doc", "text", "pencil", "globe", "richtext"],
    "reading": ["book", "bookmark", "eyeglasses", "text"],
    "read": ["book", "bookmark", "text"],
    "library": ["books", "book", "building"],
    "birthday": ["gift", "balloon", "party"],
    "celebration": ["party", "balloon", "gift", "sparkles"],
    "party": ["party", "balloon", "gift"],
    "gift": ["gift", "shippingbox"],
    "weight": ["scalemass", "dumbbell", "figure"],
    "camera": ["camera", "video", "web"],
    "surveillance": ["web", "video", "eye", "camera"],
    "monitor": ["display", "eye", "gauge", "waveform"],
    "scan": ["viewfinder", "scanner", "qrcode", "doc"],
    "scanner": ["scanner", "viewfinder", "doc"],
    "document": ["doc", "text", "folder"],
    "documents": ["doc", "text", "folder"],
    "file": ["doc", "folder"],
    "files": ["doc", "folder"],
    "clean": ["bubbles", "sparkles", "trash", "paintbrush"],
    "cleaning": ["bubbles", "sparkles", "trash", "paintbrush"],
    "trash": ["trash", "xmark"],
    "delete": ["trash", "xmark", "minus"],
    "map": ["map", "mappin", "location", "globe"],
    "location": ["location", "mappin", "map"],
    "drone": ["drone"],
    "bird": ["bird"],
    "birdwatching": ["bird", "binoculars"],
    "car": ["car", "steeringwheel", "fuelpump"],
    "maintenance": ["wrench", "screwdriver", "gearshape", "hammer"],
    "repair": ["wrench", "screwdriver", "hammer"],
    "wallet": ["wallet", "creditcard", "banknote"],
    "calendar": ["calendar", "clock"],
    "voice": ["mic", "waveform", "speaker"],
    "record": ["mic", "waveform", "record"],
    "video": ["video", "film", "play"],
    "stream": ["play", "video", "antenna", "wave"],
    "tv": ["tv", "play", "sparkles"],
    "radio": ["radio", "antenna", "dot"],
    "art": ["paintbrush", "paintpalette", "photo", "theatermasks"],
    "design": ["paintbrush", "paintpalette", "pencil", "ruler"],
    "drawing": ["pencil", "paintbrush", "scribble", "hand"],
    "paint": ["paintbrush", "paintpalette"],
    "color": ["paintpalette", "eyedropper", "swatchpalette"],
    "book": ["book", "books", "bookmark"],
    "ebook": ["book", "books", "bookmark", "text"],
  ]

  /// Rank roots for a list of weighted keywords.
  func search(keywords: [WeightedKeyword], limit: Int) -> [Root] {
    var scores: [Int: Double] = [:]

    for keyword in keywords {
      let text = keyword.text.lowercased().trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty else { continue }
      let words = text.split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
        .filter { !Self.noiseWords.contains($0) }

      if words.count > 1, let hits = phraseIndex[words.joined(separator: " ")] {
        for index in hits {
          scores[index, default: 0] += 2.0 * keyword.weight
        }
      }

      for word in words {
        let perWordWeight = keyword.weight / Double(words.count)

        if let aliases = Self.aliasMap[word] {
          for alias in aliases {
            if let hits = tokenIndex[alias] {
              let perAlias = 0.9 * perWordWeight * (tokenDamping[alias] ?? 1.0) / Double(aliases.count).squareRoot()
              for index in hits {
                scores[index, default: 0] += perAlias
              }
            }
          }
        }

        if let hits = tokenIndex[word] {
          let perToken = perWordWeight * (tokenDamping[word] ?? 1.0)
          for index in hits {
            scores[index, default: 0] += perToken
          }
        } else if word.count >= 4, Self.aliasMap[word] == nil {
          // Prefix fallback for morphology: "running" -> "run", "cycling" -> "cycle".
          for (token, hits) in tokenIndex
          where token.hasPrefix(word) || (word.hasPrefix(token) && token.count >= 4 && word.count <= token.count + 4) {
            let perToken = 0.35 * keyword.weight / Double(words.count)
            for index in hits {
              scores[index, default: 0] += perToken
            }
          }
        }
      }
    }

    // Simple roots are usually the iconic concept; heavily composed names
    // (dollarsign.gauge.chart.lefthalf.righthalf) are niche variations that
    // should not outrank their plain building blocks.
    let ranked = scores.map { index, score in
      let segments = roots[index].name.split(separator: ".").count
      return (index: index, score: score / (1.0 + 0.2 * Double(segments - 1)))
    }

    return ranked
      .sorted { lhs, rhs in
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return roots[lhs.index].name.count < roots[rhs.index].name.count
      }
      .prefix(limit)
      .map { roots[$0.index] }
  }
}
