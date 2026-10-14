import SwiftUI

/// 明細読み込み中に表示するプレースホルダーカード。
struct BillDetailSkeletonCard: View {
    /// 各行の幅を親に対する比率で指定する。
    let lineWidths: [CGFloat]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            ForEach(Array(lineWidths.enumerated()), id: \.offset) { _, ratio in
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: proxy.size.width * ratio, height: 14)
                }
                .frame(height: 14)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: AppRadius.md, elevation: .flat)
        .opacity(isPulsing ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
