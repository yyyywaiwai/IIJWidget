import SwiftUI

struct UsageListTab: View {
    let monthly: [MonthlyUsageService]
    let daily: [DailyUsageService]
    let serviceStatus: ServiceStatusResponse?
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool
    let hidePhoneOnScreenshot: Bool

    @State private var selectedTab: UsageTab = .monthly
    @State private var isStatusExpanded = false

    fileprivate enum UsageTab: String, CaseIterable {
        case monthly
        case daily

        var title: String {
            switch self {
            case .monthly: return "月別"
            case .daily: return "日別"
            }
        }

        var icon: String {
            switch self {
            case .monthly: return "calendar"
            case .daily: return "clock"
            }
        }

        var accentRole: AccentRole {
            switch self {
            case .monthly: return .monthlyChart
            case .daily: return .dailyChart
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            UsageTabSwitcher(selectedTab: $selectedTab, accentColors: accentColors)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)

            TabView(selection: $selectedTab) {
                usagePage {
                    monthlyContent
                }
                .tag(UsageTab.monthly)

                usagePage {
                    dailyContent
                }
                .tag(UsageTab.daily)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func usagePage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                content()
                serviceStatusSection
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
    }

    private var monthlyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if monthly.isEmpty {
                EmptyUsageRow(text: "まだ月別データがありません", icon: "calendar.badge.clock")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                MonthlyUsageSection(
                    services: monthly,
                    accentColors: accentColors,
                    usageAlertSettings: usageAlertSettings,
                    showsLowSpeedUsage: showsLowSpeedUsage,
                    hidePhoneOnScreenshot: hidePhoneOnScreenshot
                )
            }
        }
    }

