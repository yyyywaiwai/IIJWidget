import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selectedSection: AppSection
    @Binding var hasCompletedOnboarding: Bool
    let focusedField: FocusState<CredentialsField?>.Binding
    let payload: AggregatePayload?
    let presentOnboarding: () -> Void

    var body: some View {
        TabView(selection: $selectedSection) {
            HomeDashboardTab(
                payload: payload,
                accentColors: viewModel.accentColors,
                usageAlertSettings: viewModel.usageAlertSettings,
                defaultUsageChart: viewModel.displayPreferences.defaultUsageChart,
                hidePhoneOnScreenshot: viewModel.displayPreferences.hidePhoneOnScreenshot,
                saveDefaultUsageChart: viewModel.updateDefaultUsageChart
            )
                .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.iconName) }
                .tag(AppSection.home)

            UsageListTab(
                monthly: payload?.monthlyUsage ?? [],
                daily: payload?.dailyUsage ?? [],
                serviceStatus: payload?.serviceStatus,
                accentColors: viewModel.accentColors,
                usageAlertSettings: viewModel.usageAlertSettings,
                showsLowSpeedUsage: viewModel.displayPreferences.showsLowSpeedUsage,
                hidePhoneOnScreenshot: viewModel.displayPreferences.hidePhoneOnScreenshot
            )
            .tabItem { Label(AppSection.usage.title, systemImage: AppSection.usage.iconName) }
            .tag(AppSection.usage)

            BillingTabView(viewModel: viewModel, bill: payload?.bill, accentColors: viewModel.accentColors)
                .tabItem { Label(AppSection.billing.title, systemImage: AppSection.billing.iconName) }
                .tag(AppSection.billing)

            SettingsTab(
                viewModel: viewModel,
                focusedField: focusedField,
                hasCompletedOnboarding: $hasCompletedOnboarding,
                presentOnboarding: presentOnboarding
            )
            .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.iconName) }
            .tag(AppSection.settings)
        }
    }
}
