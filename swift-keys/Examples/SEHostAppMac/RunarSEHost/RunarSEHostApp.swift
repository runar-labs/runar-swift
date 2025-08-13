import SwiftUI

@main
struct RunarSEHostApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var status: String = "Idle"

    var body: some View {
        VStack(spacing: 12) {
            Text("Secure Enclave Test Host").font(.headline)
            Text(status).font(.caption).foregroundStyle(.secondary)
            Button("Generate SE Key") {
                do {
                    let key = try RunarSEKeyManager.createOrLoadP256SigningKey(label: "com.runar.keys.test.identity")
                    status = "OK: \(key)"
                } catch {
                    status = "Error: \(error.localizedDescription)"
                }
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}


