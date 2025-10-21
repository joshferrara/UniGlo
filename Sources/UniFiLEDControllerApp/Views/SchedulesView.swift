import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var scheduleToEdit: Schedule?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Schedules")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    scheduleToEdit = Schedule(name: "New Schedule")
                } label: {
                    Label("Add Schedule", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Schedule List
            if appState.schedules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No schedules yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Create a schedule to automatically control LED lights")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.schedules) { schedule in
                            ScheduleRow(
                                schedule: schedule,
                                binding: binding(for: schedule),
                                onEdit: {
                                    scheduleToEdit = schedule
                                },
                                onDelete: {
                                    if let index = appState.schedules.firstIndex(where: { $0.id == schedule.id }) {
                                        appState.schedules.remove(at: index)
                                        appState.saveState()
                                        Task {
                                            await appState.scheduler.rebuildTimers()
                                        }
                                    }
                                }
                            )

                            if schedule.id != appState.schedules.last?.id {
                                Divider()
                                    .padding(.leading, 20)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $scheduleToEdit) { schedule in
            ScheduleEditor(schedule: schedule) { updated in
                if let index = appState.schedules.firstIndex(where: { $0.id == updated.id }) {
                    appState.schedules[index] = updated
                } else {
                    appState.schedules.append(updated)
                }
                appState.saveState()
                scheduleToEdit = nil

                // Rebuild scheduler timers after schedule changes
                Task {
                    await appState.scheduler.rebuildTimers()
                }
            }
        }
    }

    private func binding(for schedule: Schedule) -> Binding<Bool> {
        Binding<Bool>(
            get: { schedule.enabled },
            set: { newValue in
                guard let index = appState.schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
                appState.schedules[index].enabled = newValue
                appState.saveState()

                // Rebuild scheduler timers when enabling/disabling schedules
                Task {
                    await appState.scheduler.rebuildTimers()
                }
            }
        )
    }
}

struct ScheduleRow: View {
    let schedule: Schedule
    let binding: Binding<Bool>
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Schedule icon
            Image(systemName: schedule.enabled ? "calendar.badge.checkmark" : "calendar")
                .font(.title3)
                .foregroundStyle(schedule.enabled ? .blue : .secondary)
                .frame(width: 32)

