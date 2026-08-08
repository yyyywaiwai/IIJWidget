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

  fileprivate enum UsageTab: String, CaseIterable, Hashable {
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
                    gradientColors: accentColors.palette(for: .monthlyChart).chartGradient
                  )
                  monthlyContent
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                  SectionHeader(
                    title: "日別利用量",
                    systemImage: "clock",
                    gradientColors: accentColors.palette(for: .dailyChart).chartGradient
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

  @ViewBuilder
  private var serviceStatusSection: some View {
    if let serviceStatus {
      VStack(alignment: .leading, spacing: AppSpacing.md) {
        DisclosureGroup(isExpanded: $isStatusExpanded) {
          ServiceStatusList(status: serviceStatus)
            .padding(.top, AppSpacing.sm)
        } label: {
          SectionHeader(
            title: "回線ステータス",
            systemImage: "dot.radiowaves.left.and.right",
            gradientColors: [
              Color(red: 0.16, green: 0.56, blue: 0.35), Color(red: 0.39, green: 0.77, blue: 0.48),
            ]
          )
        }
      }
      .padding(AppSpacing.lg)
      .cardSurface(cornerRadius: AppRadius.lg, material: .ultraThinMaterial, elevation: .flat)
    }
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

  var body: some View {
    let gradientColors = accentColors.palette(for: .monthlyChart).chartGradient
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      HStack(spacing: AppSpacing.sm) {
        Image(systemName: "simcard.fill")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(
            LinearGradient(
              colors: gradientColors,
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .accessibilityHidden(true)
        ScreenshotProtectedText(
          service.titlePrimary,
          font: .subheadline,
          foregroundStyle: .primary,
          isProtected: hidePhoneOnScreenshot
        )
        .fontWeight(.bold)
        .fontDesign(.rounded)
      }
      if let detail = service.titleDetail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
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
            alertColor: alertColor,
            isLast: index == service.entries.count - 1
          )
        }
      }
    }
    .padding(AppSpacing.lg)
    .cardSurface(
      cornerRadius: AppRadius.md,
      material: .ultraThinMaterial,
      stroke: .tinted(gradientColors),
      elevation: .flat
    )
  }

  private var alertColor: Color {
    accentColors.palette(for: .usageAlertWarning).previewSymbolColor
  }

  private func isAlert(entry: MonthlyUsageEntry) -> Bool {
    guard usageAlertSettings.isEnabled, let threshold = usageAlertSettings.monthlyThresholdMB else {
      return false
    }
    let totalGB = (entry.highSpeedGB ?? 0) + (entry.lowSpeedGB ?? 0)
    return usageAlertSettings.exceedsMonthlyThreshold(totalGB: totalGB, threshold: threshold)
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

  var body: some View {
    let gradientColors = accentColors.palette(for: .dailyChart).chartGradient
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      HStack(spacing: AppSpacing.sm) {
        Image(systemName: "simcard.fill")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(
            LinearGradient(
              colors: gradientColors,
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .accessibilityHidden(true)
        ScreenshotProtectedText(
          service.titlePrimary,
          font: .subheadline,
          foregroundStyle: .primary,
          isProtected: hidePhoneOnScreenshot
        )
        .fontWeight(.bold)
        .fontDesign(.rounded)
      }
      if let detail = service.titleDetail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
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
            alertColor: alertColor,
            isLast: index == service.entries.count - 1
          )
        }
      }
    }
    .padding(AppSpacing.lg)
    .cardSurface(
      cornerRadius: AppRadius.md,
      material: .ultraThinMaterial,
      stroke: .tinted(gradientColors),
      elevation: .flat
    )
  }

  private var alertColor: Color {
    accentColors.palette(for: .usageAlertWarning).previewSymbolColor
  }

  private func isAlert(entry: DailyUsageEntry) -> Bool {
    guard usageAlertSettings.isEnabled, let threshold = usageAlertSettings.dailyThresholdMB else {
      return false
    }
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
  let alertColor: Color
  let isLast: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: AppSpacing.sm) {
        Text(label)
          .font(.system(.callout, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.secondary)
        Spacer(minLength: AppSpacing.sm)
        if hasData {
          // 色だけに頼らず記号でも警告を伝える (色覚特性への配慮)。
          if isAlert {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(alertColor)
              .accessibilityHidden(true)
          }
          UsageBreakdownView(
            highSpeedText: highSpeedText,
            lowSpeedText: lowSpeedText,
            isAlert: isAlert,
            showsLowSpeedUsage: showsLowSpeedUsage,
            alertColor: alertColor
          )
        } else if let note {
          Text(note)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, AppSpacing.sm + 2)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(label)
      .accessibilityValue(accessibilityValueText)

      if !isLast {
        Divider()
          .opacity(0.5)
      }
    }
  }

  private var accessibilityValueText: String {
    guard hasData else { return note ?? "データなし" }
    var parts: [String] = ["高速 \(highSpeedText ?? "-")"]
    if showsLowSpeedUsage {
      parts.append("低速 \(lowSpeedText ?? "-")")
    }
    if isAlert {
      parts.append("使いすぎアラートのしきい値を超えています")
    }
    return parts.joined(separator: "、")
  }
}

