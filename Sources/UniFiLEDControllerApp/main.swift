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
        WindowGroup("UniFi LED Controller") {
            MainView()
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(appState)
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
