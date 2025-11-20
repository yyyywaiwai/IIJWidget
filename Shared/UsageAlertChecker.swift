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
            lastAlertMonth: lastMonthlyMonth,
            defaults: defaults,
            center: center,
            key: lastMonthlyKey
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
        lastAlertMonth: String?,
        defaults: UserDefaults,
        center: UNUserNotificationCenter,
        key: String
    ) async {
        guard let threshold else { return }
        
        // Only send once per month
        guard lastAlertMonth != currentMonth else {
            return
        }
        
        let totalUsedGB = payload.monthlyUsage.reduce(0.0) { serviceSum, service in
            serviceSum + service.entries.reduce(0.0) { entrySum, entry in
                entrySum + (entry.highSpeedGB ?? 0) + (entry.lowSpeedGB ?? 0)
            }
        }
        let totalUsedMB = totalUsedGB * 1024
        

        
        if totalUsedMB > Double(threshold) {
            let content = UNMutableNotificationContent()
            content.title = "データ利用量アラート (今月)"
            content.body = "今月の利用量が\(Int(totalUsedMB))MBを超えました (設定: \(threshold)MB)"
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
            content.body = "当日の利用量が\(Int(totalUsedMB))MBを超えました (設定: \(threshold)MB)"
            content.sound = .default
            
            // Use 1 second trigger to ensure notification appears in Notification Center
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "daily_usage_alert_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
            try? await center.add(request)
            defaults.set(todayString, forKey: key)
        }
    }
}
