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

/// Fascia "iPhone non raggiungibile": icona e testo (non solo colore), su una riga sola per non togliere spazio
/// all'esercizio. Se il testo intero non ci sta, si passa a varianti più corte (l'etichetta vocale resta completa).
struct OfflineBanner: View {
    @Environment(\.palette) private var palette
    let lastUpdate: Date?

    private var time: String? {
        lastUpdate?.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(time.map { "iPhone non raggiungibile · \($0)" } ?? "iPhone non raggiungibile")
            line(time.map { "iPhone assente · \($0)" } ?? "iPhone assente")
            line(time.map { "Offline · \($0)" } ?? "Offline")
            line(time ?? "Offline")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        // Lo sfondo copre solo la riga (non l'area dell'ora): lascia più spazio all'esercizio.
        .background(palette.raised, ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(time.map { "iPhone non raggiungibile. Ultimo aggiornamento alle \($0)" } ?? "iPhone non raggiungibile")
    }

    private func line(_ text: String) -> some View {
        Label(text, systemImage: "iphone.slash")
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
