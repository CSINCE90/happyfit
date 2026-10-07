import SwiftUI

/// Impostazioni: recupero predefinito, incremento del peso, catalogo esercizi.
struct SettingsView: View {
    @AppStorage(AppSettings.defaultRestKey) private var defaultRest = AppSettings.defaultRestFallback
    @AppStorage(AppSettings.weightStepKey) private var weightStep = AppSettings.weightStepFallback

    private let presets: [Double] = [1, 2.5, 5]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $defaultRest, in: 0...900, step: 15) {
                        Text("Recupero: \(Formatting.rest(defaultRest))")
                    }
                } header: {
                    Text("Recupero predefinito")
                } footer: {
                    Text("Usato per i nuovi esercizi che non hanno un recupero personalizzato.")
                }

                Section {
                    Picker("Incremento", selection: $weightStep) {
                        ForEach(presets, id: \.self) { Text("\(Formatting.weight($0)) kg").tag($0) }
                        if !presets.contains(weightStep) {
                            Text("\(Formatting.weight(weightStep)) kg").tag(weightStep)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $weightStep, in: 0.25...25, step: 0.25) {
                        Text("Valore: \(Formatting.weight(weightStep)) kg")
                    }
                } header: {
                    Text("Incremento del peso")
                } footer: {
                    Text("Di quanto cambia il peso a ogni tocco su + e −.")
                }

                Section("Esercizi") {
                    NavigationLink("Catalogo esercizi") { ExerciseCatalogView() }
                    NavigationLink("Esercizi archiviati") { ArchivedExercisesView() }
                }
            }
            .navigationTitle("Impostazioni")
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(PreviewData.container())
}
#endif
