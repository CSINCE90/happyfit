import SwiftUI
import SwiftData

/// Navigazione principale a schede.
struct RootView: View {
    var body: some View {
        TabView {
            WorkoutHomeView()
                .tabItem { Label("Allenamento", systemImage: "figure.strengthtraining.traditional") }
            TemplateListView()
                .tabItem { Label("Schede", systemImage: "list.bullet.rectangle") }
            HistoryView()
                .tabItem { Label("Storico", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
}
