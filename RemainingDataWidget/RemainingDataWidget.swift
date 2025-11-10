import SwiftUI
import WidgetKit
import AppIntents

struct RemainingDataEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct RemainingDataProvider: TimelineProvider {
    private let store = WidgetDataStore()

    func placeholder(in context: Context) -> RemainingDataEntry {
        RemainingDataEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RemainingDataEntry) -> Void) {
        if context.isPreview {
            completion(RemainingDataEntry(date: Date(), snapshot: .placeholder))
        } else {
            let snapshot = store.loadSnapshot()
            completion(RemainingDataEntry(date: snapshot?.fetchedAt ?? Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemainingDataEntry>) -> Void) {
        let snapshot = store.loadSnapshot()
        let entryDate = snapshot?.fetchedAt ?? Date()
        let entry = RemainingDataEntry(date: entryDate, snapshot: snapshot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct RemainingDataWidgetEntryView: View {
    let entry: RemainingDataProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        widgetContent
            .containerBackground(.fill, for: .widget)
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        case .accessoryRectangular:
            rectangularView
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    private var circularView: some View {
        Group {
            if let service = entry.snapshot?.primaryService {
                Gauge(value: service.remainingGB, in: 0...service.totalCapacityGB) {
                    Text("残")
                } currentValueLabel: {
                    Text(shortGB(service.remainingGB))
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                Text("-")
                    .font(.caption)
            }
        }
    }

    private var inlineView: some View {
        if let service = entry.snapshot?.primaryService {
            Text("残\(shortGB(service.remainingGB)) / \(shortGB(service.totalCapacityGB))")
        } else {
            Text("データ未取得")
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let service = entry.snapshot?.primaryService {
                Text(service.serviceName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Gauge(value: service.usedRatio) {
                    Text("使用")
                }
                .gaugeStyle(.accessoryLinear)
                Text("残量 \(shortGB(service.remainingGB)) / \(shortGB(service.totalCapacityGB))")
                    .font(.footnote)
            } else {
                Text("IIJmioデータ未取得")
                    .font(.footnote)
            }
        }
    }

    private var smallView: some View {
        cardBackground(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    refreshButton
                }
                if let service = entry.snapshot?.primaryService {
                    HStack {
                        Spacer(minLength: 0)
                        circularMeter(for: service, size: 96)
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("データ未取得")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var mediumView: some View {
        cardBackground(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(entry.snapshot?.primaryService?.serviceName ?? "IIJmio")
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    refreshButton
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let service = entry.snapshot?.primaryService {
                            Text("\(detailedGB(service.remainingGB)) / \(detailedGB(service.totalCapacityGB))")
                                .font(.headline)
                        } else {
                            Text("データ未取得")
                                .font(.headline)
                        }
                        Text("更新 \(formatted(date: entry.snapshot?.fetchedAt ?? entry.date))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let service = entry.snapshot?.primaryService {
                        circularMeter(for: service, size: 90)
                    } else {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.secondary)
                            .frame(width: 90, height: 90)
                    }
                }
            }
        }
    }

    private func circularMeter(for service: WidgetServiceSnapshot, size: CGFloat) -> some View {
        let ratio = min(max(service.remainingGB / service.totalCapacityGB, 0), 1)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.05, 1 - service.usedRatio)))
                .stroke(
                    AngularGradient(colors: ringColors(for: ratio), center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(shortGB(service.remainingGB))
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                Text("残")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var refreshButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: RefreshWidgetIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        } else {
            Image(systemName: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ringColors(for ratio: Double) -> [Color] {
        switch ratio {
        case 0.5...:
            return [Color.green, Color.teal]
        case 0.2...:
            return [Color.orange, Color.yellow]
        default:
            return [Color.red, Color.pink]
        }
    }

    private func cardBackground<Content: View>(
        alignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding()
    }

    private func shortGB(_ value: Double) -> String {
        if value >= 10 {
            return String(format: "%.0fGB", value)
        } else {
            return String(format: "%.1fGB", value)
        }
    }

    private func detailedGB(_ value: Double) -> String {
        String(format: "%.2fGB", value)
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct RemainingDataWidget: Widget {
    let kind = WidgetKind.remainingData

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RemainingDataProvider()) { entry in
            RemainingDataWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("データ残量")
        .description("IIJmioの残りデータ容量を表示します。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}
