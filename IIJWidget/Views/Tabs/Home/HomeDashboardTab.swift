import SwiftUI

struct HomeDashboardTab: View {
    let payload: AggregatePayload?
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let defaultUsageChart: UsageChartDefault
    let hidePhoneOnScreenshot: Bool
    let saveDefaultUsageChart: (UsageChartDefault) -> Void
    let refresh: () async -> Void
    let presentOnboarding: () -> Void

    var body: some View {
        Group {
            if let payload {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        HomeOverviewHeader(
                            serviceInfoList: payload.top.serviceInfoList,
                            latestBillAmount: payload.bill.latestEntry?.plainAmountText,
                            accentColors: accentColors,
                            hidePhoneOnScreenshot: hidePhoneOnScreenshot
                        )

                        UsageChartSwitcher(
                            monthlyServices: payload.monthlyUsage,
                            dailyServices: payload.dailyUsageWithHistory,
                            accentColors: accentColors,
                            usageAlertSettings: usageAlertSettings,
                            defaultChart: defaultUsageChart,
                            onDefaultChange: saveDefaultUsageChart
                        )
                    }
                    .padding(AppSpacing.lg)
                }
                .refreshable { await refresh() }
            } else {
                EmptyStateView(
                    title: "ダッシュボードがありません",
                    message: "ログイン情報を設定して最新の残量を取得すると、ここに表示されます。",
                    systemImage: "antenna.radiowaves.left.and.right.slash"
                ) {
                    Button("ログイン情報を設定") {
                        presentOnboarding()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("最新取得") {
                        Task { await refresh() }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
