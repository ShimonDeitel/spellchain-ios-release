import Foundation

/// Offline, on-device word validator.
///
/// At launch we load the bundled `words.txt` (a filtered copy of the system word list — lowercase
/// a–z, length 3–7) into a `Set<String>` for O(1) membership checks. Loading happens once, lazily,
/// off the main thread isn't required because the file is small (a few hundred KB) and the load is
/// a fast line split.
final class WordDictionary {
    static let shared = WordDictionary()

    /// The full validation set — every legal word, lowercased.
    private(set) var words: Set<String> = []

    /// Words grouped by their *sorted letter signature*, so the daily-set generator can quickly
    /// count how many dictionary words a given multiset of letters can build.
    private(set) var bySignature: [String: [String]] = [:]

    private(set) var isLoaded = false

    private init() {}

    /// Load `words.txt` from the main bundle. Idempotent. Returns true on success.
    @discardableResult
    func load(bundle: Bundle = .main) -> Bool {
        if isLoaded { return true }
        guard let url = bundle.url(forResource: "words", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            isLoaded = true   // never retry-loop; degrade to an empty (but valid) dictionary
            return false
        }
        var set = Set<String>()
        set.reserveCapacity(60_000)
        for line in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let w = line.trimmingCharacters(in: .whitespaces)
            // The build step already filters, but stay defensive against any stray content.
            if w.count >= 3, w.count <= 7, w.allSatisfy({ $0.isASCII && $0.isLetter }) {
                set.insert(w.lowercased())
            }
        }
        words = set
        // Build the signature index used only by the generator (cheap, one-time).
        var sig: [String: [String]] = [:]
        sig.reserveCapacity(set.count)
        for w in set { sig[String(w.sorted()), default: []].append(w) }
        bySignature = sig
        isLoaded = true
        return true
    }

    /// True iff `word` is in the dictionary AND can be built from `available` letter counts.
    func isValid(_ word: String, given available: [Character: Int]) -> Bool {
        WordRules.canBuild(word, from: available) && words.contains(word.lowercased())
    }
}

/// Pure, testable word/letter rules. No I/O — every function here is deterministic.
enum WordRules {
    static let minLength = 3
    static let maxLength = 7

    /// Letter-count multiset for a set of available letters.
    static func counts(of letters: [Character]) -> [Character: Int] {
        var c: [Character: Int] = [:]
        for ch in letters { c[Character(ch.lowercased()), default: 0] += 1 }
        return c
    }

    /// Can `word` be spelled using only `available` letters, each used at most its count?
    /// Length and a–z constraints are enforced here too.
    static func canBuild(_ word: String, from available: [Character: Int]) -> Bool {
        let w = word.lowercased()
        guard w.count >= minLength, w.count <= maxLength else { return false }
        guard w.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        var remaining = available
        for ch in w {
            guard let n = remaining[ch], n > 0 else { return false }
            remaining[ch] = n - 1
        }
        return true
    }
}
