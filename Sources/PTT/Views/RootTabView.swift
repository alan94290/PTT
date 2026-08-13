import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            BoardHomeView()
                .tabItem { Label("看板", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
