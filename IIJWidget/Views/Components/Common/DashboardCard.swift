import SwiftUI

struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder private let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.5),
                                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05),
                    radius: 12,
                    x: 0,
                    y: 6
                )
        }
    }
}
