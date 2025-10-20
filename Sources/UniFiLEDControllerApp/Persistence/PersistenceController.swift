import Foundation
import OSLog

enum PersistenceError: Error {
    case invalidURL
}

final class PersistenceController {
    static let shared = PersistenceController()

    private var baseDirectory: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("UniFiLEDController", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() { }

    func save(controllerConfig: ControllerConfig) throws {
        // Save the config (without password) to JSON
        let data = try JSONEncoder().encode(controllerConfig)
        try data.write(to: baseDirectory.appendingPathComponent("controllerConfig.json"), options: [.atomic])

        // Save password to Keychain if username is provided
        if !controllerConfig.username.isEmpty {
            let account = keychainAccount(for: controllerConfig)
            if !controllerConfig.password.isEmpty {
                try KeychainHelper.shared.savePassword(controllerConfig.password, for: account)
                Logger.app.info("Saved password to Keychain for account: \(account)")
            } else {
                // If password is empty, delete from Keychain
                try? KeychainHelper.shared.deletePassword(for: account)
                Logger.app.info("Deleted password from Keychain for account: \(account)")
            }
        }
    }

    func loadControllerConfig() throws -> ControllerConfig {
        let url = baseDirectory.appendingPathComponent("controllerConfig.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ControllerConfig()
        }
        let data = try Data(contentsOf: url)
        var config = try JSONDecoder().decode(ControllerConfig.self, from: data)

        // Load password from Keychain
        if !config.username.isEmpty {
            let account = keychainAccount(for: config)
            if let password = try? KeychainHelper.shared.getPassword(for: account) {
                config.password = password
                Logger.app.info("Loaded password from Keychain for account: \(account)")
            } else {
                Logger.app.info("No password found in Keychain for account: \(account)")
            }
        }

        return config
    }

    /// Generate a unique Keychain account identifier based on the controller URL and username
    private func keychainAccount(for config: ControllerConfig) -> String {
        let baseURLString = config.baseURL?.absoluteString ?? "default"
        return "\(baseURLString):\(config.username)"
    }

    func save(schedules: [Schedule]) throws {
        let data = try JSONEncoder().encode(schedules)
        try data.write(to: baseDirectory.appendingPathComponent("schedules.json"), options: [.atomic])
    }

    func loadSchedules() throws -> [Schedule] {
        let url = baseDirectory.appendingPathComponent("schedules.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Schedule].self, from: data)
    }
}
