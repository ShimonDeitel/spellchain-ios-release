import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @EnvironmentObject var account: AccountManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("spellchain.theme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage("spellchain.haptics") private var hapticsEnabled = true
    @Environment(\.colorScheme) private var scheme

    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @State private var restoreMessage: String?

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Spellchain \(v)"
    }

    var body: some View {
        NavigationStack {
            Form {
                proSection
                appearanceSection
                gameSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .tint(Color.appAccent)
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .alert("Delete Account?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    appModel.deleteAllData()
                    account.deleteAccount()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and erases your results on this device and from iCloud. This can't be undone.")
            }
        }
    }

    @ViewBuilder
    private var proSection: some View {
        Section {
            if store.isPro {
                HStack {
                    Label("Spellchain Pro", systemImage: "sparkles")
                    Spacer()
                    Text("Unlocked").foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Haptics.tap(); showPaywall = true
                } label: {
                    HStack {
                        Label("Unlock Spellchain Pro", systemImage: "sparkles")
                        Spacer()
                        Text(store.displayPrice).foregroundStyle(.secondary)
                    }
                }
                Button("Restore Purchase") {
                    Task {
                        await store.restore()
                        restoreMessage = store.isPro ? "Restored." : "No previous purchase found."
                    }
                }
                if let restoreMessage {
                    Text(restoreMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } footer: {
            if !store.isPro {
                Text("One-time purchase. Unlimited practice, the full archive, alternate packs & the words-you-missed breakdown.")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeRaw) {
                ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var gameSection: some View {
        Section("Game") {
            Toggle("Haptics", isOn: $hapticsEnabled)
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            if account.isSignedIn {
                HStack {
                    Text("Signed in")
                    Spacer()
                    Text(account.displayName.isEmpty ? "Apple ID" : account.displayName)
                        .foregroundStyle(.secondary)
                }
                Button("Sign Out", role: .destructive) { account.signOut() }
                Button("Delete Account", role: .destructive) { showDeleteConfirm = true }
            } else {
                // Optional opt-in: signing in is never required to play — it only enables
                // cross-device sync of your results.
                SignInWithAppleButton(.continue) { request in
                    account.configure(request)
                } onCompletion: { result in
                    account.handle(result)
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 44)
                .clipShape(Capsule())
                .accessibilityIdentifier("settings-siwa-button")
            }
            Link("Privacy Policy", destination: URL(string: "https://shimondeitel.github.io/spellchain-site/privacy.html")!)
        } header: {
            Text("Account")
        } footer: {
            VStack(spacing: 6) {
                if !account.isSignedIn {
                    Text("Optional. Sign in with Apple to sync your results across your devices. You don't need an account to play.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(version).frame(maxWidth: .infinity, alignment: .center).padding(.top, 4)
            }
        }
    }
}
