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
            let accounts = keychainAccounts(for: controllerConfig)
            let account = accounts[0]
            if !controllerConfig.password.isEmpty {
                try KeychainHelper.shared.savePassword(controllerConfig.password, for: account)
                for legacyAccount in accounts.dropFirst() {
                    try? KeychainHelper.shared.deletePassword(for: legacyAccount)
                }
                Logger.app.info("Saved password to Keychain for account: \(account)")
            } else {
                // If password is empty, delete from Keychain
                for account in accounts {
                    try? KeychainHelper.shared.deletePassword(for: account)
                }
                Logger.app.info("Deleted password from Keychain for username: \(controllerConfig.username)")
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
            let accounts = keychainAccounts(for: config)
            for account in accounts {
                if let password = try KeychainHelper.shared.getPassword(for: account) {
                    config.password = password

                    if account != accounts[0] {
                        try? KeychainHelper.shared.savePassword(password, for: accounts[0])
                        try? KeychainHelper.shared.deletePassword(for: account)
                        Logger.app.info("Migrated password to normalized Keychain account: \(accounts[0])")
                    }

                    Logger.app.info("Loaded password from Keychain for account: \(account)")
                    break
                }
            }

            if config.password.isEmpty {
                Logger.app.info("No password found in Keychain for username: \(config.username)")
            }
        }

        return config
    }

    /// Generate normalized and legacy Keychain account identifiers based on the controller URL and username.
    private func keychainAccounts(for config: ControllerConfig) -> [String] {
        let variants = baseURLKeyVariants(for: config.baseURL)
        return variants.map { "\($0):\(config.username)" }
    }

    private func baseURLKeyVariants(for baseURL: URL?) -> [String] {
        guard let baseURL else {
            return ["default"]
        }

        let raw = baseURL.absoluteString
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let withTrailingSlash = trimmed + "/"

        var variants = [trimmed]
        if raw != trimmed {
            variants.append(raw)
        }
        if !variants.contains(withTrailingSlash) {
            variants.append(withTrailingSlash)
        }

        return variants
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
