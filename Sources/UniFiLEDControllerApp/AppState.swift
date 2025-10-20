import Foundation
import OSLog

@MainActor
final class AppState: ObservableObject {
    @Published var controllerConfig = ControllerConfig()
    @Published var devices: [AccessPoint] = []
    @Published var schedules: [Schedule] = []
    @Published var overrides: [OverrideState] = []

    let scheduler = SchedulerService()
    let controllerClient = UniFiControllerClient()

    init() {}

    func refreshDevices() async {
        Logger.app.info("Starting device refresh...")
        Logger.app.info("Controller URL: \(self.controllerConfig.baseURL?.absoluteString ?? "none")")
        Logger.app.info("Site: \(self.controllerConfig.site)")
        Logger.app.info("Username: \(self.controllerConfig.username)")

        do {
            let fetched = try await controllerClient.fetchDevices(config: controllerConfig)
            devices = fetched
            Logger.app.info("Successfully refreshed \(fetched.count) devices")
        } catch let error as UniFiControllerError {
            switch error {
            case .invalidConfiguration:
                Logger.app.error("Failed to refresh devices: Invalid configuration. Please check your settings.")
            case .authenticationFailed:
                Logger.app.error("Failed to refresh devices: Authentication failed. Please check your username and password.")
            case .requestFailed:
                Logger.app.error("Failed to refresh devices: Request failed. Please check your controller URL and network connection.")
            }
        } catch {
            Logger.app.error("Failed to refresh devices: \(error.localizedDescription)")
        }
    }

    func loadPersistedState() async {
        Logger.app.info("Loading persisted state...")
        do {
            controllerConfig = try PersistenceController.shared.loadControllerConfig()
            schedules = try PersistenceController.shared.loadSchedules()
            Logger.app.info("Successfully loaded persisted state")
        } catch {
            Logger.app.error("Failed to load persisted state: \(error.localizedDescription)")
        }
    }

    func saveState() {
        Logger.app.info("Saving state...")
        do {
            try PersistenceController.shared.save(controllerConfig: controllerConfig)
            try PersistenceController.shared.save(schedules: schedules)
            Logger.app.info("Successfully saved state")
        } catch {
            Logger.app.error("Failed to save state: \(error.localizedDescription)")
        }
    }
}
