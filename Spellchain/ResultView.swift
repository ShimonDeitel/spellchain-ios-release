import SwiftUI

/// Post-round summary: final score, best word, the shareable score card, and the Pro "words you
/// missed" breakdown (gated; non-Pro sees a teaser that opens the paywall).
struct ResultView: View {
    let summary: RoundSummary
    let puzzle: Puzzle
    let streak: Int

    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showShare = false
    @State private var showPaywall = false
    @State private var shareImage: UIImage?

    private var allSolutions: [String] { appModel.allSolutions(for: puzzle) }
    private var foundSet: Set<String> { Set(summary.words.map { $0.lowercased() }) }
    private var missed: [String] { allSolutions.filter { !foundSet.contains($0.lowercased()) } }

    private var card: ScoreCard {
        ScoreCard(letters: puzzle.letters, score: summary.score, wordCount: summary.wordCount,
                  bestWord: summary.bestWord, bestChain: summary.bestChain, streak: streak,
                  dateText: dateText)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    card.shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                    shareButton
                    missedSection
                    Button { dismiss() } label: {
                        Text("Done").frame(maxWidth: .infinity).padding(.vertical, 2)
                    }
                    .softButton()
                    .padding(.horizontal)
                    .accessibilityIdentifier("result-done")
                }
                .padding(.vertical, 28)
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showShare) {
            if let shareImage { ShareSheet(items: [shareImage]) }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Time!").font(.largeTitle.weight(.heavy))
            Text("\(summary.wordCount) words · \(summary.score) points")
                .font(.headline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var shareButton: some View {
        Button {
            Haptics.tap()
            shareImage = card.render()
            if shareImage != nil { showShare = true }
        } label: {
            Label("Share Score Card", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity).padding(.vertical, 2)
        }
        .prominentButton()
        .padding(.horizontal)
        .accessibilityIdentifier("share-button")
    }

    @ViewBuilder
    private var missedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Words you missed").font(.headline)
                Spacer()
                Text("\(missed.count)").font(.subheadline).foregroundStyle(.secondary)
            }
            if store.isPro {
                FlowWords(words: Array(missed.prefix(120)))
                if missed.isEmpty {
                    Text("You found them all. Incredible.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text("Unlock Spellchain Pro to see every word in today's set you didn't find.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { Haptics.tap(); showPaywall = true } label: {
                    Label("See missed words · \(store.displayPrice)", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 2)
                }
                .softButton()
                .accessibilityIdentifier("result-unlock-missed")
            }
        }
        .appCard()
        .padding(.horizontal)
    }

    private var dateText: String {
        if summary.dateKey == "practice" { return "Practice" }
        let parts = summary.dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return summary.dateKey }
        var c = DateComponents(); c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard let d = Calendar.current.date(from: c) else { return summary.dateKey }
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: d)
    }
}

/// A simple wrapping word grid (chips) for the missed-words list.
struct FlowWords: View {
    let words: [String]
    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(words, id: \.self) { w in
                Text(w.uppercased())
                    .font(.caption.weight(.semibold)).tracking(0.5)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.appCard2, in: Capsule())
            }
        }
    }
}
