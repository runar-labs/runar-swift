import SwiftUI
import RunarKeys
import X509
import CryptoKit
import Security

@main
struct RunarSEHostApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var log: String = ""
    @State private var nodeAgreementPrivate: P256.KeyAgreement.PrivateKey? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text("Secure Enclave Test Host").font(.headline)
            TextEditor(text: $log)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
            Button("1) Generate or Load SE Key") {
                do {
                    let key = try RunarSEKeyManager.createOrLoadP256SigningKey(label: "com.runar.keys.test.identity")
                    let fp = RunarSEKeyManager.publicKeySHA256Hex(for: key) ?? "(no fp)"
                    append("SE key OK\n  fp: \(fp)")
                } catch {
                    append("SE key Error: \(error.localizedDescription)")
                }
            }
            Button("2) Build CSR + SAN=node-id (message)") {
                do {
                    let secKey = try RunarSEKeyManager.createOrLoadP256SigningKey(label: "com.runar.keys.test.identity")
                    // Compute CRI for logging
                    let subject = try dn(cn: "node-csr-test")
                    guard let pub = SecKeyCopyPublicKey(secKey) else { throw NSError(domain: "CSR", code: -1) }
                    var perr: Unmanaged<CFError>?
                    guard let pubX963 = SecKeyCopyExternalRepresentation(pub, &perr) as Data? else { throw perr!.takeRetainedValue() as Error }
                    let p256Pub = try P256.Signing.PublicKey(x963Representation: pubX963)
                    let certPub = try Certificate.PublicKey(p256Pub)
                    let attrs = try CSRBuilder.buildExtensionRequestAttributes(nodeIdSAN: "node-\(UUID().uuidString.prefix(8))")
                    let cri = try CertificateSigningRequestHelper.infoBytes(version: .v1, subject: subject, publicKey: certPub, attributes: attrs)
                    append("CRI (message) bytes: \(cri.count)\n\(hex(Data(cri)))")
                    // Sign message
                    var serr: Unmanaged<CFError>?
                    guard let sig = SecKeyCreateSignature(secKey, SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256, Data(cri) as CFData, &serr) as Data? else { throw serr!.takeRetainedValue() as Error }
                    append("SIG (message) len=\(sig.count)\n\(hex(sig))")
                    let csr = try CSRBuilder.buildCSRMessageSignedManual(subjectCN: "node-csr-test", signingKey: secKey, nodeIdSAN: "node-\(UUID().uuidString.prefix(8))")
                    append("CSR (message) DER len=\(csr.count)\n\(hex(csr))")
                    let parsed = try CertificateSigningRequest(derEncoded: Array(csr))
                    append("CSR OK (message)\n  subject: \(parsed.subject)")
                } catch {
                    append("CSR Error (message): \(String(describing: error))")
                }
            }
            // Removed digest path buttons to keep only the proven working path
            Button("Build CSR (message, manual) and parse subject") {
                do {
                    let secKey = try RunarSEKeyManager.createOrLoadP256SigningKey(label: "com.runar.keys.test.identity")
                    let csr = try CSRBuilder.buildCSRMessageSignedManual(subjectCN: "node-csr-test", signingKey: secKey)
                    append("CSR (message, manual) DER len=\(csr.count)\n\(hex(csr))")
                    let parsed = try CertificateSigningRequest(derEncoded: Array(csr))
                    append("CSR OK (message, manual)\n  subject: \(parsed.subject)")
                } catch {
                    append("CSR Error (message, manual): \(String(describing: error))")
                }
            }
            Button("Build CSR (digest, manual) and parse subject") {
                do {
                    let secKey = try RunarSEKeyManager.createOrLoadP256SigningKey(label: "com.runar.keys.test.identity")
                    let csr = try CSRBuilder.buildCSRDigestSignedManual(subjectCN: "node-csr-test", signingKey: secKey)
                    append("CSR (digest, manual) DER len=\(csr.count)\n\(hex(csr))")
                    let parsed = try CertificateSigningRequest(derEncoded: Array(csr))
                    append("CSR OK (digest, manual)\n  subject: \(parsed.subject)")
                } catch {
                    append("CSR Error (digest, manual): \(String(describing: error))")
                }
            }
            Divider()
            Group {
                Button("3) Mobile: Initialize user root secret") {
                    do {
                        let secret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
                        try UserRootStore.save(secret)
                        append("Mobile init OK\n  root: \(secret.count) bytes")
                    } catch {
                        append("Mobile init Error: \(error.localizedDescription)")
                    }
                }
                Button("4) Network: derive key, wrap for node, unwrap and verify") {
                    do {
                        let master = try UserRootStore.load()
                        let networkPriv = try NetworkKeys.deriveAgreementPrivateKey(userRoot: master, label: "default")
                        // Simulated node agreement keypair
                        let nodePriv = P256.KeyAgreement.PrivateKey(); let nodePub = nodePriv.publicKey
                        let wrapped = try NetworkKeys.exportWrappedPrivateScalar(networkPriv, to: nodePub)
                        let imported = try NetworkKeys.importWrappedPrivateScalar(wrapped, for: nodePriv)
                        precondition(imported.publicKey.rawRepresentation == networkPriv.publicKey.rawRepresentation)
                        self.nodeAgreementPrivate = nodePriv
                        append("Network key OK\n  wrapped: \(wrapped.count) bytes")
                    } catch {
                        append("Network key Error: \(error.localizedDescription)")
                    }
                }
                Button("5) Profiles: derive personal/work and envelope roundtrip") {
                    do {
                        let master = try UserRootStore.load()
                        let personal = try ProfileKeys.deriveAgreementPrivateKey(userRoot: master, label: "personal")
                        let work = try ProfileKeys.deriveAgreementPrivateKey(userRoot: master, label: "work")
                        let message = Data("This is a test message".utf8)
                        // Encrypt with ECIES for personal profile
                        let ct = try ECIES.encrypt(data: message, recipientPublicKey: personal.publicKey)
                        let pt = try ECIES.decrypt(encrypted: ct, recipientPrivateKey: personal)
                        precondition(pt == message)
                        append("Profiles OK\n  personal/work derived\n  envelope roundtrip OK (")
                    } catch {
                        append("Profiles Error: \(error.localizedDescription)")
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    private func append(_ line: String) {
        if log.isEmpty { log = line } else { log += "\n" + line }
    }

    private func dn(cn: String) throws -> DistinguishedName {
        let attr = try RelativeDistinguishedName.Attribute(type: .RDNAttributeType.commonName, printableString: cn)
        return DistinguishedName([RelativeDistinguishedName([attr])])
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}


