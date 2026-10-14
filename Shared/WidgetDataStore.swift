import Foundation

struct WidgetDataStore {
    private let key = "gapi.widget.snapshot.v2"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save(snapshot: WidgetSnapshot) {
        guard let defaults = AppGroup.userDefaults, let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func loadSnapshot() -> WidgetSnapshot? {
        guard let defaults = AppGroup.userDefaults, let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    func setRefreshingState(_ isRefreshing: Bool) -> Bool {
        updateSnapshot { $0.updatingRefreshingState(isRefreshing) }
        return true
    }

    func setSuccessUntil(_ date: Date?) {
        updateSnapshot { $0.updatingSuccessUntil(date) }
    }

    func clear() {
        AppGroup.userDefaults?.removeObject(forKey: key)
    }

    private func updateSnapshot(_ transform: (WidgetSnapshot) -> WidgetSnapshot) {
        let snapshot = loadSnapshot() ?? WidgetSnapshot(fetchedAt: Date(), primaryService: nil)
        save(snapshot: transform(snapshot))
    }
}
