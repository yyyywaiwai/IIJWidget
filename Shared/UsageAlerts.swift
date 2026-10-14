import CryptoKit
import Foundation

struct UsageAlertSettings: Codable, Equatable {
    var isEnabled: Bool
    var monthlyThresholdMB: Int?
    var dailyThresholdMB: Int?

    static let `default` = UsageAlertSettings(
        isEnabled: false,
        monthlyThresholdMB: nil,
        dailyThresholdMB: nil
    )

    var needsFreshMonthlyUsage: Bool {
        isEnabled && (monthlyThresholdMB ?? 0) > 0
    }

    func updating(
        isEnabled: Bool? = nil,
        monthlyThresholdMB: Int?? = nil,
        dailyThresholdMB: Int?? = nil
    ) -> UsageAlertSettings {
        var copy = self
        if let isEnabled { copy.isEnabled = isEnabled }
        if let monthlyThresholdMB { copy.monthlyThresholdMB = monthlyThresholdMB }
        if let dailyThresholdMB { copy.dailyThresholdMB = dailyThresholdMB }
        return copy
    }

    /// GB 単位の値がしきい値 (MB) を超えているか。
    /// 換算係数は Shared 内の他の処理と揃えて 1024 とする。
    func exceedsMonthlyThreshold(totalGB: Double, threshold: Int) -> Bool {
        (totalGB * 1024) > Double(threshold)
    }
}

struct UsageAlert: Equatable {
    let identifier: String
    let body: String
    let expiresAt: Date

    static func candidates(
        payload: AggregatePayload,
        freshDailyUsage: [DailyUsageService],
        settings: UsageAlertSettings,
        accountID: String,
        now: Date
    ) -> [UsageAlert] {
        guard settings.isEnabled, !accountID.isEmpty else { return [] }
        let calendar = UsageDateLabel.calendar
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let monthInterval = calendar.dateInterval(of: .month, for: now),
              let dayInterval = calendar.dateInterval(of: .day, for: now) else { return [] }
        let monthLabel = String(format: "%04d年%02d月", year, month)
        let dayLabel = String(format: "%04d年%02d月%02d日", year, month, day)
        var alerts: [UsageAlert] = []

        for (index, line) in payload.top.serviceInfoList.enumerated() {
            let suffix = line.phoneNo?.filter(\.isNumber).suffix(4) ?? ""
            let name = suffix.isEmpty ? "回線\(index + 1)" : "回線（末尾\(suffix)）"

            func append(threshold: Int?, values: [Double?], unit: Double,
                        period: String, interval: DateInterval, label: String) {
                let values = values.compactMap { $0 }
                guard let threshold, threshold > 0, !values.isEmpty,
                      values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return }
                let totalMB = values.reduce(0, +) * unit
                guard totalMB.isFinite, totalMB > Double(threshold) else { return }
                let key = [accountID, line.id, period, label]
                    .map { "\($0.utf8.count):\($0)" }.joined()
                let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                alerts.append(UsageAlert(
                    identifier: "usage-alert.\(digest)",
                    body: "\(name)の\(period)の使用量が\(threshold) MBを超えました。",
                    expiresAt: interval.end
                ))
            }

            // top-only更新で保持した月次キャッシュを新しい測定値として扱わない。
            if payload.historyFetchedAt == payload.fetchedAt,
               let entry = payload.monthlyUsage.first(where: { $0.lineID == line.id })?
                .entries.first(where: { $0.monthLabel == monthLabel && $0.hasData }) {
                append(threshold: settings.monthlyThresholdMB,
                       values: [entry.highSpeedGB, entry.lowSpeedGB], unit: 1024,
                       period: "今月", interval: monthInterval, label: monthLabel)
            }
            if let entry = freshDailyUsage.first(where: { $0.lineID == line.id })?
                .entries.first(where: { $0.dateLabel == dayLabel && $0.hasData }) {
                append(threshold: settings.dailyThresholdMB,
                       values: [entry.highSpeedMB, entry.lowSpeedMB], unit: 1,
                       period: "今日", interval: dayInterval, label: dayLabel)
            }
        }
        return alerts
    }
}

struct UsageAlertStore {
    private let key = "usageAlert.settings.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> UsageAlertSettings {
        let defaults = AppGroup.userDefaults ?? UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let decoded = try? decoder.decode(UsageAlertSettings.self, from: data) {
            return decoded
        }
        return .default
    }

    func save(_ settings: UsageAlertSettings) {
        let defaults = AppGroup.userDefaults ?? UserDefaults.standard

        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
