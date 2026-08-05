import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#endif

private struct LoginRequest: Encodable {
    let loginId: String
    let password: String
}

private struct LoginResponse: Decodable {
    let mioId: String
    let token: String
    let contractorName: String?
}

@main
enum ValidateGAPILogin {
    static func main() async {
        do {
            guard let (loginId, password) = readCredentials() else {
                throw ValidationError.missingCredentials
            }

            let authenticatedSession = try await login(loginId: loginId, password: password)
            let client = MyIIJmioAPIClient(debugResponsesEnabled: false)
            let payload = try await client.fetchAll(session: authenticatedSession, forceUpdate: true)
            try validate(payload)
            let monthlyPoints = monthlyChartPoints(from: payload.monthlyUsage)
            let dailyPoints = dailyChartPoints(from: payload.dailyUsage)

            print(
                "GAPI_LOGIN_E2E_OK "
                    + "services=\(payload.top.serviceInfoList.count) "
                    + "bills=\(payload.bill.billList.count) "
                    + "monthlyServices=\(payload.monthlyUsage.count) "
                    + "dailyServices=\(payload.dailyUsage.count) "
                    + "monthlyPoints=\(monthlyPoints.count) "
                    + "dailyPoints=\(dailyPoints.count)"
            )
        } catch {
            FileHandle.standardError.write(Data("GAPI_LOGIN_E2E_FAILED: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func readCredentials() -> (loginId: String, password: String)? {
        #if canImport(Darwin)
        var original = termios()
        let input = STDIN_FILENO
        let hasTerminal = tcgetattr(input, &original) == 0
        if hasTerminal {
            var hidden = original
            hidden.c_lflag &= ~tcflag_t(ECHO)
            _ = tcsetattr(input, TCSANOW, &hidden)
        }
        defer {
            if hasTerminal {
                _ = tcsetattr(input, TCSANOW, &original)
            }
        }
        #endif

        guard let loginId = readLine(), !loginId.isEmpty,
              let password = readLine(), !password.isEmpty else {
            return nil
        }
        return (loginId, password)
    }

    private static func login(loginId: String, password: String) async throws -> MyIIJmioSession {
        let endpoint = URL(string: "https://gapi.iijmio.jp/token")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "appVersion=\(MyIIJmioAPIClient.officialAppVersion)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(LoginRequest(loginId: loginId, password: password))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let urlSession = URLSession(configuration: configuration)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ValidationError.missingHTTPResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw ValidationError.loginHTTPStatus(httpResponse.statusCode)
        }

        let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
        guard !loginResponse.mioId.isEmpty, !loginResponse.token.isEmpty else {
            throw ValidationError.invalidLoginResponse
        }
        return MyIIJmioSession(
            token: loginResponse.token,
            mioId: loginResponse.mioId,
            contractorName: loginResponse.contractorName,
            appVersion: MyIIJmioAPIClient.officialAppVersion,
            createdAt: Date()
        )
    }

    private static func validate(_ payload: AggregatePayload) throws {
        guard !payload.top.serviceInfoList.isEmpty else {
            throw ValidationError.emptyServices
        }
        guard !payload.serviceStatus.serviceInfoList.isEmpty else {
            throw ValidationError.emptyServiceStatus
        }
        guard !payload.monthlyUsage.isEmpty else {
            throw ValidationError.emptyMonthlyUsage
        }
        guard !payload.dailyUsage.isEmpty else {
            throw ValidationError.emptyDailyUsage
        }
        guard payload.monthlyUsage.contains(where: { !$0.entries.isEmpty }) else {
            throw ValidationError.emptyMonthlyEntries
        }
        guard payload.dailyUsage.contains(where: { !$0.entries.isEmpty }) else {
            throw ValidationError.emptyDailyEntries
        }
        guard !monthlyChartPoints(from: payload.monthlyUsage).isEmpty else {
            throw ValidationError.emptyMonthlyChartPoints
        }
        guard !dailyChartPoints(from: payload.dailyUsage).isEmpty else {
            throw ValidationError.emptyDailyChartPoints
        }

        _ = try JSONEncoder().encode(payload)
    }
}

private enum ValidationError: LocalizedError {
    case missingCredentials
    case missingHTTPResponse
    case loginHTTPStatus(Int)
    case invalidLoginResponse
    case emptyServices
    case emptyServiceStatus
    case emptyMonthlyUsage
    case emptyDailyUsage
    case emptyMonthlyEntries
    case emptyDailyEntries
    case emptyMonthlyChartPoints
    case emptyDailyChartPoints

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "login ID or password was not provided"
        case .missingHTTPResponse:
            return "the login request did not return an HTTP response"
        case .loginHTTPStatus(let statusCode):
            return "the login request returned HTTP \(statusCode)"
        case .invalidLoginResponse:
            return "the login response did not contain a usable session"
        case .emptyServices:
            return "the mapped payload contains no services"
        case .emptyServiceStatus:
            return "the mapped payload contains no service status"
        case .emptyMonthlyUsage:
            return "the mapped payload contains no monthly usage"
        case .emptyDailyUsage:
            return "the mapped payload contains no daily usage"
        case .emptyMonthlyEntries:
            return "the mapped monthly usage contains no entries"
        case .emptyDailyEntries:
            return "the mapped daily usage contains no entries"
        case .emptyMonthlyChartPoints:
            return "the mapped monthly usage produces no chart points"
        case .emptyDailyChartPoints:
            return "the mapped daily usage produces no chart points"
        }
    }
}
