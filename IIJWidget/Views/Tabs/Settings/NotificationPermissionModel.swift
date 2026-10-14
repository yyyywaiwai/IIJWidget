import Observation
import UserNotifications

/// Keeps notification authorization state and its asynchronous lifecycle out of the form.
@Observable
@MainActor
final class NotificationPermissionModel {
    private(set) var status: UNAuthorizationStatus?
    private(set) var errorMessage: String?
    private(set) var isRequesting = false

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func refreshStatus() async {
        status = await notificationCenter.notificationSettings().authorizationStatus
    }

    func requestPermissionIfNeeded() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        errorMessage = nil

        do {
            if await notificationCenter.notificationSettings().authorizationStatus == .notDetermined {
                _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            }
        } catch {
            errorMessage = "通知の許可を確認できませんでした。再度お試しください。"
        }
        await refreshStatus()
    }
}
