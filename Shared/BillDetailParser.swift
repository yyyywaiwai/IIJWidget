import Foundation

struct BillDetailHTMLParser {
    private let html: String

    init(html: String) {
        self.html = html
    }

    func parse() -> BillDetailResponse? {
        guard let summaryBlock = firstMatch(in: html, pattern: #"(?s)<div[^>]*class=\"[^\"]*bill-detail-top[^\"]*\"[^>]*>(.*?)</div>"#) else {
            return nil
        }
        let summaryLines = textLines(from: summaryBlock)
        guard let monthText = summaryLines.first else { return nil }
        guard let amountHTML = firstMatch(
            in: html,
            pattern: #"<(?:div|span)[^>]*class=\"[^\"]*bill-detail-price-num[^\"]*\"[^>]*>(.*?)</(?:div|span)>"#
        ) else {
            return nil
        }
        let totalAmountText = plainText(from: amountHTML)
        let taxBreakdowns = parseTaxBreakdowns()
        let sections = parseSections()
        guard !sections.isEmpty else { return nil }
        return BillDetailResponse(
            monthText: monthText,
            totalAmountText: totalAmountText,
            totalAmount: parseAmount(totalAmountText),
            taxBreakdowns: taxBreakdowns,
            sections: sections
        )
    }

    private func parseTaxBreakdowns() -> [BillDetailResponse.TaxBreakdown] {
        guard let tableHTML = firstMatch(in: html, pattern: #"(?s)<table[^>]*class=\"[^\"]*bill-detail-tax[^\"]*\"[^>]*>(.*?)</table>"#) else {
            return []
        }
        let rowRegex = try! NSRegularExpression(pattern: #"(?s)<tr[^>]*>(.*?)</tr>"#)
        let nsTable = tableHTML as NSString
        return rowRegex.matches(in: tableHTML, range: NSRange(location: 0, length: nsTable.length)).compactMap { match in
            let rowHTML = nsTable.substring(with: match.range(at: 1))
            let cells = extractCells(from: rowHTML)
            guard !cells.isEmpty else { return nil }
            let label = cells[safe: 0] ?? ""
            let amount = cells[safe: 1]
            let taxLabel = cleaned(cells[safe: 2])
            let taxAmount = cleaned(cells[safe: 3])
            return BillDetailResponse.TaxBreakdown(
                label: label,
                amountText: amount ?? "",
                taxLabel: taxLabel,
                taxAmountText: taxAmount
            )
        }
    }

    private func parseSections() -> [BillDetailResponse.Section] {
        guard let tableHTML = firstMatch(in: html, pattern: #"(?s)<table[^>]*class=\"[^\"]*bill-detail-table[^\"]*\"[^>]*>(.*?)</table>"#) else {
            return []
        }
        let rowRegex = try! NSRegularExpression(pattern: #"(?s)<tr[^>]*>(.*?)</tr>"#)
        let nsTable = tableHTML as NSString
        var sections: [BillDetailResponse.Section] = []
        var builder: SectionBuilder?

        for match in rowRegex.matches(in: tableHTML, range: NSRange(location: 0, length: nsTable.length)) {
            let fullRowHTML = nsTable.substring(with: match.range)
            let rowHTML = nsTable.substring(with: match.range(at: 1))
            if fullRowHTML.contains("bill-detail-table-plan") {
                if let completed = builder?.build() {
                    sections.append(completed)
                }
                let title = plainText(from: rowHTML)
                builder = SectionBuilder(title: title)
                continue
            }

            guard var current = builder else { continue }

            if fullRowHTML.contains("bill-detail-table-label") {
                builder = current
                continue
            }

            if fullRowHTML.contains("bill-detail-table-total") {
                if let subtotalHTML = firstMatch(in: rowHTML, pattern: #"(?s)<td[^>]*bill-detail-table-r-sum[^>]*>(.*?)</td>"#) {
                    current.subtotalText = plainText(from: subtotalHTML)
                }
                builder = current
                continue
            }

            let cells = extractCells(from: rowHTML)
            guard !cells.isEmpty else { builder = current; continue }
            let labelText = cells[safe: 0] ?? ""
            let lines = labelText
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let title = lines.first ?? labelText
            let detail = cleaned(String(lines.dropFirst().joined(separator: " ")))
            let item = BillDetailResponse.Item(
                title: title,
                detail: detail,
                quantityText: cleaned(cells[safe: 1]),
                unitPriceText: cleaned(cells[safe: 2]),
                amountText: cleaned(cells[safe: 3])
            )
            current.items.append(item)
            builder = current
        }

        if let completed = builder?.build() {
            sections.append(completed)
        }

        return sections
    }

    private func extractCells(from rowHTML: String) -> [String] {
        let cellRegex = try! NSRegularExpression(pattern: #"(?s)<t[dh][^>]*>(.*?)</t[dh]>"#)
        let nsRow = rowHTML as NSString
        return cellRegex.matches(in: rowHTML, range: NSRange(location: 0, length: nsRow.length)).map {
            plainText(from: nsRow.substring(with: $0.range(at: 1)), condenseWhitespace: false)
        }
    }

    private func firstMatch(in target: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsTarget = target as NSString
        guard let match = regex.firstMatch(in: target, range: NSRange(location: 0, length: nsTarget.length)) else {
            return nil
        }
        return nsTarget.substring(with: match.range(at: 1))
    }

    private func textLines(from htmlFragment: String) -> [String] {
        let text = plainText(from: htmlFragment, condenseWhitespace: false)
        return text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func plainText(from htmlFragment: String, condenseWhitespace: Bool = true) -> String {
        var text = htmlFragment.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&yen;", with: "¥")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if condenseWhitespace {
            text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: " \n", with: "\n")
        text = text.replacingOccurrences(of: "\n ", with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseAmount(_ text: String) -> Int? {
        let digits = text
            .replacingOccurrences(of: "円", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(digits)
    }

    private struct SectionBuilder {
        let title: String
        var items: [BillDetailResponse.Item] = []
        var subtotalText: String?

        func build() -> BillDetailResponse.Section {
            BillDetailResponse.Section(title: title, items: items, subtotalText: subtotalText)
        }
    }
    private func cleaned(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
