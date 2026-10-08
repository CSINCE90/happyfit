import SwiftUI

/// Progresso di un esercizio: un segmento per serie fino a 8, oltre una barra continua.
struct SetProgressView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let completed: Int
    let total: Int

    var body: some View {
        Group {
            if total <= 8 {
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<max(total, 1), id: \.self) { index in
                        Capsule()
                            .fill(index < completed ? palette.accent : palette.raised)
                    }
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.raised)
                        Capsule()
                            .fill(palette.accent)
                            .frame(width: proxy.size.width * CGFloat(completed) / CGFloat(max(total, 1)))
                    }
                }
            }
        }
        .frame(height: 6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: completed)
        .accessibilityElement()
        .accessibilityLabel("\(completed) serie completate su \(total)")
    }
}

/// Anello del timer di recupero: si svuota man mano che il tempo passa.
struct TimerRing: View {
    @Environment(\.palette) private var palette
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(palette.raised, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// Cerchio di completamento della serie: vuoto, oppure pieno d'accento con ✓ (la ✓ è il segnale, non solo il colore).
struct CompletionCircle: View {
    @Environment(\.palette) private var palette
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isCompleted ? palette.accentOutline : palette.textSecondary, lineWidth: isCompleted ? 1.5 : 3)
                .background(Circle().fill(isCompleted ? palette.accent : Color.clear))
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(palette.onAccent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
