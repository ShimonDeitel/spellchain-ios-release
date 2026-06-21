import SwiftUI

/// The timed round. Tap letters (or type) to build a word, submit, and watch the score + chain
/// multiplier climb. When the 3-minute timer ends, we persist the result and show the score card.
struct RoundView: View {
    let puzzle: Puzzle
    let isDaily: Bool

    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @AppStorage("spellchain.haptics") private var hapticsEnabled = true
    @Environment(\.dismiss) private var dismiss

    @StateObject private var engine = RoundEngine()
    @State private var input = ""
    @State private var flash: SubmitResult?
    @State private var summary: RoundSummary?
    @State private var showResult = false
    @State private var started = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 14) {
                topBar
                scoreHeader
                Spacer(minLength: 0)
                inputDisplay
                tileGrid
                actionRow
                feedbackBar
                foundList
            }
            .padding()
        }
        .onAppear {
            guard !started else { return }
            started = true
            engine.hapticsEnabled = hapticsEnabled
            engine.onComplete = { s in
                if isDaily { appModel.recordDailyResult(s) }
                summary = s
                showResult = true
            }
            engine.start(puzzle: puzzle)
        }
        .fullScreenCover(isPresented: $showResult, onDismiss: { dismiss() }) {
            if let summary {
                ResultView(summary: summary, puzzle: puzzle, streak: appModel.currentStreak)
            }
        }
    }

    // MARK: Top bar (timer + quit)

    private var topBar: some View {
        HStack {
            Button { Haptics.tap(); engine.cancel(reset: true); dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Quit round")
            .accessibilityIdentifier("round-quit")
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text(mmss(engine.secondsRemaining))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.title3.weight(.bold))
            .foregroundStyle(engine.secondsRemaining <= 10 ? Color.red : .primary)
            Spacer()
            Image(systemName: "xmark").opacity(0)   // keep the timer centered
        }
    }

    // MARK: Score + chain

    private var scoreHeader: some View {
        HStack(spacing: 12) {
            MetricTile(value: "\(engine.score)", label: "Score")
            MetricTile(value: "\(engine.wordCount)", label: "Words")
            MetricTile(value: String(format: "%.2g×", engine.currentMultiplier), label: "Chain")
        }
    }

    // MARK: Input

    private var inputDisplay: some View {
        Text(input.isEmpty ? " " : input.uppercased())
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .tracking(4)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(input.isEmpty ? .secondary : Color.appAccent)
            .accessibilityIdentifier("round-input")
    }

    private var tileGrid: some View {
        // Two rows: 4 + 3 (the fanned / ascending feel).
        let row1 = Array(puzzle.letters.prefix(4))
        let row2 = Array(puzzle.letters.suffix(max(0, puzzle.letters.count - 4)))
        return VStack(spacing: 10) {
            HStack(spacing: 10) { ForEach(Array(row1.enumerated()), id: \.offset) { i, ch in tile(ch, index: i) } }
            HStack(spacing: 10) { ForEach(Array(row2.enumerated()), id: \.offset) { i, ch in tile(ch, index: i + 4) } }
        }
    }

    private func tile(_ ch: Character, index: Int) -> some View {
        LetterTile(letter: ch, highlighted: index == puzzle.letters.count / 2, size: 64) {
            guard input.count < WordRules.maxLength else { return }
            input.append(ch)
            Haptics.soft()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                if !input.isEmpty { input.removeLast(); Haptics.soft() }
            } label: {
                Image(systemName: "delete.left").frame(maxWidth: .infinity).padding(.vertical, 2)
            }
            .softButton()
            .accessibilityLabel("Delete letter")
            .disabled(input.isEmpty)

            Button { submit() } label: {
                Text("Enter").frame(maxWidth: .infinity).padding(.vertical, 2)
            }
            .prominentButton()
            .disabled(input.count < WordRules.minLength)
            .accessibilityIdentifier("round-enter")
        }
    }

    private var feedbackBar: some View {
        Text(feedbackText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(feedbackColor)
            .frame(height: 22)
            .animation(.easeOut(duration: 0.2), value: flash)
    }

    private var foundList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(engine.found) { fw in
                    HStack {
                        Text(fw.word.uppercased())
                            .font(.body.weight(.semibold)).tracking(1)
                        Spacer()
                        if fw.chainAtSubmit > 0 {
                            Text("×\(String(format: "%.2g", Scoring.chainMultiplier(chain: fw.chainAtSubmit)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("+\(fw.points)").font(.body.weight(.bold)).foregroundStyle(Color.appAccent)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .frame(maxHeight: 180)
    }

    // MARK: Actions

    private func submit() {
        let result = engine.submit(input)
        flash = result
        switch result {
        case .accepted: input = ""
        case .duplicate: break
        default: Haptics.error()
        }
        // Clear the input on any rejection so the player keeps moving.
        if case .accepted = result {} else { input = "" }
    }

    private var feedbackText: String {
        switch flash {
        case .accepted(let pts, let chain):
            return chain > 1 ? "+\(pts) · chain ×\(String(format: "%.2g", Scoring.chainMultiplier(chain: chain - 1)))" : "+\(pts)"
        case .tooShort: return "Too short — 3+ letters"
        case .notInLetters: return "Uses letters you don't have"
        case .notAWord: return "Not in the word list"
        case .duplicate: return "Already found"
        case nil: return " "
        }
    }

    private var feedbackColor: Color {
        if case .accepted = flash { return Color.appAccent }
        if flash == nil { return .clear }
        return .secondary
    }
}
