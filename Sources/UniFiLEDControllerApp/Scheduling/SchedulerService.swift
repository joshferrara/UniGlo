import Foundation
import AppKit

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
        for schedule in appState.schedules where schedule.enabled {
            for rule in schedule.rules {
                let identifier = UUID()
                let timer = DispatchSource.makeTimerSource()
                timer.schedule(deadline: .now() + 5)
                timer.setEventHandler { [weak self] in
                    Task { await self?.refreshDevices() }
                }
                timer.resume()
                timers[identifier] = timer
            }
        }
    }

    deinit {
        Task { @MainActor in
            cancelAll()
            removeObservers()
        }
    }

    @MainActor
    private func refreshDevices() async {
        guard let appState else { return }
        await appState.refreshDevices()
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
