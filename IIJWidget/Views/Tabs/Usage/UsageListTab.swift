import SwiftUI

struct UsageListTab: View {
    let monthly: [MonthlyUsageService]
    let daily: [DailyUsageService]
    let serviceStatus: ServiceStatusResponse?
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let showsLowSpeedUsage: Bool
    let hidePhoneOnScreenshot: Bool
    let refresh: () async -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: UsageTab = .monthly
    @State private var isStatusExpanded = false

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    private enum UsageTab: String, CaseIterable, Hashable {
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
        let useTwoColumn = isRegularWidth

        return Group {
            if useTwoColumn {
                ScrollView {
                    VStack(spacing: AppSpacing.xxl) {
                        HStack(alignment: .top, spacing: AppSpacing.xxl) {
                            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                                SectionHeader(
                                    title: "月別利用量",
                                    systemImage: "calendar",
                                    gradientColors: accentColors.palette(for: .monthlyChart)
                                        .chartGradient
                                )
                                monthlyContent
                            }
                            .frame(maxWidth: .infinity, alignment: .top)

                            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                                SectionHeader(
                                    title: "日別利用量",
                                    systemImage: "clock",
                                    gradientColors: accentColors.palette(for: .dailyChart)
                                        .chartGradient
                                )
                                dailyContent
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }

                        serviceStatusSection
                    }
                    .padding(AppSpacing.xxl)
                }
                .refreshable { await refresh() }
            } else {
                VStack(spacing: 0) {
                    SegmentedSelector(
                        items: UsageTab.allCases,
                        selection: $selectedTab,
                        title: \.title,
                        systemImage: \.icon,
                        gradientColors: { accentColors.palette(for: $0.accentRole).chartGradient }
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.md)

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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func usagePage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                content()
                serviceStatusSection
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.lg)
        }
        .refreshable { await refresh() }
    }

    private var monthlyContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if monthly.isEmpty {
                EmptyStateView(
                    title: "月別データがありません",
                    message: "最新の利用量を取得すると、ここに月ごとの通信量が表示されます。",
                    systemImage: "calendar.badge.clock"
                ) {
                    Button("最新取得") {
                        Task { await refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if daily.isEmpty {
                EmptyStateView(
                    title: "日別データがありません",
                    message: "最新の利用量を取得すると、ここに日ごとの通信量が表示されます。",
                    systemImage: "clock.badge.questionmark"
                ) {
                    Button("最新取得") {
                        Task { await refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
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

    private var serviceStatusSection: some View {
        ServiceStatusSection(status: serviceStatus, isExpanded: $isStatusExpanded)
    }
}
