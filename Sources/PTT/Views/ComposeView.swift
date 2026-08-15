import SwiftUI

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ComposeViewModel

    init(mode: ComposeMode) {
        _viewModel = StateObject(wrappedValue: ComposeViewModel(mode: mode))
    }

    var body: some View {
        Form {
            if viewModel.mode.needsTitle {
                Section("標題") {
                    TextField("標題", text: $viewModel.title)
                }
            }

            Section("內容") {
                TextEditor(text: $viewModel.body)
                    .frame(minHeight: 220)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(viewModel.mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text("送出")
                    }
                }
                .disabled(!viewModel.canSubmit || viewModel.isSubmitting)
            }
        }
        .onChange(of: viewModel.didSucceed) { succeeded in
            if succeeded { dismiss() }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
    }
}
