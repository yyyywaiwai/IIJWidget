import Foundation
import UserNotifications

/// Checks usage alerts and sends notifications when thresholds are exceeded
struct UsageAlertChecker {
    private let alertStore = UsageAlertStore()
    
    /// Check usage alerts and send notifications if thresholds are exceeded
    func checkUsageAlerts(payload: AggregatePayload) async {
        let settings = alertStore.load()
        guard settings.isEnabled, settings.sendNotification else {
            return
        }
        
        let center = UNUserNotificationCenter.current()
        
        // Check notification permission
        let notificationSettings = await center.notificationSettings()
        guard notificationSettings.authorizationStatus == .authorized else {
            return
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        let todayString = ISO8601DateFormatter().string(from: today).prefix(10)
        let calendar = Calendar.current
        let currentMonth = String(format: "%04d-%02d",
            calendar.component(.year, from: today),
            calendar.component(.month, from: today))
        
        // Get last notification dates from UserDefaults
        let defaults = AppGroup.userDefaults ?? .standard
        let lastMonthlyKey = "lastMonthlyAlertDate"
        let lastDailyKey = "lastDailyAlertDate"
        let lastMonthlyMonth = defaults.string(forKey: lastMonthlyKey)
        let lastDailyDate = defaults.string(forKey: lastDailyKey)
        
        // Check Monthly Usage
        await checkMonthlyUsage(
            payload: payload,
            threshold: settings.monthlyThresholdMB,
            currentMonth: currentMonth,
            currentMonthDate: today,
            lastAlertMonth: lastMonthlyMonth,
            defaults: defaults,
            center: center,
            key: lastMonthlyKey,
            calendar: calendar
        )
        
        // Check Daily Usage
        await checkDailyUsage(
            payload: payload,
            threshold: settings.dailyThresholdMB,
            todayString: String(todayString),
            lastAlertDate: lastDailyDate,
            defaults: defaults,
            center: center,
            key: lastDailyKey,
            today: today
        )
    }
    
    // MARK: - Private Helpers
    
    private func checkMonthlyUsage(
        payload: AggregatePayload,
        threshold: Int?,
        currentMonth: String,
        currentMonthDate: Date,
        lastAlertMonth: String?,
        defaults: UserDefaults,
        center: UNUserNotificationCenter,
        key: String,
        calendar: Calendar
    ) async {
        guard let threshold else { return }
        
        // Only send once per month
        guard lastAlertMonth != currentMonth else {
            return
        }
        
        let totalUsedGB = payload.monthlyUsage.reduce(0.0) { serviceSum, service in
            serviceSum + service.entries.reduce(0.0) { entrySum, entry in
                guard isSameMonth(as: currentMonthDate, label: entry.monthLabel, calendar: calendar) else { return entrySum }
                return entrySum + (entry.highSpeedGB ?? 0) + (entry.lowSpeedGB ?? 0)
            }
        }
        // 1GB=1000MB としてユーザ表示・閾値判定を合わせる
        let totalUsedMB = totalUsedGB * 1000
        

        
        if totalUsedMB > Double(threshold) {
            let content = UNMutableNotificationContent()
            content.title = "データ利用量アラート (今月)"
            let currentMBText = Int(totalUsedMB)
            content.body = "今月の利用量が設定した\(threshold)MBを超えました (現在: \(currentMBText)MB)"
            content.sound = .default
            
            // Use 1 second trigger to ensure notification appears in Notification Center
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "monthly_usage_alert_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
            try? await center.add(request)
            defaults.set(currentMonth, forKey: key)
        }
    }
    
    private func checkDailyUsage(
        payload: AggregatePayload,
        threshold: Int?,
        todayString: String,
        lastAlertDate: String?,
        defaults: UserDefaults,
        center: UNUserNotificationCenter,
        key: String,
        today: Date
    ) async {
        guard let threshold else { return }
        
        // Only send once per day
        guard lastAlertDate != todayString else {
            return
        }
        
        let calendar = Calendar.current
        let year = calendar.component(.year, from: today)
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        let todayDateString = "\(year)年\(month)月\(day)日"
        

        let totalUsedMB = payload.dailyUsage.reduce(0.0) { serviceSum, service in
            serviceSum + service.entries.filter { $0.dateLabel == todayDateString }.reduce(0.0) { entrySum, entry in
                entrySum + (entry.highSpeedMB ?? 0) + (entry.lowSpeedMB ?? 0)
            }
        }

        
        if totalUsedMB > Double(threshold) {
            let content = UNMutableNotificationContent()
            content.title = "データ利用量アラート (当日)"
            content.body = "当日の利用量が設定した\(threshold)MBを超えました (現在: \(Int(totalUsedMB))MB)"
            content.sound = .default
            
            // Use 1 second trigger to ensure notification appears in Notification Center
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "daily_usage_alert_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
            try? await center.add(request)
            defaults.set(todayString, forKey: key)
        }
    }
}

private func isSameMonth(as reference: Date, label: String, calendar: Calendar) -> Bool {
    guard let components = monthComponents(from: label, calendar: calendar),
          let month = components.month,
          let year = components.year else {
        return false
    }

    let refYear = calendar.component(.year, from: reference)
    let refMonth = calendar.component(.month, from: reference)
    return refYear == year && refMonth == month
}

private func monthComponents(from label: String, calendar: Calendar) -> DateComponents? {
    // 抽出できる数値のみを使って年/月を判定する
    let regex = try? NSRegularExpression(pattern: "\\d+")
    let nsString = label as NSString
    let matches = regex?.matches(in: label, range: NSRange(location: 0, length: nsString.length)) ?? []
    let segments = matches.compactMap { Int(nsString.substring(with: $0.range)) }

    var year: Int?
    var month: Int?

    if segments.count >= 2 {
        if let first = segments.first, first >= 1000 {
            year = first
            month = segments[1]
        } else if let last = segments.last, last >= 1000 {
            year = last
            month = segments.first
        }
    }

    if month == nil, let first = segments.first, first <= 12 {
        month = first
    }

    var components = DateComponents()
    components.year = year
    components.month = month
    // day は不要
    return (components.year != nil && components.month != nil) ? components : nil
}
