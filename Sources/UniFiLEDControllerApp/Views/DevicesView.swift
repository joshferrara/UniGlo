import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRefreshing = false
    @State private var isTogglingAll = false
    @State private var pendingDeviceToggles: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Access Points")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        runBulkToggle(false)
                    } label: {
                        Label("All Off", systemImage: "lightbulb.slash")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .help("Turn off all LEDs")
                    .disabled(!canSendCommands)

                    Button {
                        runBulkToggle(true)
                    } label: {
                        Label("All On", systemImage: "lightbulb")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .help("Turn on all LEDs")
                    .disabled(!canSendCommands)

                    Button {
                        refresh()
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.callout)
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh devices")
                    .disabled(isRefreshing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if let banner = appState.statusBanner {
                StatusBannerView(banner: banner) {
                    appState.clearStatusBanner()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            Divider()

            // Device List
            if appState.devices.isEmpty && isRefreshing {
                Spacer()
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Refreshing access points...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if appState.devices.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "wifi.router")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No access points found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(emptyStateSubtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.devices) { device in
                            DeviceRow(
                                device: device,
                                binding: binding(for: device),
                                isUpdating: pendingDeviceToggles.contains(device.id)
                            )

                            if device.id != appState.devices.last?.id {
                                Divider()
                                    .padding(.leading, 20)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyStateSubtitle: String {
        if appState.controllerConfig.baseURL == nil || appState.controllerConfig.username.isEmpty {
            return "Configure your controller in Settings and click Refresh."
        }

        return "Check the connection status above, then review Settings and try Refresh again."
    }

    private var canSendCommands: Bool {
        !isRefreshing &&
        !isTogglingAll &&
        appState.controllerConfig.baseURL != nil &&
        !appState.controllerConfig.username.isEmpty &&
        !appState.controllerConfig.password.isEmpty
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await appState.refreshDevices()
            await MainActor.run { isRefreshing = false }
        }
    }

    private func binding(for device: AccessPoint) -> Binding<Bool> {
        Binding<Bool>(
            get: { device.ledEnabled },
            set: { newValue in
                Task { await update(device: device, ledEnabled: newValue) }
            }
        )
    }

    private func runBulkToggle(_ enabled: Bool) {
        guard canSendCommands else { return }
        isTogglingAll = true
        Task {
            await toggleAll(enabled)
            await MainActor.run { isTogglingAll = false }
        }
    }

    private func update(device: AccessPoint, ledEnabled: Bool) async {
        guard !pendingDeviceToggles.contains(device.id) else { return }
        await MainActor.run {
            _ = pendingDeviceToggles.insert(device.id)
        }
        defer {
            Task { @MainActor in
                pendingDeviceToggles.remove(device.id)
            }
        }

        do {
            try await appState.controllerClient.toggleDeviceLED(config: appState.controllerConfig, deviceId: device.deviceId, enable: ledEnabled)
            await appState.refreshDevices()
        } catch {
            appState.setStatus(.error, "Couldn't update \(device.name): \(friendlyMessage(for: error))")
        }
    }

    private func toggleAll(_ enabled: Bool) async {
        do {
            try await appState.controllerClient.toggleLED(config: appState.controllerConfig, enable: enabled)
            await appState.refreshDevices()
            appState.setStatus(.success, "Turned \(enabled ? "on" : "off") LEDs for all access points.")
        } catch {
            appState.setStatus(.error, "Couldn't turn \(enabled ? "on" : "off") all LEDs: \(friendlyMessage(for: error))")
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        switch error as? UniFiControllerError {
        case .invalidConfiguration:
            return "check the controller URL, site, and SSL setting in Settings."
        case .authenticationFailed:
            return "check the username and password in Settings."
        case .ledControlUnsupported:
            return "this access point does not expose LED control through the UniFi API."
        case .ledStateVerificationFailed:
            return "the controller accepted the request but did not keep the requested LED state."
        case .rateLimited:
            return "the controller is rate limiting login attempts. Wait a few minutes, then try again."
        case .requestFailed:
            return "check the controller connection and try again."
        case nil:
            return error.localizedDescription
        }
    }
}

struct DeviceRow: View {
    let device: AccessPoint
    let binding: Binding<Bool>
    let isUpdating: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Device icon
            Image(systemName: "wifi.router")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            // Device info
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(.body, design: .default))
                    .fontWeight(.medium)
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(device.isOnline ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(device.isOnline ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundStyle(device.isOnline ? .green : .red)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(device.isOnline ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            )

            // LED toggle
            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            }

            Toggle(isOn: binding) {
                Text("LED")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .tint(Color.unigloBlue)
            .disabled(!device.isOnline || isUpdating)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
