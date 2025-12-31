import SwiftUI

private enum UsageAlertField: Hashable {
    case monthly
    case daily
}

struct SettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var hasCompletedOnboarding: Bool
    let presentOnboarding: () -> Void
    @State private var showLogoutConfirmation = false
    @State private var logoutErrorMessage: String?
    @FocusState private var usageAlertFocusedField: UsageAlertField?

    private var accentColor: Color {
        .accentColor
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("使いすぎアラート")
                    InfoTipButton(
                        message: usageAlertHintText,
                        accessibilityLabel: "使いすぎアラートのヒント"
                    )
                    Spacer(minLength: 0)
                }) {
                    Toggle(isOn: Binding(
                        get: { viewModel.usageAlertSettings.isEnabled },
                        set: { viewModel.updateUsageAlertSettings(viewModel.usageAlertSettings.updating(isEnabled: $0)) }
                    )) {
                        Text("使いすぎアラートを有効にする")
                            .foregroundStyle(accentColor)
                    }
                    .tint(accentColor)

                    if viewModel.usageAlertSettings.isEnabled {
                        HStack {
                            Text("今月に")
                                .foregroundStyle(accentColor)
                            TextField("1000", value: Binding(
                                get: { viewModel.usageAlertSettings.monthlyThresholdMB },
                                set: { viewModel.updateUsageAlertSettings(viewModel.usageAlertSettings.updating(monthlyThresholdMB: $0)) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .focused($usageAlertFocusedField, equals: .monthly)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            Text("MBを超えた時警告")
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
                            .focused($usageAlertFocusedField, equals: .daily)
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

                    Toggle(isOn: Binding(
                        get: { viewModel.displayPreferences.showsBillingChart },
                        set: { viewModel.updateShowsBillingChart($0) }
                    )) {
                        Text("請求タブのグラフを表示")
                            .foregroundStyle(accentColor)
                    }
                    .toggleStyle(.switch)
                    .tint(accentColor)

                    Toggle(isOn: Binding(
                        get: { viewModel.displayPreferences.calculateTodayFromRemaining },
                        set: { viewModel.updateCalculateTodayFromRemaining($0) }
                    )) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("当日利用量をデータ残量から計算する")
                                .foregroundStyle(accentColor)
                            InfoTipButton(
                                message: calculateTodayHintText,
                                accessibilityLabel: "当日利用量計算のヒント"
                            )
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(accentColor)

                    Toggle(isOn: Binding(
                        get: { viewModel.displayPreferences.hidePhoneOnScreenshot },
                        set: { viewModel.updateHidePhoneOnScreenshot($0) }
                    )) {
                        Text("スクショ時に電話番号を隠す")
                            .foregroundStyle(accentColor)
                    }
                    .toggleStyle(.switch)
                    .tint(accentColor)
                }

                Section(header: Text("プロジェクト")) {
                    if let repositoryURL {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Link(destination: repositoryURL) {
                                Label("GitHub リポジトリを開く", systemImage: "arrow.up.right.square")
                            }
                            InfoTipButton(
                                message: repositoryHintText,
                                accessibilityLabel: "GitHub リポジトリのヒント"
                            )
                            Spacer(minLength: 0)
                        }
                    }
                }

                debugSection

                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
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
            }
            .navigationTitle("設定")
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if usageAlertFocusedField != nil {
                    HStack {
                        Spacer()
                        Button("完了") {
                            usageAlertFocusedField = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.clear)
                }
            }
        }
        .onChange(of: viewModel.usageAlertSettings.isEnabled) { isEnabled in
            if !isEnabled {
                usageAlertFocusedField = nil
            }
        }
    }

    private func performLogout() {
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

private extension SettingsTab {
    @ViewBuilder
    var debugSection: some View {
        Section(header: Text("デバッグ"), footer: debugFooter) {
            NavigationLink {
                DebugToolsView()
            } label: {
                DebugHintRow(
                    title: "キャッシュ・レスポンス確認",
                    systemImage: "ladybug",
                    hintText: debugResponseHintText,
                    hintAccessibilityLabel: "キャッシュ・レスポンス確認のヒント",
                    accentColor: accentColor
                )
            }

            NavigationLink {
                RefreshLogView()
            } label: {
                DebugHintRow(
                    title: "リフレッシュログを確認",
                    systemImage: "doc.text.magnifyingglass",
                    hintText: refreshLogHintText,
                    hintAccessibilityLabel: "リフレッシュログのヒント",
                    accentColor: accentColor
                )
            }
        }
    }

    var debugFooter: some View {
        Text("作者から調査依頼があった時のみ使用してください。")
            .font(.footnote)
    }
}

private let repositoryURL = URL(string: "https://github.com/yyyywaiwai/IIJWidget")

private struct AccentPalettePickerRow: View {
    let title: String
    @Binding var selection: AccentPalette
    @State private var isPresenting = false
    @ScaledMetric(relativeTo: .subheadline) private var paletteInfoWidth: CGFloat = 150

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    AccentPaletteSwatch(palette: selection)
                        .frame(width: 48)
                    Text(selection.displayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(width: paletteInfoWidth, alignment: .leading)
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

private struct InfoTipButton: View {
    let message: String
    let accessibilityLabel: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isPresented) {
            InfoTipPopover(text: message)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("ヒントを表示")
    }
}

private struct DebugHintRow: View {
    let title: String
    let systemImage: String
    let hintText: String
    let hintAccessibilityLabel: String
    let accentColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(accentColor)
            InfoTipButton(
                message: hintText,
                accessibilityLabel: hintAccessibilityLabel
            )
            Spacer(minLength: 0)
        }
    }
}

private struct InfoTipPopover: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private let usageAlertHintText = "設定したMBを超えると、月別/日別のグラフと一覧が警告色で強調表示されます。"
private let calculateTodayHintText = "ONにすると日別の取得は30日表のみとなり、当日分はデータ残量の差分から補完します。"
private let repositoryHintText = "このアプリはオープンソースです。MITライセンスの規約に従って自由にコードを利用できます"
private let debugResponseHintText = "直近のAPIレスポンスをキャッシュから確認できます。"
private let refreshLogHintText = "更新の実行履歴と結果を確認できます。"
