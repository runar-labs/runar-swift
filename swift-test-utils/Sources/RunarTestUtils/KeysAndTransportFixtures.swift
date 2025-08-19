import Foundation
import RunarFFI
import SwiftCBOR

public enum FixturesError: Error { case generic(String) }

public struct PeerInfo: Codable { public let public_key: Data; public let addresses: [String] }
public struct Empty: Codable {}
public struct NodeMetadata: Codable { public var services: [Empty]; public var subscriptions: [Empty] }
public struct NodeInfo: Codable {
    public var node_public_key: Data
    public var network_ids: [String]
    public var addresses: [String]
    public var node_metadata: NodeMetadata
    public var version: Int64
}

public enum TestFixtures {
    public static func createKeyManagerWithCert() throws -> FFIKeys {
        let ca = try FFIKeys()
        _ = try ca.nodeId() // ensure ok
        let node = try FFIKeys()
        let csr = try node.generateCSR()
        let ncm = try ca.processSetupToken(csr)
        try node.installCertificate(ncm)
        // Install an empty label mapping and a placeholder NodeInfo; SwiftNode will update addresses after start
        let emptyMapping = CBOR.map([:])
        let mappingCBOR = Data(emptyMapping.encode())
        try node.setLabelMapping(mappingCBOR)
        // Proper initial NodeInfo using real public key and configured network id; address uses bind 0 (updated after start)
        let placeholderInfo = nodeInfo(publicKey: try node.publicKey(), addresses: ["127.0.0.1:0"], networks: ["net"], version: 0)
        try node.setLocalNodeInfo(placeholderInfo)
        return node
    }

    public static func transportOptions(bindAddr: String?, handshakeMs: UInt64? = nil, openStreamMs: UInt64? = nil, maxMessage: UInt64? = nil) -> Data {
        struct Opts: Codable { let v: UInt32; let bind_addr: String?; let handshake_timeout_ms: UInt64?; let open_stream_timeout_ms: UInt64?; let max_message_size: UInt64? }
        let opts = Opts(v: 1, bind_addr: bindAddr, handshake_timeout_ms: handshakeMs, open_stream_timeout_ms: openStreamMs, max_message_size: maxMessage)
        let enc = CodableCBOREncoder()
        return (try? enc.encode(opts)) ?? Data()
    }

    public static func peerInfo(publicKey: Data, addresses: [String]) -> Data {
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("public_key")] = .array([UInt8](publicKey).map { .unsignedInt(UInt64($0)) })
        map[.utf8String("addresses")] = .array(addresses.map { .utf8String($0) })
        return Data(CBOR.map(map).encode())
    }

    public static func nodeInfo(publicKey: Data, addresses: [String], networks: [String], version: Int64 = 0) -> Data {
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("node_public_key")] = .array([UInt8](publicKey).map { .unsignedInt(UInt64($0)) })
        map[.utf8String("network_ids")] = .array(networks.map { .utf8String($0) })
        map[.utf8String("addresses")] = .array(addresses.map { .utf8String($0) })
        map[.utf8String("node_metadata")] = .map([
            .utf8String("services"): .array([]),
            .utf8String("subscriptions"): .array([])
        ])
        map[.utf8String("version")] = .unsignedInt(UInt64(max(0, version)))
        return Data(CBOR.map(map).encode())
    }

    public static func exportState(_ keys: FFIKeys) throws -> Data {
        try keys.exportState()
    }

    public static func importState(_ keys: FFIKeys, state: Data) throws {
        try keys.importState(state)
    }
}


