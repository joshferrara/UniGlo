// Marketing screenshot harness for UniGlo.
//
// Renders the real app UI with polished demo data straight to PNG — including
// hand-drawn window chrome (traffic lights + tab pills) — in light AND dark,
// with no screen-recording permission and no dependence on window focus for
// most of the rendering. Used to generate images/uniglo-*.png on the gh-pages
// marketing site.
//
// HOW TO WIRE IT UP (in a scratch worktree of `main`, don't commit):
//   1. Copy this file to Sources/UniFiLEDControllerApp/SnapshotRunner.swift
//   2. main.swift — replace `@main` on the App struct with:
//        @main
//        enum AppEntry {
//            static func main() {
//                if CommandLine.arguments.contains("--snapshot") {
//                    SnapshotRunner.run()
//                } else {
//                    UniFiLEDControllerApp.main()
//                }
//            }
//        }
//   3. MainView.swift — add `init(initialTab: Int = 0)` with
//      `@State private var selection: Int` and `.tag(0/1/2)` on the tab items
//      (the harness hosts DevicesView/SchedulesView/SettingsView directly, so
//      this is only needed if you host MainView instead).
//   4. Sparkle/SparkleUpdater.swift — pass
//      `startingUpdater: !CommandLine.arguments.contains("--snapshot")`.
//
// RUN (two passes; appearance must be fixed per process or the titlebar
// materials render wrong):
//   swift build
//   ./.build/debug/UniFiLEDControllerApp --snapshot /tmp/shots
//   ./.build/debug/UniFiLEDControllerApp --snapshot /tmp/shots --dark
//   rm /tmp/shots/uniglo-warmup.png
//
// GOTCHAS learned the hard way:
//   • cacheDisplay can't composite the native SwiftUI TabView titlebar
//     material in dark mode (renders as a white blob) — hence SnapshotChrome.
//   • SwiftUI controls draw greyed-out unless the app is genuinely active;
//     .environment(\.controlActiveState, .key) alone is NOT enough for
//     AppKit-bridged controls (switches), so the harness retries activation.
//   • The first capture can race activation — that's what the warmup shot is
//     for (discard it).

import AppKit
import SwiftUI

@MainActor
enum SnapshotRunner {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = SnapshotDelegate()
        app.delegate = delegate
        app.run()
    }
}

/// Always draws as the key/main window so controls render in their active
/// (tinted) state even when the harness doesn't actually have focus.
final class SnapshotWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hand-drawn window chrome (traffic lights + tab picker) that renders
/// identically in light/dark via cacheDisplay, unlike the native titlebar
/// materials which cacheDisplay can't composite.
struct SnapshotChrome<Content: View>: View {
    let selectedTab: Int
    let tabs = ["Devices", "Schedules", "Settings"]
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.0, green: 0.373, blue: 0.341)).frame(width: 13, height: 13)
                    Circle().fill(Color(red: 1.0, green: 0.737, blue: 0.180)).frame(width: 13, height: 13)
                    Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.255)).frame(width: 13, height: 13)
                    Spacer()
                }
                .padding(.leading, 20)
                HStack(spacing: 4) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, title in
                        Text(title)
                            .font(.system(size: 15))
                            .fontWeight(index == selectedTab ? .medium : .regular)
                            .foregroundStyle(index == selectedTab ? .primary : .secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(index == selectedTab ? Color.primary.opacity(0.09) : Color.clear)
                            )
                    }
                }
            }
            .frame(height: 54)
            Divider()
            content
        }
    }
}

@MainActor
final class SnapshotDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    private var outputDir: URL {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--snapshot"), args.count > idx + 1 {
            return URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("shots")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        NSApp.activate(ignoringOtherApps: true)

        struct Shot {
            let name: String
            let dark: Bool
            let tab: Int?   // nil = schedule editor
        }

        let darkOnly = CommandLine.arguments.contains("--dark")
        let suffix = darkOnly ? "dark" : "light"
        NSApp.appearance = NSAppearance(named: darkOnly ? .darkAqua : .aqua)

        let shots: [Shot] = [
            Shot(name: "warmup", dark: darkOnly, tab: 0),
            Shot(name: "devices-\(suffix)", dark: darkOnly, tab: 0),
            Shot(name: "schedules-\(suffix)", dark: darkOnly, tab: 1),
            Shot(name: "settings-\(suffix)", dark: darkOnly, tab: 2),
            Shot(name: "editor-\(suffix)", dark: darkOnly, tab: nil),
        ]

        var queue = shots

