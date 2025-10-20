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
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(appState)
                .task {
                    // Load persisted settings when app starts
                    await appState.loadPersistedState()

                    // Configure scheduler with appState
                    await appState.scheduler.configure(with: appState)

                    // Auto-refresh devices if we have valid configuration
                    if appState.controllerConfig.baseURL != nil && !appState.controllerConfig.username.isEmpty {
                        await appState.refreshDevices()
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
        .defaultSize(CGSize(width: 900, height: 600))
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
