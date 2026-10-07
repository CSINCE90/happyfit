import SwiftUI

/// Schermata iniziale provvisoria dell'app iOS.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text(AppBranding.appName)
                .font(.largeTitle.bold())
            Text("iPhone")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
