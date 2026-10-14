import Foundation
import XCTest
@testable import IIJFetcher

final class ChartDataBuilderTests: XCTestCase {
    func testMonthlyAggregation_sumsLinesAndIgnoresUnavailableValues() throws {
        let first = monthlyService("first", entries: [
            monthlyEntry("2026-10", high: 1.5, low: 0.5),
            monthlyEntry("2026-09", high: nil, low: 0.25),
            monthlyEntry("2026-08", high: 100, low: 100, hasData: false),
        ])
        let second = monthlyService("second", entries: [
            monthlyEntry("2026年10月", high: 2, low: nil),
            monthlyEntry("2026年09月", high: nil, low: nil),
        ])

        let points = monthlyChartPoints(from: [first, second])

        XCTAssertEqual(points.map(\.displayLabel), ["8月", "9月", "10月"])
        XCTAssertEqual(points.map(\.value), [0, 0.25, 4])
        XCTAssertEqual(points.map(\.id), points.map(\.rawKey))
        XCTAssertEqual(Set(points.map(\.id)).count, 3)
        XCTAssertNotNil(try XCTUnwrap(points.last).date)
    }

    func testMonthlyHistory_keepsLatestFourteenInChronologicalOrder() {
        let entries = (0..<16).map { offset in
            monthlyEntry(monthLabel(offset: offset), high: Double(offset), low: nil)
        }
        let points = monthlyChartPoints(from: [monthlyService("line", entries: entries.reversed())])

        XCTAssertEqual(points.count, 14)
        XCTAssertEqual(points.map(\.value), (2..<16).map(Double.init))
        XCTAssertEqual(points.map(\.sortKey), points.map(\.sortKey).sorted())
    }

    func testDailyAggregation_preservesMegabytesAndUnavailableDays() {
        let services = [
            dailyService("first", entries: [
                dailyEntry("2026-10-03", high: 300, low: 20),
                dailyEntry("2026-10-02", high: 999, low: nil, hasData: false),
            ]),
            dailyService("second", entries: [
                dailyEntry("2026年10月03日", high: 80, low: nil),
                dailyEntry("2026-10-01", high: nil, low: 5),
            ]),
        ]

        let points = dailyChartPoints(from: services)

        XCTAssertEqual(points.map(\.displayLabel), ["10/1", "10/2", "10/3"])
        XCTAssertEqual(points.map(\.value), [5, 0, 400])
    }

    func testDailyHistory_doesNotApplyMonthlyFourteenPointLimit() {
        let entries = (1...31).map { day in
            dailyEntry(String(format: "2026-10-%02d", day), high: Double(day), low: nil)
        }
        let points = dailyChartPoints(from: [dailyService("line", entries: entries.reversed())])

        XCTAssertEqual(points.count, 31)
        XCTAssertEqual(points.map(\.value), (1...31).map(Double.init))
    }

    func testDateLabels_acceptCompactDatesAndKeepUnparseableLabels() throws {
        let monthly = monthlyChartPoints(from: [monthlyService("line", entries: [
            monthlyEntry("202610", high: 1, low: nil),
        ])])
        let daily = dailyChartPoints(from: [dailyService("line", entries: [
            dailyEntry("20261013", high: 1, low: nil),
        ])])
        let unavailable = dailyChartPoints(from: [dailyService("line", entries: [
            dailyEntry("集計待ち", high: nil, low: nil, hasData: false),
        ])])

        XCTAssertEqual(monthly.first?.displayLabel, "10月")
        XCTAssertEqual(daily.first?.displayLabel, "10/13")
        let point = try XCTUnwrap(unavailable.first)
        XCTAssertEqual(point.id, "集計待ち")
        XCTAssertEqual(point.displayLabel, "集計待ち")
        XCTAssertEqual(point.value, 0)
        XCTAssertEqual(point.sortKey, 0)
        XCTAssertNil(point.date)
    }

    func testEmptySources_produceNoPoints() {
        XCTAssertTrue(monthlyChartPoints(from: []).isEmpty)
        XCTAssertTrue(dailyChartPoints(from: []).isEmpty)
        XCTAssertTrue(billingChartPoints(from: BillSummaryResponse(billList: [])).isEmpty)
    }

