import AppIntents
import SwiftUI

/// 手動更新はホーム画面専用。ロック画面の表示からは参照しない。
struct WidgetRefreshControls: View {
    let isRefreshing: Bool
    let showsSuccess: Bool

    var body: some View {
        Group {
            if showsSuccess {
                successStatusLabel
            }
            if isRefreshing {
                refreshStatusLabel
            }
            Button(intent: RefreshWidgetIntent()) {
                RefreshSymbol(isRefreshing: isRefreshing)
            }
            .buttonStyle(.plain)
            .padding(6)
            .background(
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .accessibilityLabel("データ更新")
        }
    }

    private var refreshStatusLabel: some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
            Text("更新中")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private var successStatusLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
            Text("完了")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}

private struct RefreshSymbol: View {
    let isRefreshing: Bool

    var body: some View {
        if isRefreshing {
            glyph
                .symbolEffect(.pulse, options: .repeat(Int.max), value: isRefreshing)
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Image(systemName: "arrow.clockwise")
            .font(.caption)
    }
}
