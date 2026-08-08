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
              dailyServices: payload.dailyUsage,
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
  let defaultChart: UsageChartDefault
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
    self.defaultChart = defaultChart
    self.onDefaultChange = onDefaultChange
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
              MonthlyUsageChartCard(
                services: monthlyServices, accentColor: accentColors,
                usageAlertSettings: usageAlertSettings)
              DailyUsageChartCard(
                services: dailyServices, accentColor: accentColors,
                usageAlertSettings: usageAlertSettings)
            }
          } else {
            VStack(spacing: AppSpacing.lg) {
              MonthlyUsageChartCard(
                services: monthlyServices, accentColor: accentColors,
                usageAlertSettings: usageAlertSettings)
              DailyUsageChartCard(
                services: dailyServices, accentColor: accentColors,
                usageAlertSettings: usageAlertSettings)
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
}

struct HomeOverviewHeader: View {
  let serviceInfoList: [MemberTopResponse.ServiceInfo]
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

struct ServiceInfoCard: View {
  let info: MemberTopResponse.ServiceInfo
  let latestBillAmount: String?
  let accentColors: AccentColorSettings
  let hidePhoneOnScreenshot: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// リングを文字サイズに追従させる。大きすぎるとカードを圧迫するので上限を設ける。
  @ScaledMetric(relativeTo: .title) private var ringBaseSize: CGFloat = 120

  private var ringSize: CGFloat { min(ringBaseSize, 176) }

  private var remainingRatio: Double {
    guard let remaining = info.remainingDataGB, let total = info.totalCapacity, total > 0 else {
      return 0
    }
    return min(max(remaining / total, 0), 1)
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        // 特大文字では横並びだと本文が潰れるため縦積みに切り替える。
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
          detailColumn
          ring
        }
      } else {
        HStack(alignment: .center, spacing: AppSpacing.xl) {
          detailColumn
          Spacer(minLength: AppSpacing.md)
          ring
        }
      }
    }
    .padding(AppSpacing.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }

  @ViewBuilder
  private var ring: some View {
    if let remaining = info.remainingDataGB, let total = info.totalCapacity, total > 0 {
      ServiceUsageRing(
        remainingGB: remaining,
        totalCapacityGB: total,
        accentColors: accentColors
      )
      .frame(width: ringSize, height: ringSize)
    }
  }

  private var detailColumn: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm + 2) {
      HStack(spacing: AppSpacing.sm) {
        Image(systemName: "simcard.fill")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(
            LinearGradient(
              colors: accentColors.widgetRingColors(for: remainingRatio),
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .accessibilityHidden(true)
        Text(info.displayPlanName)
          .font(.system(.headline, design: .rounded, weight: .bold))
      }

      VStack(alignment: .leading, spacing: AppSpacing.xs + 2) {
        HStack(spacing: AppSpacing.xs + 2) {
          Image(systemName: "phone.fill")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          ScreenshotProtectedText(
            info.phoneLabel,
            font: .subheadline,
            foregroundStyle: .secondary,
            isProtected: hidePhoneOnScreenshot
          )
        }

        if let total = info.totalCapacity {
          HStack(spacing: AppSpacing.xs + 2) {
            Image(systemName: "externaldrive.fill")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
            Text("プラン容量 \(total, specifier: "%.0f")GB")
              .font(.system(.caption, design: .rounded))
              .foregroundStyle(.secondary)
          }
        }
      }

      if let remaining = info.remainingDataGB {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
          Text("\(remaining, specifier: "%.2f")")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .contentTransition(.numericText(value: remaining))
          Text("GB")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
          Text("残")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("データ残量")
        .accessibilityValue("\(String(format: "%.2f", remaining))ギガバイト")
      }

      if let latestBillAmount {
        HStack(spacing: AppSpacing.xs + 2) {
          Image(systemName: "yensign.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(accentColors.palette(for: .billingChart).previewSymbolColor)
            .accessibilityHidden(true)
          Text(latestBillAmount)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("直近のご請求")
      }
    }
  }
}

struct ServiceUsageRing: View {
  let remainingGB: Double
  let totalCapacityGB: Double
  let accentColors: AccentColorSettings
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var remainingRatio: Double {
    guard totalCapacityGB > 0 else { return 0 }
    return min(max(remainingGB / totalCapacityGB, 0), 1)
  }

  private var accessibilityValueText: String {
    let percent = Int((remainingRatio * 100).rounded())
    return "\(String(format: "%.2f", remainingGB))ギガバイト、"
      + "全\(String(format: "%.0f", totalCapacityGB))ギガバイト中 残り\(percent)パーセント"
  }

  var body: some View {
    let colors = accentColors.widgetRingColors(for: remainingRatio)
    return GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      let lineWidth: CGFloat = size * 0.12

      ZStack {
        // トラック（背景リング）
        Circle()
          .stroke(
            Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06),
            lineWidth: lineWidth
          )

        // プログレスリング。残量ゼロのときは弧を描かない
        // (以前は trim の下限が 0.03 だったため、残量 0 でもわずかに塗られていた)。
        if remainingRatio > 0 {
          Circle()
            .trim(from: 0, to: CGFloat(remainingRatio))
            .stroke(
              AngularGradient(
                gradient: Gradient(colors: colors + [colors.first ?? .blue]),
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
              ),
              style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(
              reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85),
              value: remainingRatio
            )
        }

        // 中央の数値
        VStack(spacing: 2) {
          Text("\(remainingGB, specifier: "%.1f")")
            .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: remainingGB))
          Text("GB")
            .font(.system(size: size * 0.12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: size, height: size)
      .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("データ残量")
    .accessibilityValue(accessibilityValueText)
  }
}
