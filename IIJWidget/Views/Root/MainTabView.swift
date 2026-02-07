import SwiftUI

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selectedSection: AppSection
    @Binding var hasCompletedOnboarding: Bool
    let payload: AggregatePayload?
    let isRefreshing: Bool
    let presentOnboarding: () -> Void

    var body: some View {
        TabView(selection: $selectedSection) {
            Group {
                HomeDashboardTab(
                    payload: payload,
                    isRefreshing: isRefreshing,
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
                    isRefreshing: isRefreshing,
                    accentColors: viewModel.accentColors,
                    usageAlertSettings: viewModel.usageAlertSettings,
                    showsLowSpeedUsage: viewModel.displayPreferences.showsLowSpeedUsage,
                    hidePhoneOnScreenshot: viewModel.displayPreferences.hidePhoneOnScreenshot
                )
                .tabItem { Label(AppSection.usage.title, systemImage: AppSection.usage.iconName) }
                .tag(AppSection.usage)

                BillingTabView(
                    viewModel: viewModel,
                    bill: payload?.bill,
                    isRefreshing: isRefreshing,
                    accentColors: viewModel.accentColors,
                    showsBillingChart: viewModel.displayPreferences.showsBillingChart
                )
                    .tabItem { Label(AppSection.billing.title, systemImage: AppSection.billing.iconName) }
                    .tag(AppSection.billing)

                SettingsTab(
                    viewModel: viewModel,
                    hasCompletedOnboarding: $hasCompletedOnboarding,
                    presentOnboarding: presentOnboarding
                )
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.iconName) }
                .tag(AppSection.settings)
            }
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
    }
}
