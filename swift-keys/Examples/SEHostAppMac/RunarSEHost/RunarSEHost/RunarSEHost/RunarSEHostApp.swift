import SwiftUI
import RunarKeys
import X509
import CryptoKit
import Security
import SwiftCommon
import RunarTransporter

 

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
    @State private var currentNodeId: String? = nil
    @State private var t1: NetworkQuicTransporter? = nil
    @State private var t2: NetworkQuicTransporter? = nil
    @State private var t1NodeId: String = ""
    @State private var t2NodeId: String = ""
 

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
                    append("Step 1")
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
                    append("Step 2")
                    
                    let handle = try mk.createCA(subjectCN: "Runar Test CA", validityYears: 5)
                    self.caHandle = handle
                    append("[Mobile] CA created\n  subject: \(handle.generated.certificate.subject)\n")
                } catch {
                    append("[Mobile] CA ERROR: \(error.localizedDescription)\n")
                }
            }
            Button("3) Node: Generate or Load identity SE key") {
                do {
                    append("Step 3")
                    let key = try mk.generateNodeIdentity(label: "com.runar.keys.test.identity")
                    let fp = RunarSEKeyManager.publicKeySHA256Hex(for: key) ?? "(no fp)"
                    append("[Node] Identity SE key\n  fp: \(fp)\n")
                } catch {
                    append("[Node] Identity SE key ERROR: \(error.localizedDescription)\n")
                }
            }
            Button("4) Node: Build CSR + SAN=node-id (message)") {
                do {
                    append("Step 4")
                    let secKey = try mk.generateNodeIdentity(label: "com.runar.keys.test.identity")
                    // Compute CRI for logging
                    let subject = try dn(cn: "node-csr-test")
                    guard let pub = SecKeyCopyPublicKey(secKey) else { throw NSError(domain: "CSR", code: -1) }
                    var perr: Unmanaged<CFError>?
                    guard let pubX963 = SecKeyCopyExternalRepresentation(pub, &perr) as Data? else { throw perr!.takeRetainedValue() as Error }
                    let p256Pub = try P256.Signing.PublicKey(x963Representation: pubX963)
                    let certPub = Certificate.PublicKey(p256Pub)
                    let nodeId = Ids.compactId(pubX963)
                    self.currentNodeId = nodeId
                    let attrs = try CSRBuilder.buildExtensionRequestAttributes(nodeIdSAN: nodeId)
                    let cri = try CertificateSigningRequestHelper.infoBytes(version: .v1, subject: subject, publicKey: certPub, attributes: attrs)
                    append("[Node] CSR (message) CRI bytes: \(cri.count)\n\(hex(Data(cri)))\n")
                    // Sign message
                    var serr: Unmanaged<CFError>?
                    guard let sig = SecKeyCreateSignature(secKey, SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256, Data(cri) as CFData, &serr) as Data? else { throw serr!.takeRetainedValue() as Error }
                    append("[Node] CSR SIG (message) len=\(sig.count)\n\(hex(sig))\n")
                    let csr = try mk.buildCSR(signingKey: secKey, subjectCN: "node-csr-test", nodeIdSAN: nodeId)
                    self.lastCSR = csr
                    append("[Node] CSR (message) DER len=\(csr.count)\n\(hex(csr))\n")
                    let parsed = try CertificateSigningRequest(derEncoded: Array(csr))
                    append("[Node] CSR OK (message)\n  subject: \(parsed.subject)\n")
                } catch {
                    append("[Node] CSR Error (message): \(String(describing: error))\n")
                }
            }
            // 5) Mobile: Issue leaf certificate from CSR
            Button("5) Mobile: Issue leaf cert from CSR", action: {
                do {
                    append("Step 5")
                    guard let ca = self.caHandle else { append("[Mobile] Issue leaf ERROR: CA not created\n"); return }
                    guard let csr = self.lastCSR else { append("[Mobile] Issue leaf ERROR: CSR not available\n"); return }
                    append("[Mobile] CSR PoP verify...\n")
                    let req = try CertificateSigningRequest(derEncoded: Array(csr))
                    let isValid = req.publicKey.isValidSignature(req.signature, for: req)
                    append("[Mobile] CSR PoP = \(isValid)\n")
                    guard let nodeId = self.currentNodeId else { append("[Mobile] Issue leaf ERROR: node-id not available\n"); return }
                    do {
                        let leaf = try mk.issueLeaf(from: ca, csrDER: csr, subjectOverrideCN: nodeId, sanDNS: [nodeId], validityDays: 180)
                        self.leafCert = leaf
                        append("[Mobile] Leaf issued\n  subject: \(leaf.subject)\n")
                        // Validate chain with SNI
                        try mk.validateChain(leaf: leaf, ca: ca.generated.certificate, sniHost: nodeId)
                        append("[Mobile] Chain OK (SNI=\(nodeId))\n")
                        // SPKI pinning example
                        let spki = CertificateUtils.spkiBytes(leaf.publicKey)
                        let pinnedOk = mk.spkiPinned(leaf, expectedSPKI: spki)
                        append("[Mobile] SPKI pin check = \(pinnedOk)\n")
                    } catch {
                        // Extra diagnostics
                        append("[Mobile] Issue leaf ERROR: \(error.localizedDescription)\n")
                        // Try to parse CSR again and dump minimal components
                        do {
                            let req2 = try CertificateSigningRequest(derEncoded: Array(csr))
                            append("[Diag] CSR subject=\(req2.subject)\n")
                            let spkiLen = CertificateUtils.spkiBytes(req2.publicKey).count
                            append("[Diag] CSR pub spkiLen=\(spkiLen) bytes\n")
                            append("[Diag] CSR sig algo=ecdsaWithSHA256\n")
                            // Attempt to build a cert with a constant small serial to check DER constraints
                            let testSerial: [UInt8] = [0x01]
                            _ = try CertificateIssuer.signLeafWithPublicKey(
                                ca: ca.generated,
                                leafPublicKey: req2.publicKey,
                                subjectCN: nodeId,
                                sanDNS: [nodeId],
                                validityDays: 30,
                                serialBytes: testSerial
                            )
                            append("[Diag] Fallback issuance with serial=01 succeeded\n")
                        } catch {
                            append("[Diag] Additional failure: \(error.localizedDescription)\n")
                        }
                    }
                } catch {
                    append("[Mobile] Issue leaf ERROR: \(error.localizedDescription)\n")
                }
            })
            // 5b) Node: Install issued leaf certificate into Keychain
            Button("5b) Node: Install issued leaf cert into Keychain", action: {
                do {
                    append("Step 5b")
                    guard let leaf = self.leafCert else { append("[Node] Install cert ERROR: leaf cert not available\n"); return }
                    guard let nodeId = self.currentNodeId else { append("[Node] Install cert ERROR: node-id not available\n"); return }
                    // Ensure node private key exists (same label used earlier)
                    _ = try mk.generateNodeIdentity(label: "com.runar.keys.test.identity")
                    // Convert to SecCertificate and add to keychain with a friendly label
                    guard let secCert = CertificateUtils.toSecCertificate(leaf) else { append("[Node] Install cert ERROR: could not convert to SecCertificate\n"); return }
                    let label = "Runar Node Certificate \(nodeId)"
                    let addQuery: [String: Any] = [
                        kSecClass as String: kSecClassCertificate,
                        kSecValueRef as String: secCert,
                        kSecAttrLabel as String: label
                    ]
                    let status = SecItemAdd(addQuery as CFDictionary, nil)
                    if status == errSecDuplicateItem {
                        append("[Node] Certificate already installed label=\(label)\n")
                    } else if status == errSecSuccess {
                        append("[Node] Certificate installed label=\(label) size=\(CertificateUtils.toDER(leaf).count) bytes\n")
                    } else {
                        append("[Node] Install cert ERROR: OSStatus \(status)\n")
                    }
                } catch {
                    append("[Node] Install cert ERROR: \(error.localizedDescription)\n")
                }
            })
            // Removed non-recommended CSR paths; keeping only message-signed
            Divider()
            Group {
                Button("6) Mobile→Node: Network key → wrap for node, store blob, load, unwrap and store") {
                    do {
                        append("Step 6")
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
                        append("Step 7")
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
                        append("Step 8")
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
                Button("9) Envelope API (facade): encrypt on mobile (profile+network), decrypt via facade") {
                    do {
                        append("Step 9")
                        let message = Data("Envelope API test payload".utf8)
                        let netId = "default"
                        let profileId = "personal"
                        let env = try mk.encryptWithEnvelope(data: message, networkId: netId, profileIds: [profileId])
                        append("[Mobile] Envelope API created\n  ct=\(env.encryptedData.count) bytes, netId=\(env.networkId ?? "nil"), wraps: net=\(env.networkEncryptedKey.count) profileKeys=\(env.profileEncryptedKeys.keys.sorted())\n")
                        let ptNet = try mk.decryptWithNetwork(envelopeData: env)
                        precondition(ptNet == message)
                        append("[Mobile] Envelope API decrypt OK (network)\n")
                        let ptProf = try mk.decryptWithProfile(envelopeData: env, profileId: profileId)
                        precondition(ptProf == message)
                        append("[Mobile] Envelope API decrypt OK (profile)\n")
                    } catch {
                        append("[Mobile] Envelope API ERROR: \(error.localizedDescription)\n")
                    }
                }
                // Transporter E2E (optional)
                Group {
                Divider()
                Button("10) Transporter TLS E2E: start two nodes", action: {
                    Task {
                        do {
                            append("Step 10")
                            append("[Transport] Setting up CA and two nodes...\n")
                            let ca = try mk.createCA(subjectCN: "Runar Test CA")
                            let sk1 = try mk.generateNodeIdentity(label: "hostapp-node1")
                            let pk1 = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: sk1)
                            let id1 = RunarKeys.Ids.compactId(pk1)
                            let csr1 = try mk.buildCSR(signingKey: sk1, subjectCN: id1, nodeIdSAN: id1)
                            let cert1 = try mk.issueLeaf(from: ca, csrDER: csr1, subjectOverrideCN: id1, sanDNS: [id1], validityDays: 90)
                            let sk2 = try mk.generateNodeIdentity(label: "hostapp-node2")
                            let pk2 = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: sk2)
                            let id2 = RunarKeys.Ids.compactId(pk2)
                            let csr2 = try mk.buildCSR(signingKey: sk2, subjectCN: id2, nodeIdSAN: id2)
                            let cert2 = try mk.issueLeaf(from: ca, csrDER: csr2, subjectOverrideCN: id2, sanDNS: [id2], validityDays: 90)
 
                             let chain1 = [RunarKeys.CertificateUtils.toDER(cert1), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]
                             let chain2 = [RunarKeys.CertificateUtils.toDER(cert2), RunarKeys.CertificateUtils.toDER(ca.generated.certificate)]
 
                             let node1Info = RunarNodeInfo(nodePublicKey: pk1, addresses: ["127.0.0.1:50091"], services: [])
                             let node2Info = RunarNodeInfo(nodePublicKey: pk2, addresses: ["127.0.0.1:50092"], services: [])
 
                             let opt1 = NetworkQuicTransportOptions(verifyCertificates: true, keepAliveInterval: 15, connectionIdleTimeout: 60, streamIdleTimeout: 30, maxIdleStreamsPerPeer: 10, certificates: chain1, secKey: sk1, mobileKeyManager: mk)
                             let opt2 = NetworkQuicTransportOptions(verifyCertificates: true, keepAliveInterval: 15, connectionIdleTimeout: 60, streamIdleTimeout: 30, maxIdleStreamsPerPeer: 10, certificates: chain2, secKey: sk2, mobileKeyManager: mk)
 
                             let handler1 = HostEchoHandler(nodeId: id1, log: { line in append(line) })
                             let handler2 = HostEchoHandler(nodeId: id2, log: { line in append(line) })
                             let tr1 = NetworkQuicTransporter(nodeInfo: node1Info, bindAddress: "127.0.0.1:50091", messageHandler: handler1, options: opt1, logger: RunarLogger(subsystem: "com.runar.transporter", category: "hostapp-1"))
                             let tr2 = NetworkQuicTransporter(nodeInfo: node2Info, bindAddress: "127.0.0.1:50092", messageHandler: handler2, options: opt2, logger: RunarLogger(subsystem: "com.runar.transporter", category: "hostapp-2"))
                             handler1.transporter = tr1
                             handler2.transporter = tr2
                             try await tr1.start(); try await tr2.start()
                             self.t1 = tr1; self.t2 = tr2
                             self.t1NodeId = id1; self.t2NodeId = id2
                             append("[Transport] Started transporter1 + transporter2\n")
 
                             // connect both ways
                             let peer1 = RunarPeerInfo(publicKey: pk1, addresses: ["127.0.0.1:50091"]) // seen by node2
                             let peer2 = RunarPeerInfo(publicKey: pk2, addresses: ["127.0.0.1:50092"]) // seen by node1
                             try await tr1.connect(to: peer2)
                             try await tr2.connect(to: peer1)
                             append("[Transport] Connected both directions\n")
                         } catch {
                             append("[Transport] ERROR: \(error.localizedDescription)\n")
                         }
                     }
                 })
                 Button("10b) Transporter: send request from node1 to node2", action: {
                     Task {
                         append("Step 10b")
                         guard let tr1 = self.t1 else { append("[Transport] ERROR: transporter1 not started\n"); return }
                         let msg = RunarNetworkMessage(sourceNodeId: self.t1NodeId, destinationNodeId: self.t2NodeId, messageType: MessageTypes.request, payloads: [NetworkMessagePayloadItem(path: "/echo", valueBytes: Data("ping".utf8), correlationId: "req-1")])
                         do { try await tr1.send(message: msg); append("[Transport] Sent request ping\n") } catch { append("[Transport] send ERROR: \(error.localizedDescription)\n") }
                     }
                 })
                 Button("10c) Transporter: send request from node2 to node1", action: {
                     Task {
                         append("Step 10c")
                         guard let tr2 = self.t2 else { append("[Transport] ERROR: transporter2 not started\n"); return }
                         let msg = RunarNetworkMessage(sourceNodeId: self.t2NodeId, destinationNodeId: self.t1NodeId, messageType: MessageTypes.request, payloads: [NetworkMessagePayloadItem(path: "/echo", valueBytes: Data("pong".utf8), correlationId: "req-2")])
                         do { try await tr2.send(message: msg); append("[Transport] Sent request pong\n") } catch { append("[Transport] send ERROR: \(error.localizedDescription)\n") }
                     }
                 })
                 Button("10d) Transporter: stop both", action: {
                     Task { await self.t1?.stop(); await self.t2?.stop(); append("[Transport] Stopped both transporters\n") }
                 })
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

 
final class HostEchoHandler: MessageHandlerProtocol {
    let nodeId: String
    weak var transporter: TransportProtocol?
    let log: (String) -> Void
    init(nodeId: String, log: @escaping (String) -> Void) { self.nodeId = nodeId; self.log = log }
    func handleMessage(_ message: RunarNetworkMessage) {
        log("[Handler \(nodeId)] received: type=\(message.messageType) from=\(message.sourceNodeId) path=\(message.payloads.first?.path ?? "-") corr=\(message.payloads.first?.correlationId ?? "-")")
        if message.messageType == MessageTypes.request, let corr = message.payloads.first?.correlationId {
            let response = RunarNetworkMessage(
                sourceNodeId: nodeId,
                destinationNodeId: message.sourceNodeId,
                messageType: MessageTypes.response,
                payloads: [NetworkMessagePayloadItem(path: "/echo", valueBytes: message.payloads.first?.valueBytes ?? Data(), correlationId: corr)]
            )
            log("[Handler \(nodeId)] sending response corr=\(corr)")
            Task { try? await transporter?.send(message: response) }
        }
    }
    func peerConnected(_ peerInfo: RunarNodeInfo) { log("[Handler \(nodeId)] peer connected: \(peerInfo.nodeId)") }
    func peerDisconnected(_ peerId: String) { log("[Handler \(nodeId)] peer disconnected: \(peerId)") }
}
 


