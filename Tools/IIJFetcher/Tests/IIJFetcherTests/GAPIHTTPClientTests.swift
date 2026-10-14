import Foundation
import XCTest
@testable import IIJFetcher

final class GAPIHTTPClientTests: XCTestCase {
    func testFullRefresh_PreservesGAPISequenceAndForceUpdateScope() async throws {
        let stub = GAPIRequestStub { request in
            let name: String
            switch request.url?.path {
            case "/token":
                return .json(#"{"mioId":"MA0000000","token":"fixture-token"}"#)
            case "/pastDataTraffic":
                let serviceCode = Self.query(request)["serviceCode"] ?? ""
                name = serviceCode.hasPrefix("hdc") ? "pastDataTraffic-hdc" : "pastDataTraffic-hdd"
            default:
                name = String((request.url?.path ?? "").dropFirst())
            }
            return .init(data: try Self.fixture(name))
        }
        defer { stub.close() }
        let client = makeClient(stub)

        let payload = try await client.fetchAll(
            credentials: Credentials(mioId: "fixture-id", password: "fixture-password"),
            forceUpdate: true
        )

        XCTAssertEqual(stub.requests.compactMap { $0.url?.path }, [
            "/token", "/lineInfo", "/dataTraffic", "/contract", "/usageFee",
            "/pastDataTraffic", "/pastDataTraffic"
        ])
        XCTAssertEqual(payload.top.serviceInfoList.map(\.id), ["hdu00000001", "hdu00000002"])
        XCTAssertNil(payload.thirtyDayUsage, "Normal refresh must not request the legacy history table")

        let login = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(login.httpMethod, "POST")
        XCTAssertEqual(login.value(forHTTPHeaderField: "Authorization"),
                       "appVersion=\(MyIIJmioAPIClient.officialAppVersion)")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.body(login)) as? [String: String])
        XCTAssertEqual(body, ["loginId": "fixture-id", "password": "fixture-password"])

