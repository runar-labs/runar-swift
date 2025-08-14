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
    @State private var mk = MobileKeyManager()
    @State private var nodeAgreementPrivate: P256.KeyAgreement.PrivateKey? = nil
    @State private var nodeNetworkAgreementPrivate: P256.KeyAgreement.PrivateKey? = nil
    @State private var caHandle: MobileKeyManager.CAHandle? = nil
    @State private var lastCSR: Data? = nil
    @State private var leafCert: Certificate? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text("Runar Keys E2E Host").font(.headline)
            TextEditor(text: $log)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
            // 1) Mobile: Initialize user root
            Button("1) Mobile: Initialize user root secret (biometry)") {
                do {
                    let secret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
                    try mk.initializeUserRoot(secret: secret, requireUserPresence: true, requireBiometryCurrentSet: true)
                    append("[Mobile] Initialize user root secret\n  root: \(secret.count) bytes\n")
                } catch {
                    append("[Mobile] Initialize user root secret ERROR: \(error.localizedDescription)\n")
                }
            }
            // 2) Mobile: Create CA
            Button("2) Mobile: Create CA") {
                do {
                    let handle = try mk.createCA(subjectCN: "Runar Test CA", validityYears: 5)
                    self.caHandle = handle
                    append("[Mobile] CA created\n  subject: \(handle.generated.certificate.subject)\n")
                } catch {
                    append("[Mobile] CA ERROR: \(error.localizedDescription)\n")
                }
            }
            Button("3) Node: Generate or Load identity SE key") {
                do {
                    let key = try mk.generateNodeIdentity(label: "com.runar.keys.test.identity")
                    let fp = RunarSEKeyManager.publicKeySHA256Hex(for: key) ?? "(no fp)"
                    append("[Node] Identity SE key\n  fp: \(fp)\n")
                } catch {
                    append("[Node] Identity SE key ERROR: \(error.localizedDescription)\n")
                }
            }
            Button("4) Node: Build CSR + SAN=node-id (message)") {
                do {
                    let secKey = try mk.generateNodeIdentity(label: "com.runar.keys.test.identity")
                    // Compute CRI for logging
                    let subject = try dn(cn: "node-csr-test")
                    guard let pub = SecKeyCopyPublicKey(secKey) else { throw NSError(domain: "CSR", code: -1) }
                    var perr: Unmanaged<CFError>?
                    guard let pubX963 = SecKeyCopyExternalRepresentation(pub, &perr) as Data? else { throw perr!.takeRetainedValue() as Error }
                    let p256Pub = try P256.Signing.PublicKey(x963Representation: pubX963)
                    let certPub = Certificate.PublicKey(p256Pub)
                    let attrs = try CSRBuilder.buildExtensionRequestAttributes(nodeIdSAN: "node-\(UUID().uuidString.prefix(8))")
                    let cri = try CertificateSigningRequestHelper.infoBytes(version: .v1, subject: subject, publicKey: certPub, attributes: attrs)
                    append("[Node] CSR (message) CRI bytes: \(cri.count)\n\(hex(Data(cri)))\n")
                    // Sign message
                    var serr: Unmanaged<CFError>?
                    guard let sig = SecKeyCreateSignature(secKey, SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256, Data(cri) as CFData, &serr) as Data? else { throw serr!.takeRetainedValue() as Error }
                    append("[Node] CSR SIG (message) len=\(sig.count)\n\(hex(sig))\n")
                    let csr = try mk.buildCSR(signingKey: secKey, subjectCN: "node-csr-test", nodeIdSAN: "node-\(UUID().uuidString.prefix(8))")
                    self.lastCSR = csr
                    append("[Node] CSR (message) DER len=\(csr.count)\n\(hex(csr))\n")
                    let parsed = try CertificateSigningRequest(derEncoded: Array(csr))
                    append("[Node] CSR OK (message)\n  subject: \(parsed.subject)\n")
                } catch {
                    append("[Node] CSR Error (message): \(String(describing: error))\n")
                }
            }
            // 5) Mobile: Issue leaf certificate from CSR
            Button("5) Mobile: Issue leaf cert from CSR") {
                do {
                    guard let ca = self.caHandle else { append("[Mobile] Issue leaf ERROR: CA not created\n"); return }
                    guard let csr = self.lastCSR else { append("[Mobile] Issue leaf ERROR: CSR not available\n"); return }
                    append("[Mobile] CSR PoP verify...\n")
                    let req = try CertificateSigningRequest(derEncoded: Array(csr))
                    let isValid = req.publicKey.isValidSignature(req.signature, for: req)
                    append("[Mobile] CSR PoP = \(isValid)\n")
                    let leaf = try mk.issueLeaf(from: ca, csrDER: csr, subjectOverrideCN: "node-leaf", sanDNS: ["node.runar"], validityDays: 180)
                    self.leafCert = leaf
                    append("[Mobile] Leaf issued\n  subject: \(leaf.subject)\n")
                    // Validate chain with SNI
                    try mk.validateChain(leaf: leaf, ca: ca.generated.certificate, sniHost: "node.runar")
                    append("[Mobile] Chain OK (SNI=node.runar)\n")
                    // SPKI pinning example
                    let spki = CertificateUtils.spkiBytes(leaf.publicKey)
                    let pinnedOk = mk.spkiPinned(leaf, expectedSPKI: spki)
                    append("[Mobile] SPKI pin check = \(pinnedOk)\n")
                } catch {
                    append("[Mobile] Issue leaf ERROR: \(error.localizedDescription)\n")
                }
            }
            // Removed non-recommended CSR paths; keeping only message-signed
            Divider()
            Group {
                Button("6) Mobile→Node: Network key → wrap for node, store blob, load, unwrap and store") {
                    do {
                        let master = try mk.loadUserRoot()
                        let networkPriv = try mk.deriveNetworkAgreement(label: "default", userRoot: master)
                        // Simulated node agreement keypair
                        let nodePriv = P256.KeyAgreement.PrivateKey(); let nodePub = nodePriv.publicKey
                        let wrapped = try mk.exportNetworkAgreementWrapped(networkPriv, to: nodePub)
                        let blobLabel = "net-enc-\(UUID().uuidString)"
                        try NetworkKeys.storeEncryptedScalar(label: blobLabel, scalarCiphertext: wrapped)
                        append("[Mobile] Stored network encrypted blob label=\(blobLabel) size=\(wrapped.count)\n")
                        let loadedBlob = try NetworkKeys.loadEncryptedScalar(label: blobLabel)
                        append("[Mobile] Loaded network encrypted blob size=\(loadedBlob.count)\n")
                        precondition(loadedBlob == wrapped)
                        let imported = try mk.importNetworkAgreementWrapped(loadedBlob, for: nodePriv)
                        precondition(imported.publicKey.rawRepresentation == networkPriv.publicKey.rawRepresentation)
                        self.nodeAgreementPrivate = nodePriv
                        self.nodeNetworkAgreementPrivate = imported
                        append("[Mobile→Node] Network key wrap\n  wrapped: \(wrapped.count) bytes\n")
                        append("[Node] Network key installed\n  pub: \(imported.publicKey.x963Representation.base64EncodedString())\n")
                    } catch {
                        append("[Mobile→Node] Network key ERROR: \(error.localizedDescription)\n")
                    }
                }
                Button("7) Node: Use network key for ECIES decryption") {
                    do {
                        guard let nodeNet = self.nodeNetworkAgreementPrivate else { append("[Node] ECIES ERROR: network key not installed\n"); return }
                        let message = Data("Hello Node with ECIES".utf8)
                        // Mobile encrypts to Node's installed network public key
                        let ct = try ECIES.encrypt(data: message, recipientPublicKey: nodeNet.publicKey)
                        let pt = try ECIES.decrypt(encrypted: ct, recipientPrivateKey: nodeNet)
                        precondition(pt == message)
                        append("[Node] ECIES decrypt OK\n")
                    } catch {
                        append("[Node] ECIES ERROR: \(error.localizedDescription)\n")
                    }
                }
                Button("8) Multi-recipient envelope: encrypt on mobile (profile+network), decrypt on node and mobile") {
                    do {
                        let master = try mk.loadUserRoot()
                        let profileKey = try mk.deriveProfileAgreement(label: "personal", userRoot: master)
                        guard let nodeNet = self.nodeNetworkAgreementPrivate else { append("[Node] Envelope ERROR: network key not installed\n"); return }
                        let message = Data("This is a multi-recipient message".utf8)
                        let env = try MultiRecipientEnvelope.encrypt(data: message, recipients: [
                            "profile": profileKey.publicKey,
                            "network": nodeNet.publicKey,
                        ])
                        append("[Mobile] Multi-recipient envelope created\n  ct=\(env.ciphertext.count) bytes, wraps=\(env.wraps.keys.sorted())\n")
                        // Node decrypts with network key
                        let nodePT = try MultiRecipientEnvelope.decrypt(env, recipientLabel: "network", recipientPrivateKey: nodeNet)
                        precondition(nodePT == message)
                        append("[Node] Envelope decrypt OK (network)\n")
                        // Mobile decrypts with profile key
                        let mobilePT = try MultiRecipientEnvelope.decrypt(env, recipientLabel: "profile", recipientPrivateKey: profileKey)
                        precondition(mobilePT == message)
                        append("[Mobile] Envelope decrypt OK (profile)\n")
                    } catch {
                        append("[Mobile] Profiles ERROR: \(error.localizedDescription)\n")
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


