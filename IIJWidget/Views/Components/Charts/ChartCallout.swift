import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ChartCallout: View {
    let title: String
    let valueText: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.bold())
            Text(valueText)
                .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: 8, y: 4)
        )
    }

    private var backgroundColor: Color {
        if colorScheme == .light {
            return Color(uiColor: .systemBackground).opacity(0.95)
        }
        return Color(uiColor: .secondarySystemBackground).opacity(0.85)
    }

    private var shadowColor: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.black.opacity(0.3)
    }
}
