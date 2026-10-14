import SwiftUI

struct HomeOverviewHeader: View {
    let serviceInfoList: [TrafficSummary.ServiceInfo]
    let latestBillAmount: String?
    let accentColors: AccentColorSettings
    let hidePhoneOnScreenshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            SectionHeader(
                title: "登録回線一覧",
                systemImage: "antenna.radiowaves.left.and.right",
                gradientColors: accentColors.palette(for: .monthlyChart).chartGradient
            )
            LazyVStack(spacing: AppSpacing.lg) {
                ForEach(serviceInfoList) { info in
                    ServiceInfoCard(
                        info: info,
                        latestBillAmount: latestBillAmount,
                        accentColors: accentColors,
                        hidePhoneOnScreenshot: hidePhoneOnScreenshot
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
