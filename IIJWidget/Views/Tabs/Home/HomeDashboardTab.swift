import SwiftUI

struct HomeDashboardTab: View {
    let payload: AggregatePayload?
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16)]

    var body: some View {
        Group {
            if let payload {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HomeOverviewHeader(
                            serviceInfoList: payload.top.serviceInfoList,
                            latestBillAmount: payload.bill.latestEntry?.plainAmountText
                        )

                        LazyVGrid(columns: columns, spacing: 16) {
                            UsageChartSwitcher(
                                monthlyServices: payload.monthlyUsage,
                                dailyServices: payload.dailyUsage
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

    @State private var selection: Tab = .monthly

    var body: some View {
        VStack(spacing: 12) {
            Picker("利用量表示", selection: $selection) {
                ForEach(UsageChartSwitcher.Tab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            ZStack {
                MonthlyUsageChartCard(services: monthlyServices)
                    .opacity(selection == .monthly ? 1 : 0)
                    .allowsHitTesting(selection == .monthly)
                    .accessibilityHidden(selection != .monthly)

                DailyUsageChartCard(services: dailyServices)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("登録回線一覧")
                .font(.title3.bold())
            LazyVStack(spacing: 16) {
                ForEach(serviceInfoList) { info in
                    ServiceInfoCard(info: info, latestBillAmount: latestBillAmount)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ServiceInfoCard: View {
    let info: MemberTopResponse.ServiceInfo
    let latestBillAmount: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.displayPlanName)
                        .font(.headline)
                    Text("電話番号: \(info.phoneLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if let remaining = info.remainingDataGB {
                        Text("残量 \(remaining, specifier: "%.2f")GB")
                            .font(.headline)
                            .monospacedDigit()
                    }
                    if let latestBillAmount {
                        Text(latestBillAmount)
                            .font(.headline.weight(.semibold))
                    }
                }
            }

            if let total = info.totalCapacity {
                ProgressView(value: progressValue(remaining: info.remainingDataGB, total: total)) {
                    Text("プラン容量 \(total, specifier: "%.0f")GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func progressValue(remaining: Double?, total: Double) -> Double {
        guard let remaining else { return 0 }
        let used = max(total - remaining, 0)
        return min(used / total, 1)
    }
}
