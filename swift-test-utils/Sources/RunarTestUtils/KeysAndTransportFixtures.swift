import Foundation
import RunarFFI
import SwiftCBOR

public enum FixturesError: Error { case generic(String) }

public struct PeerInfo: Codable { 
    public let public_key: Data
    public let addresses: [String] 
}

public struct Empty: Codable {}

public struct NodeMetadata: Codable { 
    public var services: [Empty]
    public var subscriptions: [Empty] 
}

public struct NodeInfo: Codable {
    public var node_public_key: Data
    public var network_ids: [String]
    public var addresses: [String]
    public var node_metadata: NodeMetadata
    public var version: Int64
}

// MARK: - Label Resolution Types (For Serializer Package)

/// Information about a label's key mapping
public struct LabelKeyInfo {
    public let profileIds: [Data]
    public let networkId: String?

    public init(profileIds: [Data], networkId: String?) {
        self.profileIds = profileIds
        self.networkId = networkId
    }
}

/// Key mapping configuration
public struct KeyMappingConfig {
    public let labelMappings: [String: LabelKeyInfo]
    
    public init(labelMappings: [String: LabelKeyInfo]) {
        self.labelMappings = labelMappings
    }
}

/// Protocol for label resolution that matches serializer package needs
public protocol TestLabelResolver {
    func resolveLabel(_ label: String) -> LabelKeyInfo?
}

/// Configurable label resolver implementation for serializer package
/// This implements the TestLabelResolver protocol that can be used by tests
public struct ConfigurableLabelResolver: TestLabelResolver {
    private let config: KeyMappingConfig
    
    public init(config: KeyMappingConfig) {
        self.config = config
    }
    
    public func resolveLabel(_ label: String) -> LabelKeyInfo? {
        return config.labelMappings[label]
    }
}

// MARK: - Test Keystore Factory

public struct TestKeystoreFactory {
    
    /// Creates a complete test context with mobile CA, node, and user mobile keystores
    /// This mirrors Rust's build_test_context() function exactly
    public static func createTestContext() throws -> TestContext {
        // Build mobile network master (CA)
        let mobileNetworkMaster = KeysFFI()
        try mobileNetworkMaster.initializeAsMobile()
        try mobileNetworkMaster.mobileInitializeUserRootKey()
        let networkId = try mobileNetworkMaster.mobileGenerateNetworkDataKey()
        // Use the network data key as the network public key since getNetworkPublicKey was removed
        let networkPub = networkId
        
        // Build user mobile with only profile keys and installed network public key (no private)
        let userMobile = KeysFFI()
        try userMobile.initializeAsMobile()
        try userMobile.mobileInitializeUserRootKey()
        let profilePk = try userMobile.mobileDeriveUserProfileKey("user")
        // Install only the network public key, not the network private key
        // so this user mobile can encrypt for the network, but not decrypt
        try userMobile.mobileInstallNetworkPublicKey(networkPublicKey: networkPub)
        
        // Build node and install certificate
        let nodeKeys = KeysFFI()
        try nodeKeys.initializeAsNode()
        let csr = try nodeKeys.nodeGenerateCSR()
        let ncm = try mobileNetworkMaster.mobileProcessSetupToken(csr)
        try nodeKeys.nodeInstallCertificate(ncm)
        
        // Install network key on node
        let nodeAgreementPk = try nodeKeys.nodeGetAgreementPublicKey()
        let nkm = try mobileNetworkMaster.mobileCreateNetworkKeyMessage(networkPublicKey: networkId, nodeAgreementPk: nodeAgreementPk)
        try nodeKeys.nodeInstallNetworkKey(nkm)
        
        // Create resolver mapping exactly like Rust
        let networkIdString = String(data: networkId, encoding: .utf8) ?? ""
        let resolver = ConfigurableLabelResolver(config: KeyMappingConfig(
            labelMappings: [
                "user": LabelKeyInfo(profileIds: [profilePk], networkId: nil),
                "system": LabelKeyInfo(profileIds: [profilePk], networkId: networkIdString),
                "system_only": LabelKeyInfo(profileIds: [], networkId: networkIdString), // system only has no profile ids
                "search": LabelKeyInfo(profileIds: [profilePk], networkId: networkIdString)
            ]
        ))
        
        return TestContext(
            userMobileKs: userMobile,
            nodeKs: nodeKeys,
            resolver: resolver,
            networkId: String(data: networkId, encoding: .utf8) ?? "",
            profilePk: profilePk
        )
    }
    
    /// Creates a simple mobile keystore for basic testing
    public static func createMobileKeystore() throws -> KeysFFI {
        let keys = KeysFFI()
        try keys.initializeAsMobile()
        try keys.mobileInitializeUserRootKey()
        return keys
    }
    
    /// Creates a simple node keystore for basic testing
    public static func createNodeKeystore() throws -> KeysFFI {
        let keys = KeysFFI()
        try keys.initializeAsNode()
        return keys
    }
    
