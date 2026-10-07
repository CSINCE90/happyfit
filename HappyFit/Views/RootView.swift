import SwiftUI
import SwiftData

/// Navigazione principale a schede.
struct RootView: View {
    @State private var selection: Int

    init(initialTab: Int = 0) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            WorkoutHomeView()
                .tabItem { Label("Allenamento", systemImage: "figure.strengthtraining.traditional") }
                .tag(0)
            TemplateListView()
                .tabItem { Label("Schede", systemImage: "list.bullet.rectangle") }
                .tag(1)
            HistoryView()
                .tabItem { Label("Storico", systemImage: "clock.arrow.circlepath") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                .tag(3)
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .modelContainer(PreviewData.container())
}
#endif
