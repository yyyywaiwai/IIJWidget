import Foundation

enum CommunicationMethod: String, CaseIterable, Codable, Identifiable {
    case myIIJmioGAPI
    case legacyMemberSite

    var id: Self { self }

    var displayName: String {
        switch self {
        case .myIIJmioGAPI:
            return "新形式（MyIIJmioアプリ方式）"
        case .legacyMemberSite:
            return "従来方式（会員サイト）"
        }
    }

    var explanation: String {
        switch self {
        case .myIIJmioGAPI:
            return "本家MyIIJmioアプリと同じ通信方式で取得します。"
        case .legacyMemberSite:
            return "IIJmio会員サイトのセッションCookieを使って取得します。"
        }
    }
}
