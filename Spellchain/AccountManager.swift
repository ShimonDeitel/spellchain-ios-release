import Foundation
import AuthenticationServices
import SwiftUI

/// Sign in with Apple. Identifies the user (a stable id kept on-device) so paid status can follow
/// them and their results sync via iCloud. No password is ever handled; data stays on the device
/// unless iCloud sync is available. Works fully offline / without an iCloud account.
@MainActor
final class AccountManager: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var displayName = ""

    private let kUserID = "spellchain.account.userID"
    private let kName = "spellchain.account.name"

    private var userID: String {
        get { UserDefaults.standard.string(forKey: kUserID) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kUserID) }
    }

    init() {
        displayName = UserDefaults.standard.string(forKey: kName) ?? ""
        isSignedIn = !userID.isEmpty
        if isSignedIn { refreshCredentialState() }
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        userID = cred.user
        // Apple only returns fullName on the FIRST authorization; restore the cached name on re-auth.
        if displayName.isEmpty { displayName = UserDefaults.standard.string(forKey: kName) ?? "" }
        if let full = cred.fullName {
            let name = [full.givenName, full.familyName].compactMap { $0 }.joined(separator: " ")
            if !name.isEmpty {
                displayName = name
                UserDefaults.standard.set(name, forKey: kName)
            }
        }
        isSignedIn = true
        Haptics.success()
    }

    func signOut() {
        // Keep the cached name (kName) so a returning user re-displays correctly; the stable
        // userID is the identity/join key and is what we clear.
        UserDefaults.standard.removeObject(forKey: kUserID)
        isSignedIn = false
        Haptics.soft()
    }

    /// Full account deletion (App Review 5.1.1(v)): best-effort delete of the server-side paid
    /// record, then remove all local identity. The caller also wipes the user's local app data.
    func deleteAccount() {
        CloudSync.deletePaidStatus(userID: userID)
        UserDefaults.standard.removeObject(forKey: kUserID)
        UserDefaults.standard.removeObject(forKey: kName)
        displayName = ""; isSignedIn = false
        Haptics.success()
    }

    /// If the user revoked Apple ID access in Settings, sign out locally to stay consistent.
    func refreshCredentialState() {
        let id = userID
        guard !id.isEmpty else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: id) { [weak self] state, _ in
            guard state == .revoked || state == .notFound else { return }
            Task { @MainActor in self?.signOut() }
        }
    }
}
