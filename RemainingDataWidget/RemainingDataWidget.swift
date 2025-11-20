import SwiftUI
import WidgetKit
import AppIntents

struct RemainingDataEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let accentColors: AccentColorSettings
}

struct RemainingDataProvider: AppIntentTimelineProvider {
    typealias Intent = RemainingDataConfigurationIntent
    private let store = WidgetDataStore()
    private let refreshService = WidgetRefreshService()
    private let accentStore = AccentColorStore()

    func placeholder(in context: Context) -> RemainingDataEntry {
        RemainingDataEntry(date: Date(), snapshot: .placeholder, accentColors: accentStore.load())
    }

    func snapshot(for configuration: RemainingDataConfigurationIntent, in context: Context) async -> RemainingDataEntry {
        if context.isPreview {
            return RemainingDataEntry(date: Date(), snapshot: .placeholder, accentColors: accentStore.load())
        }
        let snapshot = store.loadSnapshot()
        return RemainingDataEntry(
            date: snapshot?.fetchedAt ?? Date(),
            snapshot: snapshot,
            accentColors: resolveAccentColors(from: configuration)
        )
    }

    func timeline(for configuration: RemainingDataConfigurationIntent, in context: Context) async -> Timeline<RemainingDataEntry> {
        if context.isPreview {
            let previewEntry = RemainingDataEntry(date: Date(), snapshot: .placeholder, accentColors: accentStore.load())
            return Timeline(entries: [previewEntry], policy: .after(Date().addingTimeInterval(1800)))
        }

        let snapshot = await loadSnapshotForTimeline()
        let entryDate = snapshot?.fetchedAt ?? Date()
        let entry = RemainingDataEntry(
            date: entryDate,
            snapshot: snapshot,
            accentColors: resolveAccentColors(from: configuration)
        )
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func loadSnapshotForTimeline() async -> WidgetSnapshot? {
        if let cached = store.loadSnapshot(), cached.isRefreshing {
            return cached
        }

        do {
            let outcome = try await refreshService.refresh(
                manualCredentials: nil,
                persistManualCredentials: false,
                allowSessionReuse: true,
                allowKeychainFallback: true
            )
            
            // Check usage alerts after successful refresh
            await UsageAlertChecker().checkUsageAlerts(payload: outcome.payload)
            
            if let snapshot = WidgetSnapshot(payload: outcome.payload) {
                return snapshot
            }
        } catch WidgetRefreshError.missingCredentials {
            // 資格情報未設定時は保存済みスナップショットを返す
        } catch {
            print("[RemainingDataProvider] refresh failed: \(error.localizedDescription)")
        }
        return store.loadSnapshot()
    }

    private func resolveAccentColors(from configuration: RemainingDataConfigurationIntent) -> AccentColorSettings {
        configuration.resolvedAccentSettings(using: accentStore)
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
            lockScreenRefreshWrapper {
                circularView
            }
        case .accessoryInline:
            lockScreenRefreshWrapper {
                inlineView
            }
        case .accessoryRectangular:
            lockScreenRefreshWrapper {
                rectangularView
            }
        case .systemSmall:
            smallView
        default:
            mediumView
        }
    }

    @ViewBuilder
    private func lockScreenRefreshWrapper<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: RefreshWidgetIntent()) {
                RefreshPulseContainer(isRefreshing: isRefreshing, content: content)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            content()
        }
    }

    private var isRefreshing: Bool {
        entry.snapshot?.isRefreshing == true
    }

    private var circularView: some View {
        Group {
            if isRefreshing {
                refreshingCircular
            } else if let service = entry.snapshot?.primaryService {
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

    private var refreshingCircular: some View {
        ZStack {
            Circle()
                .strokeBorder(.primary.opacity(0.2), lineWidth: 4)
            Text("更新中")
                .font(.caption2.weight(.semibold))
        }
    }

    private var inlineView: some View {
        if isRefreshing {
            Text("更新中")
        } else if let service = entry.snapshot?.primaryService {
            Text("残\(shortGB(service.remainingGB)) / \(shortGB(service.totalCapacityGB))")
        } else {
            Text("データ未取得")
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let service = entry.snapshot?.primaryService {
                Text(isRefreshing ? "更新中..." : service.serviceName)
                    .font(.caption)
                    .fontWeight(.semibold)
                FilledLinearMeter(
                    ratio: remainingRatio(for: service),
                    colors: ringColors(for: remainingRatio(for: service))
                )
                .frame(height: 8)
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
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if isRefreshing {
                        refreshStatusLabel
                    }
                    refreshButton
                }
                if isRefreshing {
                    Text("更新中...")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
                } else if let service = entry.snapshot?.primaryService {
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
                    Text(isRefreshing ? "更新中..." : (entry.snapshot?.primaryService?.serviceName ?? "IIJmio"))
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    if isRefreshing {
                        refreshStatusLabel
                    }
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

    private func circularMeter(for service: WidgetServiceSnapshot, size: CGFloat, lineWidth: CGFloat = 10) -> some View {
        let ratio = min(max(service.remainingGB / service.totalCapacityGB, 0), 1)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.05, 1 - service.usedRatio)))
                .stroke(
                    AngularGradient(colors: ringColors(for: ratio), center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if isRefreshing {
                    Text("更新中...")
                        .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else {
                    Text(shortGB(service.remainingGB))
                        .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    Text("残")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var refreshStatusLabel: some View {
        Text("更新中...")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            )
    }

    @ViewBuilder
    private var refreshButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: RefreshWidgetIntent()) {
                RefreshSymbol(isRefreshing: isRefreshing)
            }
            .buttonStyle(.borderless)
        } else {
            LegacyRefreshSymbol()
                .foregroundStyle(.secondary)
        }
    }

    private func ringColors(for ratio: Double) -> [Color] {
        entry.accentColors.widgetRingColors(for: ratio)
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

    private func remainingRatio(for service: WidgetServiceSnapshot) -> Double {
        guard service.totalCapacityGB > 0 else { return 0 }
        return min(max(service.remainingGB / service.totalCapacityGB, 0), 1)
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct FilledLinearMeter: View {
    let ratio: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(ratio, 0), 1)
            let width = proxy.size.width * clamped
            Capsule()
                .fill(Color.white.opacity(0.2))
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: max(width, proxy.size.height))
        }
        .compositingGroup()
        .clipped()
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct RefreshSymbol: View {
    let isRefreshing: Bool

    var body: some View {
        if isRefreshing {
            glyph
                .symbolEffect(
                    .pulse,
                    options: .repeat(Int.max),
                    value: isRefreshing
                )
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Image(systemName: "arrow.clockwise")
            .font(.caption)
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct RefreshPulseContainer<Content: View>: View {
    let isRefreshing: Bool
    let content: () -> Content

    var body: some View {
        if isRefreshing {
            TimelineView(.periodic(from: .now, by: 0.9)) { context in
                content()
                    .opacity(opacity(for: context.date))
            }
        } else {
            content()
        }
    }

    private func opacity(for date: Date) -> Double {
        let cycle: Double = 0.9
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        // triangle wave between 0.5 and 1.0
        let triangle = phase <= 0.5 ? phase * 2 : (1 - phase) * 2
        return 0.5 + (triangle * 0.5)
    }
}

private struct LegacyRefreshSymbol: View {
    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.caption)
    }
}

struct RemainingDataWidget: Widget {
    let kind = WidgetKind.remainingData

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: RemainingDataConfigurationIntent.self, provider: RemainingDataProvider()) { entry in
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
