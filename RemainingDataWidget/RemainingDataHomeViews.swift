import SwiftUI

struct RemainingDataSmallView: View {
    let presentation: RemainingDataPresentation

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    WidgetRefreshControls(
                        isRefreshing: presentation.isRefreshing,
                        showsSuccess: presentation.showsSuccess
                    )
                }
                if presentation.isRefreshing {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("更新中")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                } else if let service = presentation.service {
                    HStack {
                        Spacer(minLength: 0)
                        RemainingDataCircularMeter(
                            service: service,
                            colors: presentation.ringColors(for: service.remainingRatio),
                            isRefreshing: false,
                            size: 100
                        )
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("データ未取得")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct RemainingDataMediumView: View {
    let presentation: RemainingDataPresentation

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(alignment: .center, spacing: 16) {
                    summary
                    Spacer()
                    if let service = presentation.service {
                        RemainingDataCircularMeter(
                            service: service,
                            colors: presentation.ringColors(for: service.remainingRatio),
                            isRefreshing: presentation.isRefreshing,
                            size: 88
                        )
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(width: 88, height: 88)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "simcard.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: presentation.ringColors(for: presentation.service?.remainingRatio ?? 0.5),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(presentation.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            WidgetRefreshControls(
                isRefreshing: presentation.isRefreshing,
                showsSuccess: presentation.showsSuccess
            )
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let service = presentation.service {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    WidgetDataText.gigabytes(service.remainingGB, size: 32, weight: .bold)
                    Text("GB")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(presentation.fetchedAt, format: .dateTime.hour().minute())
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("データ未取得")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("アプリで最新取得を実行")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct WidgetCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding()
    }
}
