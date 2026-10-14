import SwiftUI

struct MonthlyUsageSection: View {
    let services: [MonthlyUsageService]
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool
    let hidePhoneOnScreenshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(services) { service in
                MonthlyUsageServiceCard(
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

struct MonthlyUsageServiceCard: View {
    let service: MonthlyUsageService
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool
    let hidePhoneOnScreenshot: Bool

    var body: some View {
        UsageServiceCard(
            title: service.titlePrimary,
            detail: service.titleDetail,
            gradientColors: accentColors.palette(for: .monthlyChart).chartGradient,
            hidePhoneOnScreenshot: hidePhoneOnScreenshot
        ) {
            VStack(spacing: 0) {
                ForEach(service.entries) { entry in
                    UsageEntryRow(
                        label: entry.monthLabel,
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

    private func isAlert(entry: MonthlyUsageEntry) -> Bool {
        guard usageAlertSettings.isEnabled, let threshold = usageAlertSettings.monthlyThresholdMB
        else {
            return false
        }
        let totalGB = (entry.highSpeedGB ?? 0) + (entry.lowSpeedGB ?? 0)
        return usageAlertSettings.exceedsMonthlyThreshold(totalGB: totalGB, threshold: threshold)
    }
}
