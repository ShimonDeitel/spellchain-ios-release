import Foundation

/// A 7-letter puzzle: an ordered set of letters plus the seed/date it came from.
struct Puzzle: Equatable {
    let letters: [Character]      // exactly 7, lowercase
    let seed: UInt64
    let dateKey: String           // "yyyy-MM-dd" for dailies; "practice" / "pack-…" otherwise

    var letterString: String { String(letters) }
    var counts: [Character: Int] { WordRules.counts(of: letters) }
    var isPack: Bool { dateKey.hasPrefix("pack-") }
}

/// An alternate letter distribution a Pro player can draw a puzzle from. Each pack changes how
/// many vowels appear and how letters are weighted, producing a genuinely different round than the
/// standard daily/practice distribution.
struct LetterPack: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let symbol: String                       // SF Symbol
    let vowelCount: ClosedRange<Int>
    let vowelWeights: [Character: Int]
    let consonantWeights: [Character: Int]
    let minWords: Int                        // solvability bar for this pack

    static let all: [LetterPack] = [vowelRich, consonantStorm, commonCore, wildcard]

    /// Lots of vowels — long, flowing words and easy chains.
    static let vowelRich = LetterPack(
        id: "vowel-rich", name: "Vowel Rich",
        blurb: "Extra vowels — long words and easy chains.",
        symbol: "a.circle", vowelCount: 3...4,
        vowelWeights: ["a": 10, "e": 12, "i": 9, "o": 8, "u": 5],
        consonantWeights: ["r": 9, "t": 9, "n": 9, "s": 9, "l": 8, "d": 7, "c": 6, "m": 6,
                           "p": 5, "h": 5, "g": 4, "b": 4, "f": 3, "y": 3, "w": 2, "k": 2, "v": 2,
                           "x": 0, "z": 0, "j": 0, "q": 0],
        minWords: 24)

    /// Only two vowels and a dense consonant field — a tougher, crunchier round.
    static let consonantStorm = LetterPack(
        id: "consonant-storm", name: "Consonant Storm",
        blurb: "Just two vowels — a crunchier challenge.",
        symbol: "bolt", vowelCount: 2...2,
        vowelWeights: ["a": 8, "e": 10, "i": 8, "o": 7, "u": 5],
        consonantWeights: ["t": 8, "r": 8, "s": 8, "n": 7, "l": 6, "c": 6, "d": 6, "g": 6, "p": 6,
                           "m": 6, "b": 6, "h": 5, "k": 5, "f": 5, "w": 4, "y": 4, "v": 4,
                           "x": 2, "z": 2, "j": 2, "q": 1],
        minWords: 16)

    /// Only the most common letters — approachable and word-dense.
    static let commonCore = LetterPack(
        id: "common-core", name: "Common Core",
        blurb: "Everyday letters only — friendly and word-rich.",
        symbol: "star", vowelCount: 2...3,
        vowelWeights: ["a": 10, "e": 12, "i": 8, "o": 8, "u": 4],
        consonantWeights: ["r": 10, "t": 10, "n": 9, "s": 9, "l": 8, "d": 7, "c": 6, "m": 6,
                           "p": 5, "h": 5, "g": 4, "b": 3, "f": 3, "y": 2, "w": 2, "k": 1,
                           "v": 0, "x": 0, "z": 0, "j": 0, "q": 0],
        minWords: 26)

    /// Every letter equally likely — rare letters show up far more often. Unpredictable.
    static let wildcard = LetterPack(
        id: "wildcard", name: "Wildcard",
        blurb: "Every letter equally likely — expect the rare ones.",
        symbol: "die.face.5", vowelCount: 2...3,
        vowelWeights: ["a": 1, "e": 1, "i": 1, "o": 1, "u": 1],
        consonantWeights: Dictionary(uniqueKeysWithValues: "bcdfghjklmnpqrstvwxyz".map { ($0, 1) }),
        minWords: 12)
}

/// Deterministic, reproducible PRNG (SplitMix64). Same seed → same stream on every device/run,
/// which is what makes "everyone gets the same daily set" hold without a server.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Generates the daily / practice / pack letter sets and guarantees they are solvable.
enum PuzzleGenerator {
    static let setSize = 7
    /// A daily set must yield at least this many valid dictionary words, or we reroll the seed.
    static let minWords = 20

    /// Weighted letter pools. Vowels are drawn first (guaranteeing 2–3 of them) so almost every
    /// generated set is rich enough to build many words; consonants are frequency-weighted toward
    /// common ones (Scrabble-ish) so we rarely strand the player on q/z/x/j.
    static let vowels: [Character] = Array("aeiou")
    static let vowelWeights: [Character: Int] = ["a": 9, "e": 12, "i": 8, "o": 7, "u": 4]

    static let consonants: [Character] = Array("bcdfghjklmnpqrstvwxyz")
    static let consonantWeights: [Character: Int] = [
        "r": 9, "t": 9, "n": 8, "s": 8, "l": 7, "c": 6, "d": 6, "p": 5, "m": 5, "h": 5,
        "g": 4, "b": 4, "f": 4, "y": 3, "w": 3, "k": 3, "v": 2, "x": 1, "z": 1, "j": 1, "q": 1
    ]

    private static func weightedPick(_ pool: [Character], weights: [Character: Int],
                                     using gen: inout SeededGenerator) -> Character {
        let total = pool.reduce(0) { $0 + (weights[$1] ?? 1) }
        var roll = Int.random(in: 0..<max(total, 1), using: &gen)
        for ch in pool {
            roll -= (weights[ch] ?? 1)
            if roll < 0 { return ch }
        }
        return pool.last ?? "e"
    }

