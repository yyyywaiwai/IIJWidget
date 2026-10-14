import Foundation

/// Cache decisions are kept separate from authentication, network requests and persistence.
enum PayloadRefreshPolicy {
    static func canReuseHistory(
        cached: AggregatePayload?,
        forceUpdate: Bool,
        needsFreshMonthlyUsage: Bool,
        now: Date = Date(),
        calendar: Calendar = UsageDateLabel.calendar
    ) -> Bool {
        guard let cached, !forceUpdate, !needsFreshMonthlyUsage else { return false }
        return calendar.isDate(cached.historyFetchedAt, inSameDayAs: now)
    }

    static func hasSameLines(_ first: TrafficSummary, _ second: TrafficSummary) -> Bool {
        Set(first.serviceInfoList.map(\.id)) == Set(second.serviceInfoList.map(\.id))
    }

    /// A partial refresh is valid only for the same set of lines. Otherwise the caller
    /// must request a full payload so billing, contracts and monthly usage stay aligned.
    static func mergingTop(
        _ top: TrafficSummary,
        dailyUsage: [DailyUsageService],
        into cached: AggregatePayload,
        now: Date = Date()
    ) -> AggregatePayload? {
        guard hasSameLines(top, cached.top) else { return nil }
        return AggregatePayload(
            fetchedAt: now,
            top: top,
            bill: cached.bill,
            serviceStatus: cached.serviceStatus,
            monthlyUsage: cached.monthlyUsage,
            dailyUsage: DailyUsageMerger.merge(history: cached.dailyUsage, current: dailyUsage),
            billDetails: cached.billDetails,
            historyFetchedAt: cached.historyFetchedAt
        )
    }

    /// The legacy history is supplemental data, never the source of current GAPI values.
    static func retainingHistory(
        in fetched: AggregatePayload,
        from cached: AggregatePayload?
    ) -> AggregatePayload {
        var result = fetched
        let lineIDs = Set(fetched.top.serviceInfoList.map(\.id))
        result.thirtyDayUsage = cached?.thirtyDayUsage?.filter { lineIDs.contains($0.lineID) }
        return result
    }
}
