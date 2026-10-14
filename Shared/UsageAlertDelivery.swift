import Darwin
import Foundation
import UserNotifications

struct UsageAlertDelivery {
    let directory: URL

    func deliver(_ alerts: [UsageAlert], now: Date,
                 send: (UsageAlert) async throws -> Void) async throws {
        guard !alerts.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = open(directory.appendingPathComponent("usage-alert.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw POSIXError(.EIO) }
        defer { close(lock) }
        // アプリとWidgetは別プロセスなので、actorだけでは二重配送を防げない。
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            // shortcut: 並行判定中は先行処理を優先。未通知分は次回更新で再判定する。
            if errno == EWOULDBLOCK { return }
            throw POSIXError(.EIO)
        }
        defer { flock(lock, LOCK_UN) }

        let url = directory.appendingPathComponent("usage-alert-delivery.json")
        var delivered: [String: Date]
        do {
            delivered = try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            delivered = [:]
        }
        delivered = delivered.filter { $0.value > now }
        for alert in alerts where alert.expiresAt > now && delivered[alert.identifier] == nil {
            try Task.checkCancellation()
            try await send(alert)
            delivered[alert.identifier] = alert.expiresAt
            // shortcut: 登録直後のプロセス終了では再通知の余地がある。厳密な一度限り配送が必要ならOSと再照合する。
            try JSONEncoder().encode(delivered).write(to: url, options: .atomic)
        }
    }
}

#if os(iOS)
@MainActor
enum UsageAlertNotifier {
    static func notify(payload: AggregatePayload, freshDailyUsage: [DailyUsageService],
                       accountID: String) async {
        let settings = UsageAlertStore().load()
        let alerts = UsageAlert.candidates(payload: payload, freshDailyUsage: freshDailyUsage,
                                          settings: settings, accountID: accountID, now: Date())
        guard !alerts.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else { return }
        do {
            guard let directory = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroup.identifier
            ) else { throw CocoaError(.fileNoSuchFile) }
            try await UsageAlertDelivery(directory: directory).deliver(alerts, now: Date()) { alert in
                // 許可確認などのawait中にOFF・ログアウト・アカウント変更された場合は送らない。
                guard UsageAlertStore().load() == settings,
                      try MyIIJmioTokenStore().load()?.mioId == accountID else { throw CancellationError() }
                let content = UNMutableNotificationContent()
                content.title = "使いすぎアラート"
                content.body = alert.body
                content.sound = .default
                try await center.add(UNNotificationRequest(identifier: alert.identifier,
                                                            content: content, trigger: nil))
            }
        } catch is CancellationError {
            return
        } catch {
            RefreshLogStore().append(trigger: .usageAlert, result: .failure,
                                     errorDescription: "データ更新は成功しましたが、通知の登録に失敗しました: \(error.localizedDescription)")
        }
    }
}
#endif
