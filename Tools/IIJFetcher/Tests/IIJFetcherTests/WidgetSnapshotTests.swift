import Foundation
import XCTest
@testable import IIJFetcher

final class WidgetSnapshotTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testSnapshotCodable_PreservesAllFields() throws {
        let snapshot = makeSnapshot(isRefreshing: true, successUntil: fetchedAt.addingTimeInterval(5))

        let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(restored, snapshot)
    }

    func testSnapshotCodable_LegacyStateDefaultsToIdle() throws {
        var object = try encodedObject(makeSnapshot(isRefreshing: true, successUntil: fetchedAt))
        object.removeValue(forKey: "isRefreshing")
        object.removeValue(forKey: "successUntil")

        let snapshot = try decodeSnapshot(object)

        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.primaryService, makeService())
        XCTAssertFalse(snapshot.isRefreshing)
        XCTAssertNil(snapshot.successUntil)
    }

    func testSnapshotCodable_NullOptionalFieldsRemainCompatible() throws {
        var object = try encodedObject(makeSnapshot())
        object["primaryService"] = NSNull()
        object["isRefreshing"] = NSNull()
        object["successUntil"] = NSNull()

        let snapshot = try decodeSnapshot(object)

        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertNil(snapshot.primaryService)
        XCTAssertFalse(snapshot.isRefreshing)
        XCTAssertNil(snapshot.successUntil)
    }

    func testSnapshotCodable_MissingFetchDateIsRejected() throws {
        var object = try encodedObject(makeSnapshot())
        object.removeValue(forKey: "fetchedAt")

        XCTAssertThrowsError(try decodeSnapshot(object))
    }

    func testServiceRatios_ClampToZeroThroughOne() {
        let cases: [(total: Double, remaining: Double, used: Double, usedRatio: Double, remainingRatio: Double)] = [
            (20, 12, 8, 0.4, 0.6),
            (20, 20, 0, 0, 1),
            (20, 25, 0, 0, 1),
            (20, 0, 20, 1, 0),
            (20, -5, 25, 1, 0),
            (0, 5, 0, 0, 0),
            (-10, 5, 0, 0, 0)
        ]

        for item in cases {
            let service = makeService(total: item.total, remaining: item.remaining)
            let context = "total=\(item.total), remaining=\(item.remaining)"
            XCTAssertEqual(service.usedGB, item.used, accuracy: 0.000_001, context)
            XCTAssertEqual(service.usedRatio, item.usedRatio, accuracy: 0.000_001, context)
            XCTAssertEqual(service.remainingRatio, item.remainingRatio, accuracy: 0.000_001, context)
        }
    }

    func testUpdatingRefreshingState_PreservesSnapshotDataAndSuccessDeadline() {
        let deadline = fetchedAt.addingTimeInterval(5)
        let snapshot = makeSnapshot(successUntil: deadline)

        let refreshing = snapshot.updatingRefreshingState(true)

        XCTAssertEqual(refreshing.fetchedAt, snapshot.fetchedAt)
        XCTAssertEqual(refreshing.primaryService, snapshot.primaryService)
        XCTAssertEqual(refreshing.successUntil, deadline)
        XCTAssertTrue(refreshing.isRefreshing)
        XCTAssertFalse(snapshot.isRefreshing)
        XCTAssertEqual(refreshing.updatingRefreshingState(false), snapshot)
    }

    func testUpdatingSuccessUntil_PreservesSnapshotDataAndRefreshingState() {
        let snapshot = makeSnapshot(isRefreshing: true)
        let deadline = fetchedAt.addingTimeInterval(5)

        let successful = snapshot.updatingSuccessUntil(deadline)

        XCTAssertEqual(successful.fetchedAt, snapshot.fetchedAt)
        XCTAssertEqual(successful.primaryService, snapshot.primaryService)
        XCTAssertTrue(successful.isRefreshing)
        XCTAssertEqual(successful.successUntil, deadline)
        XCTAssertNil(snapshot.successUntil)
        XCTAssertEqual(successful.updatingSuccessUntil(nil), snapshot)
    }

    func testShowsSuccess_ExpiresExactlyAtDeadline() {
        let deadline = fetchedAt.addingTimeInterval(5)
        let snapshot = makeSnapshot(successUntil: deadline)

        XCTAssertTrue(snapshot.showsSuccess(at: deadline.addingTimeInterval(-0.001)))
        XCTAssertFalse(snapshot.showsSuccess(at: deadline))
        XCTAssertFalse(snapshot.showsSuccess(at: deadline.addingTimeInterval(0.001)))
        XCTAssertFalse(makeSnapshot().showsSuccess(at: fetchedAt))
    }

    func testPayloadSnapshot_UsesCurrentServiceValuesAndPreservesTransientState() throws {
        let deadline = fetchedAt.addingTimeInterval(5)
        let fallback = makeSnapshot(isRefreshing: true, successUntil: deadline)
        let payload = makePayload(total: 30, remaining: 18)

        let snapshot = try XCTUnwrap(WidgetSnapshot(payload: payload, fallback: fallback))
        let service = try XCTUnwrap(snapshot.primaryService)

        XCTAssertEqual(snapshot.fetchedAt, payload.fetchedAt)
        XCTAssertEqual(service.serviceName, "現在のプラン")
        XCTAssertEqual(service.phoneNumber, "070-0000-0001")
        XCTAssertEqual(service.totalCapacityGB, 30)
        XCTAssertEqual(service.remainingGB, 18)
        XCTAssertTrue(snapshot.isRefreshing)
        XCTAssertEqual(snapshot.successUntil, deadline)
    }

    func testPayloadSnapshot_MissingValuesUseFallbackCapacityAndRemainingData() throws {
        let fallback = makeSnapshot()
        let snapshot = try XCTUnwrap(WidgetSnapshot(payload: makePayload(total: nil, remaining: nil), fallback: fallback))

        XCTAssertEqual(snapshot.primaryService?.totalCapacityGB, fallback.primaryService?.totalCapacityGB)
        XCTAssertEqual(snapshot.primaryService?.remainingGB, fallback.primaryService?.remainingGB)
    }

    func testPayloadSnapshot_NonpositiveCapacityUsesPositiveFallback() throws {
        for total in [0.0, -10.0] {
            let snapshot = try XCTUnwrap(WidgetSnapshot(payload: makePayload(total: total, remaining: 0), fallback: makeSnapshot()))

            XCTAssertEqual(snapshot.primaryService?.totalCapacityGB, 20)
            XCTAssertEqual(snapshot.primaryService?.remainingGB, 0)
        }
    }

    func testPayloadSnapshot_MissingCapacityUsesRemainingDataOrMinimum() throws {
        for remaining in [8.0, 0.0, -2.0] {
            let snapshot = try XCTUnwrap(WidgetSnapshot(payload: makePayload(total: nil, remaining: remaining)))

            XCTAssertEqual(snapshot.primaryService?.totalCapacityGB, max(remaining, 0.01))
            XCTAssertEqual(snapshot.primaryService?.remainingGB, remaining)
            XCTAssertFalse(snapshot.isRefreshing)
            XCTAssertNil(snapshot.successUntil)
        }
    }

    func testPayloadSnapshot_AllMissingValuesProduceMinimumCapacity() throws {
        let snapshot = try XCTUnwrap(WidgetSnapshot(payload: makePayload(total: nil, remaining: nil)))

        XCTAssertEqual(snapshot.primaryService?.totalCapacityGB, 0.01)
        XCTAssertEqual(snapshot.primaryService?.remainingGB, 0)
    }

    func testPayloadSnapshot_EmptyServicesReturnNilEvenWithFallback() {
        let payload = makePayload(services: [])

        XCTAssertNil(WidgetSnapshot(payload: payload))
        XCTAssertNil(WidgetSnapshot(payload: payload, fallback: makeSnapshot()))
    }

    private func makeService(total: Double = 20, remaining: Double = 12) -> WidgetServiceSnapshot {
        WidgetServiceSnapshot(
            serviceName: "保存済みプラン",
            phoneNumber: "070-0000-0000",
            totalCapacityGB: total,
            remainingGB: remaining
        )
    }

    private func makeSnapshot(isRefreshing: Bool = false, successUntil: Date? = nil) -> WidgetSnapshot {
        WidgetSnapshot(
            fetchedAt: fetchedAt,
            primaryService: makeService(),
            isRefreshing: isRefreshing,
            successUntil: successUntil
        )
    }

    private func makePayload(total: Double?, remaining: Double?) -> AggregatePayload {
        makePayload(services: [TrafficSummary.ServiceInfo(
            id: "line-1",
            serviceCode: "service-1",
            groupServiceCode: nil,
            totalCapacity: total,
            remainingDataGB: remaining,
            planName: "現在のプラン",
            phoneNo: "070-0000-0001"
        )])
    }

    private func makePayload(services: [TrafficSummary.ServiceInfo]) -> AggregatePayload {
        AggregatePayload(
            fetchedAt: fetchedAt.addingTimeInterval(60),
            top: TrafficSummary(serviceInfoList: services),
            bill: BillSummaryResponse(billList: []),
            serviceStatus: ServiceStatusResponse(serviceInfoList: []),
            monthlyUsage: [],
            dailyUsage: []
        )
    }

    private func encodedObject(_ snapshot: WidgetSnapshot) throws -> [String: Any] {
        let data = try JSONEncoder().encode(snapshot)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decodeSnapshot(_ object: [String: Any]) throws -> WidgetSnapshot {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
