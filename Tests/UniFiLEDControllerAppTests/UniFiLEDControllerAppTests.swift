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
}
