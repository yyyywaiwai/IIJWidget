import SwiftUI
import UserNotifications

struct NotificationPermissionRows: View {
    let status: UNAuthorizationStatus?
    let errorMessage: String?
    let isRequesting: Bool
    let requestPermission: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch status {
        case .authorized:
            Label("通知は許可されています", systemImage: "bell.badge")
        case .provisional:
            Label("通知センターに静かに通知します", systemImage: "bell")
        case .denied:
            Button("設定で通知を許可する") {
                guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                openURL(url)
            }
            Text("通知が許可されていないため、グラフと一覧の警告表示のみ有効です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .notDetermined:
            Button("通知を許可する", action: requestPermission)
                .disabled(isRequesting)
        default:
            Text("通知設定を確認中…")
                .foregroundStyle(.secondary)
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}
