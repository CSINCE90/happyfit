import SwiftUI

/// Impostazioni: aspetto e colore d'accento, recupero predefinito, incremento del peso, catalogo esercizi.
struct SettingsView: View {
    @Environment(\.palette) private var palette
    @AppStorage(AppSettings.accentKey) private var accentRaw = AccentPreset.default.rawValue
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppSettings.defaultRestKey) private var defaultRest = AppSettings.defaultRestFallback
    @AppStorage(AppSettings.weightStepKey) private var weightStep = AppSettings.weightStepFallback

    @State private var confirmingReset = false

    private let presets: [Double] = [1, 2.5, 5]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Aspetto", selection: $appearanceRaw) {
                        ForEach(AppearancePreference.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                    AccentPicker(selection: $accentRaw)
                } header: {
                    Eyebrow("Aspetto e colore")
                } footer: {
                    Text("Colore d'accento: \((AccentPreset(rawValue: accentRaw) ?? .default).displayName).")
                }
                .hfListRow()

                Section {
                    Stepper(value: $defaultRest, in: 0...900, step: 15) {
                        Text("Recupero: \(Formatting.rest(defaultRest))")
                    }
                } header: {
                    Eyebrow("Recupero predefinito")
                } footer: {
                    Text("Usato per i nuovi esercizi che non hanno un recupero personalizzato.")
                }
                .hfListRow()

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
                    Eyebrow("Incremento del peso")
                } footer: {
                    Text("Di quanto cambia il peso a ogni tocco su + e −.")
                }
                .hfListRow()

                Section {
                    Button("Ripristina valori predefiniti", systemImage: "arrow.counterclockwise", role: .destructive) {
                        confirmingReset = true
                    }
                    .foregroundStyle(palette.destructive)
                    .frame(minHeight: 44)
                } footer: {
                    Text("Riporta recupero e incremento del peso ai valori iniziali. Schede, esercizi e storico non cambiano.")
                }
                .hfListRow()

                Section {
                    NavigationLink("Catalogo esercizi") { ExerciseCatalogView() }
                    NavigationLink("Esercizi archiviati") { ArchivedExercisesView() }
                } header: {
                    Eyebrow("Esercizi")
                }
                .hfListRow()
            }
            .hfScreenBackground()
            .navigationTitle("Impostazioni")
            .confirmationDialog("Ripristinare le impostazioni?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Ripristina", role: .destructive) {
                    defaultRest = AppSettings.defaultRestFallback
                    weightStep = AppSettings.weightStepFallback
                }
                Button("Annulla", role: .cancel) {}
            }
        }
    }
}

/// Fila di cerchi colorati per scegliere l'accento: quello scelto ha la ✓ (non solo il colore).
private struct AccentPicker: View {
    @Environment(\.palette) private var palette
    @Binding var selection: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) { circles }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: Spacing.s), count: 3), alignment: .leading, spacing: Spacing.s) { circles }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var circles: some View {
        ForEach(AccentPreset.allCases) { preset in
            Button {
                selection = preset.rawValue
            } label: {
                ZStack {
                    Circle().fill(preset.fill)
                    if preset.rawValue == selection {
                        Image(systemName: "checkmark").font(.headline.weight(.black)).foregroundStyle(Palette.ink)
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(palette.textPrimary, lineWidth: preset.rawValue == selection ? 3 : 0).padding(-4))
                .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Accento \(preset.displayName)")
            .accessibilityAddTraits(preset.rawValue == selection ? .isSelected : [])
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(PreviewData.container())
}
#endif