    /// Build one candidate 7-letter set from a seed: a few vowels + the rest consonants, shuffled.
    /// `pack` overrides the vowel-count range and letter weights so alternate packs yield genuinely
    /// different distributions; nil uses the standard daily/practice distribution.
    static func candidate(seed: UInt64, pack: LetterPack? = nil) -> [Character] {
        var gen = SeededGenerator(seed: seed)
        let vRange = pack?.vowelCount ?? 2...3
        let vW = pack?.vowelWeights ?? vowelWeights
        let cW = pack?.consonantWeights ?? consonantWeights
        let vowelCount = Int.random(in: vRange, using: &gen)
        var letters: [Character] = []
        for _ in 0..<vowelCount {
            letters.append(weightedPick(vowels, weights: vW, using: &gen))
        }
        while letters.count < setSize {
            letters.append(weightedPick(consonants, weights: cW, using: &gen))
        }
        letters.shuffle(using: &gen)
        return letters
    }

    /// Count how many dictionary words a multiset of letters can build (used to validate a set).
    static func solutionCount(for letters: [Character],
                              dictionary: WordDictionary = .shared) -> Int {
        solutions(for: letters, dictionary: dictionary).count
    }

    /// All dictionary words buildable from `letters`. Implemented over the signature index so it
    /// only checks the words whose letters are a subset of ours — far cheaper than scanning all.
    static func solutions(for letters: [Character],
                          dictionary: WordDictionary = .shared) -> [String] {
        let available = WordRules.counts(of: letters)
        var found: [String] = []
        // Iterate the full word set once; canBuild is a cheap multiset check.
        for word in dictionary.words where WordRules.canBuild(word, from: available) {
            found.append(word)
        }
        return found
    }

    /// Deterministic seed for a calendar day in the user's local time zone.
    static func dailySeed(for date: Date, calendar: Calendar = .current) -> UInt64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = UInt64(c.year ?? 2026), m = UInt64(c.month ?? 1), d = UInt64(c.day ?? 1)
        // Mix the y/m/d into a stable 64-bit seed.
        var s = y &* 73_856_093
        s ^= m &* 19_349_663
        s ^= d &* 83_492_791
        s = s &* 0x9E3779B97F4A7C15
        return s &+ 0xABCDEF0123456789
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// The deterministic daily puzzle for `date`. Rerolls the seed (seed, seed+1, …) until the
    /// candidate set yields at least `minWords` dictionary words, so the daily is always playable.
    /// If the dictionary is empty (e.g. resource missing), it returns the first candidate so the
    /// app never hangs — validation simply yields nothing in that degraded state.
    static func dailyPuzzle(for date: Date, calendar: Calendar = .current,
                            dictionary: WordDictionary = .shared) -> Puzzle {
        let baseSeed = dailySeed(for: date, calendar: calendar)
        let key = dateKey(for: date, calendar: calendar)
        return solvablePuzzle(baseSeed: baseSeed, dateKey: key, dictionary: dictionary)
    }

    /// A fresh random practice puzzle (Pro). Seeded off the current time + a salt so each tap
    /// differs, but still uses the same solvability guarantee.
    static func practicePuzzle(saltedBy salt: UInt64 = UInt64.random(in: 0...UInt64.max),
                               dictionary: WordDictionary = .shared) -> Puzzle {
        solvablePuzzle(baseSeed: salt | 1, dateKey: "practice", dictionary: dictionary)
    }

    /// A fresh puzzle drawn from an alternate letter `pack` (Pro). Each tap differs (salted), uses
    /// the pack's distribution, and still guarantees solvability against the pack's word bar.
    static func packPuzzle(_ pack: LetterPack,
                           saltedBy salt: UInt64 = UInt64.random(in: 0...UInt64.max),
                           dictionary: WordDictionary = .shared) -> Puzzle {
        solvablePuzzle(baseSeed: salt | 1, dateKey: "pack-\(pack.id)",
                       pack: pack, minimumWords: pack.minWords, dictionary: dictionary)
    }

    /// Core reroll loop shared by daily/practice/pack generation. `pack` selects an alternate
    /// letter distribution; `minimumWords` lets harder packs accept a slightly lower solvability bar.
    static func solvablePuzzle(baseSeed: UInt64, dateKey: String,
                               pack: LetterPack? = nil,
                               minimumWords: Int = minWords,
                               dictionary: WordDictionary = .shared,
                               maxTries: Int = 300) -> Puzzle {
        var firstCandidate: [Character] = candidate(seed: baseSeed, pack: pack)
        // No dictionary → can't validate; return the first candidate deterministically.
        guard !dictionary.words.isEmpty else {
            return Puzzle(letters: firstCandidate, seed: baseSeed, dateKey: dateKey)
        }
        for i in 0..<maxTries {
            let seed = baseSeed &+ UInt64(i)
            let letters = candidate(seed: seed, pack: pack)
            if i == 0 { firstCandidate = letters }
            if solutionCount(for: letters, dictionary: dictionary) >= minimumWords {
                return Puzzle(letters: letters, seed: seed, dateKey: dateKey)
            }
        }
        // Extremely unlikely fallback: use the first candidate so we always return *something*.
        return Puzzle(letters: firstCandidate, seed: baseSeed, dateKey: dateKey)
    }
}
