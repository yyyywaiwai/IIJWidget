import SwiftUI

struct HomeDashboardTab: View {
  let payload: AggregatePayload?
  let accentColors: AccentColorSettings
  let usageAlertSettings: UsageAlertSettings
  let defaultUsageChart: UsageChartDefault
  let hidePhoneOnScreenshot: Bool
  let saveDefaultUsageChart: (UsageChartDefault) -> Void

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private var gridColumns: [GridItem] {
    if horizontalSizeClass == .regular {
      return [GridItem(.flexible(), spacing: 16)]
    } else {
      return [GridItem(.adaptive(minimum: 320), spacing: 16)]
    }
  }

  var body: some View {
    Group {
      if let payload {
        ScrollView(.vertical, showsIndicators: false) {
          VStack(alignment: .leading, spacing: 20) {
            HomeOverviewHeader(
              serviceInfoList: payload.top.serviceInfoList,
              latestBillAmount: payload.bill.latestEntry?.plainAmountText,
              accentColors: accentColors,
              hidePhoneOnScreenshot: hidePhoneOnScreenshot
            )

            LazyVGrid(columns: gridColumns, spacing: 16) {
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

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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

  private var isRegularWidth: Bool { horizontalSizeClass == .regular }

  var body: some View {
    Group {
      if isRegularWidth {
        GeometryReader { geometry in
          let width = geometry.size.width
          let useSideBySide = width > 900

          VStack(spacing: 16) {
            if useSideBySide {
              // iPad Landscape (Wide): HStack
              HStack(alignment: .top, spacing: 16) {
                MonthlyUsageChartCard(
                  services: monthlyServices, accentColor: accentColors,
                  usageAlertSettings: usageAlertSettings)
                DailyUsageChartCard(
                  services: dailyServices, accentColor: accentColors,
                  usageAlertSettings: usageAlertSettings)
              }
              .frame(maxWidth: .infinity)
            } else {
              // iPad Portrait (Narrower): VStack
              VStack(spacing: 16) {
                MonthlyUsageChartCard(
                  services: monthlyServices, accentColor: accentColors,
                  usageAlertSettings: usageAlertSettings)
                DailyUsageChartCard(
                  services: dailyServices, accentColor: accentColors,
                  usageAlertSettings: usageAlertSettings)
              }
              .frame(maxWidth: .infinity)
            }
          }
        }
        .frame(minHeight: isRegularWidth ? 500 : 300)  // Provide enough height for the orientation-aware content
      } else {
        // iPhone / Compact: TabView Switcher
        VStack(spacing: 16) {
          HStack(spacing: 0) {
            ForEach(UsageChartSwitcher.Tab.allCases) { tab in
              Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                  selection = tab
                }
                onDefaultChange(UsageChartDefault(rawValue: tab.rawValue) ?? .monthly)
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: tab == .monthly ? "calendar" : "clock")
                    .font(.system(size: 12, weight: .medium))
                  Text(tab.label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(selection == tab ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .background {
                  if selection == tab {
                    Capsule()
                      .fill(
                        LinearGradient(
                          colors: tab == .monthly
                            ? accentColors.palette(for: .monthlyChart).chartGradient
                            : accentColors.palette(for: .dailyChart).chartGradient,
                          startPoint: .topLeading,
                          endPoint: .bottomTrailing
                        )
                      )
                      .shadow(
                        color: (tab == .monthly
                          ? accentColors.palette(for: .monthlyChart).chartGradient.first
                          : accentColors.palette(for: .dailyChart).chartGradient.first)?
                          .opacity(0.4) ?? .clear,
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
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 10) {
        Image(systemName: "antenna.radiowaves.left.and.right")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(
            LinearGradient(
              colors: accentColors.palette(for: .monthlyChart).chartGradient,
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        Text("登録回線一覧")
          .font(.system(.title3, design: .rounded, weight: .bold))
      }
      LazyVStack(spacing: 16) {
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
  @Environment(\.colorScheme) private var colorScheme

  private var remainingRatio: Double {
    guard let remaining = info.remainingDataGB, let total = info.totalCapacity, total > 0 else {
      return 0
    }
    return min(max(remaining / total, 0), 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 20) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            Image(systemName: "simcard.fill")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(
                LinearGradient(
                  colors: accentColors.widgetRingColors(for: remainingRatio),
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
            Text(info.displayPlanName)
              .font(.system(.headline, design: .rounded, weight: .bold))
          }

          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
              Image(systemName: "phone.fill")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
              ScreenshotProtectedText(
                info.phoneLabel,
                font: .subheadline,
                foregroundStyle: .secondary,
                isProtected: hidePhoneOnScreenshot
              )
            }

            if let total = info.totalCapacity {
              HStack(spacing: 6) {
                Image(systemName: "externaldrive.fill")
                  .font(.system(size: 10))
                  .foregroundStyle(.tertiary)
                Text("プラン容量 \(total, specifier: "%.0f")GB")
                  .font(.system(.caption, design: .rounded))
                  .foregroundStyle(.secondary)
              }
            }
          }

          if let remaining = info.remainingDataGB {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text("\(remaining, specifier: "%.2f")")
                .font(.system(size: 28, weight: .bold, design: .rounded))
              Text("GB")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
              Text("残")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.tertiary)
            }
            .monospacedDigit()
          }

          if let latestBillAmount {
            HStack(spacing: 6) {
              Image(systemName: "yensign.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
              Text(latestBillAmount)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
          }
        }

        Spacer(minLength: 12)

        if let remaining = info.remainingDataGB, let total = info.totalCapacity, total > 0 {
          ServiceUsageRing(
            remainingGB: remaining,
            totalCapacityGB: total,
            accentColors: accentColors
          )
          .frame(width: 120, height: 120)
        }
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(
              LinearGradient(
                colors: [
                  Color.white.opacity(colorScheme == .dark ? 0.12 : 0.5),
                  Color.white.opacity(colorScheme == .dark ? 0.04 : 0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 1
            )
        }
        .shadow(
          color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 16, x: 0, y: 6
        )
        .shadow(
          color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03), radius: 3, x: 0, y: 1)
    }
  }
}

struct ServiceUsageRing: View {
  let remainingGB: Double
  let totalCapacityGB: Double
  let accentColors: AccentColorSettings
  @Environment(\.colorScheme) private var colorScheme

  private var remainingRatio: Double {
    guard totalCapacityGB > 0 else { return 0 }
    return min(max(remainingGB / totalCapacityGB, 0), 1)
  }

  private var usedRatio: Double {
    1 - remainingRatio
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

        // プログレスリング
        Circle()
          .trim(from: 0, to: CGFloat(max(0.03, remainingRatio)))
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

        // 中央の数値
        VStack(spacing: 2) {
          Text("\(remainingGB, specifier: "%.1f")")
            .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
            .monospacedDigit()
          Text("GB")
            .font(.system(size: size * 0.12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: size, height: size)
      .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
  }
}
