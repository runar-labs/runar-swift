import Foundation
import RunarFFI
import SwiftCBOR

public enum FixturesError: Error { case generic(String) }

public struct PeerInfo: Codable { public let public_key: Data; public let addresses: [String] }
public struct NodeMetadata: Codable { public var services: [String]; public var subscriptions: [String] }
public struct NodeInfo: Codable {
    public var node_public_key: Data
    public var network_ids: [String]
    public var addresses: [String]
    public var node_metadata: NodeMetadata
    public var version: UInt64
}

public enum TestFixtures {
    public static func createKeyManagerWithCert() throws -> FFIKeys {
        let ca = try FFIKeys()
        _ = try ca.nodeId() // ensure ok
        let node = try FFIKeys()
        let csr = try node.generateCSR()
        let ncm = try ca.processSetupToken(csr)
        try node.installCertificate(ncm)
        return node
    }

    public static func transportOptions(bindAddr: String?, handshakeMs: UInt64? = nil, openStreamMs: UInt64? = nil, maxMessage: UInt64? = nil) -> Data {
        struct Opts: Codable { let v: UInt32; let bind_addr: String?; let handshake_timeout_ms: UInt64?; let open_stream_timeout_ms: UInt64?; let max_message_size: UInt64? }
        let opts = Opts(v: 1, bind_addr: bindAddr, handshake_timeout_ms: handshakeMs, open_stream_timeout_ms: openStreamMs, max_message_size: maxMessage)
        let enc = CodableCBOREncoder()
        return (try? enc.encode(opts)) ?? Data()
    }

    public static func peerInfo(publicKey: Data, addresses: [String]) -> Data {
        let p = PeerInfo(public_key: publicKey, addresses: addresses)
        return (try? CodableCBOREncoder().encode(p)) ?? Data()
    }

    public static func nodeInfo(publicKey: Data, addresses: [String], networks: [String], services: [String] = [], subscriptions: [String] = [], version: UInt64 = 0) -> Data {
        let meta = NodeMetadata(services: services, subscriptions: subscriptions)
        let info = NodeInfo(node_public_key: publicKey, network_ids: networks, addresses: addresses, node_metadata: meta, version: version)
        return (try? CodableCBOREncoder().encode(info)) ?? Data()
    }

    public static func exportState(_ keys: FFIKeys) throws -> Data {
        try keys.exportState()
    }

    public static func importState(_ keys: FFIKeys, state: Data) throws {
        try keys.importState(state)
    }
}


