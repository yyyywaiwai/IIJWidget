import Foundation

struct UsageChartPoint: Identifiable, Equatable {
    let id = UUID()
    let displayLabel: String
    let rawKey: String
    let value: Double
    let sortKey: Int
    let date: Date?

    init(rawKey: String, displayLabel: String, value: Double, date: Date?) {
        self.rawKey = rawKey
        self.displayLabel = displayLabel
        self.value = value
        self.date = date
        if let date {
            sortKey = date.chartSortKey
        } else {
            sortKey = rawKey.numericIdentifier
        }
    }
}

extension UsageChartPoint {
    static func == (lhs: UsageChartPoint, rhs: UsageChartPoint) -> Bool {
        lhs.displayLabel == rhs.displayLabel &&
        lhs.rawKey == rhs.rawKey &&
        lhs.value == rhs.value &&
        lhs.sortKey == rhs.sortKey &&
        lhs.date == rhs.date
    }
}

struct BillChartPoint: Identifiable {
    let id: String
    let label: String
    let value: Double
    let isUnpaid: Bool
    let sortKey: Int
    let date: Date?
}

func monthlyChartPoints(from services: [MonthlyUsageService]) -> [UsageChartPoint] {
    struct Aggregate { var total: Double; var date: Date? }
    var accumulator: [String: Aggregate] = [:]

    for service in services {
        for entry in service.entries {
            let key = entry.monthLabel
            let addition = entry.hasData ? (entry.highSpeedGB ?? 0) + (entry.lowSpeedGB ?? 0) : 0
            let date = parseYearMonth(from: key)
            if let existing = accumulator[key] {
                let updatedDate = existing.date ?? date
                accumulator[key] = Aggregate(total: existing.total + addition, date: updatedDate)
            } else {
                accumulator[key] = Aggregate(total: addition, date: date)
            }
        }
    }

    let points = accumulator.map { key, bucket in
        UsageChartPoint(
            rawKey: key,
            displayLabel: monthDisplayLabel(from: key),
            value: bucket.total,
            date: bucket.date ?? parseYearMonth(from: key)
        )
    }
    let sorted = points.sorted { $0.sortKey < $1.sortKey }
    return Array(sorted.suffix(6))
}

func dailyChartPoints(from services: [DailyUsageService]) -> [UsageChartPoint] {
    struct Aggregate { var total: Double; var date: Date? }
    var accumulator: [String: Aggregate] = [:]

    for service in services {
        for entry in service.entries {
            let key = entry.dateLabel
            let addition = entry.hasData ? (entry.highSpeedMB ?? 0) + (entry.lowSpeedMB ?? 0) : 0
            let date = parseYearMonthDay(from: key)
            if let existing = accumulator[key] {
                let updatedDate = existing.date ?? date
                accumulator[key] = Aggregate(total: existing.total + addition, date: updatedDate)
            } else {
                accumulator[key] = Aggregate(total: addition, date: date)
            }
        }
    }

    let points = accumulator.map { key, bucket in
        UsageChartPoint(
            rawKey: key,
            displayLabel: dayDisplayLabel(from: key),
            value: bucket.total,
            date: bucket.date ?? parseYearMonthDay(from: key)
        )
    }
    let sorted = points.sorted { $0.sortKey < $1.sortKey }
    return sorted
}

func billingChartPoints(from bill: BillSummaryResponse) -> [BillChartPoint] {
    let points = bill.billList.map { entry in
        let date = parseYearMonth(from: entry.month ?? "")
        return BillChartPoint(
            id: entry.id,
            label: entry.formattedMonth,
            value: Double(entry.totalAmount ?? 0),
            isUnpaid: entry.isUnpaid == true,
            sortKey: date?.chartSortKey ?? entry.monthNumericValue,
            date: date
        )
    }
    let sorted = points.sorted { $0.sortKey < $1.sortKey }
    return Array(sorted.suffix(6))
}

func billingAxisLabel(for point: BillChartPoint) -> String {
    if let date = point.date {
        return monthAxisLabel(for: date)
    }
    return point.label
}

func discreteDomain(forCount count: Int) -> ClosedRange<Double> {
    guard count > 0 else { return -0.5...0.5 }
    let upperBound = Double(count - 1) + 0.5
    return -0.5...upperBound
}

func monthAxisLabel(for date: Date) -> String {
    let month = Calendar.current.component(.month, from: date)
    return "\(month)月"
}

