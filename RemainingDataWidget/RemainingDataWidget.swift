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
    private let logStore = RefreshLogStore()
    private let displayPreferenceStore = DisplayPreferencesStore()

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
        let now = Date()
        let accent = resolveAccentColors(from: configuration)

        var entries: [RemainingDataEntry] = []
        let baseEntry = RemainingDataEntry(
            date: snapshot?.fetchedAt ?? now,
            snapshot: snapshot,
            accentColors: accent
        )
        entries.append(baseEntry)

        if let successUntil = snapshot?.successUntil, successUntil > now {
            let cleared = RemainingDataEntry(
                date: successUntil,
                snapshot: snapshot?.updatingSuccessUntil(nil),
                accentColors: accent
            )
            entries.append(cleared)
        }

        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func loadSnapshotForTimeline() async -> WidgetSnapshot? {
        let cached = store.loadSnapshot()
        if cached?.isRefreshing == true {
            return cached
        }

        let preferences = displayPreferenceStore.load()
        do {
            let outcome = try await refreshService.refreshForWidget(calculateTodayFromRemaining: preferences.calculateTodayFromRemaining)

            logStore.append(trigger: .widgetAutomatic, result: .success)
            
            if let snapshot = WidgetSnapshot(payload: outcome.payload, fallback: cached) {
                return snapshot
            }
        } catch WidgetRefreshError.missingCredentials {
            // 資格情報未設定時は保存済みスナップショットを返す
            logStore.append(
                trigger: .widgetAutomatic,
                result: .failure,
                errorDescription: WidgetRefreshError.missingCredentials.localizedDescription
            )
        } catch {
            print("[RemainingDataProvider] refresh failed: \(error.localizedDescription)")
            logStore.append(
                trigger: .widgetAutomatic,
                result: .failure,
                errorDescription: error.localizedDescription
            )
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

    private var showSuccess: Bool {
        if let until = entry.snapshot?.successUntil {
            return until > Date()
        }
        return false
    }

    private var circularView: some View {
        Group {
            if showSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
            } else if isRefreshing {
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
        if showSuccess {
            Text("更新完了")
        } else if isRefreshing {
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
                Text(showSuccess ? "更新完了" : (isRefreshing ? "更新中..." : service.serviceName))
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if showSuccess {
                        successStatusLabel
                    }
                    if isRefreshing {
                        refreshStatusLabel
                    }
                    refreshButton
                }
                if isRefreshing {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("更新中")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                } else if let service = entry.snapshot?.primaryService {
                    HStack {
                        Spacer(minLength: 0)
                        circularMeter(for: service, size: 100)
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

    private var mediumView: some View {
        cardBackground(alignment: .top) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "simcard.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: ringColors(for: entry.snapshot?.primaryService.map { remainingRatio(for: $0) } ?? 0.5),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(showSuccess ? "更新完了" : (isRefreshing ? "更新中..." : (entry.snapshot?.primaryService?.serviceName ?? "IIJmio")))
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    if showSuccess {
                        successStatusLabel
                    }
                    if isRefreshing {
                        refreshStatusLabel
                    }
                    refreshButton
                }
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let service = entry.snapshot?.primaryService {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(service.remainingGB, specifier: "%.2f")")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                Text("GB")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .monospacedDigit()

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text(formatted(date: entry.snapshot?.fetchedAt ?? entry.date))
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
                    Spacer()
                    if let service = entry.snapshot?.primaryService {
                        circularMeter(for: service, size: 88)
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

    private func circularMeter(for service: WidgetServiceSnapshot, size: CGFloat, lineWidth: CGFloat = 10) -> some View {
        let ratio = min(max(service.remainingGB / service.totalCapacityGB, 0), 1)
        let colors = ringColors(for: ratio)
        let adjustedLineWidth = size * 0.11

        return ZStack {
            // 背景トラック
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: adjustedLineWidth)

            // プログレスリング
            Circle()
                .trim(from: 0, to: CGFloat(max(0.03, ratio)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: colors + [colors.first ?? .blue]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: adjustedLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // 中央テキスト
            VStack(spacing: 1) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Text(shortGB(service.remainingGB))
                        .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("残")
                        .font(.system(size: size * 0.11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
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

    @ViewBuilder
    private var refreshButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
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
        } else {
            LegacyRefreshSymbol()
                .foregroundStyle(.secondary)
                .padding(6)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )
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

            ZStack(alignment: .leading) {
                // 背景トラック
                Capsule()
                    .fill(Color.white.opacity(0.15))

                // プログレスバー
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(width, proxy.size.height))
            }
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
