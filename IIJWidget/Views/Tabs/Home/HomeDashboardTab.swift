import SwiftUI

struct HomeDashboardTab: View {
    let payload: AggregatePayload?
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let defaultUsageChart: UsageChartDefault
    let saveDefaultUsageChart: (UsageChartDefault) -> Void
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16)]

    var body: some View {
        Group {
            if let payload {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HomeOverviewHeader(
                            serviceInfoList: payload.top.serviceInfoList,
                            latestBillAmount: payload.bill.latestEntry?.plainAmountText,
                            accentColors: accentColors
                        )

                        LazyVGrid(columns: columns, spacing: 16) {
                            UsageChartSwitcher(
                                monthlyServices: payload.monthlyUsage,
                                dailyServices: payload.dailyUsage,
                                accentColors: accentColors,
                                usageAlertSettings: usageAlertSettings,
                                defaultChart: defaultUsageChart,
                                onDefaultChange: saveDefaultUsageChart
                            )
                        }
                    }
                    .padding()
                }
            } else {
                EmptyStateView(text: "最新の残量を取得するとダッシュボードが表示されます。設定タブで資格情報を入力し、右上の「最新取得」をタップしてください。")
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct UsageChartSwitcher: View {
    enum Tab: String, CaseIterable, Identifiable {
        case monthly
        case daily

        var id: String { rawValue }

        var label: String {
            switch self {
            case .monthly:
                return "月別"
            case .daily:
                return "日別"
            }
        }
    }

    let monthlyServices: [MonthlyUsageService]
    let dailyServices: [DailyUsageService]
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let defaultChart: UsageChartDefault
    let onDefaultChange: (UsageChartDefault) -> Void

    @State private var selection: Tab

    init(
        monthlyServices: [MonthlyUsageService],
        dailyServices: [DailyUsageService],
        accentColors: AccentColorSettings,
        usageAlertSettings: UsageAlertSettings,
        defaultChart: UsageChartDefault,
        onDefaultChange: @escaping (UsageChartDefault) -> Void
    ) {
        self.monthlyServices = monthlyServices
        self.dailyServices = dailyServices
        self.accentColors = accentColors
        self.usageAlertSettings = usageAlertSettings
        self.defaultChart = defaultChart
        self.onDefaultChange = onDefaultChange
        _selection = State(initialValue: Tab(rawValue: defaultChart.rawValue) ?? .monthly)
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("利用量表示", selection: $selection) {
                ForEach(UsageChartSwitcher.Tab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selection) { newValue in
                onDefaultChange(UsageChartDefault(rawValue: newValue.rawValue) ?? .monthly)
            }

            ZStack {
                MonthlyUsageChartCard(services: monthlyServices, accentColor: accentColors, usageAlertSettings: usageAlertSettings)
                    .opacity(selection == .monthly ? 1 : 0)
                    .allowsHitTesting(selection == .monthly)
                    .accessibilityHidden(selection != .monthly)

                DailyUsageChartCard(services: dailyServices, accentColor: accentColors, usageAlertSettings: usageAlertSettings)
                    .opacity(selection == .daily ? 1 : 0)
                    .allowsHitTesting(selection == .daily)
                    .accessibilityHidden(selection != .daily)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.88), value: selection)
        }
    }
}

struct HomeOverviewHeader: View {
    let serviceInfoList: [MemberTopResponse.ServiceInfo]
    let latestBillAmount: String?
    let accentColors: AccentColorSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("登録回線一覧")
                .font(.title3.bold())
            LazyVStack(spacing: 16) {
                ForEach(serviceInfoList) { info in
                    ServiceInfoCard(
                        info: info,
                        latestBillAmount: latestBillAmount,
                        accentColors: accentColors
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ServiceInfoCard: View {
    let info: MemberTopResponse.ServiceInfo
    let latestBillAmount: String?
    let accentColors: AccentColorSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(info.displayPlanName)
                        .font(.headline)
                    Text("電話番号: \(info.phoneLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let total = info.totalCapacity {
                        Text("プラン容量 \(total, specifier: "%.0f")GB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let remaining = info.remainingDataGB {
                        Text("残量 \(remaining, specifier: "%.2f")GB")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }

                    if let latestBillAmount {
                        Text(latestBillAmount)
                            .font(.headline.weight(.semibold))
                    }
                }

                Spacer(minLength: 12)

                if let remaining = info.remainingDataGB, let total = info.totalCapacity, total > 0 {
                    ServiceUsageRing(
                        remainingGB: remaining,
                        totalCapacityGB: total,
                        accentColors: accentColors
                    )
                    .frame(width: 96, height: 96)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ServiceUsageRing: View {
    let remainingGB: Double
    let totalCapacityGB: Double
    let accentColors: AccentColorSettings

    private var remainingRatio: Double {
        guard totalCapacityGB > 0 else { return 0 }
        return min(max(remainingGB / totalCapacityGB, 0), 1)
    }

    private var usedRatio: Double {
        1 - remainingRatio
    }

    var body: some View {
        let colors = accentColors.widgetRingColors(for: remainingRatio)
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.05, 1 - usedRatio)))
                .stroke(
                    AngularGradient(colors: colors, center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(remainingGB, specifier: "%.2f")GB")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("残")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
