import Foundation

struct MonthlyUsageEntry: Codable, Identifiable, Equatable {
    let id: String
    let monthLabel: String
    let highSpeedGB: Double?
    let lowSpeedGB: Double?
    let highSpeedText: String?
    let lowSpeedText: String?
    let note: String?
    let hasData: Bool

    init(monthLabel: String, highText: String?, lowText: String?, note: String?, hasData: Bool) {
        self.id = monthLabel
        self.monthLabel = monthLabel
        self.highSpeedText = highText?.trimmedOrNil
        self.lowSpeedText = lowText?.trimmedOrNil
        self.note = note?.trimmedOrNil
        self.hasData = hasData
        self.highSpeedGB = DataUsageValueParser.parseAmount(highText, target: .gigabyte)
        self.lowSpeedGB = DataUsageValueParser.parseAmount(lowText, target: .gigabyte)
    }
}

struct MonthlyUsageService: Codable, Identifiable, Equatable {
    let hdoCode: String
    let titlePrimary: String
    let titleDetail: String?
    let entries: [MonthlyUsageEntry]

    var id: String { hdoCode }
}

struct DailyUsageEntry: Codable, Identifiable, Equatable {
    let id: String
    let dateLabel: String
    let highSpeedMB: Double?
    let lowSpeedMB: Double?
    let highSpeedText: String?
    let lowSpeedText: String?
    let note: String?
    let hasData: Bool

    init(dateLabel: String, highText: String?, lowText: String?, note: String?, hasData: Bool) {
        self.id = dateLabel
        self.dateLabel = dateLabel
        self.highSpeedText = highText?.trimmedOrNil
        self.lowSpeedText = lowText?.trimmedOrNil
        self.note = note?.trimmedOrNil
        self.hasData = hasData
        self.highSpeedMB = DataUsageValueParser.parseAmount(highText, target: .megabyte)
        self.lowSpeedMB = DataUsageValueParser.parseAmount(lowText, target: .megabyte)
    }
}

struct DailyUsageService: Codable, Identifiable, Equatable {
    let hdoCode: String
    let titlePrimary: String
    let titleDetail: String?
    let entries: [DailyUsageEntry]

    var id: String { hdoCode }
}

struct DataUsageFormDescriptor {
    let formId: String
    let hdoCode: String
    let csrfToken: String
}

struct DataUsageLandingPage {
    let forms: [DataUsageFormDescriptor]
}

struct DataUsageHTMLParser {
    private let html: String

    init(html: String) {
        self.html = html
    }

