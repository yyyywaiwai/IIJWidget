import SwiftUI

struct UsageEntryRow: View {
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
