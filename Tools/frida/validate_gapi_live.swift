import Foundation

enum LiveValidationError: LocalizedError {
    case usage
    case invalidHeader
    case emptyServices
    case emptyBills
    case emptyMonthlyUsage
    case emptyDailyUsage
    case invalidTokenAccepted
    case unexpectedAuthenticationError(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: validate-gapi-live authorization-header-file"
        case .invalidHeader:
            return "Authorization header file is invalid"
        case .emptyServices:
            return "Live GAPI payload contains no services"
        case .emptyBills:
            return "Live GAPI payload contains no bills"
        case .emptyMonthlyUsage:
            return "Live GAPI payload contains no monthly usage"
        case .emptyDailyUsage:
            return "Live GAPI payload contains no daily usage"
        case .invalidTokenAccepted:
            return "GAPI unexpectedly accepted an invalid token"
        case .unexpectedAuthenticationError(let description):
            return "Invalid-token request returned an unexpected error: \(description)"
        }
    }
}

@main
struct GAPILiveValidator {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw LiveValidationError.usage
        }

        if CommandLine.arguments[1] == "--expect-auth-failure" {
            try await validateAuthenticationFailure()
            return
        }

        let header = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Authorization: Bearer "
        let versionMarker = ",appVersion="
        guard header.hasPrefix(prefix),
              let versionRange = header.range(of: versionMarker) else {
            throw LiveValidationError.invalidHeader
        }

        let tokenStart = header.index(header.startIndex, offsetBy: prefix.count)
        let token = String(header[tokenStart..<versionRange.lowerBound])
        let version = String(header[versionRange.upperBound...])
        guard !token.isEmpty, version == MyIIJmioAPIClient.officialAppVersion else {
            throw LiveValidationError.invalidHeader
        }

        let session = MyIIJmioSession(
            token: token,
            mioId: "live-validation",
            contractorName: nil,
            appVersion: version,
            createdAt: Date()
        )
        let client = MyIIJmioAPIClient(debugResponsesEnabled: false)
        let payload = try await client.fetchAll(session: session)

        guard !payload.top.serviceInfoList.isEmpty else { throw LiveValidationError.emptyServices }
        guard !payload.bill.billList.isEmpty else { throw LiveValidationError.emptyBills }
        guard !payload.monthlyUsage.isEmpty else { throw LiveValidationError.emptyMonthlyUsage }
        guard !payload.dailyUsage.isEmpty else { throw LiveValidationError.emptyDailyUsage }

        print(
            "GAPI_LIVE_CLIENT_OK "
                + "services=\(payload.top.serviceInfoList.count) "
                + "bills=\(payload.bill.billList.count) "
                + "monthlyServices=\(payload.monthlyUsage.count) "
                + "dailyServices=\(payload.dailyUsage.count)"
        )
    }

    private static func validateAuthenticationFailure() async throws {
        let session = MyIIJmioSession(
            token: "invalid-token-for-validation",
            mioId: "live-validation",
            contractorName: nil,
            appVersion: MyIIJmioAPIClient.officialAppVersion,
            createdAt: Date()
        )
        let client = MyIIJmioAPIClient(debugResponsesEnabled: false)
        do {
            _ = try await client.fetchAll(session: session)
            throw LiveValidationError.invalidTokenAccepted
        } catch {
            guard client.isAuthenticationError(error) else {
                throw LiveValidationError.unexpectedAuthenticationError(error.localizedDescription)
            }
            print("GAPI_AUTH_FAILURE_OK")
        }
    }
}
