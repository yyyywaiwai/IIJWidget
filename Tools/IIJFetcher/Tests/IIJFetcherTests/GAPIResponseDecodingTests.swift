import Foundation
import XCTest
@testable import IIJFetcher

final class GAPIResponseDecodingTests: XCTestCase {
    func testMissingCollections_DecodeToEmptyLists() throws {
        let lineInfo: GAPILineInfoResponse = try decode(#"{"lineInfo":{}}"#)
        let traffic: GAPIDataTrafficResponse = try decode(#"{"dataTraffic":{}}"#)
        let contract: GAPIContractResponse = try decode(#"{"contract":{}}"#)
        let fees: GAPIUsageFeeResponse = try decode("{}")
        let past: GAPIPastDataTrafficResponse = try decode("{}")

        XCTAssertTrue(lineInfo.lineInfo.allLines.isEmpty)
        XCTAssertTrue(traffic.dataTraffic.resolvedLines.isEmpty)
        XCTAssertTrue(contract.contract.allLines.isEmpty)
        XCTAssertTrue(fees.billingSummary.isEmpty)
        XCTAssertTrue(past.lastFiveMonthInfo.isEmpty)
        XCTAssertTrue(past.thisMonthDailyInfo.isEmpty)
    }

    func testNumericFields_AcceptNumbersStringsAndCommaSeparatedAmounts() throws {
        let line: GAPITrafficLine = try decode("""
        {"couponValue":"1,024.5","expireList":[
          {"expireYear":2026,"expireMonth":8,"remainingDataTraffic":"2,048","dataUnit":"MB"}
        ],"thisMonthDataList":{"availableDataTraffic":"7.5","maxDataTraffic":10,
          "couponStatus":"1","regulationStatus":0,"dataShare":"1","usePeriod":31}}
        """)
        XCTAssertEqual(line.couponValue, 1024.5)
        XCTAssertEqual(line.expireList.first?.expireYear, "2026")
        XCTAssertEqual(line.expireList.first?.expireMonth, "8")
        XCTAssertEqual(line.expireList.first?.remainingDataTraffic, 2048)
        XCTAssertEqual(line.thisMonthDataList?.availableDataTraffic, 7.5)
        XCTAssertEqual(line.thisMonthDataList?.maxDataTraffic, 10)
        XCTAssertEqual(line.thisMonthDataList?.couponStatus, 1)
        XCTAssertEqual(line.thisMonthDataList?.regulationStatus, 0)
        XCTAssertEqual(line.thisMonthDataList?.dataShare, 1)
        XCTAssertEqual(line.thisMonthDataList?.usePeriod, "31")
    }

    func testLossyNumericFields_IgnoreUnsupportedValuesWithoutDroppingLine() throws {
        let line: GAPITrafficLine = try decode("""
        {"lineServiceCode":"hdu-fixture","couponValue":"unavailable",
         "expireList":[{"expireYear":{},"remainingDataTraffic":false}],
         "thisMonthDataList":{"availableDataTraffic":[],"couponStatus":"unknown"}}
        """)
        XCTAssertEqual(line.lineServiceCode, "hdu-fixture")
        XCTAssertNil(line.couponValue)
        XCTAssertNil(line.expireList.first?.expireYear)
        XCTAssertNil(line.expireList.first?.remainingDataTraffic)
        XCTAssertNil(line.thisMonthDataList?.availableDataTraffic)
        XCTAssertNil(line.thisMonthDataList?.couponStatus)
    }

    func testNumericStrings_LargeJSONNumbersDoNotOverflowIntegerConversion() throws {
        let fee: GAPIUsageFeeResponse = try decode(#"{"billingTotalAmount":1e100}"#)
        XCTAssertEqual(fee.billingTotalAmount, "1e+100")
        let detail: GAPIBillingDetailItem = try decode(#"{"quantity":1.5}"#)
        XCTAssertEqual(detail.quantity, "1.5")
    }

    func testResolvedLines_DeduplicateByLineAndKeepFirstSource() throws {
        let response: GAPIDataTrafficResponse = try decode("""
        {"dataTraffic":{
          "hdcList":[{"serviceCode":"hdc-fixture","lineServiceCode":"line-1","planName":"first"},{}],
          "hddList":[{"serviceCode":"hdd-fixture","planCode":"shared-plan","lineServiceCodeList":[
            {"lineServiceCode":"line-1","planName":"duplicate"},{"lineServiceCode":"line-2"}]}],
          "mainHdd":[{"serviceCode":"hdd-fixture","lineServiceCodeList":[{"lineServiceCode":"line-2"}]}]
        }}
        """)
        let lines = response.dataTraffic.resolvedLines
        XCTAssertEqual(lines.map(\.id), ["line-1", "line-2"])
        XCTAssertEqual(lines[0].planName, "first")
        XCTAssertEqual(lines[0].serviceCode, "hdc-fixture")
        XCTAssertEqual(lines[1].planName, "shared-plan")
        XCTAssertEqual(lines[1].serviceCode, "hdd-fixture")
    }

    func testTrafficMapping_ConvertsUnitsAndUsesExpiryFallback() throws {
        let response: GAPIDataTrafficResponse = try decode("""
        {"dataTraffic":{"hdcList":[
          {"lineServiceCode":"mb","thisMonthDataList":{"availableDataTraffic":1536,
            "availableDataTrafficUnit":"MB","maxDataTraffic":1,"maxDataTrafficUnit":"TB"}},
          {"lineServiceCode":"expiry","expireList":[
            {"remainingDataTraffic":1024,"dataUnit":"MB"},
            {"remainingDataTraffic":1048576,"dataUnit":"KB"}]},
          {"lineServiceCode":"coupon","couponValue":3},
          {"lineServiceCode":"invalid","thisMonthDataList":{"availableDataTraffic":-1}}
        ]}}
        """)
        let lines = MyIIJmioPayloadMapper.top(dataTraffic: response).serviceInfoList
        XCTAssertEqual(lines.map(\.remainingDataGB), [1.5, 2, 3, nil])
        XCTAssertEqual(lines[0].totalCapacity, 1024)
    }

    func testBillMapping_MatchesBillingNumberBeforeMonthAndFormatsAmounts() throws {
        let fees: GAPIUsageFeeResponse = try decode("""
        {"billingSummary":[
          {"billingNo":"first","billingMonth":"2026/08","billingTotalAmount":"100"},
          {"billingNo":"second","billingMonth":"2026/08","billingTotalAmount":"2,200",
            "detailDataList":[{"subTotal":2200,"detailItemList":[
              {"amount":12.5,"unitPrice":2.25,"quantity":2}]}]}
        ]}
        """)
        let entry = BillSummaryResponse.BillEntry(billingNumber: "second", month: "202608",
                                                 totalAmount: nil, isUnpaid: nil)
        let detail = try XCTUnwrap(MyIIJmioPayloadMapper.billDetail(entry: entry, usageFee: fees))
        XCTAssertEqual(detail.totalAmount, 2200)
        XCTAssertEqual(detail.monthText, "2026年8月")
        XCTAssertEqual(detail.sections.first?.subtotalText, "2200円")
        XCTAssertEqual(detail.sections.first?.items.first?.amountText, "12.5円")
        XCTAssertEqual(detail.sections.first?.items.first?.unitPriceText, "2.25円")
    }

    func testBillMapping_LargeNumericAmountsDoNotOverflowIntegerFormatting() throws {
        let fees: GAPIUsageFeeResponse = try decode("""
        {"billingSummary":[{"billingNo":"fixture","detailDataList":[
          {"subTotal":1e30,"detailItemList":[{"amount":1e30,"unitPrice":1e30}]}]}]}
        """)
        let entry = BillSummaryResponse.BillEntry(billingNumber: "fixture", month: nil,
                                                 totalAmount: nil, isUnpaid: nil)
        let detail = try XCTUnwrap(MyIIJmioPayloadMapper.billDetail(entry: entry, usageFee: fees))
        XCTAssertTrue(try XCTUnwrap(detail.sections.first?.subtotalText).hasSuffix("円"))
        XCTAssertTrue(try XCTUnwrap(detail.sections.first?.items.first?.amountText).hasSuffix("円"))
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
