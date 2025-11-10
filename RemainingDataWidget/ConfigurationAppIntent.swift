import AppIntents
import WidgetKit

struct RemainingDataConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "IIJmio"
    static var description = IntentDescription("IIJmioのデータ残量を表示します。")
}
