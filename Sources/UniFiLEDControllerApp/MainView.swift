import SwiftUI

struct MainView: View {
    @EnvironmentObject private var sparkleUpdater: SparkleUpdater

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
                .environmentObject(sparkleUpdater)
                .tabItem {
                    Text("Settings")
                }
        }
        .tint(Color.unigloBlue)
    }
}
