import SwiftUI

/// Messaggio a tutto schermo (nessuna sessione, allenamento completato).
struct WatchMessageView: View {
    @Environment(\.palette) private var palette
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.hfHeadline)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Spiegazione prima della richiesta di sistema per le notifiche (solo la prima volta).
struct PermissionExplanationView: View {
    @Environment(\.palette) private var palette
    let viewModel: WatchSessionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Image(systemName: "bell.badge")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text("Avviso di fine recupero")
                    .font(.hfHeadline)
                    .foregroundStyle(palette.textPrimary)
                Text("Con il polso abbassato l'app non può vibrare. Per avvisarti quando il recupero finisce serve il permesso per le notifiche.")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                Button("Consenti") { Task { await viewModel.answerPermission(allow: true) } }
                    .buttonStyle(WatchPrimaryButtonStyle())
                Button("Non ora") { Task { await viewModel.answerPermission(allow: false) } }
                    .buttonStyle(WatchSecondaryButtonStyle())
            }
        }
        // Sfondo pieno (non trasparente sulla sessione) e pulsante di chiusura neutro, con la X ben leggibile.
        .presentationBackground(palette.background)
    }
}
