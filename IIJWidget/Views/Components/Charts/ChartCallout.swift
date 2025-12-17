import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ChartCallout: View {
    let title: String
    let valueText: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.system(.callout, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.2 : 0.7),
                                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
                .shadow(color: shadowColor.opacity(0.5), radius: 3, x: 0, y: 2)
        }
    }

    private var shadowColor: Color {
        colorScheme == .light ? Color.black.opacity(0.1) : Color.black.opacity(0.4)
    }
}
