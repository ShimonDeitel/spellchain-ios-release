import SwiftUI

/// A single letter tile. One designated tile is rendered in Apple-blue (the icon motif carried
/// into the UI). Tapping appends the letter to the current input.
struct LetterTile: View {
    let letter: Character
    var highlighted: Bool = false
    var dimmed: Bool = false
    var size: CGFloat = 60
    var action: (() -> Void)? = nil

    var body: some View {
        let content = Text(String(letter).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(highlighted ? .white : .primary)
            .frame(width: size, height: size)
            .background(
                highlighted ? Color.appAccent : Color.appCard,
                in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(Color.appHair.opacity(0.6), lineWidth: highlighted ? 0 : 1)
            )
            .opacity(dimmed ? 0.35 : 1)
            .accessibilityIdentifier("tile-\(letter)")

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// A fanned, ascending row of 7 letter tiles — the brand motif (one tile Apple-blue).
struct LetterFan: View {
    let letters: [Character]
    var accentIndex: Int = 0
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(letters.enumerated()), id: \.offset) { idx, ch in
                LetterTile(letter: ch, highlighted: idx == accentIndex, size: size)
                    .offset(y: -CGFloat(idx) * 2)   // gentle ascending stagger
            }
        }
    }
}

/// A small labelled metric tile used on Home / Stats.
struct MetricTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.appAccent)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Wraps UIActivityViewController so we can share a rendered Score Card image.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

func mmss(_ seconds: Int) -> String {
    String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}
