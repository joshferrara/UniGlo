import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var configDraft: ControllerConfig = .init()
    @State private var baseURLText: String = ""
    @State private var isPersisting = false

    var body: some View {
        Form {
            Section(header: Text("Controller")) {
                TextField("Controller URL", text: $baseURLText)
                TextField("Site", text: $configDraft.site)
                TextField("Username", text: $configDraft.username)
                SecureField("Password", text: $configDraft.password)
                Toggle("Accept Invalid Certificates", isOn: $configDraft.acceptInvalidCertificates)
            }
            Section(header: Text("Login")) {
                Button("Save & Refresh") {
                    persist()
                }
                .disabled(isPersisting)
            }
        }
        .padding()
        .onAppear {
            configDraft = appState.controllerConfig
            baseURLText = appState.controllerConfig.baseURL?.absoluteString ?? ""
        }
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
        configDraft.baseURL = normalizedURL.flatMap { URL(string: $0) }
        configDraft.site = configDraft.site.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.controllerConfig = configDraft
        appState.saveState()
        Task {
            await appState.refreshDevices()
            await MainActor.run { isPersisting = false }
        }
    }
}
