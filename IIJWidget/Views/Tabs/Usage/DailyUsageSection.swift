import SwiftUI

struct DailyUsageSection: View {
    let services: [DailyUsageService]
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool
    let hidePhoneOnScreenshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(services) { service in
                DailyUsageServiceCard(
                    service: service,
                    accentColors: accentColors,
                    usageAlertSettings: usageAlertSettings,
                    showsLowSpeedUsage: showsLowSpeedUsage,
                    hidePhoneOnScreenshot: hidePhoneOnScreenshot
                )
            }
        }
    }
}

struct DailyUsageServiceCard: View {
    let service: DailyUsageService
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool
    let hidePhoneOnScreenshot: Bool

    var body: some View {
        UsageServiceCard(
            title: service.titlePrimary,
            detail: service.titleDetail,
            gradientColors: accentColors.palette(for: .dailyChart).chartGradient,
            hidePhoneOnScreenshot: hidePhoneOnScreenshot
        ) {
            VStack(spacing: 0) {
                ForEach(service.entries) { entry in
                    UsageEntryRow(
                        label: entry.dateLabel,
                        highSpeedText: entry.highSpeedText,
                        lowSpeedText: entry.lowSpeedText,
                        note: entry.note,
                        hasData: entry.hasData,
                        isAlert: isAlert(entry: entry),
                        showsLowSpeedUsage: showsLowSpeedUsage,
                        alertColor: alertColor,
                        isLast: entry.id == service.entries.last?.id
                    )
                }
            }
        }
    }

    private var alertColor: Color {
        accentColors.palette(for: .usageAlertWarning).previewSymbolColor
    }

    private func isAlert(entry: DailyUsageEntry) -> Bool {
        guard usageAlertSettings.isEnabled, let threshold = usageAlertSettings.dailyThresholdMB
        else {
            return false
        }
        let totalMB = (entry.highSpeedMB ?? 0) + (entry.lowSpeedMB ?? 0)
        return totalMB > Double(threshold)
    }
}
