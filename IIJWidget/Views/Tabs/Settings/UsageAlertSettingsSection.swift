import SwiftUI

struct UsageAlertSettingsSection: View {
    @Binding var settings: UsageAlertSettings
    @State private var notificationPermission = NotificationPermissionModel()
    @FocusState private var focusedField: ThresholdField?
    @Environment(\.scenePhase) private var scenePhase

    private enum ThresholdField: Hashable {
        case monthly
        case daily
    }

    var body: some View {
        Section {
            Toggle("使いすぎアラートを有効にする", isOn: $settings.isEnabled)
                .tint(.accentColor)

            if settings.isEnabled {
                HStack {
                    Text("今月に")
                    TextField("1000", value: $settings.monthlyThresholdMB, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .monthly)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 72)
                    Text("MBを超えた時警告")
                }

                HStack {
                    Text("当日に")
                    TextField("100", value: $settings.dailyThresholdMB, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .daily)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 72)
                    Text("MBを超えた時警告")
                }

                NotificationPermissionRows(
                    status: notificationPermission.status,
                    errorMessage: notificationPermission.errorMessage,
                    isRequesting: notificationPermission.isRequesting,
                    requestPermission: requestNotificationPermission
                )
                Text("更新で超過を確認した時に通知します。回線ごとに日次・月次それぞれ1回。自動更新の時刻はiOSが決めます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("使いすぎアラート")
                InfoTipButton(
                    message: "設定したMBを超えるとグラフと一覧を強調表示します。通知を許可すると、アプリ・ウィジェット・ショートカットで更新した際に、当日・当月の超過を回線ごとに1回通知します。取得できた高速・低速の合計で判定し、欠測日は通知しません。",
                    accessibilityLabel: "使いすぎアラートのヒント"
                )
                Spacer(minLength: 0)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField != nil {
                    Spacer()
                    Button("完了") {
                        focusedField = nil
                    }
                }
            }
        }
        .onChange(of: settings.isEnabled) { _, isEnabled in
            if isEnabled {
                requestNotificationPermission()
            } else {
                focusedField = nil
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await notificationPermission.refreshStatus()
        }
    }

    private func requestNotificationPermission() {
        Task { await notificationPermission.requestPermissionIfNeeded() }
    }
}
