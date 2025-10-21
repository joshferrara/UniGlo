import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            DevicesView()
                .tabItem {
                    Text("Devices")
                }

            SchedulesView()
                .tabItem {
                    Text("Schedules")
                }

            SettingsView()
                .tabItem {
                    Text("Settings")
                }
        }
        .tint(Color.unigloBlue)
    }
}
