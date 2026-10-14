import SwiftUI

struct RemainingDataCircularMeter: View {
    let service: WidgetServiceSnapshot
    let colors: [Color]
    let isRefreshing: Bool
    let size: CGFloat

    var body: some View {
        let lineWidth = size * 0.11
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.03, service.remainingRatio)))
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
            VStack(spacing: 1) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    WidgetDataText.gigabytes(service.remainingGB, size: size * 0.22, weight: .bold)
                    Text("GB")
                        .font(.system(size: size * 0.11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct FilledLinearMeter: View {
    let ratio: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(ratio, 0), 1)
            let width = proxy.size.width * clamped
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(width, proxy.size.height))
            }
        }
        .compositingGroup()
        .clipped()
    }
}
