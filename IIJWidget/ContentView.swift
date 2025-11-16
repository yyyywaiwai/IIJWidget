import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedSection: AppSection = .home
    @State private var isOnboardingPresented = false
    @FocusState private var focusedField: CredentialsField?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            MainTabView(
                viewModel: viewModel,
                selectedSection: $selectedSection,
                hasCompletedOnboarding: $hasCompletedOnboarding,
                focusedField: $focusedField,
                payload: loadedPayload,
                presentOnboarding: { isOnboardingPresented = true }
            )
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

    private func evaluateOnboardingPresentation() {
        if !hasCompletedOnboarding && !viewModel.hasStoredCredentials {
            isOnboardingPresented = true
        }
    }
}

#Preview {
    ContentView()
}