func dayAxisLabel(for date: Date) -> String {
    let components = Calendar.current.dateComponents([.month, .day], from: date)
    guard let month = components.month, let day = components.day else { return "" }
    return "\(month)/\(day)"
}

private func monthDisplayLabel(from raw: String) -> String {
    guard let date = parseYearMonth(from: raw) else { return raw }
    return monthAxisLabel(for: date)
}

private func dayDisplayLabel(from raw: String) -> String {
    guard let date = parseYearMonthDay(from: raw) else { return raw }
    return dayAxisLabel(for: date)
}

private func numericSegments(in label: String) -> [Int] {
    var segments: [Int] = []
    var buffer = ""

    for character in label {
        if character.isNumber {
            buffer.append(character)
        } else if !buffer.isEmpty {
            if let value = Int(buffer) {
                segments.append(value)
            }
            buffer.removeAll(keepingCapacity: true)
        }
    }

    if !buffer.isEmpty, let value = Int(buffer) {
        segments.append(value)
    }

    return segments
}

private func parseYearMonth(from label: String) -> Date? {
    guard let parts = extractDateParts(from: label), let month = parts.month else { return nil }
    let calendar = Calendar.current
    var components = DateComponents()
    components.year = parts.year ?? calendar.component(.year, from: Date())
    components.month = month
    components.day = 1
    return calendar.date(from: components)
}

private func parseYearMonthDay(from label: String) -> Date? {
    guard let parts = extractDateParts(from: label), let month = parts.month else {
        return parseYearMonth(from: label)
    }
    let calendar = Calendar.current
    var components = DateComponents()
    components.year = parts.year ?? calendar.component(.year, from: Date())
    components.month = month
    components.day = parts.day ?? 1
    return calendar.date(from: components) ?? parseYearMonth(from: label)
}

private func extractDateParts(from label: String) -> (year: Int?, month: Int?, day: Int?)? {
    let segments = numericSegments(in: label)
    if let parts = datePartsFromSegments(segments) {
        return parts
    }
    let digits = label.filter(\.isNumber)
    return datePartsFromDigits(digits)
}

private func datePartsFromSegments(_ segments: [Int]) -> (year: Int?, month: Int?, day: Int?)? {
    guard !segments.isEmpty else { return nil }

    if segments.count >= 3 {
        if let first = segments.first, first >= 1000 {
            return (first, segments[1], segments[2])
        }
        if let last = segments.last, last >= 1000 {
            return (last, segments[0], segments[1])
        }
    }

    if segments.count == 2 {
        if let first = segments.first, first >= 1000 {
            return (first, segments[1], nil)
        }
        if let last = segments.last, last >= 1000 {
            return (last, segments[0], nil)
        }
        return (nil, segments[0], segments[1])
    }

    if let first = segments.first, first < 1000 {
        return (nil, first, nil)
    }

    return nil
}

private func datePartsFromDigits(_ digits: String) -> (year: Int?, month: Int?, day: Int?)? {
    guard digits.count >= 5 else { return nil }
    guard let year = Int(digits.prefix(4)) else { return nil }
    let remainder = digits.dropFirst(4)
    guard !remainder.isEmpty else { return (year, nil, nil) }

    let monthLength = remainder.count == 1 ? 1 : 2
    guard let month = Int(String(remainder.prefix(monthLength))) else { return (year, nil, nil) }

    let dayRemainder = remainder.dropFirst(monthLength)
    guard !dayRemainder.isEmpty else { return (year, month, nil) }

    let dayLength = min(2, dayRemainder.count)
    guard dayLength > 0 else { return (year, month, nil) }
    guard let day = Int(String(dayRemainder.prefix(dayLength))) else { return (year, month, nil) }

    return (year, month, day)
}

extension BillSummaryResponse {
    var latestEntry: BillEntry? {
        billList.max(by: { $0.monthNumericValue < $1.monthNumericValue })
    }
}

extension BillSummaryResponse.BillEntry {
    var monthNumericValue: Int {
        if let month, let date = parseYearMonth(from: month) {
            return date.chartSortKey
        }
        return (month ?? "").numericIdentifier
    }

    var plainAmountText: String {
        guard let totalAmount else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: totalAmount)) ?? "\(totalAmount)"
        return "\(number)円"
    }
}

private extension String {
    var numericIdentifier: Int {
        Int(filter(\.isNumber)) ?? 0
    }
}

private extension Date {
    var chartSortKey: Int {
        Int(timeIntervalSinceReferenceDate)
    }
}
