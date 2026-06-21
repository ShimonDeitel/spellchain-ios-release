import SwiftUI

/// The hub: today's letters, the Play button, the daily streak, lifetime stats, and entry points
/// to practice / archive (Pro) and settings.
struct HomeView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store

    @State private var activeRound: Puzzle?
    @State private var roundIsDaily = true
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showArchive = false

    private var playedToday: Bool { appModel.hasPlayedToday() }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 22) {
                        header
                        todayCard
                        statsRow
                        proRow
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Spellchain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.tap(); showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Color.appAccent)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings-button")
                }
            }
            .tint(Color.appAccent)
            .fullScreenCover(item: $activeRound) { puzzle in
                RoundView(puzzle: puzzle, isDaily: roundIsDaily)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showArchive) { ArchiveView() }
            .onAppear { appModel.refreshTodayIfNeeded() }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text(todayHeadline).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(Color.appAccent)
                Text("\(appModel.currentStreak) day streak")
                    .font(.headline)
            }
        }
        .padding(.top, 8)
    }

    private var todayCard: some View {
        VStack(spacing: 18) {
            Text("TODAY'S LETTERS")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .tracking(1.5)
            LetterFan(letters: appModel.today.letters, accentIndex: appModel.today.letters.count / 2, size: 46)
                .padding(.vertical, 4)

            if playedToday, let r = appModel.result(forDateKey: appModel.today.dateKey) {
                VStack(spacing: 4) {
                    Text("Today's score: \(r.score)").font(.headline)
                    Text("\(r.wordCount) words · best \(r.bestWord.uppercased())")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Haptics.tap(); roundIsDaily = true; activeRound = appModel.today
                } label: {
                    Text("Play Again").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .softButton()
            } else {
                Button {
                    Haptics.tap(); roundIsDaily = true; activeRound = appModel.today
                } label: {
                    Text("Play · 3:00").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .prominentButton()
                .accessibilityIdentifier("play-button")
            }
        }
        .appCard()
    }

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lifetime").font(.headline)
            HStack(spacing: 12) {
                MetricTile(value: "\(appModel.longestStreak)", label: "Best streak")
                MetricTile(value: "\(appModel.totalRounds)", label: "Rounds")
                MetricTile(value: "\(appModel.bestScoreEver)", label: "Top score")
            }
        }
    }

    @ViewBuilder
    private var proRow: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.tap()
                if store.isPro {
                    roundIsDaily = false
                    activeRound = appModel.practicePuzzle()
                } else { showPaywall = true }
            } label: {
                proTile(icon: "infinity", title: "Practice puzzle",
                        subtitle: store.isPro ? "Fresh random letters, any time" : "Pro",
                        locked: !store.isPro)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("practice-button")

            Button {
                Haptics.tap()
                if store.isPro { showArchive = true } else { showPaywall = true }
            } label: {
                proTile(icon: "calendar", title: "Puzzle archive",
                        subtitle: store.isPro ? "Replay past daily sets" : "Pro",
                        locked: !store.isPro)
            }
            .buttonStyle(.plain)
        }
    }

    private func proTile(icon: String, title: String, subtitle: String, locked: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .appCard()
    }

    private var todayHeadline: String {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none
        return f.string(from: .now)
    }
}