    /// Creates a CA and node setup for network testing
    public static func createCAAndNode() throws -> (ca: KeysFFI, node: KeysFFI, networkId: String) {
        let ca = KeysFFI()
        try ca.initializeAsMobile()
        try ca.mobileInitializeUserRootKey()
        
        let node = KeysFFI()
        try node.initializeAsNode()
        let csr = try node.nodeGenerateCSR()
        let ncm = try ca.mobileProcessSetupToken(csr)
        try node.nodeInstallCertificate(ncm)
        
        let networkId = try ca.mobileGenerateNetworkDataKey()
        let nodeAgreementPk = try node.nodeGetAgreementPublicKey()
        let nkm = try ca.mobileCreateNetworkKeyMessage(networkPublicKey: networkId, nodeAgreementPk: nodeAgreementPk)
        try node.nodeInstallNetworkKey(nkm)
        
        return (ca: ca, node: node, networkId: String(data: networkId, encoding: .utf8) ?? "")
    }
}

// MARK: - Test Context Type

public typealias TestContext = (
    userMobileKs: KeysFFI,         // user_mobile_ks
    nodeKs: KeysFFI,               // node_ks  
    resolver: ConfigurableLabelResolver,  // resolver
    networkId: String,             // network_id
    profilePk: Data                // profile_pk
)

// MARK: - Legacy Fixtures (Fixed)

public enum TestFixtures {
    
    /// Creates a node with certificate (FIXED: corrected method calls)
    public static func createKeyManagerWithCert() throws -> KeysFFI {
        let ca = KeysFFI()
        try ca.initializeAsMobile()
        try ca.mobileInitializeUserRootKey()
        
        let node = KeysFFI()
        try node.initializeAsNode()
        let csr = try node.nodeGenerateCSR()
        let ncm = try ca.mobileProcessSetupToken(csr)
        try node.nodeInstallCertificate(ncm)
        
        // Install an empty label mapping and a placeholder NodeInfo
        // Note: setLabelMapping function removed as it doesn't exist in Rust FFI
        
        // Proper initial NodeInfo using real public key and configured network id
        let placeholderInfo = try nodeInfo(
            publicKey: node.nodeGetPublicKey(), 
            addresses: ["127.0.0.1:0"], 
            networks: ["net"], 
            version: 0
        )
        try node.setLocalNodeInfo(placeholderInfo)
        
        return node
    }

    public static func transportOptions(bindAddr: String?, handshakeMs: UInt64? = nil, openStreamMs: UInt64? = nil, maxMessage: UInt64? = nil) -> Data {
        struct Opts: Codable { 
            let v: UInt32
            let bind_addr: String?
            let handshake_timeout_ms: UInt64?
            let open_stream_timeout_ms: UInt64?
            let max_message_size: UInt64? 
        }
        let opts = Opts(
            v: 1, 
            bind_addr: bindAddr, 
            handshake_timeout_ms: handshakeMs, 
            open_stream_timeout_ms: openStreamMs, 
            max_message_size: maxMessage
        )
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
            .utf8String("subscriptions"): .array([]),
        ])
        map[.utf8String("version")] = .unsignedInt(UInt64(max(0, version)))
        return Data(CBOR.map(map).encode())
    }

    // MARK: - CA + Nodes builders (no persistence export/import)

    public struct CANodes {
        public let ca: KeysFFI
        public let nodes: [KeysFFI]
        public let nodeIds: [String]
        public let defaultNetworkId: String
    }

    public static func createCAAndNodes(count: Int, addresses: [String], defaultNetworkId: String = "net") throws -> CANodes {
        precondition(count == addresses.count, "addresses count must match nodes count")
        let ca = KeysFFI()
        try ca.initializeAsMobile()
        try ca.mobileInitializeUserRootKey()
        
        var nodes: [KeysFFI] = []
        var nodeIds: [String] = []
        
        for i in 0 ..< count {
            let node = KeysFFI()
            try node.initializeAsNode()
            let csr = try node.nodeGenerateCSR()
            let ncm = try ca.mobileProcessSetupToken(csr)
            try node.nodeInstallCertificate(ncm)
            
            // Note: setLabelMapping function removed as it doesn't exist in Rust FFI
            
            // set NodeInfo with provided bind address
            let pk = try node.nodeGetPublicKey()
            let info = nodeInfo(publicKey: pk, addresses: [addresses[i]], networks: [defaultNetworkId], version: 0)
            try node.setLocalNodeInfo(info)
            nodes.append(node)
            
            // Generate node ID from public key (simplified)
            let nodeId = try node.nodeGetNodeId()
            nodeIds.append(nodeId)
        }
        
        return CANodes(ca: ca, nodes: nodes, nodeIds: nodeIds, defaultNetworkId: defaultNetworkId)
    }
}
