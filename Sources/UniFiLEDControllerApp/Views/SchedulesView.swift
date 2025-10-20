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
    @State private var schedule: Schedule
    let onSave: (Schedule) -> Void

    init(schedule: Schedule, onSave: @escaping (Schedule) -> Void) {
        _schedule = State(initialValue: schedule)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Name", text: $schedule.name)
                    Toggle("Enabled", isOn: $schedule.enabled)
                }
                Section("Rules") {
                    ForEach(schedule.rules.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Text(schedule.rules[index].day.rawValue.capitalized)
                            HStack {
                                DatePicker("On", selection: bindingForRule(at: index, keyPath: \.onTime), displayedComponents: [.hourAndMinute])
                                DatePicker("Off", selection: bindingForRule(at: index, keyPath: \.offTime), displayedComponents: [.hourAndMinute])
                            }
                        }
                    }
                    Button("Add Rule") {
                        let newRule = ScheduleRule(day: .monday, onTime: 7 * 3600, offTime: 22 * 3600)
                        schedule.rules.append(newRule)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(schedule)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Schedule")
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func bindingForRule(at index: Int, keyPath: WritableKeyPath<ScheduleRule, TimeInterval>) -> Binding<Date> {
        Binding<Date>(
            get: {
                guard schedule.rules.indices.contains(index) else { return Date(timeIntervalSinceReferenceDate: 0) }
                let value = schedule.rules[index][keyPath: keyPath]
                return Date(timeIntervalSinceReferenceDate: value)
            },
            set: { newValue in
                guard schedule.rules.indices.contains(index) else { return }
                schedule.rules[index][keyPath: keyPath] = newValue.timeIntervalSinceReferenceDate
            }
        )
    }
}
