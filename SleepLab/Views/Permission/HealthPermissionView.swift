import SwiftUI

struct HealthPermissionView: View {
    let isRequesting: Bool
    let errorMessage: String?
    let isDenied: Bool
    let onAuthorize: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(SleepPalette.cardStroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)

                Text("REMLogic")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(SleepPalette.titleText)

                Text("Grant Health access to import sleep stages, heart rate, HRV, respiratory rate, and workouts.")
                    .font(.body)
                    .foregroundStyle(SleepPalette.mutedText)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Sleep stages", systemImage: "moon.zzz")
                Label("Heart rate and HRV", systemImage: "heart.fill")
                Label("Respiratory rate", systemImage: "wind")
                Label("Workouts", systemImage: "figure.run")
            }
            .font(.subheadline.weight(.medium))
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SleepPalette.panelSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: onAuthorize) {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text("Allow Health Access")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(SleepPalette.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isRequesting)

            if isDenied {
                Button("Open iOS Settings", action: onOpenSettings)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SleepPalette.primary)
            }
        }
        .padding(24)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
