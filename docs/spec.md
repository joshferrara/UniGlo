# macOS UniFi LED Controller — Revised Prompt

## Goal

Build a lightweight **macOS menu bar app** to control the **LED lights** on **UniFi Access Points (APs)** with **multi-AP scheduling**. The **menu bar shows a single light icon**; **clicking it opens the main app window** with all settings and schedules.

## Menu Bar UX (Critical)

* **Menu bar icon:** a **single lightbulb** (prefer SF Symbol `lightbulb`/`lightbulb.fill` or a custom vector).
* **Click behavior (primary/left-click):** **Open the main app interface** as a standard window (not a popover).

  * The icon is **not** a toggle and does **not** show a dropdown menu.
  * The main interface should **come to the foreground** (`activate(ignoringOtherApps: true)`).
* **Right-click (optional):** If implemented, show a minimal context menu with **About**, **Check for Updates**, **Quit**.
* **State indication (optional):** If desired, support **template tinting** or **dual icon** (filled vs. outline) to indicate all-LEDs-off vs. mixed/on states. This is purely visual; clicking still opens the window.

## Core Features

1. **LED Control**

   * Toggle **LED on/off** per AP and **bulk actions** (e.g., “Turn off all LEDs”).
   * **Temporary override** (e.g., “Turn off for 1 hour”), with countdown indicator.

2. **Scheduling**

   * Create **multiple schedules** (e.g., “Work Hours,” “Night Mode”).
   * Assign each schedule to **one or more APs**.
   * **Per-day rules** with explicit on/off times (e.g., “Every day ON 7:00 AM, OFF 10:00 PM” or unique times per weekday/weekend).
   * **Persistence** across launches; edit/duplicate/delete schedules.
   * System-wake and clock-change safe (handle DST/clock changes).

3. **Device Management**

   * **Auto-discovery** of APs (mDNS/Bonjour or via UniFi controller).
   * **Manual add** by IP/hostname if needed.
   * **Auth support:** UniFi Network Controller (local/Cloud Key/UDM), credentials or token; store securely in **Keychain**.

4. **Main App Interface**

   * **Tabs or sections:**

     * **Devices:** list of APs (name, IP, LED status, last seen, tags), per-device toggle.
     * **Schedules:** list, detail editor (per-day matrix), assignment to APs, enable/disable.
     * **Settings:** controller connection, discovery options, timezone, notifications, autostart at login.
   * **Notifications (optional):** banner when a schedule triggers (“Night Mode: LEDs OFF”).

## Platform & Tech

* **Language/Framework:** Swift + SwiftUI (macOS 13+).
* **Menu bar:** `NSStatusBar` status item (so clicking can open a **window**, not a popover).
* **Windows:** SwiftUI windows via `@Environment(\.openWindow)` or `NSApp.activate`.
* **Persistence:** Schedules/assignments in SQLite or JSON; **credentials in Keychain**.
* **Launch at login:** SMAppService / Login Item.
* **Updates:** optional Sparkle.

## UniFi API Notes

* Use UniFi Network API to read/write device `led_enabled` state.
* Support both **controller-mediated** updates and **local device** endpoints when applicable.
* Handle **HTTPS** (self-signed certs), **timeouts**, **errors**, and **rate limiting** gracefully.

## Edge Cases & Acceptance Criteria

* **Acceptance (menu bar):**

  * Only a **single light icon** is visible in the menu bar.
  * **Left-click opens** the **full main window**; no dropdown/popup UI.
  * App **activates to foreground** reliably even if another app is fullscreen.
* **Schedules execute** at the correct local times, including **DST** transitions.
* **Offline APs** are clearly labeled; schedule actions queue or fail gracefully.
* **Auth failures** prompt re-login; credentials remain in Keychain.
* **Uninstall safety:** local data removed on request.

---

## (Optional) Implementation Scaffold

If you’re handing this to a builder/Copilot, you can include this minimal pattern to enforce the “icon opens window” behavior:

```swift
import SwiftUI

@main
struct UniFiLEDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("UniFi LED Controller") {
            MainView() // Your tabs: Devices, Schedules, Settings
        }
        .defaultSize(CGSize(width: 900, height: 600))
        .commands {
            CommandGroup(replacing: .appInfo) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "LED Control")
            button.action = #selector(openMainWindow)
            button.target = self
        }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Find or create the main window
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Force SwiftUI to instantiate the WindowGroup
            NSApp.sendAction(#selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: nil, from: nil)
            // Replace with a custom mechanism to open the WindowGroup if needed
        }
    }
}
```

> Note: In production, replace the “AboutPanel hack” with a dedicated `WindowManager` or `openWindow(id:)` using SwiftUI’s multi-window APIs (macOS 13+).

