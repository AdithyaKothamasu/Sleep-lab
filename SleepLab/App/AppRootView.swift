import SwiftUI
import UIKit

struct AppRootView: View {
    @EnvironmentObject private var viewModel: SleepLabViewModel

    var body: some View {
        ZStack {
            SleepPalette.backgroundGradient
                .ignoresSafeArea()

            switch viewModel.loadState {
            case .idle, .denied, .failed:
                HealthPermissionView(
                    isRequesting: viewModel.loadState == .requestingAuthorization,
                    errorMessage: viewModel.errorMessage,
                    isDenied: viewModel.loadState == .denied,
                    onAuthorize: {
                        viewModel.requestAccessAndLoadTimeline()
                    },
                    onOpenSettings: {
                        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(settingsURL)
                    }
                )
                .padding(.horizontal, 20)

            case .requestingAuthorization, .loading:
                ProgressView("Importing sleep data")
                    .progressViewStyle(.circular)
                    .font(.headline)
                    .tint(SleepPalette.primary)

            case .ready:
                TimelineView()
            }
        }
        .task {
            viewModel.prepareStores()
            viewModel.checkAndLoadIfAuthorized()
        }
    }
}
