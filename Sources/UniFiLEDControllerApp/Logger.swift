import Foundation
import OSLog

extension Logger {
    private static let subsystem = "com.unifiled.controller"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
}
