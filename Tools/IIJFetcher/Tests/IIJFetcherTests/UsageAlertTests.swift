import Foundation
import XCTest
@testable import IIJFetcher

final class UsageAlertTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_471_600) // 2026-10-09 00:00 JST

    private func payload(at date: Date, daily: Double? = 101, monthly: Double? = 2,
                         hasData: Bool = true, historyFetchedAt: Date? = nil) -> AggregatePayload {
        let parts = UsageDateLabel.calendar.dateComponents([.year, .month, .day], from: date)
        let month = String(format: "%04d年%02d月", parts.year!, parts.month!)
        let day = String(format: "%04d年%02d月%02d日", parts.year!, parts.month!, parts.day!)
        return AggregatePayload(
            fetchedAt: date,
            top: TrafficSummary(serviceInfoList: [TrafficSummary.ServiceInfo(
                id: "line-1", serviceCode: "service", groupServiceCode: nil, totalCapacity: 5,
                remainingDataGB: 3, planName: "テスト", phoneNo: "09000000001")]),
            bill: BillSummaryResponse(billList: []),
            serviceStatus: ServiceStatusResponse(serviceInfoList: []),
            monthlyUsage: [MonthlyUsageService(lineID: "line-1", titlePrimary: "テスト", titleDetail: nil,
                entries: [MonthlyUsageEntry(monthLabel: month, highSpeedGB: monthly,
                                            lowSpeedGB: nil, note: nil, hasData: hasData)])],
            dailyUsage: [DailyUsageService(lineID: "line-1", titlePrimary: "テスト", titleDetail: nil,
                entries: [DailyUsageEntry(dateLabel: day, highSpeedMB: daily,
                                          lowSpeedMB: nil, note: nil, hasData: hasData)])],
            historyFetchedAt: historyFetchedAt
        )
    }

    private func alerts(_ payload: AggregatePayload, account: String = "account-1",
                        settings: UsageAlertSettings = UsageAlertSettings(
                            isEnabled: true, monthlyThresholdMB: 1024, dailyThresholdMB: 100),
                        now: Date? = nil, daily: [DailyUsageService]? = nil) -> [UsageAlert] {
        UsageAlert.candidates(payload: payload, freshDailyUsage: daily ?? payload.dailyUsage,
                              settings: settings, accountID: account, now: now ?? self.now)
    }

    func testUsageAlerts_CurrentPeriodsAndValidMeasurementsOnly() throws {
        let current = payload(at: now)
        let first = alerts(current)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first, alerts(current))
        XCTAssertTrue(first.allSatisfy { !$0.identifier.contains("account") && !$0.body.contains("09000000001") })
        XCTAssertTrue(Set(first.map(\.identifier)).isDisjoint(with: alerts(current, account: "account-2").map(\.identifier)))
        XCTAssertTrue(alerts(current, settings: .default).isEmpty)
        XCTAssertTrue(alerts(current, account: "").isEmpty)
        XCTAssertTrue(alerts(current, settings: UsageAlertSettings(
            isEnabled: true, monthlyThresholdMB: -1, dailyThresholdMB: 0)).isEmpty)
        XCTAssertTrue(alerts(payload(at: now, daily: 100, monthly: 1)).isEmpty)
        XCTAssertTrue(alerts(payload(at: now, daily: nil, monthly: nil)).isEmpty)
        XCTAssertTrue(alerts(payload(at: now, hasData: false)).isEmpty)
        XCTAssertTrue(alerts(payload(at: now, daily: .nan, monthly: .infinity)).isEmpty)
        XCTAssertTrue(alerts(payload(at: now, daily: -1, monthly: -1)).isEmpty)
        XCTAssertEqual(alerts(current, daily: []).count, 1)
        XCTAssertEqual(alerts(payload(at: now, historyFetchedAt: now.addingTimeInterval(-60))).count, 1)
        XCTAssertFalse(UsageAlertSettings.default.needsFreshMonthlyUsage)
        XCTAssertTrue(UsageAlertSettings(isEnabled: true, monthlyThresholdMB: 1, dailyThresholdMB: nil).needsFreshMonthlyUsage)

        let nextDay = try XCTUnwrap(UsageDateLabel.calendar.date(byAdding: .day, value: 1, to: now))
        let nextMonth = try XCTUnwrap(UsageDateLabel.calendar.date(byAdding: .month, value: 1, to: now))
        XCTAssertEqual(alerts(current, now: nextDay).count, 1)
        XCTAssertEqual(alerts(payload(at: now.addingTimeInterval(-1))).count, 1)
        XCTAssertTrue(alerts(current, now: nextMonth).isEmpty)
        let tomorrow = alerts(payload(at: nextDay), now: nextDay)
        XCTAssertEqual(first[0].identifier, tomorrow[0].identifier)
        XCTAssertNotEqual(first[1].identifier, tomorrow[1].identifier)

        let withLowSpeed = AggregatePayload(fetchedAt: now, top: current.top, bill: current.bill,
            serviceStatus: current.serviceStatus, monthlyUsage: [],
            dailyUsage: [DailyUsageService(lineID: "line-1", titlePrimary: "テスト", titleDetail: nil,
                entries: [DailyUsageEntry(dateLabel: current.dailyUsage[0].entries[0].dateLabel,
                    highSpeedMB: 90, lowSpeedMB: 11, note: nil, hasData: true)])])
        XCTAssertEqual(alerts(withLowSpeed).count, 1)
        let unrelatedLine = DailyUsageService(lineID: "deleted-line", titlePrimary: "旧回線", titleDetail: nil,
                                              entries: withLowSpeed.dailyUsage[0].entries)
        XCTAssertTrue(alerts(withLowSpeed, daily: [unrelatedLine]).isEmpty)
    }

    func testDelivery_DeduplicationFailureRetryAndConcurrentRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let delivery = UsageAlertDelivery(directory: directory)
        let candidates = alerts(payload(at: now))
        var sent: [String] = []
        do {
            try await delivery.deliver(candidates, now: now) { alert in
                if alert == candidates[1] { throw CocoaError(.fileWriteUnknown) }
                sent.append(alert.identifier)
                // 別インスタンス（Widget側）との競合でも配送を重ねない。
                try await UsageAlertDelivery(directory: directory).deliver(candidates, now: self.now) { _ in
                    XCTFail("Concurrent delivery must not enter the locked section")
                }
            }
            XCTFail("A rejected notification must propagate an error")
        } catch CocoaError.fileWriteUnknown {}
        XCTAssertEqual(sent, [candidates[0].identifier])

        try await delivery.deliver(candidates, now: now) { sent.append($0.identifier) }
        XCTAssertEqual(sent, candidates.map(\.identifier))
        try await UsageAlertDelivery(directory: directory).deliver(candidates, now: now) { _ in
            XCTFail("A fresh instance must retain delivery history")
        }
        let nextDay = try XCTUnwrap(UsageDateLabel.calendar.date(byAdding: .day, value: 1, to: now))
        try await delivery.deliver(alerts(payload(at: nextDay), now: nextDay), now: nextDay) {
            sent.append($0.identifier)
        }
        XCTAssertEqual(sent.count, 3)
        try await delivery.deliver([UsageAlert(identifier: "expired", body: "", expiresAt: now)], now: nextDay) { _ in
            XCTFail("Expired periods must not notify")
        }

        try Data("broken".utf8).write(to: directory.appendingPathComponent("usage-alert-delivery.json"))
        do {
            try await delivery.deliver(candidates, now: now) { _ in
                XCTFail("Corrupt history must not cause a notification flood")
            }
            XCTFail("Corrupt history must be reported")
        } catch is DecodingError {}
    }
}
