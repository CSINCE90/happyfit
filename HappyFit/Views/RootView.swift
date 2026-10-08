import SwiftUI
import SwiftData

/// Navigazione principale a schede.
struct RootView: View {
    @Environment(\.palette) private var palette
    @State private var selection: Int

    init(initialTab: Int = 0) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            // Il contenuto di ogni scheda mantiene la tinta normale; solo la barra usa quella di selezione.
            WorkoutHomeView()
                .tint(palette.accentText)
                .tabItem { Label("Allenamento", systemImage: "figure.strengthtraining.traditional") }
                .tag(0)
            TemplateListView()
                .tint(palette.accentText)
                .tabItem { Label("Schede", systemImage: "list.bullet.rectangle") }
                .tag(1)
            HistoryView()
                .tint(palette.accentText)
                .tabItem { Label("Storico", systemImage: "clock.arrow.circlepath") }
                .tag(2)
            SettingsView()
                .tint(palette.accentText)
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(palette.tabSelection)
    }
}

#if DEBUG
#Preview {
    RootView()
        .modelContainer(PreviewData.container())
}
#endif
