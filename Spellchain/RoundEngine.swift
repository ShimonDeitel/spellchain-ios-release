import Foundation
import SwiftUI

/// One found word inside a round, with the points it earned and the chain depth it landed at.
struct FoundWord: Identifiable, Equatable {
    let id = UUID()
    let word: String
    let points: Int
    let chainAtSubmit: Int
}

/// The outcome of submitting a word.
enum SubmitResult: Equatable {
    case accepted(points: Int, chain: Int)
    case tooShort
    case notInLetters
    case notAWord
    case duplicate
}

/// Drives a single timed round: counts down, validates submissions against the puzzle + dictionary,
/// tracks the live score and chain multiplier, and fires `onComplete` exactly once at time-up.
@MainActor
final class RoundEngine: ObservableObject {
    // Config
    static let defaultDuration = 180   // 3 minutes

    // Live state
    @Published private(set) var puzzle: Puzzle?
    @Published private(set) var secondsRemaining = defaultDuration
    @Published private(set) var score = 0
    @Published private(set) var chain = 0                // consecutive valid words
    @Published private(set) var bestChain = 0
    @Published private(set) var found: [FoundWord] = []  // newest first
    @Published private(set) var isRunning = false
    @Published private(set) var isComplete = false
    @Published var hapticsEnabled = true

    /// Fires once when the timer reaches zero (or `finish()` is called). Not called on `cancel`.
    var onComplete: ((RoundSummary) -> Void)?

    private var totalDuration = defaultDuration
    private var timer: Timer?
    private var foundSet: Set<String> = []
    private let dictionary: WordDictionary

    init(dictionary: WordDictionary = .shared) {
        self.dictionary = dictionary
    }

    var bestWord: String {
        found.max { $0.points < $1.points }?.word ?? ""
    }
    var wordCount: Int { found.count }
    var currentMultiplier: Double { Scoring.chainMultiplier(chain: chain) }

    // MARK: Lifecycle

    func start(puzzle: Puzzle, duration: Int = defaultDuration) {
        cancel(reset: true)
        self.puzzle = puzzle
        totalDuration = duration
        secondsRemaining = duration
        score = 0; chain = 0; bestChain = 0
        found = []; foundSet = []
        isComplete = false
        isRunning = true
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard isRunning else { return }
        secondsRemaining -= 1
        if secondsRemaining <= 10, secondsRemaining > 0, hapticsEnabled { Haptics.rigid() }
        if secondsRemaining <= 0 {
            secondsRemaining = 0
            finish()
        }
    }

    /// End the round normally (time-up or explicit finish) → fires `onComplete` once.
    func finish() {
        guard isRunning else { return }
        invalidate()
        isRunning = false
        isComplete = true
        if hapticsEnabled { Haptics.success() }
        onComplete?(summary)
    }

    /// Abort without completing (e.g. user backs out). Never fires `onComplete`.
    func cancel(reset: Bool) {
        invalidate()
        isRunning = false
        if reset {
            isComplete = false
            secondsRemaining = totalDuration
            score = 0; chain = 0; bestChain = 0
            found = []; foundSet = []
        }
    }

    private func invalidate() { timer?.invalidate(); timer = nil }

    // MARK: Submission

    @discardableResult
    func submit(_ raw: String) -> SubmitResult {
        guard isRunning, let puzzle else { return .notAWord }
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard word.count >= WordRules.minLength else { breakChain(); return .tooShort }
        guard !foundSet.contains(word) else { return .duplicate }   // dup doesn't break the chain
        guard WordRules.canBuild(word, from: puzzle.counts) else { breakChain(); return .notInLetters }
        guard dictionary.words.contains(word) else { breakChain(); return .notAWord }

        // Accept.
        let earned = Scoring.points(forValidWordLength: word.count, chain: chain)
        score += earned
        let entry = FoundWord(word: word, points: earned, chainAtSubmit: chain)
        found.insert(entry, at: 0)
        foundSet.insert(word)
        chain += 1
        bestChain = max(bestChain, chain)
        if hapticsEnabled { Haptics.tap() }
        return .accepted(points: earned, chain: chain)
    }

    private func breakChain() {
        if chain > 0, hapticsEnabled { Haptics.warning() }
        chain = 0
    }

    // MARK: Summary

    var summary: RoundSummary {
        RoundSummary(
            dateKey: puzzle?.dateKey ?? "",
            letters: puzzle?.letterString ?? "",
            score: score,
            wordCount: wordCount,
            bestWord: bestWord,
            bestChain: bestChain,
            words: found.map { $0.word }
        )
    }
}

/// Immutable result of a finished round, handed to AppModel for persistence + the result screen.
struct RoundSummary: Equatable {
    let dateKey: String
    let letters: String
    let score: Int
    let wordCount: Int
    let bestWord: String
    let bestChain: Int
    let words: [String]
}
