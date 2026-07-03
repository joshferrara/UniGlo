import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sparkleUpdater: SparkleUpdater
    @State private var configDraft: ControllerConfig = .init()
    @State private var baseURLText: String = ""
    @State private var isPersisting = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Configure your UniFi Controller connection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            if let banner = appState.statusBanner {
                StatusBannerView(banner: banner) {
                    appState.clearStatusBanner()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    // Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color.unigloBlue)
                            Text("Getting Started")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("To use UniGlo, you'll need to create a local user account in your UniFi Network application with minimal permissions.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                if let url = URL(string: "https://joshferrara.com/UniGlo/get-started") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("View Setup Guide")
                                        .font(.subheadline)
                                    Image(systemName: "arrow.up.forward")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 500)
                    .background(cardBackground)

                    // Controller Connection Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.green)
                            Text("Controller Connection")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            // Controller URL
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Controller URL")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Required")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                TextField("https://192.168.1.1:8443", text: $baseURLText)
                                    .textFieldStyle(.roundedBorder)
                                Text("The URL of your UniFi Controller")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Site
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Site")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Optional")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                TextField("default", text: $configDraft.site)
                                    .textFieldStyle(.roundedBorder)
                                Text("Leave blank or use 'default' for the default site")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 500)
                    .background(cardBackground)

                    // Credentials Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundStyle(Color.unigloBlue)
                            Text("Credentials")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            // Username
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Username")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Required")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                TextField("admin", text: $configDraft.username)
                                    .textFieldStyle(.roundedBorder)
                                Text("Your UniFi Controller username")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Password
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Password")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Required")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                SecureField("Enter password", text: $configDraft.password)
                                    .textFieldStyle(.roundedBorder)
                                Text("Stored securely in the macOS Keychain")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 500)
                    .background(cardBackground)

                    // Security Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Accept Invalid SSL Certificates")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Enable if using self-signed certificates")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $configDraft.acceptInvalidCertificates)
                                .labelsHidden()
                                .tint(Color.unigloBlue)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 500)
                    .background(cardBackground)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                if isPersisting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving & refreshing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Save & Refresh") {
                    persist()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.unigloBlue)
                .disabled(isPersisting || !canSave)

                Button("Check for Updates…") {
                    sparkleUpdater.checkForUpdates(nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            configDraft = appState.controllerConfig
            baseURLText = appState.controllerConfig.baseURL?.absoluteString ?? ""
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var canSave: Bool {
        !baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !configDraft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !configDraft.password.isEmpty
    }

    private func persist() {
        guard !isPersisting else { return }
        isPersisting = true
        let trimmedURL = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsedURL = trimmedURL
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined()
        let normalizedURL: String?
        if collapsedURL.isEmpty {
            normalizedURL = nil
        } else if collapsedURL.contains("://") {
            normalizedURL = collapsedURL
        } else {
            normalizedURL = "https://" + collapsedURL
        }

        guard let normalizedURL,
              let url = URL(string: normalizedURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            appState.setStatus(.error, "Enter a valid controller URL, such as https://192.168.1.1:8443.")
            isPersisting = false
            return
        }

        configDraft.baseURL = url
        baseURLText = url.absoluteString
        let trimmedSite = configDraft.site.trimmingCharacters(in: .whitespacesAndNewlines)
        configDraft.site = trimmedSite.isEmpty ? "default" : trimmedSite
        configDraft.username = configDraft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.controllerConfig = configDraft
        guard appState.saveState() else {
            isPersisting = false
            return
        }

        Task {
            await appState.refreshDevices()
            await MainActor.run { isPersisting = false }
        }
    }
}