    func testBillingHistory_keepsLatestFourteenAndPreservesUnpaidState() {
        let entries: [BillSummaryResponse.BillEntry] = (0..<16).map { offset in
            let year = 2025 + offset / 12
            let month = offset % 12 + 1
            let label = String(format: "%04d%02d", year, month)
            return BillSummaryResponse.BillEntry(
                billingNumber: "bill-\(offset)",
                month: label,
                totalAmount: offset * 100,
                isUnpaid: offset == 15
            )
        }
        let bill = BillSummaryResponse(billList: entries.reversed())
        let points = billingChartPoints(from: bill)

        XCTAssertEqual(points.count, 14)
        XCTAssertEqual(points.map(\.id), (2..<16).map { "bill-\($0)" })
        XCTAssertEqual(points.map(\.value), (2..<16).map { Double($0 * 100) })
        XCTAssertEqual(points.filter(\.isUnpaid).map(\.id), ["bill-15"])
        XCTAssertEqual(bill.latestEntry?.billingNumber, "bill-15")
        XCTAssertEqual(points.last.map(billingAxisLabel), "4月")
    }

    func testBillingMissingFields_useExistingFallbacks() throws {
        let entry = BillSummaryResponse.BillEntry(
            billingNumber: nil, month: nil, totalAmount: nil, isUnpaid: nil
        )
        let point = try XCTUnwrap(billingChartPoints(from: BillSummaryResponse(billList: [entry])).first)

        XCTAssertEqual(point.id, "unknown")
        XCTAssertEqual(point.value, 0)
        XCTAssertFalse(point.isUnpaid)
        XCTAssertNil(point.date)
        XCTAssertEqual(billingAxisLabel(for: point), "-")
        XCTAssertEqual(entry.plainAmountText, "-")
    }

    func testUsagePoint_identityRemainsStableWhenValueChanges() {
        let original = point("20261013", value: 1)
        let updated = point("20261013", value: 2)

        XCTAssertEqual(original.id, updated.id)
        XCTAssertNotEqual(original, updated)
        XCTAssertEqual(original, point("20261013", value: 1))
        XCTAssertEqual(original.sortKey, 20261013)
    }

    func testDiscreteDomain_preservesHalfUnitPadding() {
        XCTAssertEqual(discreteDomain(forCount: 0), -0.5...0.5)
        XCTAssertEqual(discreteDomain(forCount: -1), -0.5...0.5)
        XCTAssertEqual(discreteDomain(forCount: 1), -0.5...0.5)
        XCTAssertEqual(discreteDomain(forCount: 7), -0.5...6.5)
    }

    private func monthlyService(_ id: String, entries: [MonthlyUsageEntry]) -> MonthlyUsageService {
        MonthlyUsageService(lineID: id, titlePrimary: id, titleDetail: nil, entries: entries)
    }

    private func dailyService(_ id: String, entries: [DailyUsageEntry]) -> DailyUsageService {
        DailyUsageService(lineID: id, titlePrimary: id, titleDetail: nil, entries: entries)
    }

    private func monthlyEntry(
        _ label: String, high: Double?, low: Double?, hasData: Bool = true
    ) -> MonthlyUsageEntry {
        MonthlyUsageEntry(monthLabel: label, highSpeedGB: high, lowSpeedGB: low, note: nil, hasData: hasData)
    }

    private func dailyEntry(
        _ label: String, high: Double?, low: Double?, hasData: Bool = true
    ) -> DailyUsageEntry {
        DailyUsageEntry(dateLabel: label, highSpeedMB: high, lowSpeedMB: low, note: nil, hasData: hasData)
    }

    private func monthLabel(offset: Int) -> String {
        String(format: "%04d-%02d", 2025 + offset / 12, offset % 12 + 1)
    }

    private func point(_ key: String, value: Double) -> UsageChartPoint {
        UsageChartPoint(rawKey: key, displayLabel: key, value: value, date: nil)
    }
}
