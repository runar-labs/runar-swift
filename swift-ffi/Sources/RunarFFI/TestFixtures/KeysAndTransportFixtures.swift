import Foundation
import RunarFFI
import SwiftCBOR

public enum FixturesError: Error { case generic(String) }

public struct PeerInfo: Codable {
    public let publicKey: Data
    public let addresses: [String]
}

public struct Empty: Codable {}
public struct NodeMetadata: Codable {
    public var services: [Empty]
    public var subscriptions: [Empty]
}

public struct NodeInfo: Codable {
    public var nodePublicKey: Data
    public var networkIds: [String]
    public var addresses: [String]
    public var nodeMetadata: NodeMetadata
    public var version: Int64
}

@available(macOS 11.0, *)
public enum TestFixtures {
    @available(macOS 11.0, *)
    public static func createKeyManagerWithCert() throws -> KeysFFI {
        let certificateAuthority = KeysFFI()
        // Initialize CA mobile root key first, before any cert steps
        try certificateAuthority.mobileInitializeUserRootKey()
        _ = try certificateAuthority.nodeGetPublicKey() // ensure ok
        let node = KeysFFI()
        try node.initializeAsNode()
        let csr = try node.nodeGenerateCSR()
        let ncm = try certificateAuthority.mobileProcessSetupToken(csr)
        try node.nodeInstallCertificate(ncm)
        // Install an empty label mapping and a placeholder NodeInfo; SwiftNode will update addresses after start
        let emptyMapping = CBOR.map([:])
        let mappingCBOR = Data(emptyMapping.encode())
        try node.setLabelMapping(mappingCBOR)
        // Proper initial NodeInfo using real public key and configured network id
        // Address uses bind 0 (updated after start)
        let placeholderInfo = try nodeInfo(
            publicKey: node.nodeGetPublicKey(),
            addresses: ["127.0.0.1:0"],
            networks: ["net"],
            version: 0
        )
        try node.setLocalNodeInfo(placeholderInfo)
        return node
    }

    public static func transportOptions(
        bindAddr: String?,
        handshakeMs: UInt64? = nil,
        openStreamMs: UInt64? = nil,
        maxMessage: UInt64? = nil
    ) -> Data {
        struct Opts: Codable {
            let version: UInt32
            let bindAddress: String?
            let handshakeTimeoutMs: UInt64?
            let openStreamTimeoutMs: UInt64?
            let maxMessageSize: UInt64?
        }
        let opts = Opts(
            version: 1,
            bindAddress: bindAddr,
            handshakeTimeoutMs: handshakeMs,
            openStreamTimeoutMs: openStreamMs,
            maxMessageSize: maxMessage
        )
        let enc = CodableCBOREncoder()
        return (try? enc.encode(opts)) ?? Data()
    }

    public static func peerInfo(publicKey: Data, addresses: [String]) -> Data {
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("public_key")] = .array(
            [UInt8](publicKey).map { .unsignedInt(UInt64($0)) }
        )
        map[.utf8String("addresses")] = .array(addresses.map { .utf8String($0) })
        return Data(CBOR.map(map).encode())
    }

    public static func nodeInfo(publicKey: Data, addresses: [String], networks: [String], version: Int64 = 0) -> Data {
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("node_public_key")] = .array(
            [UInt8](publicKey).map { .unsignedInt(UInt64($0)) }
        )
        map[.utf8String("network_ids")] = .array(networks.map { .utf8String($0) })
        map[.utf8String("addresses")] = .array(addresses.map { .utf8String($0) })
        map[.utf8String("node_metadata")] = .map([
            .utf8String("services"): .array([]),
            .utf8String("subscriptions"): .array([]),
        ])
        map[.utf8String("version")] = .unsignedInt(UInt64(max(0, version)))
        return Data(CBOR.map(map).encode())
    }

    // MARK: - CA + Nodes builders (no persistence export/import)

    @available(macOS 11.0, *)
    public struct CANodes {
        public let certificateAuthority: KeysFFI
        public let nodes: [KeysFFI]
        public let nodeIds: [String]
        public let defaultNetworkId: String
    }

    @available(macOS 11.0, *)
    public static func createCAAndNodes(
        count: Int,
        addresses: [String],
        defaultNetworkId: String = "net"
    ) throws -> CANodes {
        precondition(count == addresses.count, "addresses count must match nodes count")
        let certificateAuthority = KeysFFI()
        try certificateAuthority.initializeAsMobile()
        _ = try certificateAuthority.nodeGetPublicKey()
        var nodes: [KeysFFI] = []
        var nodeIds: [String] = []
        for index in 0 ..< count {
            let node = KeysFFI()
            try node.initializeAsNode()
            let csr = try node.nodeGenerateCSR()
            let ncm = try certificateAuthority.mobileProcessSetupToken(csr)
            try node.nodeInstallCertificate(ncm)
            // empty resolver mapping
            let emptyMapping = CBOR.map([:])
            try node.setLabelMapping(Data(emptyMapping.encode()))
            // set NodeInfo with provided bind address
            let publicKey = try node.nodeGetPublicKey()
            let info = nodeInfo(
                publicKey: publicKey,
                addresses: [addresses[index]],
                networks: [defaultNetworkId],
                version: 0
            )
            try node.setLocalNodeInfo(info)
            nodes.append(node)
            // Generate node ID from public key (simplified)
            let nodeId = publicKey.base64EncodedString()
            nodeIds.append(nodeId)
        }
        return CANodes(
            certificateAuthority: certificateAuthority,
            nodes: nodes,
            nodeIds: nodeIds,
            defaultNetworkId: defaultNetworkId
        )
    }
}
