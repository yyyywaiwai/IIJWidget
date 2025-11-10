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
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("アカウント")
                .font(.headline)

            TextField("mioID / メールアドレス", text: $viewModel.mioId)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .mioId)

            SecureField("パスワード", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .password)

            Text("入力した資格情報は端末のキーチェーンに暗号化して保存され、次回起動時に自動で入力されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var fetchButton: some View {
        Button {
            focusedField = nil
            Task { await viewModel.fetchLatest() }
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
            placeholderView(text: "mioID とパスワードを入力して取得してください。")

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
