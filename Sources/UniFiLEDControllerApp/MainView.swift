import SwiftUI

struct MainView: View {
    @State private var selection: Tab = .devices

    var body: some View {
        TabView(selection: $selection) {
            DevicesView()
                .tabItem {
                    Label("Devices", systemImage: "wifi")
                }
                .tag(Tab.devices)

            SchedulesView()
                .tabItem {
                    Label("Schedules", systemImage: "calendar")
                }
                .tag(Tab.schedules)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
    }

    private enum Tab {
        case devices
        case schedules
        case settings
    }
}
