import SwiftUI

/// Schermata iniziale provvisoria dell'app Watch.
struct WatchContentView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(AppBranding.appName)
                .font(.title3.bold())
            Text("Watch")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WatchContentView()
}
