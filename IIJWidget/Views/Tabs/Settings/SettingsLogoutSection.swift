import SwiftUI

struct SettingsLogoutSection: View {
    let performLogout: () throws -> Void
    @State private var showConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button(role: .destructive) {
                showConfirmation = true
            } label: {
                Label {
                    Text("ログアウト")
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity)
            }
        } footer: {
            Text("ログアウトするとキーチェーンの資格情報が削除され、次回起動時に再設定が必要です。")
                .font(.footnote)
        }
        .alert("保存済みの資格情報を削除してログアウトしますか?", isPresented: $showConfirmation) {
            Button("ログアウト", role: .destructive) {
                do {
                    try performLogout()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("ログアウトに失敗しました", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }
}
