import Foundation

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
        let data = try JSONEncoder().encode(controllerConfig)
        try data.write(to: baseDirectory.appendingPathComponent("controllerConfig.json"), options: [.atomic])
    }

    func loadControllerConfig() throws -> ControllerConfig {
        let url = baseDirectory.appendingPathComponent("controllerConfig.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ControllerConfig()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ControllerConfig.self, from: data)
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
