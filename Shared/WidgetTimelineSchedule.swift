import Foundation

/// WidgetKit 非依存のスケジュール。更新完了の表示期限も次の取得時刻と分離して扱う。
struct WidgetTimelineSchedule {
    struct Entry {
        let date: Date
        let snapshot: WidgetSnapshot?
    }

    static let refreshInterval: TimeInterval = 30 * 60

    let entries: [Entry]
    let refreshDate: Date

    init(snapshot: WidgetSnapshot?, now: Date) {
        var entries = [Entry(date: snapshot?.fetchedAt ?? now, snapshot: snapshot)]
        if let snapshot, let successUntil = snapshot.successUntil, snapshot.showsSuccess(at: now) {
            entries.append(Entry(date: successUntil, snapshot: snapshot.updatingSuccessUntil(nil)))
        }
        self.entries = entries
        refreshDate = now.addingTimeInterval(Self.refreshInterval)
    }
}
