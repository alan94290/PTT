import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("帳號") {
                    LabeledContent("目前登入", value: sessionVM.username ?? "-")
                }

                Section {
                    Button(role: .destructive) {
                        Task { await sessionVM.logout() }
                    } label: {
                        if sessionVM.isConnecting {
                            ProgressView()
                        } else {
                            Text("登出")
                        }
                    }
                }

                Section("關於") {
                    Text("此 App 透過 WebSocket 直接連線 ptt.cc，畫面上顯示的內容都是即時從 BBS 讀取、解析而來，並非另外儲存的資料庫。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SessionViewModel())
}
