import SwiftUI

struct UsageListTab: View {
    let monthly: [MonthlyUsageService]
    let daily: [DailyUsageService]
    let serviceStatus: ServiceStatusResponse?
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool

    @State private var isMonthlyExpanded = true
    @State private var isDailyExpanded = true
    @State private var isStatusExpanded = false

    var body: some View {
        List {
            Section {
                DisclosureGroup(isExpanded: $isMonthlyExpanded) {
                    if monthly.isEmpty {
                        PlaceholderRow(text: "まだ月別データがありません。")
                    } else {
                        MonthlyUsageSection(
                            services: monthly,
                            usageAlertSettings: usageAlertSettings,
                            showsLowSpeedUsage: showsLowSpeedUsage
                        )
                            .padding(.top, 8)
                    }
                } label: {
                    Label("月別データ利用量", systemImage: "calendar")
                        .font(.headline)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isDailyExpanded) {
                    if daily.isEmpty {
                        PlaceholderRow(text: "まだ日別データがありません。")
                    } else {
                        DailyUsageSection(
                            services: daily,
                            usageAlertSettings: usageAlertSettings,
                            showsLowSpeedUsage: showsLowSpeedUsage
                        )
                            .padding(.top, 8)
                    }
                } label: {
                    Label("日別データ利用量", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                }
            }

            if let serviceStatus {
                Section {
                    DisclosureGroup(isExpanded: $isStatusExpanded) {
                        ServiceStatusList(status: serviceStatus)
                            .padding(.top, 8)
                    } label: {
                        Label("回線ステータス", systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }
}

struct MonthlyUsageSection: View {
    let services: [MonthlyUsageService]
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(services) { service in
                MonthlyUsageServiceCard(
                    service: service,
                    usageAlertSettings: usageAlertSettings,
                    showsLowSpeedUsage: showsLowSpeedUsage
                )
            }
        }
    }
}

struct MonthlyUsageServiceCard: View {
    let service: MonthlyUsageService
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.titlePrimary)
                .font(.subheadline.bold())
            if let detail = service.titleDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(service.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.monthLabel)
                            .font(.callout)
                            .monospacedDigit()
                        Spacer()
                        if entry.hasData {
                            UsageBreakdownView(
                                highSpeedText: entry.highSpeedText,
                                lowSpeedText: entry.lowSpeedText,
                                isAlert: isAlert(entry: entry),
                                showsLowSpeedUsage: showsLowSpeedUsage
                            )
                        } else if let note = entry.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                if entry.id != service.entries.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func isAlert(entry: MonthlyUsageEntry) -> Bool {
        guard usageAlertSettings.isEnabled, let threshold = usageAlertSettings.monthlyThresholdMB else { return false }
        let totalGB = (entry.highSpeedGB ?? 0) + (entry.lowSpeedGB ?? 0)
        return (totalGB * 1024) > Double(threshold)
    }
}

struct DailyUsageSection: View {
    let services: [DailyUsageService]
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(services) { service in
                DailyUsageServiceCard(
                    service: service,
                    usageAlertSettings: usageAlertSettings,
                    showsLowSpeedUsage: showsLowSpeedUsage
                )
            }
        }
    }
}

struct DailyUsageServiceCard: View {
    let service: DailyUsageService
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.titlePrimary)
                .font(.subheadline.bold())
            if let detail = service.titleDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(service.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.dateLabel)
                            .font(.callout)
                            .monospacedDigit()
                        Spacer()
                        if entry.hasData {
                            UsageBreakdownView(
                                highSpeedText: entry.highSpeedText,
                                lowSpeedText: entry.lowSpeedText,
                                isAlert: isAlert(entry: entry),
                                showsLowSpeedUsage: showsLowSpeedUsage
                            )
                        } else if let note = entry.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                if entry.id != service.entries.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func isAlert(entry: DailyUsageEntry) -> Bool {
        guard usageAlertSettings.isEnabled, let threshold = usageAlertSettings.dailyThresholdMB else { return false }
        let totalMB = (entry.highSpeedMB ?? 0) + (entry.lowSpeedMB ?? 0)
        return totalMB > Double(threshold)
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
                Text("高速: \(highSpeedText ?? "-")")
                Text("低速: \(lowSpeedText ?? "-")")
            }
            .font(.caption)
            .foregroundStyle(isAlert ? .orange : .secondary)
        } else {
            Text(highSpeedText ?? "-")
                .font(.title3.bold())
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("プレフィックス: \(item.serviceCodePrefix ?? "-")")
                        .font(.subheadline)
                    Text("プランコード: \(item.planCode ?? "-")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let simList = item.simInfoList {
                        HStack {
                            ForEach(simList) { sim in
                                Label(sim.simType ?? "?", systemImage: sim.status == "O" ? "checkmark.circle" : "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(sim.status == "O" ? .green : .orange)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
