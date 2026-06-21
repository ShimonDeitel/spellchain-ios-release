import SwiftUI

/// Pro: a browsable archive of past daily puzzles. Each row deterministically regenerates that
/// day's set (no storage needed) and shows your stored result if you've played it.
struct ArchiveView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var activePuzzle: Puzzle?

    private let daysBack = 30

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    ForEach(1...daysBack, id: \.self) { offset in
                        let puzzle = appModel.archivePuzzle(daysAgo: offset)
                        let stored = appModel.result(forDateKey: puzzle.dateKey)
                        Button {
                            Haptics.tap(); activePuzzle = puzzle
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(label(forKey: puzzle.dateKey)).font(.headline)
                                    Text(puzzle.letterString.uppercased())
                                        .font(.caption).tracking(2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let stored {
                                    Text("\(stored.score)").font(.headline).foregroundStyle(Color.appAccent)
                                } else {
                                    Image(systemName: "play.circle").foregroundStyle(Color.appAccent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.appCard)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .tint(Color.appAccent)
            .fullScreenCover(item: $activePuzzle) { puzzle in
                // Archive replays are NOT daily — they don't affect the streak.
                RoundView(puzzle: puzzle, isDaily: false)
            }
        }
    }

    private func label(forKey key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return key }
        var c = DateComponents(); c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard let d = Calendar.current.date(from: c) else { return key }
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none
        return f.string(from: d)
    }
}

// Puzzle needs Identifiable for `.fullScreenCover(item:)`.
extension Puzzle: Identifiable {
    var id: String { dateKey + "-" + String(seed) }
}
