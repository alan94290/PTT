import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel

    @State private var accountID = ""
    @State private var password = ""
    @State private var remember = false
    @State private var kickOtherSessions = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("PTT 批踢踢實業坊")
                            .font(.title2.bold())
                        Text("透過加密的 WebSocket 連線直連 ptt.cc，以你的 PTT 帳號登入")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section("帳號") {
                    TextField("代號 (ID)", text: $accountID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密碼", text: $password)
                    Toggle("記住密碼（存於 Keychain）", isOn: $remember)
                    Toggle("自動踢掉其他重複登入", isOn: $kickOtherSessions)
                }

                if let error = sessionVM.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await sessionVM.login(id: accountID, password: password, kickOtherSessions: kickOtherSessions, remember: remember)
                        }
                    } label: {
                        if sessionVM.isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("登入")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(accountID.isEmpty || password.isEmpty || sessionVM.isConnecting)

                    Button("以 guest 訪客身分瀏覽") {
                        Task {
                            await sessionVM.login(id: "guest", password: "", kickOtherSessions: false, remember: false)
                        }
                    }
                    .disabled(sessionVM.isConnecting)
                }
            }
            .navigationTitle("登入")
            .onAppear {
                accountID = sessionVM.savedAccountID
                if let saved = sessionVM.savedPassword {
                    password = saved
                    remember = true
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(SessionViewModel())
}