    private var dailyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if daily.isEmpty {
                EmptyUsageRow(text: "まだ日別データがありません", icon: "clock.badge.questionmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                DailyUsageSection(
                    services: daily,
                    accentColors: accentColors,
                    usageAlertSettings: usageAlertSettings,
                    showsLowSpeedUsage: showsLowSpeedUsage,
                    hidePhoneOnScreenshot: hidePhoneOnScreenshot
                )
            }
        }
    }

    @ViewBuilder
    private var serviceStatusSection: some View {
        if let serviceStatus {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup(isExpanded: $isStatusExpanded) {
                    ServiceStatusList(status: serviceStatus)
                        .padding(.top, 8)
                } label: {
                    SectionHeaderLabel(
                        title: "回線ステータス",
                        icon: "dot.radiowaves.left.and.right",
                        gradientColors: [Color(red: 0.16, green: 0.56, blue: 0.35), Color(red: 0.39, green: 0.77, blue: 0.48)]
                    )
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

private struct UsageTabSwitcher: View {
    @Binding var selectedTab: UsageListTab.UsageTab
    let accentColors: AccentColorSettings

    var body: some View {
        HStack(spacing: 0) {
            ForEach(UsageListTab.UsageTab.allCases, id: \.self) { tab in
                let gradientColors = accentColors.palette(for: tab.accentRole).chartGradient
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(tab.title)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(
                                    color: gradientColors.first?.opacity(0.4) ?? .clear,
                                    radius: 8,
                                    x: 0,
                                    y: 4
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private struct SectionHeaderLabel: View {
    let title: String
    let icon: String
    let gradientColors: [Color]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
        }
    }
}

private struct EmptyUsageRow: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }
}

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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let gradientColors = accentColors.palette(for: .monthlyChart).chartGradient
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "simcard.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(service.titlePrimary)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
            }
            if let detail = service.titleDetail {
                ScreenshotProtectedText(
                    detail,
                    font: .caption,
                    foregroundStyle: .secondary,
                    isProtected: hidePhoneOnScreenshot
                )
            }

            VStack(spacing: 0) {
                ForEach(Array(service.entries.enumerated()), id: \.element.id) { index, entry in
                    UsageEntryRow(
                        label: entry.monthLabel,
                        highSpeedText: entry.highSpeedText,
                        lowSpeedText: entry.lowSpeedText,
                        note: entry.note,
                        hasData: entry.hasData,
                        isAlert: isAlert(entry: entry),
                        showsLowSpeedUsage: showsLowSpeedUsage,
                        isLast: index == service.entries.count - 1
                    )
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    gradientColors.first?.opacity(0.3) ?? .clear,
                                    gradientColors.last?.opacity(0.1) ?? .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
    }

    private func isAlert(entry: MonthlyUsageEntry) -> Bool {
        guard usageAlertSettings.isEnabled, let threshold = usageAlertSettings.monthlyThresholdMB else { return false }
        let totalGB = (entry.highSpeedGB ?? 0) + (entry.lowSpeedGB ?? 0)
        return (totalGB * 1024) > Double(threshold)
    }
}

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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let gradientColors = accentColors.palette(for: .dailyChart).chartGradient
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "simcard.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(service.titlePrimary)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
            }
            if let detail = service.titleDetail {
                ScreenshotProtectedText(
                    detail,
                    font: .caption,
                    foregroundStyle: .secondary,
                    isProtected: hidePhoneOnScreenshot
                )
            }

            VStack(spacing: 0) {
                ForEach(Array(service.entries.enumerated()), id: \.element.id) { index, entry in
                    UsageEntryRow(
                        label: entry.dateLabel,
                        highSpeedText: entry.highSpeedText,
                        lowSpeedText: entry.lowSpeedText,
                        note: entry.note,
                        hasData: entry.hasData,
                        isAlert: isAlert(entry: entry),
                        showsLowSpeedUsage: showsLowSpeedUsage,
                        isLast: index == service.entries.count - 1
                    )
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    gradientColors.first?.opacity(0.3) ?? .clear,
                                    gradientColors.last?.opacity(0.1) ?? .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
    }

    private func isAlert(entry: DailyUsageEntry) -> Bool {
        guard usageAlertSettings.isEnabled, let threshold = usageAlertSettings.dailyThresholdMB else { return false }
        let totalMB = (entry.highSpeedMB ?? 0) + (entry.lowSpeedMB ?? 0)
        return totalMB > Double(threshold)
    }
}

private struct UsageEntryRow: View {
    let label: String
    let highSpeedText: String?
    let lowSpeedText: String?
    let note: String?
    let hasData: Bool
    let isAlert: Bool
    let showsLowSpeedUsage: Bool
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(label)
                    .font(.system(.callout, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if hasData {
                    UsageBreakdownView(
                        highSpeedText: highSpeedText,
                        lowSpeedText: lowSpeedText,
                        isAlert: isAlert,
                        showsLowSpeedUsage: showsLowSpeedUsage
                    )
                } else if let note {
                    Text(note)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)

            if !isLast {
                Divider()
                    .opacity(0.5)
            }
        }
    }
}

private struct UsageBreakdownView: View {
    let highSpeedText: String?
    let lowSpeedText: String?
    let isAlert: Bool
    let showsLowSpeedUsage: Bool

    var body: some View {
        if showsLowSpeedUsage {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                    Text(highSpeedText ?? "-")
                }
                HStack(spacing: 4) {
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 9))
                    Text(lowSpeedText ?? "-")
                }
            }
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(isAlert ? .orange : .secondary)
        } else {
            Text(highSpeedText ?? "-")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isAlert ? .orange : .primary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("高速通信の利用量")
                .accessibilityValue(highSpeedText ?? "-")
        }
    }
}

struct ServiceStatusList: View {
    let status: ServiceStatusResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(status.serviceInfoList) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(item.serviceCodePrefix ?? "-")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(item.planCode ?? "-")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let simList = item.simInfoList {
                        HStack(spacing: 8) {
                            ForEach(simList) { sim in
                                HStack(spacing: 4) {
                                    Image(systemName: sim.status == "O" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text(sim.simType ?? "?")
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                }
                                .foregroundStyle(sim.status == "O" ? .green : .orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill((sim.status == "O" ? Color.green : Color.orange).opacity(0.12))
                                )
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                }
            }
        }
    }
}
