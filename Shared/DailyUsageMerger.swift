import Foundation

enum DailyUsageMerger {
    /// HTMLのhdoCodeをGAPI回線IDへ変換する。契約ID共有の回線を取り違えない。
    static func match(history: [DailyUsageService], lines: [TrafficSummary.ServiceInfo]) throws -> [DailyUsageService] {
        var seen = Set<String>()
        return try history.map { service in
            let direct = lines.filter { $0.id == service.lineID }
            let candidates = direct.isEmpty ? lines.filter { line in
                guard let phone = line.phoneNo?.filter(\.isNumber), !phone.isEmpty else { return false }
                let title = service.titlePrimary.filter(\.isNumber)
                let detail = (service.titleDetail ?? "").replacingOccurrences(of: "-", with: "")
                return title == phone || detail.contains(phone)
            } : direct
            guard candidates.count == 1, let line = candidates.first,
                  seen.insert(line.id).inserted else { throw WidgetRefreshError.unmatchedThirtyDayLine }
            return DailyUsageService(lineID: line.id, titlePrimary: line.displayPlanName,
                                     titleDetail: line.phoneNo, entries: service.entries)
        }
    }

    /// GAPIの実測値を優先し、過去30日・低速データだけを補完する。
    static func merge(history: [DailyUsageService], current: [DailyUsageService]) -> [DailyUsageService] {
        let historyByID = Dictionary(history.map { ($0.lineID, $0) }, uniquingKeysWith: { _, last in last })
        return current.map { service in
            var entries = Dictionary((historyByID[service.lineID]?.entries ?? []).map { ($0.dateLabel, $0) },
                                     uniquingKeysWith: { _, last in last })
            for entry in service.entries where entry.hasData {
                let previous = entries[entry.dateLabel]
                entries[entry.dateLabel] = DailyUsageEntry(
                    dateLabel: entry.dateLabel,
                    highSpeedMB: entry.highSpeedMB ?? previous?.highSpeedMB,
                    lowSpeedMB: entry.lowSpeedMB ?? previous?.lowSpeedMB,
                    note: entry.note, hasData: true
                )
            }
            return DailyUsageService(lineID: service.lineID, titlePrimary: service.titlePrimary,
                                     titleDetail: service.titleDetail,
                                     entries: entries.values.sorted { $0.dateLabel > $1.dateLabel })
        }
    }
}
