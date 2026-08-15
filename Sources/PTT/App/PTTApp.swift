import SwiftUI

@main
struct PTTApp: App {
    @StateObject private var sessionVM = SessionViewModel()
    @StateObject private var bookmarkStore = BookmarkStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionVM)
                .environmentObject(bookmarkStore)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel

    var body: some View {
        Group {
            if sessionVM.isLoggedIn {
                RootTabView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: sessionVM.isLoggedIn)
    }
}
