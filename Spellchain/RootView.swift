import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("spellchain.theme") private var themeRaw = AppTheme.system.rawValue

    @AppStorage("spellchain.onboardingSeen") private var onboardingSeen = false

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }

    var body: some View {
        Group {
            // No login gate. The game's main screen is always available; results persist locally
            // via SwiftData with zero account required (App Review 5.1.1(v)). The first-launch
            // onboarding is a one-time, dismissable value-prop card — Sign in with Apple is an
            // optional opt-in offered there and in Settings, never required to play.
            if onboardingSeen {
                HomeView()
            } else {
                OnboardingView(onContinue: { onboardingSeen = true })
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .onChange(of: store.isPro) { _, _ in appModel.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Reopen hook: when the app returns to the foreground, roll over to the new daily
            // set if the local day changed while we were away.
            if phase == .active { appModel.refreshTodayIfNeeded() }
        }
    }
}
