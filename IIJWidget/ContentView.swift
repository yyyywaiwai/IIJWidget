//
//  ContentView.swift
//  IIJWidget
//
//  Created by yyyywaiwai on 2025/11/10.
//

import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedSection: AppSection = .home
    @State private var isOnboardingPresented = false
    @FocusState private var focusedField: Field?
    @Environment(\.scenePhase) private var scenePhase

    enum Field: Hashable {
        case mioId
        case password
    }

    enum AppSection: Hashable {
        case home
        case usage
        case billing
        case settings

        var title: String {
            switch self {
            case .home: return "ホーム"
            case .usage: return "利用量"
            case .billing: return "請求"
            case .settings: return "設定"
            }
        }

        var iconName: String {
            switch self {
            case .home: return "house"
            case .usage: return "chart.bar"
            case .billing: return "yensign"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedSection) {
                HomeDashboardTab(payload: loadedPayload)
                    .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.iconName) }
                    .tag(AppSection.home)

                UsageListTab(
                    monthly: loadedPayload?.monthlyUsage ?? [],
                    daily: loadedPayload?.dailyUsage ?? [],
                    serviceStatus: loadedPayload?.serviceStatus
                )
                .tabItem { Label(AppSection.usage.title, systemImage: AppSection.usage.iconName) }
                .tag(AppSection.usage)

                BillingTabView(bill: loadedPayload?.bill)
                    .tabItem { Label(AppSection.billing.title, systemImage: AppSection.billing.iconName) }
                    .tag(AppSection.billing)

                SettingsTab(
                    viewModel: viewModel,
                    focusedField: $focusedField,
                    hasCompletedOnboarding: $hasCompletedOnboarding
                ) {
                    isOnboardingPresented = true
                }
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.iconName) }
                .tag(AppSection.settings)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        focusedField = nil
                        viewModel.refreshManually()
                    } label: {
                        Label("最新取得", systemImage: "arrow.clockwise")
                    }
                    .disabled(!viewModel.canSubmit || isLoading)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("閉じる") { focusedField = nil }
                }
            }
            .overlay(alignment: .bottom) {
                StateFeedbackBanner(state: viewModel.state)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .overlay {
                if isLoading {
                    LoadingOverlay()
                }
            }
            .navigationTitle(selectedSection.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: $isOnboardingPresented) {
            OnboardingFlowView(viewModel: viewModel) {
                hasCompletedOnboarding = true
                isOnboardingPresented = false
            }
            .interactiveDismissDisabled(true)
        }
        .onAppear {
            evaluateOnboardingPresentation()
        }
        .task {
            await viewModel.triggerAutomaticRefreshIfNeeded()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.triggerAutomaticRefreshIfNeeded() }
        }
        .onChange(of: viewModel.hasStoredCredentials) { _ in
            evaluateOnboardingPresentation()
        }
    }

    private var loadedPayload: AggregatePayload? {
        if case let .loaded(payload) = viewModel.state {
            return payload
        }
        return nil
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state {
            return true
        }
        return false
    }

    private func evaluateOnboardingPresentation() {
        if !hasCompletedOnboarding && !viewModel.hasStoredCredentials {
            isOnboardingPresented = true
        }
    }
}

struct HomeDashboardTab: View {
    let payload: AggregatePayload?