        func processNext() {
            guard !queue.isEmpty else {
                exit(0)
            }
            let shot = queue.removeFirst()
            let window = self.makeWindow(for: shot.tab, dark: shot.dark)
            self.windows.append(window)
            window.makeKeyAndOrderFront(nil)

            // Genuine activation is required for controls to draw in their
            // tinted/active state; retry until macOS grants it.
            func waitUntilActive(_ tries: Int, then: @escaping () -> Void) {
                if NSApp.isActive || tries <= 0 {
                    window.makeKeyAndOrderFront(nil)
                    then()
                    return
                }
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    waitUntilActive(tries - 1, then: then)
                }
            }

            waitUntilActive(40) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.capture(window: window, name: shot.name)
                    window.orderOut(nil)
                    processNext()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            processNext()
        }
    }

    private func makeWindow(for tab: Int?, dark: Bool) -> NSWindow {
        let appState = Self.demoAppState()
        let sparkle = SparkleUpdater()

        let window: NSWindow
        if let tab {
            let view = SnapshotChrome(selectedTab: tab) {
                Group {
                    switch tab {
                    case 0: DevicesView()
                    case 1: SchedulesView()
                    default: SettingsView().environmentObject(sparkle)
                    }
                }
                .frame(width: 1080, height: 700)
            }
            .environmentObject(appState)
            .environmentObject(sparkle)
            .environment(\.controlActiveState, .key)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            window = SnapshotWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 754),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.contentView = NSHostingView(rootView: view)
        } else {
            // Schedule editor, presented like the in-app sheet
            let editorSchedule = Self.demoSchedules().first!
            let view = ScheduleEditor(schedule: editorSchedule, onSave: { _ in })
                .environmentObject(appState)
                .environmentObject(sparkle)
                .environment(\.controlActiveState, .key)
                .frame(width: 780, height: 760)
            window = SnapshotWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 760),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.contentView = NSHostingView(rootView: view)
        }

        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }

    private func capture(window: NSWindow, name: String) {
        guard let frameView = window.contentView?.superview else { return }
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = outputDir.appendingPathComponent("uniglo-\(name).png")
        try? data.write(to: url)
        print("wrote \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
    }

    // MARK: - Demo data

    static func demoDevices() -> [AccessPoint] {
        [
            AccessPoint(
                deviceId: "demo-1", name: "Living Room", ipAddress: "192.168.1.20",
                macAddress: "aa:bb:cc:00:00:01", ledEnabled: true, lastSeen: Date(), isOnline: true
            ),
            AccessPoint(
                deviceId: "demo-2", name: "Home Office", ipAddress: "192.168.1.21",
                macAddress: "aa:bb:cc:00:00:02", ledEnabled: true, lastSeen: Date(), isOnline: true
            ),
            AccessPoint(
                deviceId: "demo-3", name: "Upstairs Hallway", ipAddress: "192.168.1.22",
                macAddress: "aa:bb:cc:00:00:03", ledEnabled: false, lastSeen: Date(), isOnline: true
            ),
            AccessPoint(
                deviceId: "demo-4", name: "Garage", ipAddress: "192.168.1.23",
                macAddress: "aa:bb:cc:00:00:04", ledEnabled: true, lastSeen: Date(), isOnline: true
            ),
        ]
    }

    static func demoSchedules() -> [Schedule] {
        let weekdays: [DayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let weeknights = Schedule(
            name: "Weeknights",
            enabled: true,
            assignments: ["aa:bb:cc:00:00:01", "aa:bb:cc:00:00:03"],
            rules: weekdays.map { ScheduleRule(day: $0, onTime: 7 * 3600, offTime: 23 * 3600) }
        )
        let weekend = Schedule(
            name: "Weekend",
            enabled: true,
            assignments: ["aa:bb:cc:00:00:01", "aa:bb:cc:00:00:02", "aa:bb:cc:00:00:03", "aa:bb:cc:00:00:04"],
            rules: [
                ScheduleRule(day: .saturday, onTime: 8 * 3600 + 1800, offTime: 23 * 3600 + 1800),
                ScheduleRule(day: .sunday, onTime: 8 * 3600 + 1800, offTime: 22 * 3600),
            ]
        )
        return [weeknights, weekend]
    }

    static func demoAppState() -> AppState {
        let state = AppState()
        state.devices = demoDevices()
        state.schedules = demoSchedules()
        var config = ControllerConfig()
        config.baseURL = URL(string: "https://192.168.1.1")
        config.username = "uniglo"
        config.password = "demo-password"
        state.controllerConfig = config
        return state
    }
}
