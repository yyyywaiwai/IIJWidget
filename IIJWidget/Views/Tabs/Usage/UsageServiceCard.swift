import SwiftUI

/// 月別・日別で共通の回線見出しとカード装飾。通信量と判定は呼び出し側が担う。
struct UsageServiceCard<Content: View>: View {
    let title: String
    let detail: String?
    let gradientColors: [Color]
    let hidePhoneOnScreenshot: Bool
    private let content: Content

    init(
        title: String,
        detail: String?,
        gradientColors: [Color],
        hidePhoneOnScreenshot: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.gradientColors = gradientColors
        self.hidePhoneOnScreenshot = hidePhoneOnScreenshot
        self.content = content()
    }

    var body: some View {
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
                    title,
                    font: .subheadline,
                    foregroundStyle: .primary,
                    isProtected: hidePhoneOnScreenshot
                )
                .fontWeight(.bold)
                .fontDesign(.rounded)
            }

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(AppSpacing.lg)
        .cardSurface(
            cornerRadius: AppRadius.md,
            material: .ultraThinMaterial,
            stroke: .tinted(gradientColors),
            elevation: .flat
        )
    }
}
