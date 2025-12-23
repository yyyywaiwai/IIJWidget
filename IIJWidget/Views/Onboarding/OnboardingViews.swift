import SwiftUI

struct OnboardingFlowView: View {
    enum Step: Int, CaseIterable {
        case disclaimer = 0
        case credentials = 1
        
        var next: Step? {
            Step(rawValue: self.rawValue + 1)
        }
        
        var prev: Step? {
            Step(rawValue: self.rawValue - 1)
        }
    }

    @ObservedObject var viewModel: AppViewModel
    let onFinish: () -> Void

    @State private var step: Step = .disclaimer
    @Namespace private var animation

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    if step != .disclaimer {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if let prev = step.prev { step = prev }
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Color.clear.frame(width: 36, height: 36)
                    }
                    
                    Spacer()
                    
                    // Progress Indicator
                    HStack(spacing: 6) {
                        ForEach(Step.allCases, id: \.self) { item in
                            Capsule()
                                .fill(step == item ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: step == item ? 20 : 6, height: 6)
                        }
                    }
                    
                    Spacer()
                    
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                TabView(selection: $step) {
                    OnboardingDisclaimerStep {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if let next = step.next { step = next }
                        }
                    }
                    .tag(Step.disclaimer)

                    OnboardingCredentialSetupStep(viewModel: viewModel) {
                        onFinish()
                    }
                    .tag(Step.credentials)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .scrollDisabled(true)
            }
        }
    }
}

struct OnboardingHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 70, height: 70)
                
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 12)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 24)
    }
}

struct OnboardingDisclaimerStep: View {
    let onAgree: () -> Void
    @State private var appearItems = false

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
                iconColor: .orange,
                title: "非公式アプリ",
                detail: "IIJmio公式のアプリではありません。開発者個人によるプロジェクトです。"
            ),
            Highlight(
                icon: "lock.shield.fill",
                iconColor: .green,
                title: "プライバシー保護",
                detail: "パスワードは端末のキーチェーンにのみ保存され、外部送信されません。"
            ),
            Highlight(
                icon: "hand.raised.fill",
                iconColor: .blue,
                title: "自己責任での利用",
                detail: "アプリの使用に伴うトラブル等について、一切の責任を負いかねます。"
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    OnboardingHeader(
                        title: "ご利用前のご確認",
                        subtitle: "IIJWidgetを安全にご利用いただくために、以下の内容をご確認ください。",
                        systemImage: "checklist.checked"
                    )

                    VStack(spacing: 12) {
                        ForEach(Array(highlights.enumerated()), id: \.offset) { index, highlight in
                            HStack(alignment: .top, spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(highlight.iconColor.opacity(0.1))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: highlight.icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(highlight.iconColor)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(highlight.title)
                                        .font(.system(.headline, design: .rounded))
                                    Text(highlight.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineSpacing(2)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .offset(y: appearItems ? 0 : 15)
                            .opacity(appearItems ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.08), value: appearItems)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            VStack(spacing: 16) {
                Text("上記の内容に同意し、アプリを開始します。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    onAgree()
                } label: {
                    Text("同意して次へ")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.accentColor.opacity(0.2), radius: 8, y: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .onAppear {
            appearItems = true
        }
    }
}

struct OnboardingCredentialSetupStep: View {
    @ObservedObject var viewModel: AppViewModel
    let onFinish: () -> Void

    @FocusState private var field: Field?
    @State private var isSubmitting = false
    @State private var loginErrorMessage: String?
    @State private var isShowingDebugTools = false

    private enum Field: Hashable {
        case mioId
        case password
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    OnboardingHeader(
                        title: "ログイン設定",
                        subtitle: "IIJmioのmioID（またはメールアドレス）とパスワードを入力してください。",
                        systemImage: "person.badge.key.fill"
                    )

                    VStack(spacing: 16) {
                        VStack(spacing: 1) {
                            ModernTextField(
                                systemImage: "person.fill",
                                placeholder: "mioID / メールアドレス",
                                text: $viewModel.mioId,
                                isFocused: field == .mioId
                            )
                            .focused($field, equals: .mioId)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            Divider().padding(.leading, 44)

                            ModernSecureField(
                                systemImage: "lock.fill",
                                placeholder: "パスワード",
                                text: $viewModel.password,
                                isFocused: field == .password
                            )
                            .focused($field, equals: .password)
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        if let loginErrorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text(loginErrorMessage)
                                }
                                .font(.caption)
                                .foregroundStyle(.red)

                                Button {
                                    isShowingDebugTools = true
                                } label: {
                                    Label("キャッシュ・レスポンス確認", systemImage: "ladybug")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.accentColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                        
                        Text("入力された資格情報は、デバイス内にのみ安全に保管されます。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                }
            }

            VStack(spacing: 0) {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 8)
                        }
                        Text(isSubmitting ? "認証中..." : "保存して利用開始")
                            .font(.system(.headline, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(viewModel.canSubmit ? Color.accentColor : Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: viewModel.canSubmit ? Color.accentColor.opacity(0.2) : .clear, radius: 8, y: 4)
                }
                .disabled(isSubmitting || !viewModel.canSubmit)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .sheet(isPresented: $isShowingDebugTools) {
            NavigationStack {
                DebugToolsView()
            }
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
                loginErrorMessage = "ログインに失敗しました。IDとパスワードを確認してください。"
            }
        }
    }
}

private struct ModernTextField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isFocused ? Color.accentColor.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

private struct ModernSecureField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                .frame(width: 24)
            
            SecureField(placeholder, text: $text)
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isFocused ? Color.accentColor.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
