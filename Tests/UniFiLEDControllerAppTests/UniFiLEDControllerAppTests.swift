import XCTest
@testable import UniFiLEDControllerApp

final class UniFiLEDControllerAppTests: XCTestCase {
    func testScheduleEncodingDecoding() throws {
        let rule = ScheduleRule(day: .monday, onTime: 25200, offTime: 72000)
        let schedule = Schedule(name: "Work Day", assignments: [], rules: [rule])
        let data = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(Schedule.self, from: data)
        XCTAssertEqual(decoded.name, schedule.name)
        XCTAssertEqual(decoded.rules.first?.day, .monday)
    }

    func testControllerConfigDoesNotEncodePassword() throws {
        var config = ControllerConfig()
        config.baseURL = URL(string: "https://192.168.1.1:8443")
        config.site = "default"
        config.username = "local-admin"
        config.password = "super-secret"

        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(ControllerConfig.self, from: data)

        XCTAssertFalse(json.contains("password"))
        XCTAssertFalse(json.contains("super-secret"))
        XCTAssertEqual(decoded.username, "local-admin")
        XCTAssertEqual(decoded.password, "")
    }
}
