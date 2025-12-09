import SwiftUI

struct OnboardingFlowView: View {
    enum Step {
        case disclaimer
        case credentials
    }

    @ObservedObject var viewModel: AppViewModel
    let onFinish: () -> Void

    @State private var step: Step = .disclaimer

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .disclaimer:
                    OnboardingDisclaimerStep {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            step = .credentials
                        }
                    }
                case .credentials:
                    OnboardingCredentialSetupStep(viewModel: viewModel) {
                        onFinish()
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == .credentials {
                        Button("戻る") {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                step = .disclaimer
                            }
                        }
                    }
                }
            }
            .navigationTitle(step == .disclaimer ? "ご利用前のお願い" : "ログイン設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct OnboardingDisclaimerStep: View {
    let onAgree: () -> Void

    private struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let detail: String
    }

    private var highlights: [Highlight] {
        [
            Highlight(
                icon: "exclamationmark.triangle.fill",
                iconColor: .pink,
                title: "非公式アプリ",
                detail: "IIJWidgetは個人プロジェクトであり、公式サポートや補償の対象ではありません。"
            ),
            Highlight(
                icon: "lock.shield.fill",
                iconColor: .blue,
                title: "資格情報の扱い",
                detail: "入力内容は端末キーチェーンにのみ暗号化保存され、サードパーティのサーバーへ送信しません。"
            ),
            Highlight(
                icon: "hand.raised.fill",
                iconColor: .orange,
                title: "自己責任での利用",
                detail: "アカウント停止などのリスクを理解した上で、自己責任でご利用ください。"
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ご利用前の確認")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("IIJWidgetを使う前に、以下のポイントをご確認ください。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 16) {
                    ForEach(highlights) { highlight in
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(highlight.iconColor.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: highlight.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(highlight.iconColor)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(highlight.title)
                                    .font(.headline)
                                Text(highlight.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }

                Text("上記に同意できない場合はアプリを終了してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onAgree()
                } label: {
                    Text("同意して続行")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct OnboardingCredentialSetupStep: View {
    @ObservedObject var viewModel: AppViewModel
    let onFinish: () -> Void

    @FocusState private var field: Field?
    @State private var isSubmitting = false
    @State private var loginErrorMessage: String?

    private enum Field: Hashable {
        case mioId
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ログイン情報を設定")
                        .font(.title.bold())
                    Text("IIJmioアカウントの資格情報を入力してください。保存後は設定タブまたは右上の更新ボタンから残量取得を実行できます。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    IconTextField(
                        systemImage: "person.fill",
                        placeholder: "mioID / メールアドレス",
                        text: $viewModel.mioId
                    )
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($field, equals: .mioId)

                    IconSecureField(
                        systemImage: "lock.fill",
                        placeholder: "パスワード",
                        text: $viewModel.password
                    )
                    .focused($field, equals: .password)

                    Text("入力内容は端末キーチェーンに暗号化して保存され、ウィジェット更新時にのみ使用されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 12) {
                    if let loginErrorMessage {
                        Text(loginErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Label("保存して取得", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSubmitting || !viewModel.canSubmit)
                }

                Text("ログインを行うと再度この画面は表示されませんが、設定タブからいつでも資格情報を更新できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func submit() async {
        await MainActor.run {
            field = nil
            loginErrorMessage = nil
            isSubmitting = true
        }

        let result = await viewModel.refresh(trigger: .manual)

        await MainActor.run {
            isSubmitting = false
            switch result {
            case .success:
                onFinish()
            case .failure(let error):
                loginErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct IconTextField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct IconSecureField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
