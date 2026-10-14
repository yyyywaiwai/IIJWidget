import SwiftUI

struct SettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var hasCompletedOnboarding: Bool
    let presentOnboarding: () -> Void

    var body: some View {
        Form {
            UsageAlertSettingsSection(settings: Binding(
                get: { viewModel.usageAlertSettings },
                set: { viewModel.updateUsageAlertSettings($0) }
            ))

            DisplaySettingsSection(
                accentColors: viewModel.accentColors,
                updateAccentColor: { viewModel.updateAccentColor(for: $0, to: $1) },
                showsLowSpeedUsage: Binding(
                    get: { viewModel.displayPreferences.showsLowSpeedUsage },
                    set: { viewModel.updateShowsLowSpeedUsage($0) }
                ),
                showsBillingChart: Binding(
                    get: { viewModel.displayPreferences.showsBillingChart },
                    set: { viewModel.updateShowsBillingChart($0) }
                ),
                hidePhoneOnScreenshot: Binding(
                    get: { viewModel.displayPreferences.hidePhoneOnScreenshot },
                    set: { viewModel.updateHidePhoneOnScreenshot($0) }
                )
            )

            SettingsProjectSection()
            SettingsDebugSection()
            SettingsLogoutSection(performLogout: performLogout)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private func performLogout() throws {
        try viewModel.logout()
        hasCompletedOnboarding = false
        presentOnboarding()
    }
}
