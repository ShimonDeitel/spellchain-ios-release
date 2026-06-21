import XCTest
@testable import Spellchain

/// Pure-logic unit tests: word/letter rules, scoring + chain math, daily-set determinism,
/// and streak math. No I/O, no StoreKit — fully deterministic.
final class SpellchainTests: XCTestCase {

    // MARK: - Word validity given a letter multiset

    func testCanBuildRespectsLetterCounts() {
        // Letters: t r a c e (each once)
        let avail = WordRules.counts(of: Array("trace"))
        XCTAssertTrue(WordRules.canBuild("cat", from: avail))
        XCTAssertTrue(WordRules.canBuild("care", from: avail))
        XCTAssertTrue(WordRules.canBuild("trace", from: avail))
        // 'rate' needs r,a,t,e — all present once → ok
        XCTAssertTrue(WordRules.canBuild("rate", from: avail))
    }

    func testCanBuildRejectsMissingAndOverusedLetters() {
        let avail = WordRules.counts(of: Array("trace")) // one of each, no duplicates
        // 'tart' needs two t's but only one is available.
        XCTAssertFalse(WordRules.canBuild("tart", from: avail))
        // 'dog' uses letters not present.
        XCTAssertFalse(WordRules.canBuild("dog", from: avail))
    }

    func testCanBuildEnforcesLengthBounds() {
        let avail = WordRules.counts(of: Array("trace"))
        XCTAssertFalse(WordRules.canBuild("at", from: avail), "2 letters is below the minimum")
        // Build an 8-letter availability and an 8-letter word → too long.
        let big = WordRules.counts(of: Array("aabbccdd"))
        XCTAssertFalse(WordRules.canBuild("aabbccdd", from: big), "8 letters exceeds the maximum")
    }

    func testCountsAreCaseInsensitive() {
        let avail = WordRules.counts(of: Array("TRACE"))
        XCTAssertTrue(WordRules.canBuild("CARE", from: avail))
        XCTAssertEqual(avail[Character("t")], 1)
    }

    // MARK: - Scoring + chain multiplier math

    func testBasePointsAreQuadraticByLength() {
        XCTAssertEqual(Scoring.basePoints(length: 3), 9)
        XCTAssertEqual(Scoring.basePoints(length: 4), 16)
        XCTAssertEqual(Scoring.basePoints(length: 5), 25)
        XCTAssertEqual(Scoring.basePoints(length: 7), 49)
    }

    func testChainMultiplierStepsAndCaps() {
        XCTAssertEqual(Scoring.chainMultiplier(chain: 0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Scoring.chainMultiplier(chain: 1), 1.25, accuracy: 0.0001)
        XCTAssertEqual(Scoring.chainMultiplier(chain: 4), 2.0, accuracy: 0.0001)
        // Cap at 3.0×.
        XCTAssertEqual(Scoring.chainMultiplier(chain: 8), 3.0, accuracy: 0.0001)
        XCTAssertEqual(Scoring.chainMultiplier(chain: 100), 3.0, accuracy: 0.0001)
    }

    func testPointsCombineBaseAndChain() {
        // First word (chain 0): 5 letters → 25 × 1.0 = 25
        XCTAssertEqual(Scoring.points(forValidWordLength: 5, chain: 0), 25)
        // Same word at chain 2 → 25 × 1.5 = 37.5 → rounds to 38
        XCTAssertEqual(Scoring.points(forValidWordLength: 5, chain: 2), 38)
        // 7-letter word at the cap → 49 × 3.0 = 147
        XCTAssertEqual(Scoring.points(forValidWordLength: 7, chain: 8), 147)
    }

    // MARK: - Daily-set determinism by date

    func testDailySeedIsDeterministicForSameDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 21))!
        let s1 = PuzzleGenerator.dailySeed(for: date, calendar: cal)
        let s2 = PuzzleGenerator.dailySeed(for: date, calendar: cal)
        XCTAssertEqual(s1, s2, "same date must yield the same seed")
    }

    func testDifferentDatesYieldDifferentSeeds() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d1 = cal.date(from: DateComponents(year: 2026, month: 6, day: 21))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 6, day: 22))!
        XCTAssertNotEqual(PuzzleGenerator.dailySeed(for: d1, calendar: cal),
                          PuzzleGenerator.dailySeed(for: d2, calendar: cal))
    }

    func testCandidateIsDeterministicAndWellFormed() {
        let a = PuzzleGenerator.candidate(seed: 12345)
        let b = PuzzleGenerator.candidate(seed: 12345)
        XCTAssertEqual(a, b, "same seed → identical 7-letter set (no server needed)")
        XCTAssertEqual(a.count, PuzzleGenerator.setSize)
        XCTAssertTrue(a.allSatisfy { $0.isASCII && $0.isLetter })
        let vowelCount = a.filter { "aeiou".contains($0) }.count
        XCTAssertGreaterThanOrEqual(vowelCount, 2, "every set should carry at least two vowels")
    }

    func testDateKeyFormatting() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        XCTAssertEqual(PuzzleGenerator.dateKey(for: date, calendar: cal), "2026-01-05")
    }

    // MARK: - Streak math

    private func days(_ offsets: [Int], cal: Calendar) -> Set<Date> {
        let today = cal.startOfDay(for: Date())
        return Set(offsets.compactMap { cal.date(byAdding: .day, value: -$0, to: today) })
    }

    func testCurrentStreakCountsTodayBackwards() {
        let cal = Calendar.current
        XCTAssertEqual(AppModel.currentStreak(days: days([0, 1, 2], cal: cal), cal: cal), 3)
    }

    func testCurrentStreakHoldsWhenTodayNotYetPlayed() {
        let cal = Calendar.current
        // Played yesterday & day before, not today → streak still 2 (today still possible).
        XCTAssertEqual(AppModel.currentStreak(days: days([1, 2], cal: cal), cal: cal), 2)
    }

    func testStreakBreaksWhenADayIsSkipped() {
        let cal = Calendar.current
        // Today, then gap at day 1, then days 2 & 3 → current streak is just 1 (skip breaks it).
        XCTAssertEqual(AppModel.currentStreak(days: days([0, 2, 3], cal: cal), cal: cal), 1)
        XCTAssertEqual(AppModel.currentStreak(days: [], cal: cal), 0)
    }

    func testLongestStreak() {
        let cal = Calendar.current
        // Runs: {0,1,2} length 3, {5,6} length 2 → longest 3.
        XCTAssertEqual(AppModel.longestStreak(days: days([0, 1, 2, 5, 6], cal: cal), cal: cal), 3)
    }

    func testDayFromKeyRoundTrips() {
        let cal = Calendar.current
        let key = "2026-06-21"
        let day = AppModel.day(fromKey: key, cal: cal)
        XCTAssertNotNil(day)
        XCTAssertEqual(AppModel.day(fromKey: "garbage", cal: cal), nil)
    }

    // MARK: - Store product id (deterministic, no live fetch)

    @MainActor
    func testStoreProductIDAndPrice() async {
        XCTAssertEqual(Store.productID, "spellchain_pro_unlock")
        let store = Store()
        XCTAssertEqual(store.displayPrice, "$0.99")
        XCTAssertFalse(store.isPro, "Pro must start locked")
    }
}
