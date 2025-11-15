import Foundation

struct AggregatePayloadStore {
    private let key = "aggregate.payload.cache"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.encoder = encoder
        self.decoder = decoder
    }

    func save(payload: AggregatePayload) {
        guard let defaults = AppGroup.userDefaults,
              let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> AggregatePayload? {
        guard let defaults = AppGroup.userDefaults,
              let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? decoder.decode(AggregatePayload.self, from: data)
    }

    func clear() {
        AppGroup.userDefaults?.removeObject(forKey: key)
    }
}
