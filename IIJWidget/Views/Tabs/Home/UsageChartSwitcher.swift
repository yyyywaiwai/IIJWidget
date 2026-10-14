import SwiftUI

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

        var accentRole: AccentRole {
            switch self {
            case .monthly: return .monthlyChart
            case .daily: return .dailyChart
            }
        }
    }

    let monthlyServices: [MonthlyUsageService]
    let dailyServices: [DailyUsageService]
    let accentColors: AccentColorSettings
    let usageAlertSettings: UsageAlertSettings
    let onDefaultChange: (UsageChartDefault) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: Tab
    @State private var availableWidth: CGFloat = 0

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
        self.onDefaultChange = onDefaultChange
        // 保存済みの選択を初回だけ取り込み、以後はこのビューが選択状態を所有する。
        _selection = State(initialValue: Tab(rawValue: defaultChart.rawValue) ?? .monthly)
    }

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if isRegularWidth {
                // iPad: 幅を実測してレイアウトを決める。GeometryReader で包むと
                // 高さまで奪われて minHeight のハックが必要になるため、背景で測る。
                Group {
                    if availableWidth > 900 {
                        HStack(alignment: .top, spacing: AppSpacing.lg) {
                            regularChartCards
                        }
                    } else {
                        VStack(spacing: AppSpacing.lg) {
                            regularChartCards
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { availableWidth = proxy.size.width }
                            .onChange(of: proxy.size) { _, newSize in availableWidth = newSize.width }
                    }
                }
            } else {
                // iPhone / Compact: セグメント切替
                VStack(spacing: AppSpacing.lg) {
                    SegmentedSelector(
                        items: Tab.allCases,
                        selection: $selection,
                        title: \.label,
                        systemImage: { $0 == .monthly ? "calendar" : "clock" },
                        gradientColors: { accentColors.palette(for: $0.accentRole).chartGradient }
                    )
                    .onChange(of: selection) { _, newValue in
                        onDefaultChange(UsageChartDefault(rawValue: newValue.rawValue) ?? .monthly)
                    }

                    ZStack {
                        if selection == .monthly {
                            MonthlyUsageChartCard(
                                services: monthlyServices,
                                accentColor: accentColors,
                                usageAlertSettings: usageAlertSettings,
                                animationTrigger: selection
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .leading)),
                                    removal: .opacity.combined(with: .move(edge: .trailing))
                                ))
                        } else {
                            DailyUsageChartCard(
                                services: dailyServices,
                                accentColor: accentColors,
                                usageAlertSettings: usageAlertSettings,
                                animationTrigger: selection
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selection)
                }
            }
        }
    }

    @ViewBuilder
    private var regularChartCards: some View {
        MonthlyUsageChartCard(
            services: monthlyServices,
            accentColor: accentColors,
            usageAlertSettings: usageAlertSettings
        )
        DailyUsageChartCard(
            services: dailyServices,
            accentColor: accentColors,
            usageAlertSettings: usageAlertSettings
        )
    }
}
