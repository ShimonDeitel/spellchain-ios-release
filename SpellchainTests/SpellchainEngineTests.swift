import XCTest
import SwiftData
@testable import Spellchain

/// Integration tests that exercise the live round engine and the dictionary-backed solvability
/// guarantee. These rely on the bundled `words.txt` resource being present in the app bundle.
@MainActor
final class SpellchainEngineTests: XCTestCase {

    private func memoryModel() -> ModelContainer {
        try! ModelContainer(for: DailyResult.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testDictionaryLoadsFromBundle() {
        let dict = WordDictionary.shared
        dict.load()
        XCTAssertTrue(dict.isLoaded)
        XCTAssertGreaterThan(dict.words.count, 10_000, "bundled words.txt should load thousands of words")
        XCTAssertTrue(dict.words.contains("trace"))
        XCTAssertTrue(dict.words.contains("cat"))
    }

    func testDailyPuzzleIsSolvableAndDeterministic() throws {
        WordDictionary.shared.load()
        guard WordDictionary.shared.words.count > 1000 else {
            throw XCTSkip("dictionary not bundled in this run")
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 21))!

        let p1 = PuzzleGenerator.dailyPuzzle(for: date, calendar: cal)
        let p2 = PuzzleGenerator.dailyPuzzle(for: date, calendar: cal)
        XCTAssertEqual(p1.letters, p2.letters, "the daily set must be identical for the same date")
        XCTAssertEqual(p1.letters.count, 7)

        let solutions = PuzzleGenerator.solutionCount(for: p1.letters)
        XCTAssertGreaterThanOrEqual(solutions, PuzzleGenerator.minWords,
                                    "the daily set must yield at least \(PuzzleGenerator.minWords) words")
    }

    func testEngineScoresValidWordsAndBreaksChainOnInvalid() throws {
        WordDictionary.shared.load()
        guard WordDictionary.shared.words.count > 1000 else {
            throw XCTSkip("dictionary not bundled in this run")
        }
        // A hand-picked solvable set: c a r e t s n → builds care, scare, caret, trace, etc.
        // Words asserted here are confirmed present in the bundled (filtered) word list.
        let puzzle = Puzzle(letters: Array("caretsn"), seed: 1, dateKey: "test")
        let engine = RoundEngine()
        engine.hapticsEnabled = false
        engine.start(puzzle: puzzle, duration: 60)
        XCTAssertTrue(WordDictionary.shared.words.contains("care"))
        XCTAssertTrue(WordDictionary.shared.words.contains("scare"))

        // First valid word at chain 0.
        if case .accepted(let pts, let chain) = engine.submit("care") {
            XCTAssertEqual(chain, 1)
            XCTAssertEqual(pts, Scoring.points(forValidWordLength: 4, chain: 0))
        } else { XCTFail("`care` should be accepted") }

        // Second valid word continues the chain (chain depth 1 → 1.25×).
        if case .accepted(_, let chain) = engine.submit("scare") {
            XCTAssertEqual(chain, 2)
        } else { XCTFail("`scare` should be accepted") }

        XCTAssertEqual(engine.wordCount, 2)
        XCTAssertGreaterThan(engine.score, 0)

        // An invalid word breaks the chain back to 0.
        let bad = engine.submit("zzz")   // not buildable / not a word
        XCTAssertNotEqual(bad, .accepted(points: 0, chain: 0))
        XCTAssertEqual(engine.chain, 0, "an invalid submission must reset the chain")

        // Duplicate doesn't double-count.
        let dup = engine.submit("care")
        XCTAssertEqual(dup, .duplicate)
        XCTAssertEqual(engine.wordCount, 2)

        engine.cancel(reset: true)
    }

    func testEngineRejectsLettersNotInSet() {
        WordDictionary.shared.load()
        let puzzle = Puzzle(letters: Array("caretsn"), seed: 1, dateKey: "test")
        let engine = RoundEngine()
        engine.hapticsEnabled = false
        engine.start(puzzle: puzzle, duration: 60)
        // 'dog' uses letters not in the set.
        XCTAssertEqual(engine.submit("dog"), .notInLetters)
        XCTAssertEqual(engine.submit("at"), .tooShort)
        engine.cancel(reset: true)
    }

    func testRecordDailyResultUpdatesStatsAndStreak() {
        let model = AppModel(container: memoryModel())
        XCTAssertEqual(model.totalRounds, 0)
        XCTAssertEqual(model.currentStreak, 0)

        let key = PuzzleGenerator.dateKey(for: .now)
        let summary = RoundSummary(dateKey: key, letters: "caretsn", score: 120,
                                   wordCount: 8, bestWord: "scare", bestChain: 4,
                                   words: ["care", "cares", "scare"])
        model.recordDailyResult(summary)

        XCTAssertEqual(model.totalRounds, 1)
        XCTAssertEqual(model.bestScoreEver, 120)
        XCTAssertTrue(model.didPlayToday)
        XCTAssertEqual(model.currentStreak, 1)

        // Replaying the same day keeps one round; a higher score replaces it.
        let better = RoundSummary(dateKey: key, letters: "caretsn", score: 200,
                                  wordCount: 12, bestWord: "tracers", bestChain: 6,
                                  words: ["tracers"])
        model.recordDailyResult(better)
        XCTAssertEqual(model.totalRounds, 1, "same day must not create a second result")
        XCTAssertEqual(model.bestScoreEver, 200)
    }

    func testPracticeResultsAreNotRecordedAsDaily() {
        let model = AppModel(container: memoryModel())
        let summary = RoundSummary(dateKey: "practice", letters: "caretsn", score: 99,
                                   wordCount: 5, bestWord: "care", bestChain: 2, words: ["care"])
        model.recordDailyResult(summary)
        XCTAssertEqual(model.totalRounds, 0, "practice rounds never count toward the daily record")
    }

    /// CloudKit can't enforce a unique dateKey, so two offline devices can each insert a result for
    /// the same day; after they sync, refresh() must collapse them to one (highest score wins) so
    /// totalRounds / totalWords / bestScore never double-count.
    func testRefreshReconcilesCloudKitDuplicatesByDateKey() {
        let container = memoryModel()
        let model = AppModel(container: container)
        let ctx = container.mainContext
        let key = "2026-06-20"

        // Simulate two merged-in records for the same day (as if from two devices).
        ctx.insert(DailyResult(date: .now, dateKey: key, letters: "caretsn",
                               score: 120, wordCount: 8, bestWord: "scare", bestChain: 4,
                               words: ["care", "scare"]))
        ctx.insert(DailyResult(date: .now, dateKey: key, letters: "caretsn",
                               score: 200, wordCount: 12, bestWord: "tracers", bestChain: 6,
                               words: ["tracers"]))
        try? ctx.save()

        model.refresh()

        XCTAssertEqual(model.totalRounds, 1, "duplicate dateKeys must collapse to one round")
        XCTAssertEqual(model.totalWords, 12, "stats must not double-count the duplicate")
        XCTAssertEqual(model.bestScoreEver, 200, "the higher-score duplicate must be the survivor")
        // The losing duplicate must actually be deleted from the store, not just hidden.
        let remaining = (try? ctx.fetch(FetchDescriptor<DailyResult>(
            predicate: #Predicate { $0.dateKey == key }))) ?? []
        XCTAssertEqual(remaining.count, 1, "the lower-score duplicate must be deleted")
        XCTAssertEqual(remaining.first?.score, 200)
    }
}
