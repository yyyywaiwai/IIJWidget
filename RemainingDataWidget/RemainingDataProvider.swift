import WidgetKit

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

    func placeholder(in context: Context) -> RemainingDataEntry {
        previewEntry()
    }

    func snapshot(for configuration: Intent, in context: Context) async -> RemainingDataEntry {
        guard !context.isPreview else { return previewEntry() }
        let snapshot = store.loadSnapshot()
        return RemainingDataEntry(
            date: snapshot?.fetchedAt ?? Date(),
            snapshot: snapshot,
            accentColors: configuration.resolvedAccentSettings(using: accentStore)
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<RemainingDataEntry> {
        if context.isPreview {
            let entry = previewEntry()
            return Timeline(
                entries: [entry],
                policy: .after(entry.date.addingTimeInterval(WidgetTimelineSchedule.refreshInterval))
            )
        }

        let snapshot = await loadSnapshotForTimeline()
        let schedule = WidgetTimelineSchedule(snapshot: snapshot, now: Date())
        let accent = configuration.resolvedAccentSettings(using: accentStore)
        let entries = schedule.entries.map {
            RemainingDataEntry(date: $0.date, snapshot: $0.snapshot, accentColors: accent)
        }
        return Timeline(entries: entries, policy: .after(schedule.refreshDate))
    }

    private func previewEntry() -> RemainingDataEntry {
        RemainingDataEntry(date: Date(), snapshot: .placeholder, accentColors: accentStore.load())
    }

    private func loadSnapshotForTimeline() async -> WidgetSnapshot? {
        let cached = store.loadSnapshot()
        guard cached?.isRefreshing != true else { return cached }

        do {
            let outcome = try await refreshService.refreshForWidget()
            logStore.append(trigger: .widgetAutomatic, result: .success)
            if let snapshot = WidgetSnapshot(payload: outcome.payload, fallback: cached) {
                return snapshot
            }
        } catch {
            logStore.append(
                trigger: .widgetAutomatic,
                result: .failure,
                errorDescription: error.localizedDescription
            )
        }
        // 初回取得前や通信失敗時も、保存済みの値を引き続き表示する。
        return store.loadSnapshot()
    }
}
