import SwiftUI
import AuthenticationServices

/// First launch. The letter-fan motif sits above a single primary "Start playing" button so the
/// player reaches the game with zero typing and zero account. Sign in with Apple is offered here
/// only as an OPTIONAL opt-in for cross-device sync — it is never required to play (App Review
/// 5.1.1(v)). The same opt-in lives in Settings.
struct OnboardingView: View {
    /// Called when the player dismisses onboarding (with or without signing in) to enter Home.
    var onContinue: () -> Void

    @EnvironmentObject var account: AccountManager
    @EnvironmentObject var appModel: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                LetterFan(letters: appModel.today.letters, accentIndex: accentIndex, size: 44)
                    .padding(.bottom, 8)

                Spacer(minLength: 28)

                VStack(spacing: 10) {
                    Text("Spellchain")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("One letter set.\nHow many words can you build?")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 28)

                VStack(spacing: 14) {
                    Button {
                        Haptics.tap()
                        onContinue()
                    } label: {
                        Text("Start playing").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .prominentButton()
                    .accessibilityIdentifier("onboarding-start")

                    SignInWithAppleButton(.continue) { request in
                        account.configure(request)
                    } onCompletion: { result in
                        account.handle(result)
                        if account.isSignedIn { onContinue() }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("siwa-button")

                    Text("Optional — sign in to sync across your devices. You can also do this later in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("No subscription. No ads. A new puzzle every day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 28)
            }
            .padding()
        }
    }

    private var accentIndex: Int {
        let n = appModel.today.letters.count
        return n > 0 ? n / 2 : 0
    }
}
