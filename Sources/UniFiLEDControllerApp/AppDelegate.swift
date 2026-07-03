import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app activates and comes to front
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Bring any restored window forward, otherwise request a new main window.
        DispatchQueue.main.async {
            if !self.bringExistingWindowToFront() {
                self.reopenMainWindow?()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }

        if !bringExistingWindowToFront() {
            reopenMainWindow?()
        }

        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when window is closed (for background scheduling)
        return false
    }

    @discardableResult
    private func bringExistingWindowToFront() -> Bool {
        guard let window = NSApp.windows.first else {
            return false
        }

        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
        return true
    }
}
