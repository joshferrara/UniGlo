import Foundation
import AppKit
import OSLog

final class SchedulerService {
    private var timers: [UUID: DispatchSourceTimer] = [:]
    private weak var appState: AppState?
    private var observers: [NSObjectProtocol] = []

    @MainActor
    func configure(with appState: AppState) {
        self.appState = appState
        Task { await self.rebuildTimers() }
        subscribeToNotifications()
    }

    @MainActor
    func rebuildTimers() async {
        cancelAll()
        guard let appState else { return }

        Logger.app.info("Building schedule timers for \(appState.schedules.count) schedules")

        for schedule in appState.schedules where schedule.enabled {
            Logger.app.info("Processing schedule: \(schedule.name) with \(schedule.rules.count) rules")

            for rule in schedule.rules {
                Logger.app.info("Rule for \(rule.day.rawValue): ON at \(self.formatTime(rule.onTime)) (\(rule.onTime)s), OFF at \(self.formatTime(rule.offTime)) (\(rule.offTime)s)")

                // Schedule "ON" timer
                if let onFireTime = calculateNextFireTime(for: rule.day, time: rule.onTime) {
                    let identifier = UUID()
                    let timer = DispatchSource.makeTimerSource(queue: .main)

                    let interval = onFireTime.timeIntervalSinceNow
                    timer.schedule(deadline: .now() + interval, repeating: .seconds(60 * 60 * 24 * 7)) // Weekly repeat

                    timer.setEventHandler { [weak self, weak appState] in
                        guard let self = self, let appState = appState else { return }
                        Logger.app.info("Schedule '\(schedule.name)' firing ON event for \(rule.day.rawValue)")
                        Task { @MainActor in
                            await self.executeScheduleAction(appState: appState, schedule: schedule, enable: true)
                        }
                    }

                    timer.resume()
                    timers[identifier] = timer

                    Logger.app.info("Scheduled ON timer for \(rule.day.rawValue) at \(self.formatTime(rule.onTime)) (fires at \(onFireTime), in \(Int(interval)) seconds)")
                }

                // Schedule "OFF" timer
                if let offFireTime = calculateNextFireTime(for: rule.day, time: rule.offTime) {
                    let identifier = UUID()
                    let timer = DispatchSource.makeTimerSource(queue: .main)

                    let interval = offFireTime.timeIntervalSinceNow
                    timer.schedule(deadline: .now() + interval, repeating: .seconds(60 * 60 * 24 * 7)) // Weekly repeat

                    timer.setEventHandler { [weak self, weak appState] in
                        guard let self = self, let appState = appState else { return }
                        Logger.app.info("Schedule '\(schedule.name)' firing OFF event for \(rule.day.rawValue)")
                        Task { @MainActor in
                            await self.executeScheduleAction(appState: appState, schedule: schedule, enable: false)
                        }
                    }

                    timer.resume()
                    timers[identifier] = timer

                    Logger.app.info("Scheduled OFF timer for \(rule.day.rawValue) at \(self.formatTime(rule.offTime)) (fires at \(offFireTime), in \(Int(interval)) seconds)")
                }
            }
        }

        Logger.app.info("Total timers scheduled: \(self.timers.count)")
    }

    private func calculateNextFireTime(for dayOfWeek: DayOfWeek, time: TimeInterval) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // Get current weekday (1 = Sunday, 7 = Saturday)
        let currentWeekday = calendar.component(.weekday, from: now)

        // Convert DayOfWeek to calendar weekday
        let targetWeekday = dayOfWeek.calendarWeekday

        Logger.app.info("Calculating fire time: now=\(now), current weekday=\(currentWeekday), target weekday=\(targetWeekday) (\(dayOfWeek.rawValue)), time=\(self.formatTime(time))")

        // Calculate days until target day
        var daysUntilTarget = targetWeekday - currentWeekday
        if daysUntilTarget < 0 {
            daysUntilTarget += 7
        }

        Logger.app.info("Days until target: \(daysUntilTarget)")

        // Create target date
        guard let targetDate = calendar.date(byAdding: .day, value: daysUntilTarget, to: now) else {
            return nil
        }

        Logger.app.info("Target date (before setting time): \(targetDate)")

        // Set time of day
        let components = calendar.dateComponents([.year, .month, .day], from: targetDate)
        guard var finalDate = calendar.date(from: components) else {
            return nil
        }

        finalDate = finalDate.addingTimeInterval(time)

        Logger.app.info("Final date (after adding time): \(finalDate)")

        // If the calculated time is in the past, add 7 days
        if finalDate <= now {
            Logger.app.info("Time is in the past, adding 7 days")
            finalDate = calendar.date(byAdding: .day, value: 7, to: finalDate) ?? finalDate
        }

        Logger.app.info("Calculated next fire time: \(finalDate)")
        return finalDate
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    @MainActor
    private func executeScheduleAction(appState: AppState, schedule: Schedule, enable: Bool) async {
        Logger.app.info("Executing schedule '\(schedule.name)' - turning LEDs \(enable ? "ON" : "OFF") for \(schedule.assignments.count) devices")

        // Get assigned devices by MAC address
        let assignedDevices = appState.devices.filter { schedule.assignments.contains($0.macAddress) }

        guard !assignedDevices.isEmpty else {
            Logger.app.warning("Schedule '\(schedule.name)' has no assigned devices (assigned MACs: \(schedule.assignments.joined(separator: ", ")))")
            return
        }

        Logger.app.info("Found \(assignedDevices.count) devices matching assignment: \(assignedDevices.map { $0.name }.joined(separator: ", "))")

        // Toggle LED for each assigned device
        for device in assignedDevices {
            do {
                try await appState.controllerClient.toggleDeviceLED(
                    config: appState.controllerConfig,
                    deviceId: device.deviceId,
                    enable: enable
                )
                Logger.app.info("Successfully toggled LED \(enable ? "ON" : "OFF") for device: \(device.name)")
            } catch {
                Logger.app.error("Failed to toggle LED for device \(device.name): \(error.localizedDescription)")
            }
        }

        // Refresh device states after changes
        await appState.refreshDevices()
    }

    deinit {
        Task { @MainActor in
            cancelAll()
            removeObservers()
        }
    }

    @MainActor
    private func cancelAll() {
        timers.values.forEach { timer in
            timer.setEventHandler { }
            timer.cancel()
        }
        timers.removeAll()
    }

    @MainActor
    private func subscribeToNotifications() {
        guard observers.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        let wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { await self?.rebuildTimers() }
        }
        let screenObserver = center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { await self?.rebuildTimers() }
        }
        observers.append(contentsOf: [wakeObserver, screenObserver])
    }

    @MainActor
    private func removeObservers() {
        guard !observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }
}

// Extension to convert DayOfWeek to Calendar weekday
extension DayOfWeek {
    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }
}
