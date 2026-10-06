import Foundation
import XCTest
@testable import IIJFetcher

final class GAPIDataTests: XCTestCase {
    func testGAPIAndThirtyDayData() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = root.appendingPathComponent("Tests/Fixtures/GAPI")
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
            try decoder.decode(type, from: Data(contentsOf: fixtures.appendingPathComponent(name + ".json")))
        }
        let info = try decode(GAPILineInfoResponse.self, "lineInfo")
        let contract = try decode(GAPIContractResponse.self, "contract")
        let fee = try decode(GAPIUsageFeeResponse.self, "usageFee")
        let traffic = try decode(GAPIDataTrafficResponse.self, "dataTraffic")
        let past = try ["hdc", "hdd"].map { suffix -> GAPIPastTrafficResult in
            let response = try decode(GAPIPastDataTrafficResponse.self, "pastDataTraffic-" + suffix)
            let line = try XCTUnwrap(traffic.dataTraffic.resolvedLines.first { $0.serviceCode == response.serviceCode })
            return GAPIPastTrafficResult(line: line, response: response)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6))!
        let payload = MyIIJmioPayloadMapper.aggregatePayload(lineInfo: info, dataTraffic: traffic,
            contract: contract, usageFee: fee, pastTraffic: past, now: now, calendar: calendar)
        XCTAssertEqual(payload.top.serviceInfoList.map(\.id), ["hdu00000001", "hdu00000002"])
        XCTAssertEqual(payload.top.serviceInfoList.first?.remainingDataGB, 7.5)
        XCTAssertEqual(payload.monthlyUsage.first?.lineID, "hdu00000001")
        XCTAssertFalse(payload.billDetails.isEmpty)
        XCTAssertEqual(payload.serviceStatus.serviceInfoList.map(\.id), ["hdu00000001", "hdu00000002"])
        XCTAssertEqual(payload.serviceStatus.serviceInfoList.first?.simInfoList?.first?.status, "利用中")
        XCTAssertEqual(payload.dailyUsage.first?.entries.first { $0.dateLabel == "2026年08月01日" }?.lowSpeedMB, 5)
        let encoded = try JSONEncoder().encode(payload)
        let restored = try decoder.decode(AggregatePayload.self, from: encoded)
        XCTAssertEqual(restored.dailyUsage, payload.dailyUsage)
        let text = String(decoding: encoded, as: UTF8.self)
        for removed in ["couponData", "sequenceNo", "hdoCode", "highSpeedText", "billNoList", "jmbNumberChangePossible"] {
            XCTAssertFalse(text.contains(removed))
        }
        // 旧キャッシュの欠損フィールドを既定値で受け入れない。
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "historyFetchedAt")
        XCTAssertThrowsError(try decoder.decode(AggregatePayload.self,
            from: JSONSerialization.data(withJSONObject: object)))

        let html = """
        <form><input name="hdoCode" value="hdu00000001"><input name="_csrf" value="fixture"></form>
        <div class="viewdata"><div class="viewdata-title">070-0000-0001<br>ギガプラン</div>
        <table class="viewdatatbl"><tr><td>2026年7月31日（金）</td><td>1GB</td><td>2MB</td></tr>
        <tr><td>2026年8月1日（土）</td><td>50MB</td><td>3MB</td></tr></table></div>
        """
        let parser = DataUsageHTMLParser(html: html)
        XCTAssertEqual(parser.extractLandingPageForms().forms.count, 1)
        let table = try XCTUnwrap(parser.parseDailyService(hdoCode: "hdu00000001"))
        let normalized = try DailyUsageMerger.match(history: [table], lines: payload.top.serviceInfoList)
        let merged = DailyUsageMerger.merge(history: normalized, current: payload.dailyUsage)
        XCTAssertEqual(merged.first?.entries.first { $0.dateLabel == "2026年07月31日" }?.highSpeedMB, 1024)
        XCTAssertEqual(merged.first?.entries.first { $0.dateLabel == "2026年08月01日" }?.highSpeedMB, 100)
        XCTAssertEqual(Set(merged[0].entries.map(\.id)).count, merged[0].entries.count)
        // 表を別保存し、GAPI値を正本にしたまま古い日付・低速値を補完する。
        var withHistory = payload
        withHistory.thirtyDayUsage = normalized
        XCTAssertEqual(withHistory.dailyUsage, payload.dailyUsage)
        XCTAssertEqual(withHistory.dailyUsageWithHistory, merged)
        let restoredHistory = try decoder.decode(AggregatePayload.self,
            from: JSONEncoder().encode(withHistory))
        XCTAssertEqual(restoredHistory.thirtyDayUsage, normalized)
        XCTAssertEqual(restoredHistory.dailyUsageWithHistory, merged)
        XCTAssertNil(restored.thirtyDayUsage)
        XCTAssertEqual(restored.dailyUsageWithHistory, payload.dailyUsage)
        let correctedTable = DailyUsageService(lineID: table.lineID, titlePrimary: table.titlePrimary,
            titleDetail: table.titleDetail, entries: [DailyUsageEntry(dateLabel: "2026年7月31日",
                highSpeedMB: 2048, lowSpeedMB: 4, note: nil, hasData: true)])
        withHistory.thirtyDayUsage = [correctedTable]
        XCTAssertEqual(withHistory.dailyUsageWithHistory.first?.entries
            .first { $0.dateLabel == "2026年07月31日" }?.highSpeedMB, 2048)
        XCTAssertThrowsError(try DailyUsageMerger.match(history: [table], lines: []))
        let missingValues = DailyUsageService(lineID: "hdu00000001", titlePrimary: "fixture", titleDetail: nil,
            entries: [DailyUsageEntry(dateLabel: "2026年8月1日", highSpeedMB: nil,
                                      lowSpeedMB: nil, note: nil, hasData: false)])
        XCTAssertEqual(DailyUsageMerger.merge(history: normalized, current: [missingValues])[0]
            .entries.first { $0.dateLabel == "2026年08月01日" }?.highSpeedMB, 50)
        let nextYear = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let recentDecember = try decoder.decode(GAPIDataTrafficResponse.self, from: Data("""
        {"dataTraffic":{"hdcList":[{"serviceCode":"hdc1","lineServiceCode":"hdu1",
        "lastSevenDaysDataList":{"lastSevenDaysDataHighUnit":"GB","dailyDataList":[
        {"month":"12","date":"31","high":"1"}]}}]}}
        """.utf8))
        let rollover = MyIIJmioPayloadMapper.mergeRecentUsage([], dataTraffic: recentDecember,
                                                             now: nextYear, calendar: calendar)
        XCTAssertEqual(rollover.first?.entries.first?.dateLabel, "2026年12月31日")
        XCTAssertEqual(rollover.first?.entries.first?.highSpeedMB, 1024)

        // mainHddとhddList重複は同一回線として扱い、同一契約の別回線は保持。
        let grouped = try decoder.decode(GAPIDataTrafficResponse.self, from: Data("""
        {"dataTraffic":{"hddList":[{"serviceCode":"hdd1","lineServiceCodeList":[
        {"lineServiceCode":"hdu1"},{"lineServiceCode":"hdu2"}]}],
        "mainHdd":[{"serviceCode":"hdd1","lineServiceCodeList":[{"lineServiceCode":"hdu1"}]}]}}
        """.utf8))
        XCTAssertEqual(grouped.dataTraffic.resolvedLines.map(\.id), ["hdu1", "hdu2"])
    }

    func testRefreshRoutes_ThirtyDayRequestsOnlyInUsageHistory() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let service = try String(contentsOf: root.appendingPathComponent("Shared/WidgetRefreshService.swift"), encoding: .utf8)
        let historyMethod = try XCTUnwrap(service.range(of: "func refreshUsageHistory()"))
        XCTAssertFalse(service[..<historyMethod.lowerBound].contains("dailyClient.fetchThirtyDays"))
        XCTAssertTrue(service[historyMethod.lowerBound...].contains("dailyClient.fetchThirtyDays"))
        let tabs = try String(contentsOf: root.appendingPathComponent("IIJWidget/Views/Root/MainTabView.swift"), encoding: .utf8)
        XCTAssertTrue(tabs.contains(".task(id: selectedSection)"))
        XCTAssertTrue(tabs.contains("guard selectedSection == .usage else { return }"))
        XCTAssertTrue(tabs.contains("await viewModel.refreshUsageHistory()"))
    }
}
