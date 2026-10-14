import SwiftUI

struct BillingTabView: View {
    let viewModel: AppViewModel
    let bill: BillSummaryResponse?
    let accentColors: AccentColorSettings
    let showsBillingChart: Bool
    let refresh: () async -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var presentedEntry: BillSummaryResponse.BillEntry?

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let useTwoColumn = isRegularWidth && isLandscape

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    if let bill {
                        if useTwoColumn {
                            HStack(alignment: .top, spacing: AppSpacing.xl) {
                                VStack(spacing: AppSpacing.xl) {
                                    BillingHighlightCard(bill: bill, accentColors: accentColors) {
                                        entry in
                                        presentedEntry = entry
                                    }
                                    if showsBillingChart {
                                        BillingBarChart(bill: bill, accentColors: accentColors)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                BillSummaryList(bill: bill, accentColors: accentColors) { entry in
                                    presentedEntry = entry
                                }
                                .padding(AppSpacing.lg)
                                .cardSurface(cornerRadius: AppRadius.lg)
                                .frame(maxWidth: 400)
                            }
                        } else {
                            BillingHighlightCard(bill: bill, accentColors: accentColors) { entry in
                                presentedEntry = entry
                            }
                            if showsBillingChart {
                                BillingBarChart(bill: bill, accentColors: accentColors)
                            }
                            BillSummaryList(bill: bill, accentColors: accentColors) { entry in
                                presentedEntry = entry
                            }
                            .padding(AppSpacing.lg)
                            .cardSurface(cornerRadius: AppRadius.lg)
                        }
                    } else {
                        EmptyStateView(
                            title: "請求データがありません",
                            message: "請求データがまだ取得されていません。下に引っ張るか、「最新取得」をタップしてください。",
                            systemImage: "yensign.circle"
                        ) {
                            Button("最新取得") {
                                Task { await refresh() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
            .refreshable { await refresh() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
        .sheet(item: $presentedEntry) { entry in
            if let bill {
                BillDetailSheet(viewModel: viewModel, bill: bill, initialEntry: entry)
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
            } else {
                EmptyView()
            }
        }
    }
}