            // Schedule info
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.system(.body, design: .default))
                    .fontWeight(.medium)

                HStack(spacing: 12) {
                    Label("\(schedule.rules.count) \(schedule.rules.count == 1 ? "rule" : "rules")", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("\(schedule.assignments.count) \(schedule.assignments.count == 1 ? "AP" : "APs")", systemImage: "wifi.router")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Enabled toggle
            Toggle(isOn: binding) {
                Text("Enabled")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onTapGesture {} // Prevent click-through to row

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Edit schedule")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Delete schedule")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}

struct ScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var schedule: Schedule
    let onSave: (Schedule) -> Void

    init(schedule: Schedule, onSave: @escaping (Schedule) -> Void) {
        _schedule = State(initialValue: schedule)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.name.isEmpty ? "New Schedule" : schedule.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Configure when LEDs turn on and off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Enabled toggle
                Toggle("Enabled", isOn: $schedule.enabled)
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Details Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.headline)
                            .foregroundColor(.primary)

                        HStack {
                            Text("Name")
                                .frame(width: 100, alignment: .leading)
                            TextField("Schedule name", text: $schedule.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }

                    // Access Points Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Access Points")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(schedule.assignments.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if appState.devices.isEmpty {
                            Text("No access points available. Add devices in Settings.")
                                .foregroundColor(.secondary)
                                .font(.callout)
                                .padding(12)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(appState.devices) { ap in
                                    Toggle(isOn: bindingForDevice(ap.macAddress)) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "wifi.router")
                                                .foregroundStyle(.secondary)
                                                .font(.caption)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(ap.name)
                                                    .font(.subheadline)
                                                    .lineLimit(1)
                                                Text(ap.ipAddress)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                    )
                                }
                            }
                        }

                        Text("Select which access points this schedule will control")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Rules Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Rules")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(schedule.rules.count) \(schedule.rules.count == 1 ? "rule" : "rules")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if schedule.rules.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.badge.questionmark")
                                    .font(.title)
                                    .foregroundStyle(.tertiary)
                                Text("No rules yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        } else {
                            VStack(spacing: 8) {
                                // Column Headers
                                HStack(spacing: 12) {
                                    Text("Day")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)

                                    Text("On")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Spacer()
                                        .frame(width: 20)

                                    Text("Off")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 4)

                                ForEach(schedule.rules.indices, id: \.self) { index in
                                    HStack(spacing: 12) {
                                        Picker("", selection: bindingForRuleDay(at: index)) {
                                            ForEach(DayOfWeek.allCases) { day in
                                                Text(day.rawValue.capitalized)
                                                    .tag(day)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(width: 120)

                                        DatePicker("", selection: bindingForRule(at: index, keyPath: \.onTime), displayedComponents: [.hourAndMinute])
                                            .datePickerStyle(.field)
                                            .labelsHidden()
                                            .frame(width: 80)

                                        Image(systemName: "arrow.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20)

                                        DatePicker("", selection: bindingForRule(at: index, keyPath: \.offTime), displayedComponents: [.hourAndMinute])
                                            .datePickerStyle(.field)
                                            .labelsHidden()
                                            .frame(width: 80)

                                        Spacer()

                                        Button {
                                            schedule.rules.remove(at: index)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.body)
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(.red)
                                        .help("Delete rule")
                                        .frame(width: 24, height: 24)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                    )
                                }
                            }
                        }

                        Button {
                            let newRule = ScheduleRule(day: .monday, onTime: 7 * 3600, offTime: 22 * 3600)
                            schedule.rules.append(newRule)
                        } label: {
                            Label("Add Rule", systemImage: "plus")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)

                        Text("Define when LEDs should turn on and off for each day")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer with action buttons
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Save Schedule") {
                    onSave(schedule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 550, idealWidth: 600, minHeight: 500, idealHeight: 600)
    }

    private func bindingForDevice(_ macAddress: String) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                schedule.assignments.contains(macAddress)
            },
            set: { isSelected in
                if isSelected {
                    if !schedule.assignments.contains(macAddress) {
                        schedule.assignments.append(macAddress)
                    }
                } else {
                    schedule.assignments.removeAll { $0 == macAddress }
                }
            }
        )
    }

    private func bindingForRuleDay(at index: Int) -> Binding<DayOfWeek> {
        Binding<DayOfWeek>(
            get: {
                guard schedule.rules.indices.contains(index) else { return .monday }
                return schedule.rules[index].day
            },
            set: { newValue in
                guard schedule.rules.indices.contains(index) else { return }
                schedule.rules[index].day = newValue
            }
        )
    }

    private func bindingForRule(at index: Int, keyPath: WritableKeyPath<ScheduleRule, TimeInterval>) -> Binding<Date> {
        Binding<Date>(
            get: {
                guard schedule.rules.indices.contains(index) else {
                    return Date()
                }

                let secondsSinceMidnight = schedule.rules[index][keyPath: keyPath]

                // Convert seconds since midnight to a Date for today
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: Date())
                let resultDate = startOfDay.addingTimeInterval(secondsSinceMidnight)
                return resultDate
            },
            set: { newValue in
                guard schedule.rules.indices.contains(index) else {
                    return
                }

                // Convert Date to seconds since midnight
                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute, .second], from: newValue)
                let hour = components.hour ?? 0
                let minute = components.minute ?? 0
                let second = components.second ?? 0
                let secondsSinceMidnight = TimeInterval(hour * 3600 + minute * 60 + second)

                schedule.rules[index][keyPath: keyPath] = secondsSinceMidnight
            }
        )
    }
}
