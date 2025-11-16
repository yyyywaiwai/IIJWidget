import SwiftUI

struct SettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    let focusedField: FocusState<CredentialsField?>.Binding
    @Binding var hasCompletedOnboarding: Bool
    let presentOnboarding: () -> Void
    @State private var showLogoutConfirmation = false
    @State private var logoutErrorMessage: String?

    var body: some View {
        Form {
            Section(header: Text("資格情報")) {
                CredentialsCard(viewModel: viewModel, focusedField: focusedField)
            }

            Section(header: Text("データ取得")) {
                Button {
                    focusedField.wrappedValue = nil
                    viewModel.refreshManually()
                } label: {
                    Label("最新の残量を取得", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!viewModel.canSubmit)
            }

            Section(header: Text("プロジェクト")) {
                Link(destination: repositoryURL) {
                    Label("GitHub リポジトリを開く", systemImage: "arrow.up.right.square")
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("ログアウトするとキーチェーンの資格情報が削除され、次回起動時に再設定が必要です。")
                    .font(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .alert(
            "保存済みの資格情報を削除してログアウトしますか?",
            isPresented: $showLogoutConfirmation
        ) {
            Button("ログアウト", role: .destructive) {
                performLogout()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert(
            "ログアウトに失敗しました",
            isPresented: Binding(
                get: { logoutErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        logoutErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                logoutErrorMessage = nil
            }
        } message: {
            if let logoutErrorMessage {
                Text(logoutErrorMessage)
            }
        }
    }

    private func performLogout() {
        focusedField.wrappedValue = nil
        do {
            try viewModel.logout()
            hasCompletedOnboarding = false
            presentOnboarding()
        } catch {
            logoutErrorMessage = error.localizedDescription
        }
    }
}

private let repositoryURL = URL(string: "https://github.com/yyyywaiwai/IIJWidget")!

struct CredentialsCard: View {
    @ObservedObject var viewModel: AppViewModel
    let focusedField: FocusState<CredentialsField?>.Binding

    var body: some View {
        if viewModel.credentialFieldsHidden {
            Label("自動ログイン済み", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .font(.subheadline)

            if let status = viewModel.loginStatusText {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.revealCredentialFields()
            } label: {
                Label("資格情報を再設定", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
        } else {
            TextField("mioID / メールアドレス", text: $viewModel.mioId)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .focused(focusedField, equals: .mioId)

            SecureField("パスワード", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
                .focused(focusedField, equals: .password)

            if let status = viewModel.loginStatusText {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("入力した資格情報は端末のキーチェーンに暗号化して保存され、次回起動時に自動で入力されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
