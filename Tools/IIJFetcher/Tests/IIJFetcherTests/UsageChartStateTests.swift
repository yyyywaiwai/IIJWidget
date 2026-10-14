import XCTest
@testable import IIJFetcher

final class UsageChartStateTests: XCTestCase {
    func testRebuild_displaysLatestPointsAndSelectsLatest() {
        var state = UsageChartState()
        state.rebuild(points: points(count: 10), displayCount: 7)

        XCTAssertEqual(state.points.map(\.id), (3..<10).map(String.init))
        XCTAssertEqual(state.indexedPoints.map(\.index), Array(0..<7))
        XCTAssertEqual(state.indexedPoints.map(\.id), state.points.map(\.id))
        XCTAssertEqual(state.displayCount, 7)
        XCTAssertEqual(state.selectedIndex, 6)
        XCTAssertEqual(state.selectedPoint?.id, "9")
        XCTAssertEqual(state.axisPositions, (0..<7).map(Double.init))
    }

    func testRebuild_unchangedCachedDataPreservesUserSelection() {
        var state = UsageChartState()
        let data = points(count: 7)
        state.rebuild(points: data, displayCount: 7)
        state.selectedIndex = 2
        let token = state.animationToken

        state.rebuild(points: data, displayCount: 7)

        XCTAssertEqual(state.selectedIndex, 2)
        XCTAssertEqual(state.animationToken, token)
    }

    func testRebuild_changedValueSelectsLatestAndChangesAnimationToken() {
        var state = UsageChartState()
        state.rebuild(points: points(count: 7), displayCount: 7)
        state.selectedIndex = 0
        let token = state.animationToken
        var updated = points(count: 7)
        updated[3] = UsageChartPoint(rawKey: "3", displayLabel: "3", value: 100, date: nil)

        state.rebuild(points: updated, displayCount: 7)

        XCTAssertEqual(state.selectedIndex, 6)
        XCTAssertNotEqual(state.animationToken, token)
        XCTAssertEqual(state.yMaxValue, 108, accuracy: 0.001)
    }

    func testRebuild_widthChangeExpandsVisibleHistoryAndSelectsLatest() {
        var state = UsageChartState()
        let data = points(count: 14)
        state.rebuild(points: data, displayCount: 7)
        state.selectedIndex = 0

        state.rebuild(points: data, displayCount: 14)

        XCTAssertEqual(state.points.count, 14)
        XCTAssertEqual(state.selectedIndex, 13)
        XCTAssertEqual(state.displayCount, 14)
    }

    func testRebuild_changesOutsideVisibleWindowPreserveSelectionAndToken() {
        var state = UsageChartState()
        state.rebuild(points: points(count: 10), displayCount: 7)
        state.selectedIndex = 2
        let token = state.animationToken
        var updated = points(count: 10)
        updated[0] = UsageChartPoint(rawKey: "0", displayLabel: "0", value: 100, date: nil)

        state.rebuild(points: updated, displayCount: 7)

        XCTAssertEqual(state.selectedIndex, 2)
        XCTAssertEqual(state.animationToken, token)
    }

    func testRebuild_emptyDataClearsSelection() {
        var state = UsageChartState()
        state.rebuild(points: points(count: 7), displayCount: 7)

        state.rebuild(points: [], displayCount: 7)

        XCTAssertTrue(state.points.isEmpty)
        XCTAssertTrue(state.indexedPoints.isEmpty)
        XCTAssertNil(state.selectedIndex)
        XCTAssertNil(state.selectedPoint)
        XCTAssertNil(state.index(for: 0))
    }

    func testSelection_roundsAndClampsToVisibleDomain() {
        var state = UsageChartState()
        state.rebuild(points: points(count: 7), displayCount: 7)

        XCTAssertEqual(state.index(for: -100), 0)
        XCTAssertEqual(state.index(for: 0.49), 0)
        XCTAssertEqual(state.index(for: 0.5), 1)
        XCTAssertEqual(state.index(for: 3.2), 3)
        XCTAssertEqual(state.index(for: 100), 6)
        XCTAssertNil(state.index(for: .nan))
        XCTAssertNil(state.index(for: .infinity))
        state.selectedIndex = 7
        XCTAssertNil(state.selectedPoint)
        state.selectedIndex = -1
        XCTAssertNil(state.selectedPoint)
    }

    func testChartMetrics_preservePaddingAndBarWidthLimits() {
        var state = UsageChartState()
        XCTAssertEqual(state.barWidth, 20)
        state.rebuild(points: points(count: 14), displayCount: 14)
        XCTAssertEqual(state.barWidth, 260.0 / 14, accuracy: 0.001)
        XCTAssertEqual(state.yMaxValue, 13 * 1.08, accuracy: 0.001)
        state.rebuild(points: points(count: 100), displayCount: 100)
        XCTAssertEqual(state.barWidth, 4)
        state.rebuild(points: points(count: 1), displayCount: 7)
        XCTAssertEqual(state.yMaxValue, 1)
    }

    private func points(count: Int) -> [UsageChartPoint] {
        (0..<count).map { index in
            UsageChartPoint(rawKey: "\(index)", displayLabel: "\(index)", value: Double(index), date: nil)
        }
    }
}
