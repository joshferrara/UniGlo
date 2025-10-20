## UniFi LED macOS Menu Bar App — Implementation Plan

### 1. Architecture & Foundation
- Create a SwiftUI macOS 13+ app with an AppDelegate-backed NSStatusItem showing the SF Symbol `lightbulb` icon; primary click calls a window manager that activates the app (`NSApp.activate(ignoringOtherApps: true)`) and presents the main SwiftUI window (default 900×600).
- Structure the UI with a root `TabView` containing **Devices**, **Schedules**, and **Settings** tabs.

### 2. LED Control Module
- Build a `UniFiControllerClient` handling HTTPS login, session cookies, and JSON REST calls; expose async APIs to fetch AP inventory and toggle LEDs via `POST /api/s/<site>/set/setting/mgmt` with `{ "led_enabled": true|false }` (per Marin Franković’s LED scheduling article, 2018).
- Support per-device overrides by calling device-specific endpoints or, when the controller lacks granular control, fall back to SSH-based commands that write `/proc/gpio/led_pattern` or `/var/etc/persistent/cfg/mgmt` values (Home Assistant community thread, Apr 2020) for advanced patterns.
- Include commands for bulk on/off, temporary overrides with timers, and optional “Locate/Blink” patterns if supported.

### 3. Device Discovery & Management
- Implement mDNS/Bonjour discovery for UniFi APs on the LAN; when unavailable, allow manual entry of IP/hostname and associate with controller inventory.
- Persist device metadata (name, MAC, IP, last seen, firmware, current LED state) locally; flag offline devices and queue LED actions for retry.

### 4. Authentication & Security
- Support username/password and token-based UniFi controller auth; store credentials securely in macOS Keychain using `SecItemAdd`/`SecItemUpdate`.
- Provide UI to select site, accept self-signed certificates, and handle session expiry with prompts.

### 5. Scheduling Engine
- Design a schedule model: name, enabled flag, per-day on/off rules, target AP assignments, optional exceptions, and priority for overlapping schedules.
- Persist schedules in SQLite (via GRDB/CoreData) or JSON with versioned schema; ensure edits/add/duplicate/delete flows.
- Implement a scheduler service using `DispatchSourceTimer`/`Timer` on a dedicated actor, recalculating triggers on app launch, wake (`NSWorkspace.screensDidWakeNotification`), and `NSCalendarDayChanged`, accounting for DST and manual clock shifts.

### 6. Temporary Overrides & Notifications
- Allow per-AP or bulk temporary overrides (e.g., off for N minutes); store countdown state and resume scheduled behavior afterward.
- Optionally integrate `UNUserNotificationCenter` to surface banner notifications when schedules trigger or overrides expire.

### 7. Settings & Preferences
- Settings tab to manage controller details, discovery toggles, timezone (default system), autostart via `SMAppService`, diagnostics logging toggle, and optional Sparkle updates.
- Provide a minimal right-click menu with About/Check for Updates/Quit if implemented.

### 8. Persistence & State Restoration
- Save window/tab selection and last-used filters; ensure data and schedules persist across launches and sync with background scheduler on launch.

### 9. Testing & Validation
- Write unit tests for scheduling calculations and UniFi controller API parsing (mocking network responses).
- Manual QA checklist: menu bar activation behavior, multi-AP bulk toggles, schedule execution across DST transition, offline AP handling, Keychain storage, temporary override expiry, and fallback SSH control.

### 10. Milestones
1. Skeleton app & menu bar integration.
2. UniFi controller client (login, inventory, LED toggle) with mock data.
3. Device list UI and per-device control.
4. Persistence layer & scheduler engine.
5. Overrides, notifications, and discovery enhancements.
6. Final polish (autostart, optional updates) and testing.
