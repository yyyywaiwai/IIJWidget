import Foundation
import XCTest
@testable import IIJFetcher

final class WidgetTimelineScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSchedule_NoSnapshotStartsNowAndRefreshesAfterThirtyMinutes() throws {
        let schedule = WidgetTimelineSchedule(snapshot: nil, now: now)
        let entry = try XCTUnwrap(schedule.entries.first)

        XCTAssertEqual(schedule.entries.count, 1)
        XCTAssertEqual(entry.date, now)
        XCTAssertNil(entry.snapshot)
        XCTAssertEqual(WidgetTimelineSchedule.refreshInterval, 30 * 60)
        XCTAssertEqual(schedule.refreshDate, now.addingTimeInterval(30 * 60))
    }

    func testSchedule_CachedSnapshotRetainsFetchDateButRefreshUsesCurrentTime() throws {
        let snapshot = makeSnapshot()
        let schedule = WidgetTimelineSchedule(snapshot: snapshot, now: now)
        let entry = try XCTUnwrap(schedule.entries.first)

        XCTAssertEqual(schedule.entries.count, 1)
        XCTAssertEqual(entry.date, snapshot.fetchedAt)
        XCTAssertEqual(entry.snapshot, snapshot)
        XCTAssertEqual(schedule.refreshDate, now.addingTimeInterval(30 * 60))
    }

    func testSchedule_ActiveSuccessAddsEntryThatClearsOnlyDeadline() throws {
        let deadline = now.addingTimeInterval(5)
        let snapshot = makeSnapshot(successUntil: deadline)
        let schedule = WidgetTimelineSchedule(snapshot: snapshot, now: now)

        XCTAssertEqual(schedule.entries.count, 2)
        XCTAssertEqual(schedule.entries.first?.date, snapshot.fetchedAt)
        XCTAssertEqual(schedule.entries.first?.snapshot, snapshot)
        let expiryEntry = try XCTUnwrap(schedule.entries.last)
        let clearedSnapshot = try XCTUnwrap(expiryEntry.snapshot)
        XCTAssertEqual(expiryEntry.date, deadline)
        XCTAssertEqual(clearedSnapshot.fetchedAt, snapshot.fetchedAt)
        XCTAssertEqual(clearedSnapshot.primaryService, snapshot.primaryService)
        XCTAssertEqual(clearedSnapshot.isRefreshing, snapshot.isRefreshing)
        XCTAssertNil(clearedSnapshot.successUntil)
        XCTAssertEqual(schedule.refreshDate, now.addingTimeInterval(30 * 60))
    }

    func testSchedule_ExpiredSuccessDoesNotAddTimelineEntry() {
        for deadline in [now.addingTimeInterval(-5), now] {
            let snapshot = makeSnapshot(successUntil: deadline)
            let schedule = WidgetTimelineSchedule(snapshot: snapshot, now: now)

            XCTAssertEqual(schedule.entries.count, 1)
            XCTAssertEqual(schedule.entries.first?.snapshot, snapshot)
            XCTAssertEqual(schedule.refreshDate, now.addingTimeInterval(30 * 60))
        }
    }

    private func makeSnapshot(successUntil: Date? = nil) -> WidgetSnapshot {
        WidgetSnapshot(
            fetchedAt: now.addingTimeInterval(-120),
            primaryService: WidgetServiceSnapshot(
                serviceName: "ギガプラン",
                phoneNumber: "070-0000-0000",
                totalCapacityGB: 20,
                remainingGB: 12
            ),
            isRefreshing: true,
            successUntil: successUntil
        )
    }
}
