import SwiftUI

/// The shareable Score Card. Fixed colors (not theme-dependent) so the exported image is
/// consistent, with the Spellchain wordmark + App Store CTA for organic growth.
struct ScoreCard: View {
    let letters: [Character]
    let score: Int
    let wordCount: Int
    let bestWord: String
    let bestChain: Int
    let streak: Int
    let dateText: String

    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 18) {
                Text(dateText.uppercased())
                    .font(.caption.weight(.semibold)).tracking(1.5)
                    .foregroundStyle(Color(white: 0.55))

                // The motif: an ascending letter fan, one tile Apple-blue.
                HStack(spacing: 5) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { idx, ch in
                        Text(String(ch).uppercased())
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(idx == letters.count / 2 ? .white : .black)
                            .frame(width: 30, height: 30)
                            .background(
                                idx == letters.count / 2 ? Color.appAccent : Color(white: 0.93),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .offset(y: -CGFloat(idx) * 1.5)
                    }
                }
                .padding(.vertical, 4)

                Text("\(score)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                Text("CHAIN SCORE").font(.caption2.weight(.semibold)).tracking(1.5)
                    .foregroundStyle(Color(white: 0.6))

                HStack(spacing: 22) {
                    stat("\(wordCount)", "words")
                    stat(bestWord.isEmpty ? "—" : bestWord.uppercased(), "best word")
                    stat("\(streak)", "day streak")
                }

                Spacer().frame(height: 2)
                Text("Spellchain")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.appAccent)
                Text("Daily Word Build · on the App Store")
                    .font(.caption).foregroundStyle(Color(white: 0.55))
            }
            .padding(34)
        }
        .frame(width: 360, height: 420)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.black)
            Text(label).font(.caption2).foregroundStyle(Color(white: 0.55))
        }
    }

    @MainActor func render() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage
    }
}