    var body: some View {
        Group {
            if let payload {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HomeOverviewHeader(
                            serviceInfoList: payload.top.serviceInfoList,
                            latestBillAmount: payload.bill.latestEntry?.plainAmountText
                        )

                        UsageGraphCard(
                            monthlyServices: payload.monthlyUsage,
                            dailyServices: payload.dailyUsage
                        )
                    }
                    .padding()
                }
            } else {
                EmptyStateView(text: "最新の残量を取得するとダッシュボードが表示されます。設定タブで資格情報を入力し、右上の「最新取得」をタップしてください。")
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct UsageListTab: View {
    let monthly: [MonthlyUsageService]
    let daily: [DailyUsageService]
    let serviceStatus: ServiceStatusResponse?

    @State private var isMonthlyExpanded = true
    @State private var isDailyExpanded = true
    @State private var isStatusExpanded = false

    var body: some View {
        List {
            Section {
                DisclosureGroup(isExpanded: $isMonthlyExpanded) {
                    if monthly.isEmpty {
                        PlaceholderRow(text: "まだ月別データがありません。")
                    } else {
                        MonthlyUsageSection(services: monthly)
                            .padding(.top, 8)
                    }
                } label: {
                    Label("月別データ利用量", systemImage: "calendar")
                        .font(.headline)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isDailyExpanded) {
                    if daily.isEmpty {
                        PlaceholderRow(text: "まだ日別データがありません。")
                    } else {
                        DailyUsageSection(services: daily)
                            .padding(.top, 8)
                    }
                } label: {
                    Label("日別データ利用量", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                }
            }

            if let serviceStatus {
                Section {
                    DisclosureGroup(isExpanded: $isStatusExpanded) {
                        ServiceStatusList(status: serviceStatus)
                            .padding(.top, 8)
                    } label: {
                        Label("回線ステータス", systemImage: "dot.radiowaves.left.and.right")
                            .font(.headline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }
}

struct BillingTabView: View {
    let bill: BillSummaryResponse?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let bill {
                    BillingHighlightCard(bill: bill)
                    BillingBarChart(bill: bill)
                    BillSummaryList(bill: bill)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    EmptyStateView(text: "請求データがまだ取得されていません。")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct SettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    let focusedField: FocusState<ContentView.Field?>.Binding
    @Binding var hasCompletedOnboarding: Bool
    let presentOnboarding: () -> Void
    @State private var showLogoutConfirmation = false
    @State private var logoutErrorMessage: String?

    var body: some View {
        Form {
            Section(header: Text("資格情報")) {
                CredentialsCard(viewModel: viewModel, focusedField: focusedField)
            }

            Section(header: Text("データ取得")) {
                Button {
                    focusedField.wrappedValue = nil
                    viewModel.refreshManually()
                } label: {
                    Label("最新の残量を取得", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!viewModel.canSubmit)
            }

            Section(header: Text("プロジェクト")) {
                Link(destination: repositoryURL) {
                    Label("GitHub リポジトリを開く", systemImage: "arrow.up.right.square")
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text("ログアウトするとキーチェーンの資格情報が削除され、次回起動時に再設定が必要です。")
                    .font(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .alert(
            "保存済みの資格情報を削除してログアウトしますか?",
            isPresented: $showLogoutConfirmation
        ) {
            Button("ログアウト", role: .destructive) {
                performLogout()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert(
            "ログアウトに失敗しました",
            isPresented: Binding(
                get: { logoutErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        logoutErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                logoutErrorMessage = nil
            }
        } message: {
            if let logoutErrorMessage {
                Text(logoutErrorMessage)
            }
        }
    }

    private func performLogout() {
        focusedField.wrappedValue = nil
        do {
            try viewModel.logout()
            hasCompletedOnboarding = false
            presentOnboarding()
        } catch {
            logoutErrorMessage = error.localizedDescription
        }
    }
}

struct CredentialsCard: View {
    @ObservedObject var viewModel: AppViewModel
    let focusedField: FocusState<ContentView.Field?>.Binding

    var body: some View {
        if viewModel.credentialFieldsHidden {
            Label("自動ログイン済み", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .font(.subheadline)

            if let status = viewModel.loginStatusText {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.revealCredentialFields()
            } label: {
                Label("資格情報を再設定", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
        } else {
            TextField("mioID / メールアドレス", text: $viewModel.mioId)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .focused(focusedField, equals: .mioId)

            SecureField("パスワード", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
                .focused(focusedField, equals: .password)

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

struct OnboardingFlowView: View {
    enum Step {
        case disclaimer
        case credentials
    }

    @ObservedObject var viewModel: AppViewModel
    let onFinish: () -> Void

    @State private var step: Step = .disclaimer

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .disclaimer:
                    OnboardingDisclaimerStep {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            step = .credentials
                        }
                    }
                case .credentials:
                    OnboardingCredentialSetupStep(viewModel: viewModel) {
                        onFinish()
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == .credentials {
                        Button("戻る") {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                step = .disclaimer
                            }
                        }
                    }
                }
            }
            .navigationTitle(step == .disclaimer ? "ご利用前のお願い" : "ログイン設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct OnboardingDisclaimerStep: View {
    let onAgree: () -> Void

    private struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let detail: String
    }

    private var highlights: [Highlight] {
        [
            Highlight(
                icon: "exclamationmark.triangle.fill",
                iconColor: .pink,
                title: "非公式アプリ",
                detail: "IIJWidgetは個人プロジェクトであり、公式サポートや補償の対象ではありません。"
            ),
            Highlight(
                icon: "lock.shield.fill",
                iconColor: .blue,
                title: "資格情報の扱い",
                detail: "入力内容は端末キーチェーンにのみ暗号化保存され、サードパーティのサーバーへ送信しません。"
            ),
            Highlight(
                icon: "hand.raised.fill",
                iconColor: .orange,
                title: "自己責任での利用",
                detail: "アカウント停止などのリスクを理解した上で、自己責任でご利用ください。"
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ご利用前の確認")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("IIJWidgetを使う前に、以下のポイントをご確認ください。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 16) {
                    ForEach(highlights) { highlight in
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(highlight.iconColor.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: highlight.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(highlight.iconColor)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(highlight.title)
                                    .font(.headline)
                                Text(highlight.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }

                Text("上記に同意できない場合はアプリを終了してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onAgree()
                } label: {
                    Text("同意して続行")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct OnboardingCredentialSetupStep: View {
    @ObservedObject var viewModel: AppViewModel
    let onFinish: () -> Void

    @FocusState private var field: Field?

    private enum Field: Hashable {
        case mioId
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ログイン情報を設定")
                        .font(.title.bold())
                    Text("IIJmioアカウントの資格情報を入力してください。保存後は設定タブまたは右上の更新ボタンから残量取得を実行できます。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    TextField("mioID / メールアドレス", text: $viewModel.mioId)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .focused($field, equals: .mioId)

                    SecureField("パスワード", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .focused($field, equals: .password)

                    Text("入力内容は端末キーチェーンに暗号化して保存され、ウィジェット更新時にのみ使用されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 12) {
                    Button {
                        field = nil
                        viewModel.refreshManually()
                        onFinish()
                    } label: {
                        Label("今すぐログインして残量取得", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSubmit)
                }

                Text("ログアウトすると再度この画面は表示されませんが、設定タブからいつでも資格情報を更新できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

struct HomeOverviewHeader: View {
    let serviceInfoList: [MemberTopResponse.ServiceInfo]
    let latestBillAmount: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ご利用状況")
                .font(.title2.bold())

            if serviceInfoList.isEmpty {
                Text("対象回線がまだ取得されていません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(serviceInfoList) { info in
                        ServiceInfoCard(info: info, latestBillAmount: latestBillAmount)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder private let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct UsageGraphCard: View {
    let monthlyServices: [MonthlyUsageService]
    let dailyServices: [DailyUsageService]

    @State private var selectedChartType: ChartType = .daily

    enum ChartType: String, CaseIterable {
        case daily = "日別"
        case monthly = "月別"
    }

    var body: some View {
        let cardTitle = "データ利用量"
        let cardSubtitle = selectedChartType == .daily ? "日別履歴 (MB)" : "月別履歴 (GB)"

        DashboardCard(title: cardTitle, subtitle: cardSubtitle) {
            VStack {
                Picker("グラフ種別", selection: $selectedChartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)

                switch selectedChartType {
                case .daily:
                    DailyUsageChartContent(services: dailyServices)
                case .monthly:
                    MonthlyUsageChartContent(services: monthlyServices)
                }
            }
        }
    }
}

struct MonthlyUsageChartContent: View {
    let services: [MonthlyUsageService]
    @State private var selectedIndex: Int?
    private var points: [UsageChartPoint] {
        monthlyChartPoints(from: services)
    }
    private var indexedPoints: [(index: Int, point: UsageChartPoint)] {
        points.enumerated().map { (index: $0.offset, point: $0.element) }
    }
    private var selectedPoint: UsageChartPoint? {
        guard let selectedIndex, indexedPoints.indices.contains(selectedIndex) else { return nil }
        return indexedPoints[selectedIndex].point
    }
    private var defaultSelectionIndex: Int? {
        indexedPoints.last?.index
    }

    var body: some View {
        if indexedPoints.isEmpty {
            ChartPlaceholder(text: "まだデータがありません")
        } else {
            chartContent
                .onAppear { selectedIndex = defaultSelectionIndex }
                .onChange(of: services) { _ in selectedIndex = defaultSelectionIndex }
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(indexedPoints, id: \.point.id) { entry in
                BarMark(
                    x: .value("月インデックス", centeredValue(for: entry.index)),
                    y: .value("合計(GB)", entry.point.value),
                    width: .fixed(28)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.8), Color.mint.opacity(0.8)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }

            if let selectedIndex, let selectedPoint {
                RuleMark(x: .value("選択", centeredValue(for: selectedIndex)))
                    .lineStyle(.init(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .center) {
                        ChartCallout(
                            title: selectedPoint.displayLabel,
                            valueText: String(format: "%.1fGB", selectedPoint.value)
                        )
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: axisPositions) { value in
                if let doubleValue = value.as(Double.self) {
                    let index = index(from: doubleValue)
                    if let index, index < indexedPoints.count {
                        AxisGridLine(centered: true)
                        AxisTick(centered: true)
                    }
                }
            }
        }
        .chartXScale(domain: centeredDomain(forCount: indexedPoints.count))
        .chartXSelection(value: chartSelectionBinding)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    axisLabelsLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !indexedPoints.isEmpty else { return }
                                    let plotFrame = proxy.plotAreaFrame
                                    let frameRect = geometry[plotFrame]
                                    let origin = frameRect.origin
                                    let xPosition = value.location.x - origin.x
                                    guard xPosition >= 0, xPosition <= frameRect.width else { return }
                                    if let axisValue: Double = proxy.value(atX: xPosition), let newIndex = index(from: axisValue) {
                                        selectedIndex = newIndex
                                    }
                                }
                        )
                }
            }
        }
        .frame(height: 220)
    }

    private var axisPositions: [Double] {
        indexedPoints.map { centeredValue(for: $0.index) }
    }

    private var chartSelectionBinding: Binding<Double?> {
        Binding(
            get: {
                guard let selectedIndex else { return nil }
                return centeredValue(for: selectedIndex)
            },
            set: { newValue in
                guard let newValue else {
                    selectedIndex = nil
                    return
                }
                if let nextIndex = index(from: newValue) {
                    selectedIndex = nextIndex
                }
            }
        )
    }

    private func centeredValue(for index: Int) -> Double {
        Double(index) + 0.5
    }

    private func index(from value: Double) -> Int? {
        guard !indexedPoints.isEmpty else { return nil }
        let lowerBound = 0.5
        let upperBound = Double(indexedPoints.count) - 0.5
        let normalized = min(max(value, lowerBound), upperBound)
        let derived = Int((normalized - 0.5).rounded())
        guard indexedPoints.indices.contains(derived) else { return nil }
        return derived
    }

    @ViewBuilder
    private func axisLabelsLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plotFrame = proxy.plotAreaFrame
        let plotRect = geometry[plotFrame]
        ForEach(Array(indexedPoints.enumerated()), id: \.offset) { entry in
            if let positionX = proxy.position(forX: centeredValue(for: entry.element.index)) {
                Text(entry.element.point.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: plotRect.origin.x + positionX, y: plotRect.maxY + 14)
            }
        }
    }
}

struct DailyUsageChartContent: View {
    let services: [DailyUsageService]
    @State private var selectedIndex: Int?

    private var points: [UsageChartPoint] {
        dailyChartPoints(from: services)
    }

    private var visiblePoints: [UsageChartPoint] {
        Array(points.suffix(7))
    }

    private var indexedPoints: [(index: Int, point: UsageChartPoint)] {
        visiblePoints.enumerated().map { (index: $0.offset, point: $0.element) }
    }

    private var selectedPoint: UsageChartPoint? {
        guard let selectedIndex, visiblePoints.indices.contains(selectedIndex) else {
            return nil
        }
        return visiblePoints[selectedIndex]
    }

    private var defaultSelectionIndex: Int? {
        indexedPoints.last?.index
    }

    var body: some View {
        if indexedPoints.isEmpty {
            ChartPlaceholder(text: "まだデータがありません")
        } else {
            chartContent
                .onAppear { selectedIndex = defaultSelectionIndex }
                .onChange(of: services) { _ in selectedIndex = defaultSelectionIndex }
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(indexedPoints, id: \.point.id) { entry in
                BarMark(
                    x: .value("日インデックス", centeredValue(for: entry.index)),
                    y: .value("合計(MB)", entry.point.value),
                    width: .fixed(34)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.85), Color.pink.opacity(0.85)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }

            if let selectedIndex, let selectedPoint {
                RuleMark(x: .value("選択", centeredValue(for: selectedIndex)))
                    .lineStyle(.init(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .center) {
                        ChartCallout(title: selectedPoint.displayLabel, valueText: String(format: "%.0fMB", selectedPoint.value))
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: axisPositions) { value in
                if let doubleValue = value.as(Double.self), let index = index(from: doubleValue), index < indexedPoints.count {
                    AxisGridLine(centered: true)
                    AxisTick(centered: true)
                }
            }
        }
        .chartXScale(domain: centeredDomain(forCount: indexedPoints.count))
        .chartXSelection(value: chartSelectionBinding)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    axisLabelsLayer(proxy: proxy, geometry: geometry)
                        .allowsHitTesting(false)
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard !indexedPoints.isEmpty else { return }
                                    let plotFrame = proxy.plotAreaFrame
                                    let frameRect = geometry[plotFrame]
                                    let origin = frameRect.origin
                                    let xPosition = value.location.x - origin.x
                                    guard xPosition >= 0, xPosition <= frameRect.width else { return }
                                    if let axisValue: Double = proxy.value(atX: xPosition), let newIndex = index(from: axisValue) {
                                        selectedIndex = newIndex
                                    }
                                }
                        )
                }
            }
        }
        .frame(height: 220)
    }

    private var axisPositions: [Double] {
        indexedPoints.map { centeredValue(for: $0.index) }
    }

    private var chartSelectionBinding: Binding<Double?> {
        Binding(
            get: {
                guard let selectedIndex else { return nil }
                return centeredValue(for: selectedIndex)
            },
            set: { newValue in
                guard let newValue else {
                    selectedIndex = nil
                    return
                }
                if let nextIndex = index(from: newValue) {
                    selectedIndex = nextIndex
                }
            }
        )
    }

    private func centeredValue(for index: Int) -> Double {
        Double(index) + 0.5
    }

    private func index(from value: Double) -> Int? {
        guard !indexedPoints.isEmpty else { return nil }
        let lowerBound = 0.5
        let upperBound = Double(indexedPoints.count) - 0.5
        let normalized = min(max(value, lowerBound), upperBound)
        let derived = Int((normalized - 0.5).rounded())
        guard indexedPoints.indices.contains(derived) else { return nil }
        return derived
    }

    @ViewBuilder
    private func axisLabelsLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plotFrame = proxy.plotAreaFrame
        let plotRect = geometry[plotFrame]
        ForEach(Array(indexedPoints.enumerated()), id: \.offset) { entry in
            if let positionX = proxy.position(forX: centeredValue(for: entry.element.index)) {
                Text(entry.element.point.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: plotRect.origin.x + positionX, y: plotRect.maxY + 14)
            }
        }
    }
}

struct BillingHighlightCard: View {
    let bill: BillSummaryResponse

    var body: some View {
        if let latest = bill.latestEntry {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(latest.formattedMonth)のご請求")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))

                Text(latest.formattedAmount)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)

                if latest.isUnpaid == true {
                    Text("未払い")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.indigo, Color.blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24)
            )
        } else {
            DashboardCard(title: "直近の請求額") {
                ChartPlaceholder(text: "請求データがありません")
            }
        }
    }
}

struct BillingBarChart: View {
    let bill: BillSummaryResponse
    private var points: [BillChartPoint] {
        billingChartPoints(from: bill)
    }
    private var indexedPoints: [(index: Int, point: BillChartPoint)] {
        points.enumerated().map { (index: $0.offset, point: $0.element) }
    }

    var body: some View {
        DashboardCard(title: "請求額の推移", subtitle: "直近6か月") {
            if indexedPoints.isEmpty {
                ChartPlaceholder(text: "データが不足しています")
            } else {
                Chart(indexedPoints, id: \.point.id) { entry in
                    BarMark(
                        x: .value("月インデックス", centeredValue(for: entry.index)),
                        y: .value("金額(¥)", entry.point.value),
                        width: .fixed(36)
                    )
                    .foregroundStyle(entry.point.isUnpaid ? unpaidGradient : paidGradient)
                    .annotation(position: .top) {
                        Text(entry.point.value, format: .currency(code: "JPY").precision(.fractionLength(0)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisPositions) { _ in
                        AxisGridLine(centered: true)
                        AxisTick(centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXScale(domain: centeredDomain(forCount: indexedPoints.count))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        axisLabelsLayer(proxy: proxy, geometry: geometry)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 260)
            }
        }
    }

    private var paidGradient: LinearGradient {
        LinearGradient(colors: [Color.blue, Color.mint], startPoint: .bottom, endPoint: .top)
    }

    private var unpaidGradient: LinearGradient {
        LinearGradient(colors: [Color.orange, Color.red], startPoint: .bottom, endPoint: .top)
    }

    private var axisPositions: [Double] {
        indexedPoints.map { centeredValue(for: $0.index) }
    }

    private func centeredValue(for index: Int) -> Double {
        Double(index) + 0.5
    }

    @ViewBuilder
    private func axisLabelsLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plotFrame = proxy.plotAreaFrame
        let plotRect = geometry[plotFrame]
        ForEach(Array(indexedPoints.enumerated()), id: \.offset) { entry in
            if let positionX = proxy.position(forX: centeredValue(for: entry.element.index)) {
                Text(billingAxisLabel(for: entry.element.point))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: plotRect.origin.x + positionX, y: plotRect.maxY + 14)
            }
        }
    }
}

struct ChartPlaceholder: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct PlaceholderRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

struct EmptyStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct StateFeedbackBanner: View {
    let state: AppViewModel.LoadState

    @ViewBuilder
    var body: some View {
        if case .failed(let message) = state {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .font(.footnote)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.9), in: Capsule())
        }
    }
}

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                Text("取得中…")
                    .font(.title3.bold())
            }
            .padding(32)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct UsageChartPoint: Identifiable, Equatable {
    let id = UUID()
    let displayLabel: String
    let rawKey: String
    let value: Double
    let sortKey: Int
    let date: Date?

    init(rawKey: String, displayLabel: String, value: Double, date: Date?) {
        self.rawKey = rawKey
        self.displayLabel = displayLabel
        self.value = value
        self.date = date
        if let date {
            sortKey = date.chartSortKey
        } else {
            sortKey = rawKey.numericIdentifier
        }
    }
}

struct BillChartPoint: Identifiable {
    let id: String
    let label: String
    let value: Double
    let isUnpaid: Bool
    let sortKey: Int
    let date: Date?
}

private func monthlyChartPoints(from services: [MonthlyUsageService]) -> [UsageChartPoint] {
    struct Aggregate { var total: Double; var date: Date? }
    var accumulator: [String: Aggregate] = [:]

    for service in services {
        for entry in service.entries {
            let label = entry.monthLabel
            let addition = entry.hasData ? (entry.highSpeedGB ?? 0) + (entry.lowSpeedGB ?? 0) : 0
            var aggregate = accumulator[label] ?? Aggregate(total: 0, date: parseYearMonth(from: label))
            aggregate.total += addition
            if aggregate.date == nil {
                aggregate.date = parseYearMonth(from: label)
            }
            accumulator[label] = aggregate
        }
    }

    let points = accumulator.map { key, bucket in
        UsageChartPoint(
            rawKey: key,
            displayLabel: monthDisplayLabel(from: key),
            value: bucket.total,
            date: bucket.date ?? parseYearMonth(from: key)
        )
    }
    let sorted = points.sorted { $0.sortKey < $1.sortKey }
    return Array(sorted.suffix(6))
}

private func dailyChartPoints(from services: [DailyUsageService]) -> [UsageChartPoint] {
    struct Aggregate { var total: Double; var date: Date? }
    var accumulator: [String: Aggregate] = [:]

    for service in services {
        for entry in service.entries {
            let label = entry.dateLabel
            let addition = entry.hasData ? (entry.highSpeedMB ?? 0) + (entry.lowSpeedMB ?? 0) : 0
            var aggregate = accumulator[label] ?? Aggregate(total: 0, date: parseYearMonthDay(from: label))
            aggregate.total += addition
            if aggregate.date == nil {
                aggregate.date = parseYearMonthDay(from: label)
            }
            accumulator[label] = aggregate
        }
    }

    let points = accumulator.map { key, bucket in
        UsageChartPoint(
            rawKey: key,
            displayLabel: dayDisplayLabel(from: key),
            value: bucket.total,
            date: bucket.date ?? parseYearMonthDay(from: key)
        )
    }
    let sorted = points.sorted { $0.sortKey < $1.sortKey }
    return sorted
}

private func billingChartPoints(from bill: BillSummaryResponse) -> [BillChartPoint] {
    let points = bill.billList.map { entry in
        let date = parseYearMonth(from: entry.month ?? "")
        return BillChartPoint(
            id: entry.id,
            label: entry.formattedMonth,
            value: Double(entry.totalAmount ?? 0),
            isUnpaid: entry.isUnpaid == true,
            sortKey: date?.chartSortKey ?? entry.monthNumericValue,
            date: date
        )
    }
    let sorted = points.sorted { $0.sortKey < $1.sortKey }
    return Array(sorted.suffix(6))
}

private func billingAxisLabel(for point: BillChartPoint) -> String {
    if let date = point.date {
        return monthAxisLabel(for: date)
    }
    return point.label
}

private func discreteDomain(forCount count: Int) -> ClosedRange<Double> {
    guard count > 0 else { return -0.5...0.5 }
    let upperBound = Double(count - 1) + 0.5
    return -0.5...upperBound
}

private func centeredDomain(forCount count: Int) -> ClosedRange<Double> {
    guard count > 0 else { return 0...1 }
    return 0...Double(count)
}

private extension BillSummaryResponse {
    var latestEntry: BillEntry? {
        billList.max(by: { $0.monthNumericValue < $1.monthNumericValue })
    }
}

private extension BillSummaryResponse.BillEntry {
    var monthNumericValue: Int {
        if let month, let date = parseYearMonth(from: month) {
            return date.chartSortKey
        }
        return (month ?? "").numericIdentifier
    }

    var plainAmountText: String {
        guard let totalAmount else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: totalAmount)) ?? "\(totalAmount)"
        return "\(number)円"
    }
}

private extension String {
    var numericIdentifier: Int {
        Int(filter(\.isNumber)) ?? 0
    }
}

private extension Date {
    var chartSortKey: Int {
        Int(timeIntervalSinceReferenceDate)
    }
}

private func monthDisplayLabel(from raw: String) -> String {
    guard let date = parseYearMonth(from: raw) else { return raw }
    return monthAxisLabel(for: date)
}

private func dayDisplayLabel(from raw: String) -> String {
    guard let date = parseYearMonthDay(from: raw) else { return raw }
    return dayAxisLabel(for: date)
}

private func numericSegments(in label: String) -> [Int] {
    var segments: [Int] = []
    var buffer = ""

    for character in label {
        if character.isNumber {
            buffer.append(character)
        } else if !buffer.isEmpty {
            if let value = Int(buffer) {
                segments.append(value)
            }
            buffer.removeAll(keepingCapacity: true)
        }
    }

    if !buffer.isEmpty, let value = Int(buffer) {
        segments.append(value)
    }

    return segments
}

private func parseYearMonth(from label: String) -> Date? {
    guard let parts = extractDateParts(from: label), let month = parts.month else { return nil }
    let calendar = Calendar.current
    var components = DateComponents()
    components.year = parts.year ?? calendar.component(.year, from: Date())
    components.month = month
    components.day = 1
    return calendar.date(from: components)
}

private func parseYearMonthDay(from label: String) -> Date? {
    guard let parts = extractDateParts(from: label), let month = parts.month else {
        return parseYearMonth(from: label)
    }
    let calendar = Calendar.current
    var components = DateComponents()
    components.year = parts.year ?? calendar.component(.year, from: Date())
    components.month = month
    components.day = parts.day ?? 1
    return calendar.date(from: components) ?? parseYearMonth(from: label)
}

private func extractDateParts(from label: String) -> (year: Int?, month: Int?, day: Int?)? {
    let segments = numericSegments(in: label)
    if let parts = datePartsFromSegments(segments) {
        return parts
    }
    let digits = label.filter(\.isNumber)
    return datePartsFromDigits(digits)
}

private func datePartsFromSegments(_ segments: [Int]) -> (year: Int?, month: Int?, day: Int?)? {
    guard !segments.isEmpty else { return nil }

    if segments.count >= 3 {
        if let first = segments.first, first >= 1000 {
            return (first, segments[1], segments[2])
        }
        if let last = segments.last, last >= 1000 {
            return (last, segments[0], segments[1])
        }
    }

    if segments.count == 2 {
        if let first = segments.first, first >= 1000 {
            return (first, segments[1], nil)
        }
        if let last = segments.last, last >= 1000 {
            return (last, segments[0], nil)
        }
        return (nil, segments[0], segments[1])
    }

    if let first = segments.first, first < 1000 {
        return (nil, first, nil)
    }

    return nil
}

private func datePartsFromDigits(_ digits: String) -> (year: Int?, month: Int?, day: Int?)? {
    guard digits.count >= 5 else { return nil }
    guard let year = Int(digits.prefix(4)) else { return nil }
    let remainder = digits.dropFirst(4)
    guard !remainder.isEmpty else { return (year, nil, nil) }

    let monthLength = remainder.count == 1 ? 1 : 2
    guard let month = Int(String(remainder.prefix(monthLength))) else { return (year, nil, nil) }

    let dayRemainder = remainder.dropFirst(monthLength)
    guard !dayRemainder.isEmpty else { return (year, month, nil) }

    let dayLength = min(2, dayRemainder.count)
    guard dayLength > 0 else { return (year, month, nil) }
    guard let day = Int(String(dayRemainder.prefix(dayLength))) else { return (year, month, nil) }

    return (year, month, day)
}

private func monthAxisLabel(for date: Date) -> String {
    let month = Calendar.current.component(.month, from: date)
    return "\(month)月"
}

private func dayAxisLabel(for date: Date) -> String {
    let components = Calendar.current.dateComponents([.month, .day], from: date)
    guard let month = components.month, let day = components.day else { return "" }
    return "\(month)/\(day)"
}

private let repositoryURL = URL(string: "https://github.com/yyyywaiwai/IIJWidget")!

struct BillSummaryList: View {
    let bill: BillSummaryResponse
    private var entries: [BillSummaryResponse.BillEntry] {
        Array(bill.billList.prefix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("直近の請求金額")
                .font(.headline)

            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.formattedMonth)
                            .font(.subheadline)
                        if entry.isUnpaid == true {
                            Text("未払い")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Text(entry.formattedAmount)
                        .font(.body.bold())
                        .monospacedDigit()
                }
                .padding(.vertical, 6)

                if entry.id != entries.last?.id {
                    Divider()
                }
            }
        }
    }
}

struct ServiceInfoCard: View {
    let info: MemberTopResponse.ServiceInfo
    let latestBillAmount: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.displayPlanName)
                        .font(.headline)
                    Text("電話番号: \(info.phoneLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if let remaining = info.remainingDataGB {
                        Text("残量 \(remaining, specifier: "%.2f")GB")
                            .font(.headline)
                            .monospacedDigit()
                    }
                    if let latestBillAmount {
                        Text(latestBillAmount)
                            .font(.headline.weight(.semibold))
                    }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private func progressValue(remaining: Double?, total: Double) -> Double {
        guard let remaining else { return 0 }
        let used = max(total - remaining, 0)
        return min(used / total, 1)
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

struct ChartCallout: View {
    let title: String
    let valueText: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.bold())
            Text(valueText)
                .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: 8, y: 4)
        )
    }

    private var backgroundColor: Color {
        if colorScheme == .light {
            return Color(uiColor: .systemBackground).opacity(0.95)
        }
        return Color(uiColor: .secondarySystemBackground).opacity(0.85)
    }

    private var shadowColor: Color {
        colorScheme == .light ? Color.black.opacity(0.08) : Color.black.opacity(0.3)
    }
}

#Preview {
    ContentView()
}
