import SwiftUI

struct DisplaySettingsSection: View {
    let accentColors: AccentColorSettings
    let updateAccentColor: (AccentRole, AccentPalette) -> Void
    @Binding var showsLowSpeedUsage: Bool
    @Binding var showsBillingChart: Bool
    @Binding var hidePhoneOnScreenshot: Bool

    var body: some View {
        Section("表示") {
            ForEach(AccentRole.allCases, id: \.self) { role in
                AccentPalettePickerRow(
                    title: role.settingsTitle,
                    selection: Binding(
                        get: { accentColors.palette(for: role) },
                        set: { updateAccentColor(role, $0) }
                    )
                )
            }

            Toggle("低速通信の通信量を表示", isOn: $showsLowSpeedUsage)
            Toggle("請求タブのグラフを表示", isOn: $showsBillingChart)
            Toggle("スクショ時に電話番号を隠す", isOn: $hidePhoneOnScreenshot)
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
    }
}

private extension AccentRole {
    var settingsTitle: String {
        switch self {
        case .monthlyChart: "月別グラフカラー"
        case .dailyChart: "日別グラフカラー"
        case .billingChart: "請求額グラフカラー"
        case .widgetRingNormal: "ウィジェット円カラー (通常)"
        case .widgetRingWarning50: "ウィジェット円カラー (50%以下警告)"
        case .widgetRingWarning20: "ウィジェット円カラー (20%以下警告)"
        case .usageAlertWarning: "使いすぎアラート警告カラー"
        }
    }
}
