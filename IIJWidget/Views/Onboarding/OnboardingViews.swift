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
                    TextField("mioID / メールアドレス", text: $viewModel.mioId)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .focused($field, equals: .mioId)

                    SecureField("パスワード", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .focused($field, equals: .password)

                    Text("入力内容は端末キーチェーンに暗号化して保存され、ウィジェット更新時にのみ使用されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 12) {
                    Button {
                        field = nil
                        viewModel.refreshManually()
                        onFinish()
                    } label: {
                        Label("今すぐログインして残量取得", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSubmit)
                }

                Text("ログインを行うと再度この画面は表示されませんが、設定タブからいつでも資格情報を更新できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

