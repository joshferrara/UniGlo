import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Access Points")
                    .font(.title2)
                Spacer()
                Button {
                    refresh()
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                Button("Turn Off All LEDs") {
                    Task { await toggleAll(false) }
                }
                Button("Turn On All LEDs") {
                    Task { await toggleAll(true) }
                }
            }
            List(appState.devices) { device in
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.headline)
                        Text(device.ipAddress)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Label(device.isOnline ? "Online" : "Offline", systemImage: device.isOnline ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(device.isOnline ? .green : .red)
                    Toggle(isOn: binding(for: device)) {
                        Text("LED")
                    }
                    .toggleStyle(.switch)
                    .disabled(!device.isOnline)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
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
            try await appState.controllerClient.toggleLED(config: appState.controllerConfig, enable: ledEnabled)
            await appState.refreshDevices()
        } catch {
            print("Failed to toggle LED for \(device.name): \(error)")
        }
    }
}
