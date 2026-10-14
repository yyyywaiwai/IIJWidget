import SwiftUI

struct ServiceStatusSection: View {
    let status: ServiceStatusResponse?
    @Binding var isExpanded: Bool

    var body: some View {
        if let status {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ServiceStatusList(status: status)
                        .padding(.top, AppSpacing.sm)
                } label: {
                    SectionHeader(
                        title: "回線ステータス",
                        systemImage: "dot.radiowaves.left.and.right",
                        gradientColors: [
                            Color(red: 0.16, green: 0.56, blue: 0.35),
                            Color(red: 0.39, green: 0.77, blue: 0.48),
                        ]
                    )
                }
            }
            .padding(AppSpacing.lg)
            .cardSurface(cornerRadius: AppRadius.lg, material: .ultraThinMaterial, elevation: .flat)
        }
    }
}
