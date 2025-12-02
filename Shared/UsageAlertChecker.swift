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
        let totalUsedMB = payload.dailyUsage.reduce(0.0) { serviceSum, service in
            serviceSum + service.entries.reduce(0.0) { entrySum, entry in
                guard isSameDay(as: today, label: entry.dateLabel, calendar: calendar) else { return entrySum }
                return entrySum + (entry.highSpeedMB ?? 0) + (entry.lowSpeedMB ?? 0)
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
    guard var components = dateComponents(from: label, calendar: calendar),
          let month = components.month else {
        return false
    }

    components.year = components.year ?? calendar.component(.year, from: reference)
    components.day = 1

    guard let entryDate = calendar.date(from: components) else { return false }
    return calendar.isDate(entryDate, equalTo: reference, toGranularity: .month)
}

private func isSameDay(as reference: Date, label: String, calendar: Calendar) -> Bool {
    guard var components = dateComponents(from: label, calendar: calendar),
          let month = components.month,
          let day = components.day else {
        return false
    }

    components.year = components.year ?? calendar.component(.year, from: reference)
    components.month = month
    components.day = day

    guard let entryDate = calendar.date(from: components) else { return false }
    return calendar.isDate(entryDate, inSameDayAs: reference)
}

private func dateComponents(from label: String, calendar: Calendar) -> DateComponents? {
    // ラベル内の数字だけを抽出して日付要素を推定する (例: "2024/12/02", "12月2日")
    let regex = try? NSRegularExpression(pattern: "\\d+")
    let nsString = label as NSString
    let matches = regex?.matches(in: label, range: NSRange(location: 0, length: nsString.length)) ?? []
    let segments = matches.compactMap { Int(nsString.substring(with: $0.range)) }

    guard !segments.isEmpty else { return nil }

    var year: Int?
    var month: Int?
    var day: Int?

    if segments.count >= 3 {
        if let first = segments.first, first >= 1000 {
            year = first
            month = segments[1]
            day = segments[2]
        } else if let last = segments.last, last >= 1000 {
            year = last
            month = segments.first
            day = segments[1]
        }
    }

    if segments.count >= 2 {
        if year == nil, segments.first ?? 0 >= 1000 {
            year = segments.first
            month = segments[1]
            day = segments.count >= 3 ? segments[2] : nil
        }
    }

    if month == nil {
        month = segments.first
    }
    if day == nil, segments.count >= 2 {
        day = segments[1]
    }

    guard let month, (1...12).contains(month) else { return nil }
    if let day, !(1...31).contains(day) {
        return nil
    }

    // 月の日数をカレンダーに合わせて簡易チェックする
    let referenceYear = year ?? calendar.component(.year, from: Date())
    if let day {
        var temp = DateComponents()
        temp.year = referenceYear
        temp.month = month
        if let date = calendar.date(from: temp),
           let validRange = calendar.range(of: .day, in: .month, for: date),
           !validRange.contains(day) {
            return nil
        }
    }

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return components
}
