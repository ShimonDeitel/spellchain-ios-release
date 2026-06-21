import Foundation
import SwiftData
import SwiftUI

/// App state: owns the SwiftData store, derives the daily streak + lifetime stats, and exposes the
/// today's-puzzle / archive / practice accessors. Stats are always derived from results — never
/// stored as truth.
@MainActor
final class AppModel: ObservableObject {
    let container: ModelContainer
    weak var store: Store?

    // Derived stats
    @Published private(set) var currentStreak = 0
    @Published private(set) var longestStreak = 0
    @Published private(set) var totalRounds = 0
    @Published private(set) var totalWords = 0
    @Published private(set) var bestScoreEver = 0
    @Published private(set) var bestWordEver = ""
    @Published private(set) var didPlayToday = false

    // Today's puzzle (recomputed on demand; cached for the session/day).
    @Published private(set) var today: Puzzle

    init(container: ModelContainer) {
        self.container = container
        WordDictionary.shared.load()
        self.today = PuzzleGenerator.dailyPuzzle(for: .now)
        #if DEBUG
        seedIfRequested()
        #endif
        refresh()
    }

    // MARK: Container (offline-first; CloudKit private-DB mirroring when an iCloud account exists)

    static func makeContainer() -> ModelContainer {
        let schema = Schema([DailyResult.self])
        if FileManager.default.ubiquityIdentityToken != nil {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            if let c = try? ModelContainer(for: schema, configurations: cloud) { return c }
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: local) { return c }
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: mem)
    }

    // MARK: Puzzles

    /// Refresh today's puzzle if the local day rolled over since we last computed it (reopen hook).
    func refreshTodayIfNeeded() {
        let key = PuzzleGenerator.dateKey(for: .now)
        if today.dateKey != key {
            today = PuzzleGenerator.dailyPuzzle(for: .now)
            refresh()
        }
    }

    func archivePuzzle(daysAgo: Int) -> Puzzle {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return PuzzleGenerator.dailyPuzzle(for: date)
    }

    func practicePuzzle() -> Puzzle { PuzzleGenerator.practicePuzzle() }

    /// All dictionary words buildable from a puzzle's letters (used for the Pro "missed words").
    func allSolutions(for puzzle: Puzzle) -> [String] {
        PuzzleGenerator.solutions(for: puzzle.letters).sorted { a, b in
            a.count != b.count ? a.count > b.count : a < b
        }
    }

    // MARK: Results

    /// Persist a finished daily round. Only the FIRST result for a given day counts toward the
    /// daily streak; replaying the same day updates the stored result if the new score is higher.
    func recordDailyResult(_ summary: RoundSummary) {
        guard !summary.dateKey.isEmpty, summary.dateKey != "practice" else { return }
        let ctx = container.mainContext
        let key = summary.dateKey
        let existing = result(forDateKey: key)
        if let existing {
            if summary.score > existing.score {
                existing.score = summary.score
                existing.wordCount = summary.wordCount
                existing.bestWord = summary.bestWord
                existing.bestChain = summary.bestChain
                existing.wordsJoined = summary.words.joined(separator: "\n")
            }
        } else {
            ctx.insert(DailyResult(date: .now, dateKey: key, letters: summary.letters,
                                   score: summary.score, wordCount: summary.wordCount,
                                   bestWord: summary.bestWord, bestChain: summary.bestChain,
                                   words: summary.words))
        }
        try? ctx.save()
        refresh()
    }

    func result(forDateKey key: String) -> DailyResult? {
        let d = FetchDescriptor<DailyResult>(predicate: #Predicate { $0.dateKey == key })
        return try? container.mainContext.fetch(d).first
    }

    func hasPlayedToday() -> Bool { result(forDateKey: today.dateKey) != nil }

    func allResults() -> [DailyResult] {
        let d = FetchDescriptor<DailyResult>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? container.mainContext.fetch(d)) ?? []
    }

    // MARK: Stats / streak

    func refresh() {
        // CloudKit forbids unique constraints, so two devices that finish the same day offline can
        // each insert a DailyResult with the same dateKey; when they sync, both survive. Reconcile
        // before deriving stats so duplicates never inflate totalRounds / totalWords / Archive.
        let all = reconcileDuplicates(allResults())
        totalRounds = all.count
        totalWords = all.reduce(0) { $0 + $1.wordCount }
        bestScoreEver = all.map(\.score).max() ?? 0
        bestWordEver = all.map(\.bestWord).filter { !$0.isEmpty }.max { $0.count < $1.count } ?? ""

        let cal = Calendar.current
        let days = Set(all.compactMap { Self.day(fromKey: $0.dateKey, cal: cal) })
        didPlayToday = days.contains(cal.startOfDay(for: .now))
        currentStreak = Self.currentStreak(days: days, cal: cal)
        longestStreak = Self.longestStreak(days: days, cal: cal)
    }

    /// Collapse CloudKit-merged duplicates: group by dateKey, keep the highest-score record per key
    /// (matching the existing "higher score wins" rule; ties broken by earliest date), delete the
    /// rest, and persist. Returns the deduplicated, surviving results. Safe to run on every refresh.
    @discardableResult
    private func reconcileDuplicates(_ results: [DailyResult]) -> [DailyResult] {
        var keepers: [String: DailyResult] = [:]
        var toDelete: [DailyResult] = []
        for r in results {
            guard let winner = keepers[r.dateKey] else { keepers[r.dateKey] = r; continue }
            // Higher score wins; on a tie, keep the earlier-dated record for stability.
            let rWins = r.score > winner.score || (r.score == winner.score && r.date < winner.date)
            if rWins {
                toDelete.append(winner)
                keepers[r.dateKey] = r
            } else {
                toDelete.append(r)
            }
        }
        if !toDelete.isEmpty {
            let ctx = container.mainContext
            for d in toDelete { ctx.delete(d) }
            try? ctx.save()
        }
        return Array(keepers.values)
    }

    /// Parse a "yyyy-MM-dd" key into the start-of-day Date in `cal`'s time zone.
    nonisolated static func day(fromKey key: String, cal: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return cal.date(from: c).map { cal.startOfDay(for: $0) }
    }

    nonisolated static func currentStreak(days: Set<Date>, cal: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        var day = cal.startOfDay(for: .now)
        if !days.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day), days.contains(yesterday)
            else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    nonisolated static func longestStreak(days: Set<Date>, cal: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var best = 1, run = 1
        for i in 1..<sorted.count {
            if let prev = cal.date(byAdding: .day, value: 1, to: sorted[i - 1]), prev == sorted[i] {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
        }
        return best
    }

    // MARK: Delete account

    func deleteAllData() {
        let ctx = container.mainContext
        try? ctx.delete(model: DailyResult.self)
        try? ctx.save()
        refresh()
    }

    // MARK: DEBUG seeding (compiled out of Release)

    #if DEBUG
    private func seedIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let n = env["SPELLCHAIN_SEED"].flatMap(Int.init), n > 0 else { return }
        let ctx = container.mainContext
        if ((try? ctx.fetch(FetchDescriptor<DailyResult>()))?.isEmpty ?? true) {
            let cal = Calendar.current
            for offset in 0..<n {
                guard let day = cal.date(byAdding: .day, value: -offset, to: .now) else { continue }
                let key = PuzzleGenerator.dateKey(for: day)
                let p = PuzzleGenerator.dailyPuzzle(for: day)
                ctx.insert(DailyResult(date: day, dateKey: key, letters: p.letterString,
                                       score: 120 + offset * 10, wordCount: 8 + offset % 5,
                                       bestWord: "puzzle", bestChain: 3 + offset % 4,
                                       words: ["cat", "care", "trace"]))
            }
            try? ctx.save()
        }
    }
    #endif
}
