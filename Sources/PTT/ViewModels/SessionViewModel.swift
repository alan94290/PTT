import Foundation

@MainActor
final class SessionViewModel: ObservableObject {
    let session = PTTSession.shared

    @Published var isConnecting = false
    @Published var isLoggedIn = false
    @Published var username: String?
    @Published var errorMessage: String?

    @Published var savedAccountID: String = UserDefaults.standard.string(forKey: "ptt.lastAccount") ?? ""
    @Published var rememberPassword: Bool = UserDefaults.standard.bool(forKey: "ptt.rememberPassword")

    var savedPassword: String? {
        guard rememberPassword, !savedAccountID.isEmpty else { return nil }
        return KeychainStore.loadPassword(for: savedAccountID)
    }

    func login(id: String, password: String, kickOtherSessions: Bool = true, remember: Bool) async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            if !(await session.isConnected) {
                try await session.connect()
            }
            try await session.login(id: id, password: password, kickOtherSessions: kickOtherSessions)
            isLoggedIn = true
            username = id

            savedAccountID = id
            UserDefaults.standard.set(id, forKey: "ptt.lastAccount")
            rememberPassword = remember
            UserDefaults.standard.set(remember, forKey: "ptt.rememberPassword")
            if remember {
                KeychainStore.savePassword(password, for: id)
            } else {
                KeychainStore.deletePassword(for: id)
            }
        } catch {
            errorMessage = error.localizedDescription
            await session.disconnect()
        }
    }

    func logout() async {
        isConnecting = true
        defer { isConnecting = false }
        try? await session.logout()
        isLoggedIn = false
        username = nil
    }
}
