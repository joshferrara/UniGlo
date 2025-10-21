import SwiftUI

@main
struct UniFiLEDControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        // Ensure the app can become active
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("UniGlo") {
            MainView()
                .frame(minWidth: 650, minHeight: 450)
                .environmentObject(appState)
                .task {
                    // Load persisted settings when app starts
                    await appState.loadPersistedState()

                    // Configure scheduler with appState
                    await appState.scheduler.configure(with: appState)

                    // Auto-refresh devices if we have valid configuration including password
                    if appState.controllerConfig.baseURL != nil &&
                       !appState.controllerConfig.username.isEmpty &&
                       !appState.controllerConfig.password.isEmpty {
                        // Add a small delay to ensure network stack is fully initialized
                        try? await Task.sleep(for: .seconds(1))
                        await appState.refreshDevices()
                    } else if appState.controllerConfig.baseURL != nil &&
                              !appState.controllerConfig.username.isEmpty {
                        // If we have URL and username but no password, wait a moment and try loading again
                        // This handles the case where Keychain permission was just granted
                        try? await Task.sleep(for: .seconds(1))
                        await appState.loadPersistedState()

                        // Try to refresh again if we now have the password
                        // Add a small delay to let the controller/network settle
                        if !appState.controllerConfig.password.isEmpty {
                            try? await Task.sleep(for: .milliseconds(500))
                            await appState.refreshDevices()
                        }
                    }
                }
                .onAppear {
                    // Ensure window is key and accepts input
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        NSApp.windows.first?.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .defaultSize(CGSize(width: 700, height: 500))
        .commands {
            CommandGroup(replacing: .appInfo) { }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 500, height: 400)
        }
    }
}
