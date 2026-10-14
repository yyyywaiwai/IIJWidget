import SwiftUI

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
