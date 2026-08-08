import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedSection: AppSection = .home
    @State private var isOnboardingPresented = false
    @State private var errorToastID = UUID()
    @State private var dismissedErrorToastID: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            MainTabView(
                viewModel: viewModel,
                selectedSection: $selectedSection,
                hasCompletedOnboarding: $hasCompletedOnboarding,
                payload: loadedPayload,
                presentOnboarding: { isOnboardingPresented = true }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.refreshManually()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("最新取得", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let message = errorMessage, dismissedErrorToastID != errorToastID {
                    StateFeedbackBanner(message: message) {
                        dismissedErrorToastID = errorToastID
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if isLoading && loadedPayload == nil {
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.triggerAutomaticRefreshIfNeeded() }
        }
        .onReceive(viewModel.$state) { state in
            guard case .failed = state else { return }
            errorToastID = UUID()
            dismissedErrorToastID = nil
        }
        .onChange(of: viewModel.hasStoredCredentials) { _, _ in
            evaluateOnboardingPresentation()
        }
        .sensoryFeedback(.error, trigger: errorToastID)
    }

    private var loadedPayload: AggregatePayload? {
        switch viewModel.state {
        case .loaded(let payload):
            return payload
        case .loading(let previous):
            return previous
        case .failed(_, let last):
            return last
        case .idle:
            return nil
        }
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state {
            return true
        }
        return false
    }

    private var errorMessage: String? {
        if case .failed(let message, _) = viewModel.state {
            return message
        }
        return nil
    }

    private func evaluateOnboardingPresentation() {
        if !hasCompletedOnboarding && !viewModel.hasStoredCredentials {
            isOnboardingPresented = true
        }
    }
}

#Preview {
    ContentView()
}
