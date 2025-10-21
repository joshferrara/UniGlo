import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRefreshing = false

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
                        Task { await toggleAll(false) }
                    } label: {
                        Label("All Off", systemImage: "lightbulb.slash")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .help("Turn off all LEDs")

                    Button {
                        Task { await toggleAll(true) }
                    } label: {
                        Label("All On", systemImage: "lightbulb")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .help("Turn on all LEDs")

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
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Device List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.devices) { device in
                        DeviceRow(device: device, binding: binding(for: device))

                        if device.id != appState.devices.last?.id {
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await appState.refreshDevices()
            await MainActor.run { isRefreshing = false }
        }
    }

    private func toggleAll(_ enabled: Bool) async {
        do {
            try await appState.controllerClient.toggleLED(config: appState.controllerConfig, enable: enabled)
            await appState.refreshDevices()
        } catch {
            print("Failed to toggle all LEDs: \(error)")
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

    private func update(device: AccessPoint, ledEnabled: Bool) async {
        do {
            try await appState.controllerClient.toggleDeviceLED(config: appState.controllerConfig, deviceId: device.deviceId, enable: ledEnabled)
            await appState.refreshDevices()
        } catch {
            print("Failed to toggle LED for \(device.name): \(error)")
        }
    }
}

struct DeviceRow: View {
    let device: AccessPoint
    let binding: Binding<Bool>

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
            Toggle(isOn: binding) {
                Text("LED")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .tint(Color.unigloBlue)
            .disabled(!device.isOnline)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
