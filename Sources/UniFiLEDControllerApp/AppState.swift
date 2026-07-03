import Foundation
import OSLog

@MainActor
final class AppState: ObservableObject {
    @Published var controllerConfig = ControllerConfig()
    @Published var devices: [AccessPoint] = []
    @Published var schedules: [Schedule] = []
    @Published var overrides: [OverrideState] = []
    @Published var statusBanner: AppStatusBanner?

    let scheduler = SchedulerService()
    let controllerClient = UniFiControllerClient()

    init() {}

    func refreshDevices() async {
        Logger.app.info("Starting device refresh...")
        Logger.app.info("Controller URL: \(self.controllerConfig.baseURL?.absoluteString ?? "none")")
        Logger.app.info("Site: \(self.controllerConfig.site)")
        Logger.app.info("Username: \(self.controllerConfig.username)")

        guard controllerConfig.baseURL != nil, !controllerConfig.username.isEmpty else {
            devices = []
            setStatus(.warning, "Add your controller URL and username in Settings before refreshing.")
            return
        }

        guard !controllerConfig.password.isEmpty else {
            devices = []
            setStatus(.warning, "The saved controller password is missing from Keychain. Re-enter it in Settings to reconnect.")
            return
        }

        do {
            let fetched = try await controllerClient.fetchDevices(config: controllerConfig)
            devices = fetched
            Logger.app.info("Successfully refreshed \(fetched.count) devices")

            if fetched.isEmpty {
                setStatus(.warning, "Connected successfully, but no access points were returned for site '\(siteName)'.")
            } else {
                setStatus(.success, "Connected successfully. Found \(fetched.count) access point\(fetched.count == 1 ? "" : "s").")
            }
        } catch let error as UniFiControllerError {
            devices = []
            switch error {
            case .invalidConfiguration:
                setStatus(.error, "Invalid configuration. Check the controller URL, site, and SSL setting in Settings.")
            case .authenticationFailed:
                setStatus(.error, "Authentication failed. Check the username and password for your UniFi local user.")
            case .ledControlUnsupported:
                setStatus(.error, "This access point does not expose LED control through the UniFi API.")
            case .ledStateVerificationFailed:
                setStatus(.error, "The controller accepted the LED change but did not report the requested LED state afterward.")
            case .rateLimited:
                setStatus(.error, "The controller blocked more login attempts. Wait a few minutes, then verify the saved credentials before retrying.")
            case .requestFailed:
                setStatus(.error, "Request failed. Check the controller URL, the self-signed certificate setting, and your local network connection.")
            }
            Logger.app.error("Failed to refresh devices: \(self.statusBanner?.message ?? "unknown")")
        } catch {
            devices = []
            setStatus(.error, "Unexpected error refreshing devices: \(error.localizedDescription)")
            Logger.app.error("Failed to refresh devices: \(error.localizedDescription)")
        }
    }

    func loadPersistedState() async {
        Logger.app.info("Loading persisted state...")
        do {
            // Load config and schedules on a background thread to avoid
            // blocking the UI if Keychain prompts for access
            let (config, loadedSchedules) = try await Task.detached {
                let config = try PersistenceController.shared.loadControllerConfig()
                let schedules = try PersistenceController.shared.loadSchedules()
                return (config, schedules)
            }.value
            controllerConfig = config
            schedules = loadedSchedules
            Logger.app.info("Successfully loaded persisted state")

            if config.baseURL != nil && !config.username.isEmpty && config.password.isEmpty {
                devices = []
                setStatus(.warning, "The saved controller password could not be loaded from Keychain. Re-enter it in Settings to reconnect.")
                Logger.app.warning("Persisted controller configuration is missing a password in Keychain")
            }
        } catch {
            setStatus(.error, "Couldn't load saved settings: \(error.localizedDescription)")
            Logger.app.error("Failed to load persisted state: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func saveState() -> Bool {
        Logger.app.info("Saving state...")
        do {
            try PersistenceController.shared.save(controllerConfig: controllerConfig)
            try PersistenceController.shared.save(schedules: schedules)
            Logger.app.info("Successfully saved state")
            return true
        } catch {
            setStatus(.error, "Couldn't save settings or password to Keychain: \(error.localizedDescription)")
            Logger.app.error("Failed to save state: \(error.localizedDescription)")
            return false
        }
    }

    func clearStatusBanner() {
        statusBanner = nil
    }

    func setStatus(_ kind: AppStatusBanner.Kind, _ message: String) {
        statusBanner = AppStatusBanner(kind: kind, message: message)
    }

    private var siteName: String {
        let trimmed = controllerConfig.site.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "default" : trimmed
    }

}
