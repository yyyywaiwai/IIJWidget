import SwiftUI

struct ServiceInfoCard: View {
    let info: TrafficSummary.ServiceInfo
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
