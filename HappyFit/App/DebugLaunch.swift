#if DEBUG
import SwiftUI
import SwiftData
import UIKit

/// Solo per il collaudo del layout: `-debugScreen <nome>` apre una schermata con dati di esempio in memoria.
/// Non esiste nelle build Release.
enum DebugLaunch {
    static var screen: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-debugScreen"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}

extension DebugLaunch {
    /// `-debugScroll end`: dopo il caricamento scorre in fondo gli scroll view, per vedere cosa resta sotto le barre fisse.
    static var scrollsToEnd: Bool { CommandLine.arguments.contains("-debugScroll") }

    @MainActor
    static func scrollAllToEnd() {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.bounds.height > 100 {
                let inset = scroll.adjustedContentInset
                let maxY = max(scroll.contentSize.height + inset.bottom - scroll.bounds.height, -inset.top)
                // A passi di una schermata: le liste "pigre" stimano l'altezza e non vanno saltate in un colpo.
                let y = min(max(scroll.contentOffset.y, -inset.top) + scroll.bounds.height * 0.8, maxY)
                scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            }
            view.subviews.forEach(visit)
        }
        windows.forEach { visit($0) }
    }
}

@MainActor
struct DebugScreenView: View {
    let name: String
    let container: ModelContainer

    init(name: String) {
        self.name = name
        self.container = PreviewData.container(openSession: ["home-open", "active", "active-timer", "number-entry", "reps-entry"].contains(name))
    }

    var body: some View {
        content
            .modelContainer(container)
            .task {
                guard DebugLaunch.scrollsToEnd else { return }
                for delay in [1.0] + Array(repeating: 0.4, count: 24) {
                    try? await Task.sleep(for: .seconds(delay))
                    DebugLaunch.scrollAllToEnd()
                }
            }
    }

    /// Mostra la schermata dentro una tab bar, per vedere le sovrapposizioni con la barra fissa.
    private func inTabBar<V: View>(@ViewBuilder _ view: () -> V) -> some View {
        TabView { view().tabItem { Label("Schede", systemImage: "list.bullet.rectangle") } }
    }

    @ViewBuilder
    private var content: some View {
        switch name {
        case "home", "home-open": RootView(initialTab: 0)
        case "templates": RootView(initialTab: 1)
        case "history": RootView(initialTab: 2)
        case "settings": RootView(initialTab: 3)
        case "template-editor": inTabBar { NavigationStack { TemplateEditorView(template: PreviewData.template(in: container)) } }
        case "catalog": inTabBar { NavigationStack { ExerciseCatalogView() } }
        case "history-detail": inTabBar { NavigationStack { SessionDetailView(session: PreviewData.closedSession(in: container)) } }
        case "exercise-edit":
            ExerciseEditSheet(exercise: PreviewData.exercise(in: container), viewModel: ExerciseCatalogViewModel(context: container.mainContext))
        case "number-entry":
            NumberEntrySheet(target: NumberTarget(entry: PreviewData.openSession(in: container).sortedExercises[0].sortedSets[0], isWeight: true)) { _ in }
        case "reps-entry":
            NumberEntrySheet(target: NumberTarget(entry: PreviewData.openSession(in: container).sortedExercises[0].sortedSets[0], isWeight: false)) { _ in }
        case "exercise-new":
            ExerciseEditSheet(exercise: nil, viewModel: ExerciseCatalogViewModel(context: container.mainContext))
        case "set-correction":
            SetCorrectionSheet(entry: PreviewData.closedSession(in: container).sortedExercises[0].sortedSets[0], onSave: { _, _, _ in })
        case "rest-edit": RestEditSheet(seconds: 90) { _ in }
        case "past-session": PastSessionSheet(viewModel: HistoryViewModel(context: container.mainContext))
        case "session-times":
            let session = PreviewData.closedSession(in: container)
            SessionTimesSheet(start: session.startedAt, end: session.endedAt ?? session.startedAt) { _, _ in true }
        case "picker": ExercisePickerView { _ in }
        case "active": ActiveWorkoutView(session: PreviewData.openSession(in: container), context: container.mainContext)
        case "active-timer":
            let vm = ActiveWorkoutViewModel(session: PreviewData.openSession(in: container), context: container.mainContext)
            let _ = vm.startRest(seconds: 90)
            ActiveWorkoutView(viewModel: vm)
        default: RootView()
        }
    }
}
#endif
