import SwiftUI

struct RemainingDataCircularAccessory: View {
    let presentation: RemainingDataPresentation

    var body: some View {
        if presentation.showsSuccess {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
        } else if presentation.isRefreshing {
            ZStack {
                Circle()
                    .strokeBorder(.primary.opacity(0.2), lineWidth: 4)
                Text("更新中")
                    .font(.caption2.weight(.semibold))
            }
        } else if let service = presentation.service {
            Gauge(value: service.remainingGB, in: 0...service.totalCapacityGB) {
                Text("GB")
            } currentValueLabel: {
                WidgetDataText.gigabytes(service.remainingGB, size: 14, weight: .semibold, compact: true)
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Text("-")
                .font(.caption)
        }
    }
}

struct RemainingDataInlineAccessory: View {
    let presentation: RemainingDataPresentation

    var body: some View {
        if presentation.showsSuccess {
            Text("更新完了")
        } else if presentation.isRefreshing {
            Text("更新中")
        } else if let service = presentation.service {
            WidgetDataText.inlineRemaining(for: service)
        } else {
            Text("データ未取得")
        }
    }
}

struct RemainingDataRectangularAccessory: View {
    let presentation: RemainingDataPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let service = presentation.service {
                Text(presentation.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                FilledLinearMeter(
                    ratio: service.remainingRatio,
                    colors: presentation.ringColors(for: service.remainingRatio)
                )
                .frame(height: 8)
                Text(
                    "残量 \(WidgetDataText.gigabytesWithUnit(service.remainingGB)) / \(WidgetDataText.gigabytesWithUnit(service.totalCapacityGB))"
                )
                .font(.footnote)
            } else {
                Text("IIJmioデータ未取得")
                    .font(.footnote)
            }
        }
    }
}
