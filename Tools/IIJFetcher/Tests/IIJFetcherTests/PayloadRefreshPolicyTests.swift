import XCTest
@testable import IIJFetcher

final class PayloadRefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_810_000)

    private func payload(lineIDs: [String] = ["line-a"], at date: Date? = nil) -> AggregatePayload {
        AggregatePayload(
            fetchedAt: date ?? now,
            top: TrafficSummary(serviceInfoList: lineIDs.map {
                .init(id: $0, serviceCode: nil, groupServiceCode: nil, totalCapacity: 10,
                      remainingDataGB: 5, planName: "Fixture", phoneNo: nil)
            }),
            bill: .init(billList: [.init(billingNumber: "bill", month: "202610", totalAmount: 1000, isUnpaid: false)]),
            serviceStatus: .init(serviceInfoList: []),
            monthlyUsage: [],
            dailyUsage: [daily(line: lineIDs.first ?? "line-a", day: "2026-10-12", amount: 100)]
        )
    }

    private func daily(line: String, day: String, amount: Double) -> DailyUsageService {
        .init(lineID: line, titlePrimary: line, titleDetail: nil,
              entries: [.init(dateLabel: day, highSpeedMB: amount, lowSpeedMB: nil, note: nil, hasData: true)])
    }

    func testHistoryReuse_RequiresCacheAndAllowsSameTokyoDay() {
        XCTAssertFalse(PayloadRefreshPolicy.canReuseHistory(cached: nil, forceUpdate: false,
                                                            needsFreshMonthlyUsage: false, now: now))
        XCTAssertTrue(PayloadRefreshPolicy.canReuseHistory(cached: payload(), forceUpdate: false,
                                                           needsFreshMonthlyUsage: false, now: now))
        XCTAssertFalse(PayloadRefreshPolicy.canReuseHistory(cached: payload(), forceUpdate: true,
                                                            needsFreshMonthlyUsage: false, now: now))
        XCTAssertFalse(PayloadRefreshPolicy.canReuseHistory(cached: payload(), forceUpdate: false,
                                                            needsFreshMonthlyUsage: true, now: now))
    }

    func testHistoryReuse_ExpiresAtTokyoMidnight() throws {
        let calendar = UsageDateLabel.calendar
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 13)))
        let cached = payload(at: midnight.addingTimeInterval(-1))
        XCTAssertTrue(PayloadRefreshPolicy.canReuseHistory(cached: cached, forceUpdate: false,
                                                           needsFreshMonthlyUsage: false, now: midnight.addingTimeInterval(-1)))
        XCTAssertFalse(PayloadRefreshPolicy.canReuseHistory(cached: cached, forceUpdate: false,
                                                            needsFreshMonthlyUsage: false, now: midnight))
    }

    func testTopMerge_PreservesHistoryTimestampAndBillingButUsesFreshDailyValues() throws {
        let cached = payload()
        let freshDaily = [daily(line: "line-a", day: "2026-10-12", amount: 200)]
        let fetchedAt = now.addingTimeInterval(60)
        let result = try XCTUnwrap(PayloadRefreshPolicy.mergingTop(cached.top, dailyUsage: freshDaily,
                                                                  into: cached, now: fetchedAt))
        XCTAssertEqual(result.fetchedAt, fetchedAt)
        XCTAssertEqual(result.historyFetchedAt, cached.historyFetchedAt)
        XCTAssertEqual(result.bill.billList.first?.totalAmount, 1000)
        XCTAssertEqual(result.dailyUsage.first?.entries.first?.highSpeedMB, 200)
        XCTAssertNil(result.thirtyDayUsage)
    }

    func testTopMerge_RejectsChangedLinesAndAcceptsReordering() {
        let cached = payload(lineIDs: ["line-a", "line-b"])
        XCTAssertNotNil(PayloadRefreshPolicy.mergingTop(payload(lineIDs: ["line-b", "line-a"]).top,
                                                       dailyUsage: [], into: cached))
        for ids in [["line-a"], ["line-a", "line-c"], []] {
            XCTAssertNil(PayloadRefreshPolicy.mergingTop(payload(lineIDs: ids).top, dailyUsage: [], into: cached))
        }
    }

    func testRetainingHistory_KeepsOnlyCurrentLinesWithoutReplacingGAPI() {
        var cached = payload(lineIDs: ["line-a", "line-b"])
        cached.thirtyDayUsage = [daily(line: "line-a", day: "2026-10-12", amount: 999),
                                daily(line: "line-b", day: "2026-10-12", amount: 999)]
        let fresh = payload()
        let result = PayloadRefreshPolicy.retainingHistory(in: fresh, from: cached)
        XCTAssertEqual(result.thirtyDayUsage?.map(\.lineID), ["line-a"])
        XCTAssertEqual(result.dailyUsage, fresh.dailyUsage)
        XCTAssertEqual(result.dailyUsageWithHistory.first?.entries.first?.highSpeedMB, 100)
        XCTAssertNil(PayloadRefreshPolicy.retainingHistory(in: fresh, from: nil).thirtyDayUsage)
    }
}
