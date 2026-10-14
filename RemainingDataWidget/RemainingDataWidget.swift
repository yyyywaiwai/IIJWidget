import SwiftUI
import WidgetKit

struct RemainingDataWidget: Widget {
    let kind = WidgetKind.remainingData

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: RemainingDataConfigurationIntent.self,
            provider: RemainingDataProvider()
        ) { entry in
            RemainingDataWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("データ残量")
        .description("IIJmioの残りデータ容量を表示します。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

struct RemainingDataWidgetEntryView: View {
    let entry: RemainingDataEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        widgetContent
            .containerBackground(.fill, for: .widget)
    }

    @ViewBuilder
    private var widgetContent: some View {
        let presentation = RemainingDataPresentation(entry: entry)
        // ロック画面では Button/Link を付けず、WidgetKit 標準のアプリ起動を維持する。
        switch family {
        case .accessoryCircular:
            RemainingDataCircularAccessory(presentation: presentation)
        case .accessoryInline:
            RemainingDataInlineAccessory(presentation: presentation)
        case .accessoryRectangular:
            RemainingDataRectangularAccessory(presentation: presentation)
        case .systemSmall:
            RemainingDataSmallView(presentation: presentation)
        default:
            RemainingDataMediumView(presentation: presentation)
        }
    }
}
