import Foundation

struct ControllerConfig: Codable {
    var baseURL: URL?
    var site: String = "default"
    var username: String = ""
    var password: String = ""  // Not stored in JSON - managed by Keychain
    var token: String?
    var acceptInvalidCertificates: Bool = false

    enum CodingKeys: String, CodingKey {
        case baseURL
        case site
        case username
        case token
        case acceptInvalidCertificates
        // password is intentionally excluded from CodingKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        site = try container.decodeIfPresent(String.self, forKey: .site) ?? "default"
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        token = try container.decodeIfPresent(String.self, forKey: .token)
        acceptInvalidCertificates = try container.decodeIfPresent(Bool.self, forKey: .acceptInvalidCertificates) ?? false
        password = ""  // Will be loaded from Keychain separately
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(baseURL, forKey: .baseURL)
        try container.encode(site, forKey: .site)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(token, forKey: .token)
        try container.encode(acceptInvalidCertificates, forKey: .acceptInvalidCertificates)
        // password is intentionally not encoded
    }

    init() {
        self.baseURL = nil
        self.site = "default"
        self.username = ""
        self.password = ""
        self.token = nil
        self.acceptInvalidCertificates = false
    }
}

struct AccessPoint: Codable, Identifiable {
    let id: UUID
    var deviceId: String  // UniFi device ID for API calls
    var name: String
    var ipAddress: String
    var macAddress: String
    var ledEnabled: Bool
    var lastSeen: Date
    var tags: [String]
    var isOnline: Bool

    init(id: UUID = UUID(), deviceId: String, name: String, ipAddress: String, macAddress: String, ledEnabled: Bool, lastSeen: Date, tags: [String] = [], isOnline: Bool = true) {
        self.id = id
        self.deviceId = deviceId
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