    func extractLandingPageForms() -> DataUsageLandingPage {
        let formRegex = try! NSRegularExpression(pattern: #"(?s)<form[^>]*>.*?</form>"#)
        let nsString = html as NSString
        var forms: [DataUsageFormDescriptor] = []

        for match in formRegex.matches(in: html, range: NSRange(location: 0, length: nsString.length)) {
            let formHTML = nsString.substring(with: match.range)
            guard let hdoCode = captureInput(named: "hdoCode", in: formHTML),
                  let csrf = captureInput(named: "_csrf", in: formHTML) else {
                continue
            }
            let formId = captureAttribute("id", in: formHTML) ?? UUID().uuidString
            forms.append(DataUsageFormDescriptor(formId: formId, hdoCode: hdoCode, csrfToken: csrf))
        }

        return DataUsageLandingPage(forms: forms)
    }

    func parseMonthlyService(hdoCode: String) -> MonthlyUsageService? {
        guard let meta = extractServiceMetadata() else { return nil }
        let entries = parseMonthlyRows(from: meta.tableHTML)
        return MonthlyUsageService(hdoCode: hdoCode, titlePrimary: meta.title, titleDetail: meta.detail, entries: entries)
    }

    func parseDailyService(hdoCode: String) -> DailyUsageService? {
        guard let meta = extractServiceMetadata() else { return nil }
        let entries = parseDailyRows(from: meta.tableHTML)
        return DailyUsageService(hdoCode: hdoCode, titlePrimary: meta.title, titleDetail: meta.detail, entries: entries)
    }

    private func extractServiceMetadata() -> UsageServiceMetadata? {
        guard let block = firstViewdataBlock() else { return nil }
        guard let titleHTML = firstMatch(in: block, pattern: #"(?s)<div class=\"viewdata-title\">(.*?)</div>"#) else {
            return nil
        }
        let lines = textLines(from: titleHTML)
        let title = lines.first ?? "不明な回線"
        let detail = lines.dropFirst().joined(separator: " / ").nilIfEmpty

        guard let tableHTML = firstMatch(in: block, pattern: #"(?s)<table class=\"viewdatatbl\">(.*?)</table>"#) else {
            return nil
        }

        return UsageServiceMetadata(title: title, detail: detail, tableHTML: tableHTML)
    }

    private func firstViewdataBlock() -> String? {
        let blockRegex = try! NSRegularExpression(pattern: #"(?s)<div class=\"viewdata\">(.*?)</table>\s*</div>"#)
        let nsString = html as NSString
        guard let match = blockRegex.firstMatch(in: html, range: NSRange(location: 0, length: nsString.length)) else {
            return nil
        }
        return nsString.substring(with: match.range)
    }

    private func parseMonthlyRows(from tableHTML: String) -> [MonthlyUsageEntry] {
        var entries: [MonthlyUsageEntry] = []
        let rowRegex = try! NSRegularExpression(pattern: #"(?s)<tr[^>]*>.*?</tr>"#)
        let nsString = tableHTML as NSString

        for match in rowRegex.matches(in: tableHTML, range: NSRange(location: 0, length: nsString.length)) {
            let rowHTML = nsString.substring(with: match.range)
            if rowHTML.contains("viewdata-header") { continue }

            if rowHTML.contains("viewdata-detail-cell-none") {
                guard let monthHTML = firstMatch(in: rowHTML, pattern: #"(?s)<td[^>]*>(.*?)</td>"#) else { continue }
                let month = plainText(from: monthHTML)
                let noteHTML = firstMatch(in: rowHTML, pattern: #"(?s)<td[^>]*colspan=\"2\"[^>]*>(.*?)</td>"#)
                let note = noteHTML.flatMap { plainText(from: $0) }
                entries.append(MonthlyUsageEntry(monthLabel: month, highText: nil, lowText: nil, note: note, hasData: false))
                continue
            }

            let cellRegex = try! NSRegularExpression(pattern: #"(?s)<td[^>]*>(.*?)</td>"#)
            let rowNSString = rowHTML as NSString
            let cellMatches = cellRegex.matches(in: rowHTML, range: NSRange(location: 0, length: rowNSString.length))
            guard cellMatches.count >= 3 else { continue }

            let month = plainText(from: rowNSString.substring(with: cellMatches[0].range))
            let high = plainText(from: rowNSString.substring(with: cellMatches[1].range))
            let low = plainText(from: rowNSString.substring(with: cellMatches[2].range))
            entries.append(MonthlyUsageEntry(monthLabel: month, highText: high, lowText: low, note: nil, hasData: true))
        }

        return entries
    }

    private func parseDailyRows(from tableHTML: String) -> [DailyUsageEntry] {
        var entries: [DailyUsageEntry] = []
        let rowRegex = try! NSRegularExpression(pattern: #"(?s)<tr[^>]*>.*?</tr>"#)
        let nsString = tableHTML as NSString

        for match in rowRegex.matches(in: tableHTML, range: NSRange(location: 0, length: nsString.length)) {
            let rowHTML = nsString.substring(with: match.range)
            if rowHTML.contains("viewdata-header") { continue }

            if rowHTML.contains("viewdata-detail-cell-none") {
                guard let dateHTML = firstMatch(in: rowHTML, pattern: #"(?s)<td[^>]*>(.*?)</td>"#) else { continue }
                let date = plainText(from: dateHTML)
                let noteHTML = firstMatch(in: rowHTML, pattern: #"(?s)<td[^>]*colspan=\"2\"[^>]*>(.*?)</td>"#)
                let note = noteHTML.flatMap { plainText(from: $0) }
                entries.append(DailyUsageEntry(dateLabel: date, highText: nil, lowText: nil, note: note, hasData: false))
                continue
            }

            let cellRegex = try! NSRegularExpression(pattern: #"(?s)<td[^>]*>(.*?)</td>"#)
            let rowNSString = rowHTML as NSString
            let cellMatches = cellRegex.matches(in: rowHTML, range: NSRange(location: 0, length: rowNSString.length))
            guard cellMatches.count >= 3 else { continue }

            let date = plainText(from: rowNSString.substring(with: cellMatches[0].range))
            let high = plainText(from: rowNSString.substring(with: cellMatches[1].range))
            let low = plainText(from: rowNSString.substring(with: cellMatches[2].range))
            entries.append(DailyUsageEntry(dateLabel: date, highText: high, lowText: low, note: nil, hasData: true))
        }

        return entries
    }

    private func captureInput(named field: String, in html: String) -> String? {
        let inputRegex = try! NSRegularExpression(pattern: #"(?is)<input[^>]*>"#)
        let nsHTML = html as NSString
        for match in inputRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let tag = nsHTML.substring(with: match.range)
            let identifier = captureAttribute("name", in: tag) ?? captureAttribute("id", in: tag)
            if identifier == field {
                return captureAttribute("value", in: tag)
            }
        }
        return nil
    }

    private func captureAttribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(pattern: "(?i)" + escaped + #"\s*=\s*['"]([^'"]+)['"]"#) else {
            return nil
        }
        let nsTag = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: nsTag.length)) else {
            return nil
        }
        return nsTag.substring(with: match.range(at: 1))
    }
}

private extension DataUsageHTMLParser {
    struct UsageServiceMetadata {
        let title: String
        let detail: String?
        let tableHTML: String
    }

    func firstMatch(in target: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsTarget = target as NSString
        guard let match = regex.firstMatch(in: target, range: NSRange(location: 0, length: nsTarget.length)) else {
            return nil
        }
        return nsTarget.substring(with: match.range(at: 1))
    }

    func textLines(from htmlFragment: String) -> [String] {
        let text = plainText(from: htmlFragment, condenseWhitespace: false)
        return text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func plainText(from htmlFragment: String, condenseWhitespace: Bool = true) -> String {
        var text = htmlFragment.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if condenseWhitespace {
            text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: " \n", with: "\n")
        text = text.replacingOccurrences(of: "\n ", with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum DataUsageUnit {
    case megabyte
    case gigabyte
}

private enum DataUsageValueParser {
    static func parseAmount(_ text: String?, target: DataUsageUnit) -> Double? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        let upper = text.uppercased()
        let sourceUnit: DataUsageUnit?
        if upper.contains("GB") {
            sourceUnit = .gigabyte
            text = text.replacingOccurrences(of: "GB", with: "", options: [.caseInsensitive])
        } else if upper.contains("MB") {
            sourceUnit = .megabyte
            text = text.replacingOccurrences(of: "MB", with: "", options: [.caseInsensitive])
        } else {
            sourceUnit = nil
        }

        text = text.replacingOccurrences(of: ",", with: "")
        text = text.replacingOccurrences(of: " ", with: "")
        guard let value = Double(text) else { return nil }

        let unit = sourceUnit ?? target
        let valueInMB: Double = {
            switch unit {
            case .megabyte: return value
            case .gigabyte: return value * 1024
            }
        }()

        switch target {
        case .megabyte:
            return valueInMB
        case .gigabyte:
            return valueInMB / 1024
        }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfEmpty: String? { trimmedOrNil }
}
