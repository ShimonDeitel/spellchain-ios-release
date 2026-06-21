import Foundation

/// Pure scoring + chain-multiplier math. Deterministic and fully unit-tested.
///
/// Rules:
///  • Base points reward longer words (length²) so a 7-letter word is worth far more than a 3.
///  • A *chain* builds with each consecutive valid word. The chain multiplier steps up every time
///    you submit a valid word without an invalid one in between; an invalid submission breaks it.
///  • The points credited for a word = basePoints(length) × chainMultiplier(at that moment).
enum Scoring {

    /// Base points for a word of `length` letters (length 3–7). Quadratic so length really pays.
    static func basePoints(length: Int) -> Int {
        let l = max(0, length)
        return l * l   // 3→9, 4→16, 5→25, 6→36, 7→49
    }

    /// Multiplier applied at a given chain depth. Chain 0 (first word) = 1.0×; each subsequent
    /// consecutive valid word adds 0.25×, capped at 3.0× so it stays bounded.
    static func chainMultiplier(chain: Int) -> Double {
        let steps = max(0, chain)
        return min(3.0, 1.0 + 0.25 * Double(steps))
    }

    /// Points credited for accepting a valid word at the current `chain` depth.
    /// `chain` is the number of consecutive valid words already accepted (0 for the first).
    static func points(forValidWordLength length: Int, chain: Int) -> Int {
        let base = Double(basePoints(length: length))
        return Int((base * chainMultiplier(chain: chain)).rounded())
    }
}
