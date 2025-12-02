import Foundation

struct DebugResponseRecord: Codable, Identifiable, Equatable {
    enum Category: String, Codable {
        case api = "API"
        case scraping = "Scraping"
    }

    let id: UUID
    let title: String
    let path: String
    let category: Category
    let capturedAt: Date
    let rawText: String
    let formattedText: String?

    init(
        id: UUID = UUID(),
        title: String,
        path: String,
        category: Category,
        capturedAt: Date = Date(),
        rawText: String,
        formattedText: String?
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.category = category
        self.capturedAt = capturedAt
        self.rawText = rawText
        self.formattedText = formattedText
    }
}

enum DebugPrettyFormatter {
    static func utf8String(from data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        return data.base64EncodedString()
    }

    static func prettyJSONString<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

final class DebugResponseStore {
    static let shared = DebugResponseStore()

    private let queue = DispatchQueue(label: "DebugResponseStore.queue")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maxRecords = 80
    private let maxTextLength = 40_000
    private let fileName = "debug-responses.json"

    private var records: [DebugResponseRecord] = []

    private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        records = loadFromDisk()
    }

    func beginCaptureSession() {
        queue.sync {
            records.removeAll()
            saveUnlocked()
        }
    }

    func finalizeCaptureSession() {
        queue.sync {
            saveUnlocked()
        }
    }

    func appendResponse(
        title: String,
        path: String,
        category: DebugResponseRecord.Category,
        rawText: String,
        formattedText: String?
    ) {
        let record = DebugResponseRecord(
            title: title,
            path: path,
            category: category,
            rawText: truncate(rawText),
            formattedText: formattedText.map { truncate($0) }
        )
        append(record)
    }

    func load() -> [DebugResponseRecord] {
        queue.sync { records.sorted { $0.capturedAt > $1.capturedAt } }
    }

    func clear() {
        queue.sync {
            records.removeAll()
            saveUnlocked()
        }
    }

    // MARK: - Private

    private func append(_ record: DebugResponseRecord) {
        queue.sync {
            records.append(record)
            if records.count > maxRecords {
                records = Array(records.suffix(maxRecords))
            }
            saveUnlocked()
        }
    }

    private func fileURL() -> URL? {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) {
            return container.appendingPathComponent(fileName)
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }

    private func loadFromDisk() -> [DebugResponseRecord] {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? decoder.decode([DebugResponseRecord].self, from: data)) ?? []
    }

    private func saveUnlocked() {
        guard let url = fileURL(), let data = try? encoder.encode(records) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func truncate(_ text: String) -> String {
        guard text.count > maxTextLength else { return text }

        let suffix = "\n…(truncated)"
        let allowedPrefixLength = maxTextLength > suffix.count ? maxTextLength - suffix.count : 0
        let prefix = text.prefix(allowedPrefixLength)

        let truncated = String(prefix) + suffix
        if truncated.count > maxTextLength {
            return String(truncated.prefix(maxTextLength))
        }
        return truncated
    }
}
