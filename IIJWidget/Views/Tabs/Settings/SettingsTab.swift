import SwiftUI

struct SettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    let focusedField: FocusState<CredentialsField?>.Binding
    @Binding var hasCompletedOnboarding: Bool
    let presentOnboarding: () -> Void
    @State private var showLogoutConfirmation = false
    @State private var logoutErrorMessage: String?
    @FocusState private var usageAlertFocused: Bool

    private var accentColor: Color {
        .accentColor
    }

    var body: some View {
        NavigationStack {
            Form {
            Section(header: Text("資格情報")) {
                CredentialsCard(viewModel: viewModel, focusedField: focusedField)
            }

            Section(header: Text("使いすぎアラート")) {
                Toggle(isOn: Binding(
                    get: { viewModel.usageAlertSettings.isEnabled },
                    set: { viewModel.updateUsageAlertSettings(viewModel.usageAlertSettings.updating(isEnabled: $0)) }
                )) {
                    Text("使いすぎアラートを有効にする")
                        .foregroundStyle(accentColor)
                }
                .tint(accentColor)

                if viewModel.usageAlertSettings.isEnabled {
                    Toggle(isOn: Binding(
                        get: { viewModel.usageAlertSettings.sendNotification },
                        set: { viewModel.updateUsageAlertSettings(viewModel.usageAlertSettings.updating(sendNotification: $0)) }
                    )) {
                        Text("通知を送信")
                            .foregroundStyle(accentColor)
                    }
                    .tint(accentColor)

                    HStack {
                        Text("今月に")
                            .foregroundStyle(accentColor)
                        TextField("1000", value: Binding(
                            get: { viewModel.usageAlertSettings.monthlyThresholdMB },
                            set: { viewModel.updateUsageAlertSettings(viewModel.usageAlertSettings.updating(monthlyThresholdMB: $0)) }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .focused($usageAlertFocused)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        Text("MB超えた時警告")
                            .foregroundStyle(accentColor)
                    }

                    HStack {
                        Text("当日に")
                            .foregroundStyle(accentColor)
                        TextField("100", value: Binding(
                            get: { viewModel.usageAlertSettings.dailyThresholdMB },
                            set: { viewModel.updateUsageAlertSettings(viewModel.usageAlertSettings.updating(dailyThresholdMB: $0)) }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .focused($usageAlertFocused)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        Text("MBを超えた時警告")
                            .foregroundStyle(accentColor)
                    }
                }
            }

            Section(header: Text("表示")) {
                AccentPalettePickerRow(
                    title: "月別グラフカラー",
                    selection: binding(for: .monthlyChart)
                )
                AccentPalettePickerRow(
                    title: "日別グラフカラー",
                    selection: binding(for: .dailyChart)
                )
                AccentPalettePickerRow(
                    title: "請求額グラフカラー",
                    selection: binding(for: .billingChart)
                )
                AccentPalettePickerRow(
                    title: "ウィジェット円カラー (通常)",
                    selection: binding(for: .widgetRingNormal)
                )
                AccentPalettePickerRow(
                    title: "ウィジェット円カラー (50%以下警告)",
                    selection: binding(for: .widgetRingWarning50)
                )
                AccentPalettePickerRow(
                    title: "ウィジェット円カラー (20%以下警告)",
                    selection: binding(for: .widgetRingWarning20)
                )
                AccentPalettePickerRow(
                    title: "使いすぎアラート警告カラー",
                    selection: binding(for: .usageAlertWarning)
                )
                Toggle(isOn: Binding(
                    get: { viewModel.displayPreferences.showsLowSpeedUsage },
                    set: { viewModel.updateShowsLowSpeedUsage($0) }
                )) {
                    Text("低速通信の通信量を表示")
                        .foregroundStyle(accentColor)
                }
                .toggleStyle(.switch)
                .tint(accentColor)
            }

            Section(header: Text("プロジェクト")) {
                if let repositoryURL {
                    Link(destination: repositoryURL) {
                        Label("GitHub リポジトリを開く", systemImage: "arrow.up.right.square")
                    }
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
            .navigationTitle("設定")
        .toolbar {
            if usageAlertFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        usageAlertFocused = false
                    }
                }
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

    private func binding(for role: AccentRole) -> Binding<AccentPalette> {
        Binding(
            get: { viewModel.accentColors.palette(for: role) },
            set: { viewModel.updateAccentColor(for: role, to: $0) }
        )
    }
}

private let repositoryURL = URL(string: "https://github.com/yyyywaiwai/IIJWidget")

private struct AccentPalettePickerRow: View {
    let title: String
    @Binding var selection: AccentPalette
    @State private var isPresenting = false

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                AccentPaletteSwatch(palette: selection)
                    .frame(width: 48)
                Text(selection.displayName)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isPresenting) {
            NavigationView {
                VStack {
                    Picker("", selection: $selection) {
                        ForEach(AccentPalette.allCases) { palette in
                            HStack(spacing: 10) {
                                AccentPaletteSwatch(palette: palette)
                                Text(palette.displayName)
                            }
                            .tag(palette)
                        }
                    }
                    .pickerStyle(.wheel)
                    .padding(.horizontal)
                }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { isPresenting = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct AccentPaletteSwatch: View {
    let palette: AccentPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: palette.chartGradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 32, height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

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
            IconTextField(
                systemImage: "person.fill",
                placeholder: "mioID / メールアドレス",
                text: $viewModel.mioId
            )
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused(focusedField, equals: .mioId)

            IconSecureField(
                systemImage: "lock.fill",
                placeholder: "パスワード",
                text: $viewModel.password
            )
            .focused(focusedField, equals: .password)

            if let status = viewModel.loginStatusText {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("入力した資格情報は端末のキーチェーンに暗号化して保存され、次回起動時に自動で入力されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                focusedField.wrappedValue = nil
                viewModel.refreshManually()
            } label: {
                Label("保存して取得", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canSubmit)
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
