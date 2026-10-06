import Foundation
import Darwin

@main
struct IIJFetcherCLI {
    static func main() async {
        do {
            // 資格情報は標準入力のみ。引数・ログ・ファイルに残さない。
            var original = termios()
            let terminal = tcgetattr(STDIN_FILENO, &original) == 0
            if terminal {
                var hidden = original
                hidden.c_lflag &= ~tcflag_t(ECHO)
                tcsetattr(STDIN_FILENO, TCSANOW, &hidden)
            }
            defer { if terminal { tcsetattr(STDIN_FILENO, TCSANOW, &original) } }
            guard let id = readLine(), let password = readLine(), !id.isEmpty, !password.isEmpty else {
                throw WidgetRefreshError.missingCredentials
            }
            let credentials = Credentials(mioId: id, password: password)
            let client = MyIIJmioAPIClient(debugResponsesEnabled: false, persistSession: false)
            let gapi = try await client.fetchAll(credentials: credentials, forceUpdate: true)
            let daily = ThirtyDayUsageClient(debugResponsesEnabled: false)
            let history: [DailyUsageService]
            do {
                history = try await daily.fetchThirtyDays()
            } catch {
                guard daily.isAuthenticationError(error) else { throw error }
                history = try await daily.fetchThirtyDays(credentials: credentials)
            }
            let normalized = try DailyUsageMerger.match(history: history, lines: gapi.top.serviceInfoList)
            let merged = DailyUsageMerger.merge(history: normalized, current: gapi.dailyUsage)
            guard !gapi.top.serviceInfoList.isEmpty, !gapi.monthlyUsage.isEmpty,
                  !merged.isEmpty, merged.allSatisfy({ !$0.entries.isEmpty }) else {
                throw MyIIJmioAPIError.invalidResponse
            }
            // 個人情報・レスポンス本文は出力しない。
            print("GAPI_30D_OK lines=\(gapi.top.serviceInfoList.count) bills=\(gapi.bill.billList.count) details=\(gapi.billDetails.count) monthly=\(gapi.monthlyUsage.count) daily=\(merged.count) tableRows=\(history.map { $0.entries.count })")
        } catch {
            fputs("FETCH_FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
