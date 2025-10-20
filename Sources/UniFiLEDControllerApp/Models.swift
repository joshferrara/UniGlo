import Foundation

struct ControllerConfig: Codable {
    var baseURL: URL?
    var site: String = "default"
    var username: String = ""
    var password: String = ""
    var token: String?
    var acceptInvalidCertificates: Bool = false
}

struct AccessPoint: Codable, Identifiable {
    let id: UUID
    var name: String
    var ipAddress: String
    var macAddress: String
    var ledEnabled: Bool
    var lastSeen: Date
    var tags: [String]
    var isOnline: Bool

    init(id: UUID = UUID(), name: String, ipAddress: String, macAddress: String, ledEnabled: Bool, lastSeen: Date, tags: [String] = [], isOnline: Bool = true) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.ledEnabled = ledEnabled
        self.lastSeen = lastSeen
        self.tags = tags
        self.isOnline = isOnline
    }
}

struct Schedule: Codable, Identifiable {
    let id: UUID
    var name: String
    var enabled: Bool
    var assignments: [UUID]
    var rules: [ScheduleRule]

    init(id: UUID = UUID(), name: String, enabled: Bool = true, assignments: [UUID] = [], rules: [ScheduleRule] = []) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.assignments = assignments
        self.rules = rules
    }
}

struct ScheduleRule: Codable, Identifiable {
    let id: UUID
    var day: DayOfWeek
    var onTime: TimeInterval
    var offTime: TimeInterval

    init(id: UUID = UUID(), day: DayOfWeek, onTime: TimeInterval, offTime: TimeInterval) {
        self.id = id
        self.day = day
        self.onTime = onTime
        self.offTime = offTime
    }
}

enum DayOfWeek: String, Codable, CaseIterable, Identifiable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    var id: String { rawValue }
}

struct OverrideState: Codable, Identifiable {
    let id: UUID
    let deviceId: UUID
    var expiresAt: Date
    var ledEnabled: Bool

    init(id: UUID = UUID(), deviceId: UUID, expiresAt: Date, ledEnabled: Bool) {
        self.id = id
        self.deviceId = deviceId
        self.expiresAt = expiresAt
        self.ledEnabled = ledEnabled
    }
}
