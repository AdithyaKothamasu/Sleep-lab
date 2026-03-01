import SwiftUI

struct AgentSettingsView: View {
    @EnvironmentObject private var viewModel: SleepLabViewModel
    @State private var isEnabled = AgentSettings.isEnabled
    @State private var connectionCode = AgentSettings.connectionCode ?? ""
    @State private var isRegistering = false
    @State private var isRevoking = false
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var showCopiedToast = false
    @State private var lastSyncText = ""

    private let agentSyncService = AgentSyncService()
    private let syncTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                headerCard

                // Connection toggle
                connectionCard

                // Connection code (when enabled)
                if isEnabled && !connectionCode.isEmpty {
                    connectionCodeCard
                }

                // Sync status (when enabled)
                if isEnabled {
                    syncStatusCard
                }

                // Danger zone
                if isEnabled {
                    disconnectCard
                }
            }
            .padding(16)
        }
        .background(Color.clear)
        .navigationTitle("AI Agent")
        .onAppear {
            updateLastSyncText()
        }
        .onReceive(syncTimer) { _ in
            updateLastSyncText()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(SleepPalette.primary)
                    .frame(width: 36, height: 36)
                    .background(SleepPalette.iconCircle)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect AI Agent")
                        .font(.headline)
                        .foregroundStyle(SleepPalette.titleText)

                    Text("Let your AI assistant access your sleep data")
                        .font(.caption)
                        .foregroundStyle(SleepPalette.mutedText)
                }
            }

            Text("Your sleep data is encrypted on the server. Only someone with your connection code can access it.")
                .font(.caption2)
                .foregroundStyle(SleepPalette.mutedText)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Connection Toggle

    private var connectionCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent Access")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SleepPalette.titleText)

                Text(isEnabled ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(isEnabled ? SleepPalette.accent : SleepPalette.mutedText)
            }

            Spacer()

            if isRegistering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            } else {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, newValue in
                        handleToggle(newValue)
                    }
            }
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Connection Code

    private var connectionCodeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connection Code")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SleepPalette.titleText)

                Spacer()

                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.accent)
            }

            Text("Paste this into your AI agent to connect")
                .font(.caption)
                .foregroundStyle(SleepPalette.mutedText)

            Button {
                UIPasteboard.general.string = connectionCode
                withAnimation {
                    showCopiedToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showCopiedToast = false
                    }
                }
            } label: {
                HStack {
                    Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)

                    Text(showCopiedToast ? "Copied!" : "Copy Connection Code")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(SleepPalette.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Sync Status

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sync Status")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SleepPalette.titleText)

                Spacer()

                if isSyncing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                }
            }

            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)

                Text(lastSyncText.isEmpty ? "Never synced" : "Last synced: \(lastSyncText)")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.mutedText)
            }

            Button {
                Task { await triggerSync() }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                    Text("Sync Now")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(SleepPalette.panelSecondary)
                .foregroundStyle(SleepPalette.titleText)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isSyncing)
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Disconnect

    private var disconnectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Disconnect")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SleepPalette.titleText)

            Text("Revokes agent access and deletes all synced data from the server.")
                .font(.caption)
                .foregroundStyle(SleepPalette.mutedText)

            Button(role: .destructive) {
                Task { await disconnect() }
            } label: {
                HStack {
                    if isRevoking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .tint(.white)
                    }

                    Text(isRevoking ? "Disconnecting..." : "Disconnect & Delete Data")
                        .font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isRevoking)
        }
        .padding(16)
        .background(SleepPalette.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SleepPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Actions

    private func handleToggle(_ newValue: Bool) {
        if newValue {
            isRegistering = true
            Task {
                do {
                    let response = try await agentSyncService.registerApiKey()
                    AgentSettings.apiKey = response.apiKey
                    AgentSettings.connectionCode = response.connectionCode
                    AgentSettings.isEnabled = true
                    connectionCode = response.connectionCode
                    isRegistering = false
                } catch {
                    isEnabled = false
                    AgentSettings.isEnabled = false
                    errorMessage = error.localizedDescription
                    isRegistering = false
                }
            }
        } else {
            // Just disable without revoking (user might want to re-enable)
            AgentSettings.isEnabled = false
        }
    }

    private func triggerSync() async {
        guard !viewModel.sleepDays.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let payload = viewModel.buildAgentSyncPayload()
            let response = try await agentSyncService.syncDays(payload)
            AgentSettings.lastSyncDate = Date()
            updateLastSyncText()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        isRevoking = true
        defer { isRevoking = false }

        do {
            try await agentSyncService.revokeAccess()
            AgentSettings.clearAll()
            isEnabled = false
            connectionCode = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateLastSyncText() {
        guard let lastSync = AgentSettings.lastSyncDate else {
            lastSyncText = ""
            return
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        lastSyncText = formatter.localizedString(for: lastSync, relativeTo: Date())
    }
}
