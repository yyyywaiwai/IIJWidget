import SwiftUI

struct StateFeedbackBanner: View {
    let state: AppViewModel.LoadState

    @ViewBuilder
    var body: some View {
        if case .failed(let message, _) = state {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .font(.footnote)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.9), in: Capsule())
        }
    }
}

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                Text("取得中…")
                    .font(.title3.bold())
            }
            .padding(32)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