private struct UsageBreakdownView: View {
  let highSpeedText: String?
  let lowSpeedText: String?
  let isAlert: Bool
  let showsLowSpeedUsage: Bool
  let alertColor: Color

  var body: some View {
    if showsLowSpeedUsage {
      VStack(alignment: .trailing, spacing: 2) {
        HStack(spacing: AppSpacing.xs) {
          Image(systemName: "bolt.fill")
            .font(.system(size: 9))
          Text(highSpeedText ?? "-")
        }
        HStack(spacing: AppSpacing.xs) {
          Image(systemName: "tortoise.fill")
            .font(.system(size: 9))
          Text(lowSpeedText ?? "-")
        }
      }
      .font(.system(.caption, design: .rounded, weight: .medium))
      .monospacedDigit()
      .foregroundStyle(isAlert ? AnyShapeStyle(alertColor) : AnyShapeStyle(.secondary))
    } else {
      Text(highSpeedText ?? "-")
        .font(.system(.title3, design: .rounded, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(isAlert ? AnyShapeStyle(alertColor) : AnyShapeStyle(.primary))
    }
  }
}

struct ServiceStatusList: View {
  let status: ServiceStatusResponse

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
      ForEach(status.serviceInfoList) { item in
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
          HStack(spacing: AppSpacing.xs + 2) {
            Image(systemName: "tag.fill")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
            Text(item.serviceCodePrefix ?? "-")
              .font(.system(.subheadline, design: .rounded, weight: .semibold))
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("サービスコード")

          HStack(spacing: AppSpacing.xs + 2) {
            Image(systemName: "doc.text.fill")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
            Text(item.planCode ?? "-")
              .font(.system(.caption, design: .rounded))
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("プランコード")

          if let simList = item.simInfoList {
            HStack(spacing: AppSpacing.sm) {
              ForEach(simList) { sim in
                let isActive = sim.status == "O"
                HStack(spacing: AppSpacing.xs) {
                  Image(
                    systemName: isActive ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                  )
                  .font(.system(size: 12))
                  Text(sim.simType ?? "?")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                }
                .foregroundStyle(isActive ? Color.green : Color.orange)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(
                  Capsule()
                    .fill((isActive ? Color.green : Color.orange).opacity(0.12))
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(sim.simType ?? "SIM")
                .accessibilityValue(isActive ? "利用中" : "要確認")
              }
            }
          }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(
          cornerRadius: AppRadius.sm,
          material: .ultraThinMaterial,
          elevation: .flat
        )
      }
    }
  }
}
