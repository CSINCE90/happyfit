import SwiftUI

/// Le tre finestre dell'eliminazione di un esercizio: conferma, "non si può" (con Archivia), conferma rimozione dalle schede.
struct ExerciseDeletionDialogs: ViewModifier {
    let viewModel: ExerciseCatalogViewModel
    /// Chiamata dopo che l'esercizio è stato eliminato o archiviato (es. per chiudere il foglio di modifica).
    var onFinished: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                title(for: confirmDeleteExercise),
                isPresented: binding { if case .confirmDelete = $0 { return true } else { return false } },
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) { if viewModel.confirmDeletion() { onFinished() } }
                Button("Annulla", role: .cancel) { viewModel.cancelDeletion() }
            } message: {
                Text("Non è usato in nessuna scheda né in nessun allenamento. Verrà eliminato definitivamente.")
            }
            .alert(
                "Non si può eliminare",
                isPresented: binding { if case .blocked = $0 { return true } else { return false } }
            ) {
                Button("Archivia") { if viewModel.archiveInsteadOfDeleting() { onFinished() } }
                Button("Annulla", role: .cancel) { viewModel.cancelDeletion() }
            } message: {
                Text(blockedMessage)
            }
            .confirmationDialog(
                title(for: templatesExercise, prefix: "Rimuovere"),
                isPresented: binding { if case .confirmRemoveFromTemplates = $0 { return true } else { return false } },
                titleVisibility: .visible
            ) {
                Button("Rimuovi dalle schede ed elimina", role: .destructive) { if viewModel.confirmDeletion() { onFinished() } }
                Button("Annulla", role: .cancel) { viewModel.cancelDeletion() }
            } message: {
                Text(templatesMessage)
            }
    }

    private func binding(_ matches: @escaping (ExerciseDeletionPlan) -> Bool) -> Binding<Bool> {
        Binding(
            get: { viewModel.deletionPlan.map(matches) ?? false },
            set: { if !$0 { viewModel.cancelDeletion() } }
        )
    }

    private var confirmDeleteExercise: Exercise? {
        if case .confirmDelete(let e) = viewModel.deletionPlan { return e }
        return nil
    }

    private var templatesExercise: Exercise? {
        if case .confirmRemoveFromTemplates(let e, _) = viewModel.deletionPlan { return e }
        return nil
    }

    private func title(for exercise: Exercise?, prefix: String = "Eliminare") -> String {
        "\(prefix) \"\(exercise?.name ?? "")\"?"
    }

    private var blockedMessage: String {
        guard case .blocked(let exercise, let count) = viewModel.deletionPlan else { return "" }
        let allenamenti = count == 1 ? "1 allenamento" : "\(count) allenamenti"
        return "\"\(exercise.name)\" compare in \(allenamenti): eliminarlo falserebbe lo storico. Puoi archiviarlo: sparisce dal catalogo ma resta nello storico."
    }

    private var templatesMessage: String {
        guard case .confirmRemoveFromTemplates(_, let templates) = viewModel.deletionPlan else { return "" }
        if templates.count == 1 {
            return "È usato nella scheda: \(templates[0]). Se continui verrà tolto da questa scheda e poi eliminato."
        }
        return "È usato nelle schede: \(templates.joined(separator: ", ")). Se continui verrà tolto da queste schede e poi eliminato."
    }
}

extension View {
    func exerciseDeletionDialogs(_ viewModel: ExerciseCatalogViewModel, onFinished: @escaping () -> Void = {}) -> some View {
        modifier(ExerciseDeletionDialogs(viewModel: viewModel, onFinished: onFinished))
    }
}
