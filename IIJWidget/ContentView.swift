//
//  ContentView.swift
//  IIJWidget
//
//  Created by yyyywaiwai on 2025/11/10.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @FocusState private var focusedField: Field?
    @Environment(\.scenePhase) private var scenePhase

    enum Field {
        case mioId
        case password
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    credentialsSection
                    fetchButton
                    stateSection
                }
                .padding()
            }
            .navigationTitle("IIJmio 残量ビュー")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("閉じる") { focusedField = nil }
                }
            }
        }
        .task {
            await viewModel.triggerAutomaticRefreshIfNeeded()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.triggerAutomaticRefreshIfNeeded() }
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("アカウント")
                .font(.headline)

            if viewModel.credentialFieldsHidden {
                Label("自動ログイン済み", systemImage: "checkmark.shield")
                    .font(.subheadline)
                    .foregroundStyle(.green)

                if let status = viewModel.loginStatusText {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.revealCredentialFields()
                } label: {
                    Label("資格情報を再設定", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            } else {
                TextField("mioID / メールアドレス", text: $viewModel.mioId)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .mioId)

                SecureField("パスワード", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .password)

                if let status = viewModel.loginStatusText {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("入力した資格情報は端末のキーチェーンに暗号化して保存され、次回起動時に自動で入力されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fetchButton: some View {
        Button {
            focusedField = nil
            viewModel.refreshManually()
        } label: {
            HStack {
                Image(systemName: "arrow.down.circle")
                Text("最新の残量を取得")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canSubmit)
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .idle:
            placeholderView(text: "アプリ起動時に自動取得します。初回は mioID とパスワードを入力してください。")

        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("取得中…")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("取得に失敗しました", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

        case .loaded(let payload):
            UsageSummaryView(payload: payload)
        }
    }

    private func placeholderView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct UsageSummaryView: View {
    let payload: AggregatePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("ご利用状況")
                .font(.title2.bold())

            ForEach(payload.top.serviceInfoList) { info in
                ServiceInfoCard(info: info)
            }

            if !payload.monthlyUsage.isEmpty {
                Divider()
                MonthlyUsageSection(services: payload.monthlyUsage)
            }

            if !payload.dailyUsage.isEmpty {
                Divider()
                DailyUsageSection(services: payload.dailyUsage)
            }

            Divider()

            BillSummaryList(bill: payload.bill)

            Divider()

            ServiceStatusList(status: payload.serviceStatus)

            Text("取得時刻: \(payload.fetchedAt.formatted(date: .numeric, time: .standard))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ServiceInfoCard: View {
    let info: MemberTopResponse.ServiceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(info.displayPlanName)
                        .font(.headline)
                    Text("電話番号: \(info.phoneLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let remaining = info.remainingDataGB {
                    Text("残量 \(remaining, specifier: "%.2f")GB")
                        .font(.headline)
                        .monospacedDigit()
                }
            }

            if let total = info.totalCapacity {
                ProgressView(value: progressValue(remaining: info.remainingDataGB, total: total)) {
                    Text("プラン容量 \(total, specifier: "%.0f")GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func progressValue(remaining: Double?, total: Double) -> Double {
        guard let remaining else { return 0 }
        let used = max(total - remaining, 0)
        return min(used / total, 1)
    }
}

struct BillSummaryList: View {
    let bill: BillSummaryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("直近の請求金額")
                .font(.headline)

            ForEach(bill.billList.prefix(6)) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.formattedMonth)
                        if entry.isUnpaid == true {
                            Text("未払い")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Text(entry.formattedAmount)
                        .font(.body.bold())
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }
}

struct MonthlyUsageSection: View {
    let services: [MonthlyUsageService]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("月別データ利用量")
                .font(.headline)

            ForEach(services) { service in
                MonthlyUsageServiceCard(service: service)
            }
        }
    }
}

struct MonthlyUsageServiceCard: View {
    let service: MonthlyUsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.titlePrimary)
                .font(.subheadline.bold())
            if let detail = service.titleDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(service.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.monthLabel)
                            .font(.callout)
                            .monospacedDigit()
                        Spacer()
                        if entry.hasData {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("高速: \(entry.highSpeedText ?? "-")")
                                Text("低速: \(entry.lowSpeedText ?? "-")")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else if let note = entry.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                if entry.id != service.entries.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DailyUsageSection: View {
    let services: [DailyUsageService]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日別データ利用量")
                .font(.headline)

            ForEach(services) { service in
                DailyUsageServiceCard(service: service)
            }
        }
    }
}

struct DailyUsageServiceCard: View {
    let service: DailyUsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.titlePrimary)
                .font(.subheadline.bold())
            if let detail = service.titleDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(service.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.dateLabel)
                            .font(.callout)
                            .monospacedDigit()
                        Spacer()
                        if entry.hasData {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("高速: \(entry.highSpeedText ?? "-")")
                                Text("低速: \(entry.lowSpeedText ?? "-")")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else if let note = entry.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                if entry.id != service.entries.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ServiceStatusList: View {
    let status: ServiceStatusResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("回線ステータス")
                .font(.headline)
            ForEach(status.serviceInfoList) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("プレフィックス: \(item.serviceCodePrefix ?? "-")")
                        .font(.subheadline)
                    Text("プランコード: \(item.planCode ?? "-")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let simList = item.simInfoList {
                        HStack {
                            ForEach(simList) { sim in
                                Label(sim.simType ?? "?", systemImage: sim.status == "O" ? "checkmark.circle" : "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(sim.status == "O" ? .green : .orange)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

#Preview {
    ContentView()
}
