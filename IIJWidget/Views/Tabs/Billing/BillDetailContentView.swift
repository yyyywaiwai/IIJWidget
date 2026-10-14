import SwiftUI

struct BillDetailContentView: View {
    let detail: BillDetailResponse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                BillDetailSummaryView(detail: detail)
                if !detail.taxBreakdowns.isEmpty {
                    BillTaxBreakdownView(breakdowns: detail.taxBreakdowns)
                }
                ForEach(detail.sections) { section in
                    BillDetailSectionView(section: section)
                }
            }
            .padding()
        }
    }
}

struct BillDetailLoadingView: View {
    var body: some View {
        // 単なるスピナーではなく最終的なレイアウトを模したスケルトンを出し、
        // 読み込み完了時のガタつきを抑える。
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                BillDetailSkeletonCard(lineWidths: [0.35, 0.6])
                BillDetailSkeletonCard(lineWidths: [0.3, 0.9, 0.75])
                BillDetailSkeletonCard(lineWidths: [0.3, 0.85, 0.7, 0.8])
            }
            .padding()
        }
        .disabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("請求明細を読み込み中")
    }
}