        for request in stub.requests {
            XCTAssertEqual(request.url?.host, "gapi.iijmio.jp")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "charset"), "utf-8")
            XCTAssertEqual(request.value(forHTTPHeaderField: "timeout"), "45000")
            let isTrafficRequest = ["/lineInfo", "/dataTraffic", "/pastDataTraffic"].contains(request.url?.path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "ForceUpdate"), isTrafficRequest ? "1" : nil)
            if request.url?.path != "/token" {
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                               "Bearer fixture-token,appVersion=\(MyIIJmioAPIClient.officialAppVersion)")
            }
        }

        XCTAssertEqual(Self.query(stub.requests[2]), [
            "dataDetailFlag": "1", "mainLineServiceCode": "hdu00000001"
        ])
        XCTAssertEqual(Self.query(stub.requests[5]), ["serviceCode": "hdc00000001"])
        XCTAssertEqual(Self.query(stub.requests[6]), [
            "serviceCode": "hdd00000002", "lineServiceCode": "hdu00000002"
        ])
    }

    func testTopRefresh_OnlyRequestsTrafficAndOmitsMissingMainLine() async throws {
        let stub = GAPIRequestStub { request in
            switch request.url?.path {
            case "/token": return .json(#"{"mioId":"fixture-id","token":"fixture-token"}"#)
            case "/lineInfo": return .json(#"{"lineInfo":{}}"#)
            case "/dataTraffic": return .json(#"{"dataTraffic":{}}"#)
            default: throw URLError(.unsupportedURL)
            }
        }
        defer { stub.close() }

        let result = try await makeClient(stub).fetchTop(
            credentials: Credentials(mioId: "fixture-id", password: "fixture-password")
        )

        XCTAssertTrue(result.top.serviceInfoList.isEmpty)
        XCTAssertTrue(result.dailyUsage.isEmpty)
        XCTAssertEqual(stub.requests.compactMap { $0.url?.path }, ["/token", "/lineInfo", "/dataTraffic"])
        XCTAssertEqual(Self.query(stub.requests[2]), ["dataDetailFlag": "1"])
        XCTAssertTrue(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "ForceUpdate") == nil })
    }

    func testLogin_EmptyCredentialsDoNotIssueRequests() async throws {
        let stub = GAPIRequestStub { _ in throw URLError(.unsupportedURL) }
        defer { stub.close() }
        let client = makeClient(stub)

        for credentials in [Credentials(mioId: "", password: "fixture"),
                            Credentials(mioId: "fixture", password: "")] {
            do {
                _ = try await client.fetchTop(credentials: credentials)
                XCTFail("Expected invalid credentials")
            } catch MyIIJmioAPIError.invalidCredentials {
                // Expected before any network request.
            }
        }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testLogin_EmptyTokenOrAccountRejectsSession() async throws {
        for json in [#"{"mioId":"fixture-id","token":""}"#,
                     #"{"mioId":"","token":"fixture-token"}"#] {
            let stub = GAPIRequestStub { _ in .json(json) }
            defer { stub.close() }
            do {
                _ = try await makeClient(stub).fetchTop(
                    credentials: Credentials(mioId: "fixture-id", password: "fixture-password")
                )
                XCTFail("Expected invalid login response")
            } catch MyIIJmioAPIError.invalidResponse {
                XCTAssertEqual(stub.requests.count, 1)
            }
        }
    }

    func testHTTPStatus_MapsAuthenticationVersionAndServerErrors() async throws {
        for status in [401, 403, 505, 429, 500] {
            let stub = GAPIRequestStub { _ in .init(statusCode: status, data: Data()) }
            defer { stub.close() }
            let client = GAPIHTTPClient(debugResponsesEnabled: false, session: stub.session)
            do {
                let _: GAPILineInfoResponse = try await client.get(path: "/lineInfo", authorization: "fixture")
                XCTFail("Expected HTTP error for \(status)")
            } catch {
                switch (status, error) {
                case (401, MyIIJmioAPIError.invalidSession), (403, MyIIJmioAPIError.invalidSession),
                     (505, MyIIJmioAPIError.forcedUpdate):
                    break
                case (_, MyIIJmioAPIError.httpError(let code)):
                    XCTAssertEqual(code, status)
                default:
                    XCTFail("Unexpected error for \(status): \(error)")
                }
            }
        }
    }

    func testHTTPResponse_MalformedJSONPropagatesDecodingError() async throws {
        let stub = GAPIRequestStub { _ in .json("not JSON") }
        defer { stub.close() }
        let client = GAPIHTTPClient(debugResponsesEnabled: false, session: stub.session)
        do {
            let _: GAPILineInfoResponse = try await client.get(path: "/lineInfo", authorization: "fixture")
            XCTFail("Expected decoding error")
        } catch is DecodingError {
            XCTAssertEqual(stub.requests.count, 1)
        }
    }

    func testTransportFailure_PropagatesWithoutRetry() async throws {
        let stub = GAPIRequestStub { _ in throw URLError(.timedOut) }
        defer { stub.close() }
        let client = GAPIHTTPClient(debugResponsesEnabled: false, session: stub.session)
        do {
            let _: GAPILineInfoResponse = try await client.get(path: "/lineInfo", authorization: "fixture")
            XCTFail("Expected transport failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
            XCTAssertEqual(stub.requests.count, 1)
        }
    }

    func testHTTPQuery_FiltersNilAndEmptyValuesAndPreservesEscaping() async throws {
        let stub = GAPIRequestStub { _ in .json(#"{"lineInfo":{}}"#) }
        defer { stub.close() }
        let client = GAPIHTTPClient(debugResponsesEnabled: false, session: stub.session)
        let _: GAPILineInfoResponse = try await client.get(
            path: "/lineInfo", authorization: "fixture", query: [
                URLQueryItem(name: "nil", value: nil), URLQueryItem(name: "empty", value: ""),
                URLQueryItem(name: "code", value: "a&b =日本語")
            ]
        )
        XCTAssertEqual(Self.query(try XCTUnwrap(stub.requests.first)), ["code": "a&b =日本語"])
    }

    private func makeClient(_ stub: GAPIRequestStub) -> MyIIJmioAPIClient {
        MyIIJmioAPIClient(debugResponsesEnabled: false, persistSession: false, session: stub.session)
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        guard let url = request.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } },
                          uniquingKeysWith: { _, last in last })
    }

    private static func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/GAPI/\(name).json"))
    }

    private static func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

/// Every session has its own handler and request list, so tests remain isolated if parallelized.
private final class GAPIRequestStub {
    struct Response {
        var statusCode = 200
        var data: Data

        static func json(_ value: String) -> Response {
            Response(data: Data(value.utf8))
        }
    }

    private let identifier = UUID().uuidString
    private let lock = NSLock()
    private var capturedRequests: [URLRequest] = []
    private let handler: (URLRequest) throws -> Response
    let session: URLSession

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    init(handler: @escaping (URLRequest) throws -> Response) {
        self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GAPIStubURLProtocol.self]
        configuration.httpAdditionalHeaders = [GAPIStubURLProtocol.identifierHeader: identifier]
        session = URLSession(configuration: configuration)
        GAPIStubURLProtocol.register(self, identifier: identifier)
    }

    func respond(to request: URLRequest) throws -> Response {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()
        return try handler(request)
    }

    func close() {
        session.invalidateAndCancel()
        GAPIStubURLProtocol.remove(identifier: identifier)
    }
}

private final class GAPIStubURLProtocol: URLProtocol {
    static let identifierHeader = "X-IIJWidget-Test-ID"
    private static let lock = NSLock()
    private static var stubs: [String: GAPIRequestStub] = [:]

    static func register(_ stub: GAPIRequestStub, identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs[identifier] = stub
    }

    static func remove(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeValue(forKey: identifier)
    }

    private static func stub(for request: URLRequest) -> GAPIRequestStub? {
        lock.lock()
        defer { lock.unlock() }
        return request.value(forHTTPHeaderField: identifierHeader).flatMap { stubs[$0] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let stub = Self.stub(for: request), let url = request.url else {
                throw URLError(.unsupportedURL)
            }
            let result = try stub.respond(to: request)
            guard let response = HTTPURLResponse(url: url, statusCode: result.statusCode,
                                                 httpVersion: "HTTP/1.1", headerFields: nil) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
