import Foundation
import XCTest
import RunarTransporter
import RunarKeys
import SwiftCommon
import SwiftASN1
import Crypto
import X509

@available(macOS 13.0, *)
final class CrossLanguageE2ETests: XCTestCase {
    private func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    private func write(_ data: Data, to path: URL) throws {
        try data.write(to: path, options: .atomic)
    }

    private func spawn(_ bin: String, _ args: [String], env: [String: String] = [:], tag: String = "RUST") throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        var e = ProcessInfo.processInfo.environment
        for (k, v) in env { e[k] = v }
        // Increase Rust logs by default
        if e["RUST_LOG"] == nil { e["RUST_LOG"] = "info,runar_node=debug,runar_transport_tests=debug,quinn=info" }
        p.environment = e
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        out.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return }
            FileHandle.standardError.write(Data("[\(tag)] ".utf8))
            FileHandle.standardError.write(data)
        }
        err.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8), !s.isEmpty else { return }
            FileHandle.standardError.write(Data("[\(tag) ERR] ".utf8))
            FileHandle.standardError.write(data)
        }
        try p.run()
        return p
    }
    
    private func makeSoftwareSecKey(label: String) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: true,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        return key
    }

    // No helper: Swift `NodeId.compactId` now matches the Rust algorithm

    func test_swift_server_rust_client() async throws {
        try await runScenario(swiftIsServer: true)
    }

    func test_rust_server_swift_client() async throws {
        try await runScenario(swiftIsServer: false)
    }

    private func runScenario(swiftIsServer: Bool) async throws {
        guard let rustClient = env("RUNAR_RUST_CLIENT_BIN"), let rustServer = env("RUNAR_RUST_SERVER_BIN") else {
            throw XCTSkip("Interop bins not provided. Run via scripts/run_cross_e2e.sh or set RUNAR_RUST_CLIENT_BIN and RUNAR_RUST_SERVER_BIN")
        }
        let tmpBase = URL(fileURLWithPath: env("RUNAR_E2E_TMPDIR") ?? NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpBase, withIntermediateDirectories: true)

        let km = RunarKeys.MobileKeyManager()
        let ca = try km.createCA(subjectCN: "Runar E2E Test CA")

        // Create Swift server identity
        let serverKey = try makeSoftwareSecKey(label: "swift-server-\(UUID().uuidString)")
        let serverPub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: serverKey)
        let serverId = RunarKeys.Ids.compactId(serverPub)
        let serverCSR = try km.buildCSR(signingKey: serverKey, subjectCN: serverId, nodeIdSAN: serverId)
        // For Swift server interop with Rust client, derive DNS-safe node id the way Rust client expects:
        // peer_node_id = compact_id("swift-server".bytes), then dns_safe ( - -> x, _ -> y )
        let rustRemoteAscii = Data("swift-server".utf8)
        let rustPeerId = NodeId.compactId(from: rustRemoteAscii)
        let rustPeerIdDnsSafe = rustPeerId.replacingOccurrences(of: "-", with: "x").replacingOccurrences(of: "_", with: "y")
        let serverCert = try km.issueLeaf(from: ca, csrDER: serverCSR, subjectOverrideCN: rustPeerIdDnsSafe, sanDNS: [rustPeerIdDnsSafe], validityDays: 30)

        // Create Swift client identity (for swift client in rust-server scenario)
        let swiftClientKey = try makeSoftwareSecKey(label: "swift-client-\(UUID().uuidString)")
        let swiftClientPub = try RunarKeys.NodeIdentitySigning.publicKeyX963(from: swiftClientKey)
        let swiftClientId = RunarKeys.Ids.compactId(swiftClientPub)
        let swiftClientCSR = try km.buildCSR(signingKey: swiftClientKey, subjectCN: swiftClientId, nodeIdSAN: swiftClientId)
        let swiftClientCert = try km.issueLeaf(from: ca, csrDER: swiftClientCSR, subjectOverrideCN: swiftClientId, sanDNS: [swiftClientId], validityDays: 30)

        // Generate Rust-side software keys and certs (client and server)
        let rustClientPriv = P256.Signing.PrivateKey()
        let rustClientPub = rustClientPriv.publicKey.x963Representation
        let rustClientId = RunarKeys.Ids.compactId(Data(rustClientPub))
        let rustClientPubCertKey = try X509.Certificate.PublicKey(P256.Signing.PublicKey(x963Representation: rustClientPub))
        let rustClientCert = try CertificateIssuer.signLeafWithPublicKey(
            ca: ca.generated,
            leafPublicKey: rustClientPubCertKey,
            subjectCN: rustClientId,
            sanDNS: [rustClientId],
            validityDays: 30,
            serialBytes: try SerialNumberStore.nextSerialBytesBigEndian()
        )

        let rustServerPriv = P256.Signing.PrivateKey()
        let rustServerPub = rustServerPriv.publicKey.x963Representation
        let rustServerId = RunarKeys.Ids.compactId(Data(rustServerPub))
        let rustServerPubCertKey = try X509.Certificate.PublicKey(P256.Signing.PublicKey(x963Representation: rustServerPub))
        let rustServerCert = try CertificateIssuer.signLeafWithPublicKey(
            ca: ca.generated,
            leafPublicKey: rustServerPubCertKey,
            subjectCN: rustServerId,
            sanDNS: [rustServerId],
            validityDays: 30,
            serialBytes: try SerialNumberStore.nextSerialBytesBigEndian()
        )

        // Export DER for Swift QUIC options
        let caDER = RunarKeys.CertificateUtils.toDER(ca.generated.certificate)
        let serverLeafDER = RunarKeys.CertificateUtils.toDER(serverCert)
        let swiftClientLeafDER = RunarKeys.CertificateUtils.toDER(swiftClientCert)

        // Export PEM files for Rust
        let caPem = try PEMDocument(type: "CERTIFICATE", derBytes: [UInt8](caDER)).pemString
        let serverPem = try PEMDocument(type: "CERTIFICATE", derBytes: [UInt8](serverLeafDER)).pemString
        let swiftClientPem = try PEMDocument(type: "CERTIFICATE", derBytes: [UInt8](swiftClientLeafDER)).pemString
        let rustClientCertPem = try PEMDocument(type: "CERTIFICATE", derBytes: [UInt8](RunarKeys.CertificateUtils.toDER(rustClientCert))).pemString
        let rustServerCertPem = try PEMDocument(type: "CERTIFICATE", derBytes: [UInt8](RunarKeys.CertificateUtils.toDER(rustServerCert))).pemString
        let rustClientKeyPem = try X509.Certificate.PrivateKey(rustClientPriv).serializeAsPEM().pemString
        let rustServerKeyPem = try X509.Certificate.PrivateKey(rustServerPriv).serializeAsPEM().pemString

        let caPath = tmpBase.appendingPathComponent("ca.pem")
        let serverCertPath = tmpBase.appendingPathComponent("swift_server_cert.pem")
        let swiftClientCertPath = tmpBase.appendingPathComponent("swift_client_cert.pem")
        let rustClientCertPath = tmpBase.appendingPathComponent("rust_client_cert.pem")
        let rustClientKeyPath = tmpBase.appendingPathComponent("rust_client_key.pem")
        let rustServerCertPath = tmpBase.appendingPathComponent("rust_server_cert.pem")
        let rustServerKeyPath = tmpBase.appendingPathComponent("rust_server_key.pem")
        try write(Data(caPem.utf8), to: caPath)
        try write(Data(serverPem.utf8), to: serverCertPath)
        try write(Data(swiftClientPem.utf8), to: swiftClientCertPath)
        try write(Data(rustClientCertPem.utf8), to: rustClientCertPath)
        try write(Data(rustClientKeyPem.utf8), to: rustClientKeyPath)
        try write(Data(rustServerCertPem.utf8), to: rustServerCertPath)
        try write(Data(rustServerKeyPem.utf8), to: rustServerKeyPath)

        // Swift transporter node info and handler
        let nodeInfoServer = RunarNodeInfo(
            nodePublicKey: serverPub,
            networkIds: ["interop"],
            addresses: ["127.0.0.1:0"],
            services: []
        )
        let nodeInfoClient = RunarNodeInfo(
            nodePublicKey: swiftClientPub,
            networkIds: ["interop"],
            addresses: ["127.0.0.1:0"],
            services: []
        )

        let handler = TestHandler()
        let logger = RunarLogger(category: "CrossE2E")

        if swiftIsServer {
            // Swift server
            let options = NetworkQuicTransportOptions.withCertificates(
                certificates: [serverLeafDER, caDER],
                secKey: serverKey,
                mobileKeyManager: km,
                verifyCertificates: true
            )
            let swiftServer = RunarTransporter.createQuicTransport(
                nodeInfo: nodeInfoServer,
                bindAddress: "127.0.0.1:44444",
                messageHandler: handler,
                options: options,
                logger: logger
            )
            try await swiftServer.start()

            // Rust client connects to Swift server
            let args = [
                "--peer", "127.0.0.1:44444",
                "--ca", caPath.path,
                "--cert", rustClientCertPath.path,
                "--key", rustClientKeyPath.path,
                "--node-id", rustClientId,
                "--timeout", "10"
            ]
            let proc = try spawn(rustClient, args)
            proc.waitUntilExit()
            XCTAssertEqual(proc.terminationStatus, 0)
            await swiftServer.stop()
        } else {
            // Rust server: bind a high, likely-free port
            let bindPort: UInt16 = 55000 + UInt16.random(in: 0..<4000)
            let bindAddr = "127.0.0.1:\(bindPort)"
            let serverArgs = [
                "--bind", bindAddr,
                "--ca", caPath.path,
                "--cert", rustServerCertPath.path,
                "--key", rustServerKeyPath.path,
                "--node-id", rustServerId,
                "--timeout", "10"
            ]
            let rustProc = try spawn(rustServer, serverArgs)
            // Give rust server time to bind (quinn init)
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // Swift client connects to Rust
            let options = NetworkQuicTransportOptions.withCertificates(
                certificates: [swiftClientLeafDER, caDER],
                secKey: swiftClientKey,
                mobileKeyManager: km,
                verifyCertificates: true
            )

            let swiftClient = RunarTransporter.createQuicTransport(
                nodeInfo: nodeInfoClient,
                bindAddress: "127.0.0.1:0",
                messageHandler: handler,
                options: options,
                logger: logger
            )
            try await swiftClient.start()

            // Attempt to connect, send a simple handshake/update
            let peerInfo = RunarPeerInfo(publicKey: Data(rustServerPub), addresses: [bindAddr], name: "rust-server")
            try await swiftClient.connect(to: peerInfo)

            try await Task.sleep(nanoseconds: 1_000_000_000)

            await swiftClient.stop()
            rustProc.terminate()
        }
    }
}

@available(macOS 13.0, *)
private final class TestHandler: MessageHandlerProtocol {
    func handleMessage(_ message: RunarNetworkMessage) {}
    func peerConnected(_ peerInfo: RunarNodeInfo) {}
    func peerDisconnected(_ peerId: String) {}
}


