import SwiftUI
import RunarKeys
import X509

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
            Button("Generate or Load SE Key") {
                do {
                    let key = try RunarSEKeyManager.createOrLoadP256SigningKey(label: "com.runar.keys.test.identity")
                    let fp = RunarSEKeyManager.publicKeySHA256Hex(for: key) ?? "(no fp)"
                    status = "OK: \(key)\nFP: \(fp)"
                } catch {
                    status = "Error: \(error.localizedDescription)"
                }
            }
            Button("Build CSR and parse subject") {
                do {
                    let secKey = try RunarSEKeyManager.createOrLoadP256SigningKey(label: "com.runar.keys.test.identity")
                    let csr = try CSRBuilder.buildCSR(subjectCN: "node-csr-test", signingKey: secKey)
                    let parsed = try CertificateSigningRequest(derEncoded: Array(csr))
                    status = "CSR OK: subject=\(parsed.subject)"
                } catch {
                    status = "CSR Error: \(error.localizedDescription)"
                }
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}


