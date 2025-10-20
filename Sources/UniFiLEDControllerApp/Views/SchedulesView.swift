import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedScheduleID: Schedule.ID?
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Schedules")
                    .font(.title2)
                Spacer()
                Button("Add Schedule") {
                    selectedScheduleID = nil
                    isEditing = true
                }
            }
            List(selection: $selectedScheduleID) {
                ForEach(appState.schedules) { schedule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(schedule.name)
                                .font(.headline)
                            Text("Assigned APs: \(schedule.assignments.count)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: binding(for: schedule))
                            .labelsHidden()
                    }
                    .tag(schedule.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedScheduleID = schedule.id
                        isEditing = true
                    }
                }
                .onDelete { indexSet in
                    appState.schedules.remove(atOffsets: indexSet)
                    appState.saveState()

                    // Rebuild scheduler timers after deletion
                    Task {
                        await appState.scheduler.rebuildTimers()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .sheet(isPresented: $isEditing, onDismiss: dismissEditor) {
            ScheduleEditor(schedule: scheduleForEditing) { updated in
                if let index = appState.schedules.firstIndex(where: { $0.id == updated.id }) {
                    appState.schedules[index] = updated
                } else {
                    appState.schedules.append(updated)
                }
                appState.saveState()
                selectedScheduleID = nil

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

    private func dismissEditor() {
        selectedScheduleID = nil
    }

    private var scheduleForEditing: Schedule {
        if let id = selectedScheduleID, let existing = appState.schedules.first(where: { $0.id == id }) {
            return existing
        }
        return Schedule(name: "New Schedule")
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
                Text("Schedule")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            Form {
                Section {
                    TextField("Name", text: $schedule.name)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Enabled", isOn: $schedule.enabled)
                } header: {
                    Text("Details")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding(.top, 8)

                Section {
                    if appState.devices.isEmpty {
                        Text("No access points available")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(appState.devices) { ap in
                            Toggle(isOn: bindingForDevice(ap.macAddress)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ap.name)
                                        .font(.subheadline)
                                    Text(ap.ipAddress)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Access Points")
                        .font(.headline)
                        .foregroundColor(.primary)
                } footer: {
                    Text("Select which access points this schedule will control")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    if !schedule.rules.isEmpty {
                        ForEach(schedule.rules.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Picker("Day", selection: bindingForRuleDay(at: index)) {
                                        ForEach(DayOfWeek.allCases) { day in
                                            Text(day.rawValue.capitalized)
                                                .tag(day)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 140)

                                    Spacer()
                                }

                                HStack(spacing: 20) {
                                    DatePicker("On", selection: bindingForRule(at: index, keyPath: \.onTime), displayedComponents: [.hourAndMinute])
                                        .datePickerStyle(.field)

                                    DatePicker("Off", selection: bindingForRule(at: index, keyPath: \.offTime), displayedComponents: [.hourAndMinute])
                                        .datePickerStyle(.field)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onDelete { indexSet in
                            schedule.rules.remove(atOffsets: indexSet)
                        }
                    }

                    Button(action: {
                        let newRule = ScheduleRule(day: .monday, onTime: 7 * 3600, offTime: 22 * 3600)
                        schedule.rules.append(newRule)
                    }) {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Rules")
                        .font(.headline)
                        .foregroundColor(.primary)
                } footer: {
                    Text("Define when LEDs should turn on and off for each day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer with action buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(schedule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 450, idealHeight: 550)
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
