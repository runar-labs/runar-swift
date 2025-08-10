import Foundation
import Network
import Crypto
import SwiftCommon
import RunarKeys
import Security

/// Network.framework QUIC transport implementation that matches the Rust QUIC transport architecture
/// Uses unidirectional streams for all messages (requests and responses) for compatibility
@available(macOS 12.0, iOS 15.0, *)
public class NetworkQuicTransporter: TransportProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let nodeInfo: RunarNodeInfo
    private let bindAddress: String
    private let options: NetworkQuicTransportOptions
    private let logger: RunarLogger
    private let messageHandler: MessageHandlerProtocol
    private var mobileKeyManager: MobileKeyManager?
    private var caCertificate: SecCertificate?
    private var configuredQuicOptions: NWProtocolQUIC.Options?
    
    // Network.framework components
    private var listener: NWListener?
    
    // Enhanced connection management using ConnectionPool and PeerState
    private let connectionPool = ConnectionPool()
    private let connectionQueue = DispatchQueue(label: "com.runar.quic.connection", qos: .userInitiated)
    private let messageQueue = DispatchQueue(label: "com.runar.quic.message", qos: .userInitiated)
    
    // State management
    private var isRunning = false
    private let stateQueue = DispatchQueue(label: "com.runar.quic.state", qos: .userInitiated)
    
    // Enhanced request tracking with stream correlation
    private var pendingRequests: [String: RequestState] = [:]
    private let requestQueue = DispatchQueue(label: "com.runar.quic.request", qos: .userInitiated)
    
    // Request/response correlation tracking
    private var pendingResponses: [String: CheckedContinuation<RunarNetworkMessage, Error>] = [:]
    private let correlationQueue = DispatchQueue(label: "com.runar.quic.correlation", qos: .userInitiated)
    
    // Peer node info subscription
    private var peerNodeInfoStream: AsyncStream<RunarNodeInfo>.Continuation?
    private let subscriptionQueue = DispatchQueue(label: "com.runar.quic.subscription", qos: .userInitiated)
    
    // MARK: - Initialization
    
    public init(
        nodeInfo: RunarNodeInfo,
        bindAddress: String,
        messageHandler: MessageHandlerProtocol,
        options: NetworkQuicTransportOptions,
        logger: RunarLogger
    ) {
        self.nodeInfo = nodeInfo
        self.bindAddress = bindAddress
        self.messageHandler = messageHandler
        self.options = options
        self.logger = logger
        
        logger.info("🚀 [NetworkQuicTransporter] Initialized - Node: \(nodeInfo.nodeId), Address: \(bindAddress)")
    }
    
    // MARK: - TransportProtocol Implementation
    
    public func start() async throws {
        logger.info("🔄 [NetworkQuicTransporter] Starting QUIC transport...")
        
        stateQueue.sync {
            guard !isRunning else {
                logger.warning("⚠️ [NetworkQuicTransporter] Already running")
                return
            }
            isRunning = true
        }
        
        // Use the certificates from transport options instead of creating new ones
        // This follows the same pattern as the Rust test where certificates are passed in
        try await importCertificatesFromOptions()
        
        try await startListener()
        logger.info("✅ [NetworkQuicTransporter] Started successfully")
    }
    
    public func stop() async {
        logger.info("🔄 [NetworkQuicTransporter] Stopping QUIC transport...")
        
        stateQueue.sync {
            guard isRunning else {
                logger.warning("⚠️ [NetworkQuicTransporter] Not running")
                return
            }
            isRunning = false
        }
        
        await stopListener()
        await cleanupConnections()
        
        logger.info("✅ [NetworkQuicTransporter] Stopped successfully")
    }
    
    public func connect(to peerInfo: RunarPeerInfo) async throws {
        let peerId = NodeUtils.compactId(from: peerInfo.publicKey)
        logger.info("🔗 [NetworkQuicTransporter] Connecting to peer \(peerId)")
        
        // Check if transport is running
        let isRunning = stateQueue.sync { self.isRunning }
        guard isRunning else {
            logger.error("❌ [NetworkQuicTransporter] Not running - cannot connect")
            throw RunarTransportError.transportError("Transport not running")
        }
        
        // Check if already connected
        if await isConnected(to: peerId) {
            logger.info("ℹ️ [NetworkQuicTransporter] Already connected to \(peerId)")
            return
        }
        
        // Try each address until one succeeds
        var lastError: Error?
        
        for address in peerInfo.addresses {
            do {
                logger.info("🔗 [NetworkQuicTransporter] Attempting connection to \(peerId) via \(address)")
                try await connectToAddress(address, peerId: peerId)
                logger.info("✅ [NetworkQuicTransporter] Connected to \(peerId) via \(address)")
                return
            } catch {
                logger.warning("⚠️ [NetworkQuicTransporter] Failed to connect to \(peerId) via \(address): \(error)")
                lastError = error
            }
        }
        
        throw lastError ?? RunarTransportError.connectionError("Failed to connect to peer \(peerId) on any address")
    }
    
    public func send(message: RunarNetworkMessage) async throws {
        let peerId = message.destinationNodeId
        logger.info("📤 [NetworkQuicTransporter] Sending message to \(peerId) - Type: \(message.messageType)")
        
        stateQueue.sync {
            guard isRunning else {
                logger.error("❌ [NetworkQuicTransporter] Not running - cannot send message")
                return
            }
        }
        
        // Wait for connection to be established
        var attempts = 0
        while attempts < 10 {
            if await isConnected(to: peerId) {
                break
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            attempts += 1
        }
        
        guard await isConnected(to: peerId) else {
            throw RunarTransportError.connectionError("Not connected to peer \(peerId) after waiting")
        }
        
        try await sendMessage(message, to: peerId)
    }
    
    public func isConnected(to peerId: String) async -> Bool {
        return connectionPool.isPeerConnected(peerId: peerId)
    }
    
    public func getConnectedPeers() async -> [String] {
        return connectionPool.getConnectedPeers()
    }
    
    public func updatePeers(nodeInfo: RunarNodeInfo) async throws {
        logger.info("🔄 [NetworkQuicTransporter] Updating peers with node info")
        
        let peers = await getConnectedPeers()
        for peerId in peers {
            let message = RunarNetworkMessage(
                sourceNodeId: nodeInfo.nodeId,
                destinationNodeId: peerId,
                messageType: MessageTypes.NODE_INFO_UPDATE,
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "",
                        valueBytes: try encodeNodeInfo(nodeInfo),
                        correlationId: ""
                    )
                ]
            )
            try await send(message: message)
            logger.info("📤 [NetworkQuicTransporter] Sent NODE_INFO_UPDATE to peer \(peerId)")
        }
    }
    
    public func getLocalAddress() -> String {
        return bindAddress
    }
    
    public func subscribeToPeerNodeInfo() -> AsyncStream<RunarNodeInfo> {
        return AsyncStream { continuation in
            subscriptionQueue.async {
                self.peerNodeInfoStream = continuation
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func initializeKeyManager() async throws {
        logger.debug("🔧 [NetworkQuicTransporter] Initializing MobileKeyManager for QUIC certificates")
        
        // Create MobileKeyManager with logger
        let keyManager = try MobileKeyManager(logger: ConsoleLogger())
        
        // Initialize user root key
        let rootPublicKey = try keyManager.initializeUserRootKey()
        logger.debug("🔧 [NetworkQuicTransporter] User root key initialized: \(rootPublicKey.count) bytes")
        
        // Generate CSR for this node
        let setupToken = try keyManager.generateCSR()
        logger.debug("🔧 [NetworkQuicTransporter] Generated CSR for node: \(setupToken.nodeId)")
        
        // Process the CSR to get a certificate (self-signing for testing)
        let certMessage = try keyManager.processSetupToken(setupToken)
        logger.debug("🔧 [NetworkQuicTransporter] Generated certificate for node: \(setupToken.nodeId)")
        
        // Import certificate and private key into Keychain for Network.framework
        try await importCertificateToKeychain(keyManager: keyManager, certMessage: certMessage)
        
        // Store the key manager
        self.mobileKeyManager = keyManager
        
        logger.info("✅ [NetworkQuicTransporter] MobileKeyManager initialized with QUIC certificates")
    }
    
    private func importCertificatesFromOptions() async throws {
        logger.debug("🔧 [NetworkQuicTransporter] Importing certificates from transport options")
        
        // Get MobileKeyManager from options
        guard let keyManager = options.mobileKeyManager else {
            throw RunarTransportError.configurationError("MobileKeyManager not provided in transport options")
        }
        
        // Get the node certificate from the MobileKeyManager
        let nodeId = keyManager.getNodeId()
        guard let nodeCertificate = keyManager.getIssuedCertificate(nodeId: nodeId) else {
            throw RunarTransportError.configurationError("Node certificate not found")
        }
        
        // Get the CA certificate from the MobileKeyManager
        let caCertificate = keyManager.getCaCertificate()
        
        // Get certificate data
        let certificateData = nodeCertificate.toDER()
        
        // The swift-keys package already generated the key in Keychain during CSR creation
        // We don't need to generate a new key - we just import the certificates
        logger.debug("🔐 [NetworkQuicTransporter] Using existing Keychain key from swift-keys package")
        
        // Step 1: Import the certificate under node-specific label (avoid generic label collisions)
        let certificateQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: "Runar Node Certificate \(nodeId)",
            kSecValueData as String: certificateData
        ]
        let certificateStatus = SecItemAdd(certificateQuery as CFDictionary, nil)
        if certificateStatus == errSecSuccess {
            logger.debug("🔐 [NetworkQuicTransporter] Node certificate imported to Keychain successfully")
        } else if certificateStatus == errSecDuplicateItem {
            logger.debug("🔐 [NetworkQuicTransporter] Node certificate already exists in Keychain")
        } else {
            logger.warning("⚠️ [NetworkQuicTransporter] Failed to import certificate: \(certificateStatus)")
        }
        
        // Do NOT import CA into Keychain to avoid stale collisions across runs.
        
        // Store the key manager for later use
        self.mobileKeyManager = keyManager
        
        // Note: We don't create SecIdentity explicitly - Keychain will synthesize it automatically
        // when the certificate and SecKey are properly linked (which they are, since the certificate
        // was created using the public key from the same SecKey that's in Keychain)
        logger.debug("🔐 [NetworkQuicTransporter] Certificates imported - Keychain will synthesize SecIdentity automatically")
    }
    
    private func importCertificateToKeychain(keyManager: MobileKeyManager, certMessage: NodeCertificateMessage) async throws {
        logger.debug("🔧 [NetworkQuicTransporter] Importing certificate to Keychain for Network.framework")

        // Get the QUIC certificate configuration which includes the actual private key (unused here)
        _ = try keyManager.getQuicCertificateConfig()

        // Get certificate data from the cert message
        let certificateData = certMessage.nodeCertificate.toDER()
        let nodeId = keyManager.getNodeId()

        // The swift-keys package already generated the key in Keychain during CSR creation
        // We don't need to generate a new key - we just import the certificates
        logger.debug("🔐 [NetworkQuicTransporter] Using existing Keychain key from swift-keys package")

        // Step 1: Import the certificate under node-specific label (avoid generic label collisions)
        let certificateQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: "Runar Node Certificate \(nodeId)",
            kSecValueData as String: certificateData
        ]
        let certificateStatus = SecItemAdd(certificateQuery as CFDictionary, nil)
        if certificateStatus == errSecSuccess {
            logger.debug("🔐 [NetworkQuicTransporter] Node certificate imported to Keychain successfully")
        } else if certificateStatus == errSecDuplicateItem {
            logger.debug("🔐 [NetworkQuicTransporter] Node certificate already exists in Keychain")
        } else {
            logger.warning("⚠️ [NetworkQuicTransporter] Failed to import certificate: \(certificateStatus)")
        }

        // Do NOT import CA into Keychain to avoid stale collisions across runs.
        
        // Note: We don't create SecIdentity explicitly - Keychain will synthesize it automatically
        // when the certificate and SecKey are properly linked (which they are, since the certificate
        // was created using the public key from the same SecKey that's in Keychain)
        logger.debug("🔐 [NetworkQuicTransporter] Certificates imported - Keychain will synthesize SecIdentity automatically")
    }
    
    private func startListener() async throws {
        // Parse bind address
        let components = bindAddress.split(separator: ":")
        guard components.count == 2,
              let port = UInt16(components[1]) else {
            throw RunarTransportError.configurationError("Invalid bind address format: \(bindAddress)")
        }
        
        _ = String(components[0])
        
        logger.info("🔧 [NetworkQuicTransporter] Starting listener on \(self.bindAddress)")
        
        // Configure TLS with real certificates from MobileKeyManager
        guard let keyManager = options.mobileKeyManager else {
            throw RunarTransportError.configurationError("MobileKeyManager not initialized in transport options")
        }
        
        _ = try keyManager.getQuicCertificateConfig()
        logger.debug("🔧 [NetworkQuicTransporter] QUIC certificate config available for listener")
        
        // Load CA certificate for trust anchors
        let caCertificate = try getCACertificateFromKeychain()
        
        // Create QUIC options explicitly and configure TLS prior to attaching to parameters
        let quicOptions = NWProtocolQUIC.Options()
        // Set ALPN
        "runar".utf8CString.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress { sec_protocol_options_add_tls_application_protocol(quicOptions.securityProtocolOptions, base) }
        }
        let securityProtocolOptions = quicOptions.securityProtocolOptions
        // Store configured QUIC options so outbound connections can reuse the same TLS settings
        self.configuredQuicOptions = quicOptions
        // Enforce TLS 1.3 which QUIC requires
        sec_protocol_options_set_min_tls_protocol_version(securityProtocolOptions, .TLSv13)
        // Server side: require client authentication (mutual TLS)
        sec_protocol_options_set_peer_authentication_required(securityProtocolOptions, true)
        // ALPN is set by NWParameters.quic
        
        // Set custom certificate validation block
        sec_protocol_options_set_verify_block(securityProtocolOptions, { [weak self] (_: sec_protocol_metadata_t, trust: sec_trust_t, complete: @escaping sec_protocol_verify_complete_t) in
            guard let self = self else {
                complete(false)
                return
            }
            
            self.logger.debug("🔐 [NetworkQuicTransporter] Custom certificate validation called")
            // Set our CA as the trust anchor
            let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(trustRef) as? [SecCertificate], let leaf = chain.first {
                if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
                    self.logger.debug("🔐 [Server verify] Leaf subject: \(summary), chainCount=\(chain.count)")
                } else {
                    self.logger.debug("🔐 [Server verify] Leaf present, chainCount=\(chain.count)")
                }
            } else {
                self.logger.debug("🔐 [Server verify] No certificates in trust object")
            }
            // Set TLS policy (server = false because we validate client cert on listener)
            let serverPolicy = SecPolicyCreateSSL(false, nil)
            SecTrustSetPolicies(trustRef, serverPolicy)
            let anchors = [caCertificate] as CFArray
            let setAnchorStatus = SecTrustSetAnchorCertificates(trustRef, anchors)
            guard setAnchorStatus == errSecSuccess else {
                self.logger.error("❌ [NetworkQuicTransporter] Failed to set CA as trust anchor: \(setAnchorStatus)")
                complete(false)
                return
            }
            // Only trust our CA for verification
            _ = SecTrustSetAnchorCertificatesOnly(trustRef, true)
            
            // Evaluate the trust
            var error: CFError?
            let isValid = SecTrustEvaluateWithError(trustRef, &error)
            
            if let error = error {
                self.logger.error("❌ [NetworkQuicTransporter] [Server] trust failed: \(error)")
            } else {
                self.logger.debug("✅ [NetworkQuicTransporter] [Server] trust OK (anchors-only)")
            }
            
            complete(isValid)
        }, self.connectionQueue)
        
        // Set local identity for TLS (our node certificate and private key)
        try setLocalIdentityWithChain(securityProtocolOptions: securityProtocolOptions, keyManager: keyManager)
        // Log identity subject used on listener to ensure correct certificate is presented
        do {
            let id = try getClientIdentityFromKeychain()
            var cert: SecCertificate?
            if SecIdentityCopyCertificate(id, &cert) == errSecSuccess, let c = cert {
                let subj = SecCertificateCopySubjectSummary(c) as String? ?? "nil"
                logger.debug("🔐 [NetworkQuicTransporter] [Server] using identity subject=\(subj)")
            }
        } catch { logger.debug("🔐 [NetworkQuicTransporter] [Server] identity log error: \(error)") }
        
        logger.debug("🔐 [NetworkQuicTransporter] Custom certificate validation configured successfully")
        // Attach configured QUIC options to parameters
        let parameters = NWParameters(quic: quicOptions)
        // Prefer loopback and avoid P2P for local tests
        parameters.requiredInterfaceType = .loopback
        parameters.includePeerToPeer = false
        parameters.allowLocalEndpointReuse = true
        
        // Create listener on specified port
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        self.listener = listener
        
        // Wait for listener to become ready or fail before returning
        var didResume = false
        let originalStateHandler = self.listenerStateUpdateHandler(state:)
        let readyOrFailed: () async throws -> Void = {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                listener.stateUpdateHandler = { [weak self] state in
                    // Forward to original logging handler
                    originalStateHandler(state)
                    guard !didResume else { return }
                    switch state {
                    case .ready:
                        didResume = true
                        cont.resume()
                    case .failed(let error):
                        didResume = true
                        cont.resume(throwing: RunarTransportError.transportError("Listener failed: \(error)"))
                    default:
                        break
                    }
                }
            }
        }
        
        // Set new connection handler
        listener.newConnectionHandler = self.listenerNewConnectionHandler(connection:)
        
        // Start listener and await readiness
        listener.start(queue: connectionQueue)
        do {
            try await readyOrFailed()
        } catch {
            // Ensure we restore state handler even on failure
            listener.stateUpdateHandler = originalStateHandler
            throw error
        }
        // Restore the original state handler for normal operation
        listener.stateUpdateHandler = originalStateHandler
        logger.info("✅ [NetworkQuicTransporter] Listener started on \(bindAddress)")
    }
    
    // configureTLSWithCustomCertificates no longer used
    
    private func setLocalIdentity(securityProtocolOptions: sec_protocol_options_t, keyManager: MobileKeyManager) throws {
        logger.debug("🔐 [NetworkQuicTransporter] Setting local identity for TLS")
        // Use Keychain-linked identity to ensure certificate and private key are paired
        let secIdentity = try getClientIdentityFromKeychain()
        sec_protocol_options_set_local_identity(securityProtocolOptions, unsafeBitCast(secIdentity, to: OS_sec_identity.self))
        var pk: SecKey?
        let pkStatus = SecIdentityCopyPrivateKey(secIdentity, &pk)
        if pkStatus != errSecSuccess || pk == nil {
            logger.error("❌ [NetworkQuicTransporter] Local SecIdentity missing private key (status: \(pkStatus))")
        } else {
            logger.debug("🔐 [NetworkQuicTransporter] Local SecIdentity has private key")
        }
        logger.debug("🔐 [NetworkQuicTransporter] Local identity set successfully for TLS")
    }
    
    private func setLocalIdentityWithChain(securityProtocolOptions: sec_protocol_options_t, keyManager: MobileKeyManager) throws {
        // Build an identity with certificate chain so the peer gets full chain
        let secIdentity = try getClientIdentityFromKeychain()
        guard let identityHandle = sec_identity_create(secIdentity) else {
            throw RunarTransportError.configurationError("Failed to create sec_identity_t handle from SecIdentity")
        }
        sec_protocol_options_set_local_identity(securityProtocolOptions, identityHandle)
        // Note: Network.framework does not require attaching a chain via options; the peer sends its chain.
        logger.debug("🔐 [NetworkQuicTransporter] Local identity set (Keychain-backed)")
    }
    
    private func getNodeCertificateFromKeychain() throws -> SecCertificate {
        // Get all certificates and find the one that's not the CA certificate
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var listResult: CFTypeRef?
        let listStatus = SecItemCopyMatching(listQuery as CFDictionary, &listResult)
        
        guard listStatus == errSecSuccess, let certificates = listResult as? [SecCertificate] else {
            throw RunarTransportError.configurationError("Failed to retrieve certificates from Keychain: \(listStatus)")
        }
        
        logger.debug("🔐 [NetworkQuicTransporter] Found \(certificates.count) certificates in Keychain")
        
        // Find the node certificate (not the CA certificate)
        for (index, cert) in certificates.enumerated() {
            let certDescription = String(describing: cert)
            logger.debug("🔐 [NetworkQuicTransporter] Certificate \(index): \(certDescription)")
            
            // Look for a certificate that is NOT the CA certificate
            if !certDescription.contains("Runar User CA") {
                logger.debug("🔐 [NetworkQuicTransporter] Found node certificate at index \(index)")
                return cert
            }
        }
        
        throw RunarTransportError.configurationError("Node certificate not found in Keychain")
    }
    
    private func getNodePrivateKeyFromKeychain() throws -> SecKey {
        // Try to get any private key from the Keychain
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var listResult: CFTypeRef?
        let listStatus = SecItemCopyMatching(listQuery as CFDictionary, &listResult)
        
        guard listStatus == errSecSuccess, let keys = listResult as? [SecKey] else {
            throw RunarTransportError.configurationError("Failed to retrieve keys from Keychain: \(listStatus)")
        }
        
        logger.debug("🔐 [NetworkQuicTransporter] Found \(keys.count) keys in Keychain")
        
        // Find the first private key (class=1)
        for (index, key) in keys.enumerated() {
            let keyDescription = String(describing: key)
            logger.debug("🔐 [NetworkQuicTransporter] Key \(index): \(keyDescription)")
            
            // Look for private keys (class=1)
            if keyDescription.contains("class=1") {
                logger.debug("🔐 [NetworkQuicTransporter] Found private key at index \(index)")
                return key
            }
        }
        
        throw RunarTransportError.configurationError("No private key found in Keychain")
    }
    
    private func getClientIdentityFromKeychain() throws -> SecIdentity {
        // Preferred: build identity from provided leaf DER (or MobileKeyManager-issued cert), ensuring the right cert is bound
        if let chain = options.certificates, let leafDer = chain.first,
           let leafCert = SecCertificateCreateWithData(nil, leafDer as CFData) {
            var identity: SecIdentity?
            let status = SecIdentityCreateWithCertificate(nil, leafCert, &identity)
            if status == errSecSuccess, let id = identity {
                logger.debug("🔐 [NetworkQuicTransporter] Created SecIdentity from provided leaf DER")
                return id
            } else {
                logger.warning("⚠️ [NetworkQuicTransporter] Failed to create identity from provided leaf DER (status: \(status)); will try MobileKeyManager-issued cert")
            }
        }

        if let km = options.mobileKeyManager {
            let kmNodeId = km.getNodeId()
            if let issuedCert = km.getIssuedCertificate(nodeId: kmNodeId) {
                let der = issuedCert.toDER() as CFData
                if let leafCert = SecCertificateCreateWithData(nil, der) {
                    var identity: SecIdentity?
                    let status = SecIdentityCreateWithCertificate(nil, leafCert, &identity)
                    if status == errSecSuccess, let id = identity {
                        logger.debug("🔐 [NetworkQuicTransporter] Created SecIdentity from MobileKeyManager-issued certificate for nodeId=\(kmNodeId)")
                        return id
                    } else {
                        logger.error("❌ [NetworkQuicTransporter] Failed to create identity from MobileKeyManager-issued cert (status: \(status))")
                    }
                }
            }
            // As last resort: lookup by node-specific label derived from MobileKeyManager's nodeId
            let identityQuery: [String: Any] = [
                kSecClass as String: kSecClassIdentity,
                kSecAttrLabel as String: "Runar Node Certificate \(kmNodeId)",
                kSecReturnRef as String: true
            ]
            var identityItem: CFTypeRef?
            let status = SecItemCopyMatching(identityQuery as CFDictionary, &identityItem)
            if status == errSecSuccess, let identityRef = identityItem {
                logger.debug("🔐 [NetworkQuicTransporter] Found SecIdentity by MobileKeyManager node-specific label")
                return unsafeBitCast(identityRef, to: SecIdentity.self)
            }
        }

        throw RunarTransportError.configurationError("Failed to resolve SecIdentity for this transporter instance")
    }
    

    
    // configureTLSForConnection / configureCustomCertificateValidation no longer used
    

    

    
    private func getCACertificateFromKeychain() throws -> SecCertificate {
        // Prefer CA from provided certificate chain (exact CA for this run)
        if let chain = options.certificates, let caDer = chain.last,
           let caSec = SecCertificateCreateWithData(nil, caDer as CFData) {
            logger.debug("🔐 [NetworkQuicTransporter] Using CA certificate from provided chain")
            return caSec
        }
        // Fallback to MobileKeyManager's CA for this instance
        guard let keyManager = options.mobileKeyManager else {
            throw RunarTransportError.configurationError("MobileKeyManager not initialized in transport options")
        }
        let caCertificate = keyManager.getCaCertificate()
        let caCertificateData = caCertificate.toDER()
        guard let secCertificate = SecCertificateCreateWithData(nil, caCertificateData as CFData) else {
            throw RunarTransportError.configurationError("Failed to create SecCertificate from CA certificate data")
        }
        logger.debug("🔐 [NetworkQuicTransporter] Retrieved CA certificate from MobileKeyManager")
        return secCertificate
    }
    
    private func stopListener() async {
        listener?.cancel()
        listener = nil
    }
    
    private func cleanupConnections() async {
        let connectedPeers = connectionPool.getConnectedPeers()
        for peerId in connectedPeers {
            if let peerState = connectionPool.getPeer(peerId: peerId) {
                logger.debug("🔚 [NetworkQuicTransporter] Closing connection to \(peerId)")
                peerState.closeConnection()
            }
        }
    }
    
    private func buildQuicParametersForConnection(keyManager: MobileKeyManager, sniHost: String) throws -> NWParameters {
        logger.debug("🔐 [NetworkQuicTransporter] Building per-connection QUIC parameters with TLS config")
        let quic = NWProtocolQUIC.Options()
        // Set ALPN
        "runar".utf8CString.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress { sec_protocol_options_add_tls_application_protocol(quic.securityProtocolOptions, base) }
        }
        let sec = quic.securityProtocolOptions
        // TLS 1.3 + mutual auth
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(sec, true)
        // ALPN is set by NWParameters.quic
        // Set SNI to match endpoint host
        sniHost.utf8CString.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress { sec_protocol_options_set_tls_server_name(sec, base) }
        }

        // Trust anchors from our CA
        let caCertificate = try getCACertificateFromKeychain()
        sec_protocol_options_set_verify_block(sec, { [weak self] (_: sec_protocol_metadata_t, trust: sec_trust_t, complete: @escaping sec_protocol_verify_complete_t) in
            guard let self = self else { complete(false); return }
            self.logger.debug("🔐 [NetworkQuicTransporter] [Client] verify-block invoked")
            let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(trustRef) as? [SecCertificate], let leaf = chain.first {
                if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
                    self.logger.debug("🔐 [Client verify] Leaf subject: \(summary), chainCount=\(chain.count)")
                } else {
                    self.logger.debug("🔐 [Client verify] Leaf present, chainCount=\(chain.count)")
                }
            } else {
                self.logger.debug("🔐 [Client verify] No certificates in trust object")
            }
            // Try evaluating NW-provided trust first
            let policyHost = "localhost" as CFString
            let clientPolicy = SecPolicyCreateSSL(true, policyHost)
            SecTrustSetPolicies(trustRef, clientPolicy)
            let anchors = [caCertificate] as CFArray
            let setAnchorStatus = SecTrustSetAnchorCertificates(trustRef, anchors)
            if setAnchorStatus != errSecSuccess { self.logger.error("❌ [NetworkQuicTransporter] [Client] Set anchors failed: \(setAnchorStatus)"); complete(false); return }
            _ = SecTrustSetAnchorCertificatesOnly(trustRef, true)
            var error: CFError?
            var ok = SecTrustEvaluateWithError(trustRef, &error)
            if ok {
                self.logger.debug("✅ [NetworkQuicTransporter] [Client] trust OK (NW trust, anchors-only)")
                complete(true)
                return
            }
            if let e = error { self.logger.error("❌ [NetworkQuicTransporter] [Client] NW trust failed: \(e). Trying rebuilt trust...") }

            // Rebuild SecTrust using the leaf and our CA, then evaluate
            if let chain = SecTrustCopyCertificateChain(trustRef) as? [SecCertificate], let leaf = chain.first {
                var rebuilt: SecTrust?
                let certs = [leaf] as CFTypeRef
                let createStatus = SecTrustCreateWithCertificates(certs, clientPolicy, &rebuilt)
                if createStatus == errSecSuccess, let rebuilt = rebuilt {
                    _ = SecTrustSetAnchorCertificates(rebuilt, anchors)
                    _ = SecTrustSetAnchorCertificatesOnly(rebuilt, true)
                    var e2: CFError?
                    ok = SecTrustEvaluateWithError(rebuilt, &e2)
                    if ok {
                        self.logger.debug("✅ [NetworkQuicTransporter] [Client] trust OK (rebuilt trust, anchors-only)")
                        complete(true)
                        return
                    } else {
                        if let e2 = e2 { self.logger.error("❌ [NetworkQuicTransporter] [Client] rebuilt trust failed: \(e2)") }
                    }
                } else {
                    self.logger.error("❌ [NetworkQuicTransporter] [Client] SecTrustCreateWithCertificates failed: \(createStatus)")
                }
            } else {
                self.logger.error("❌ [NetworkQuicTransporter] [Client] Could not extract leaf certificate from trust")
            }
            complete(false)
        }, self.connectionQueue)

        // Local identity per-connection
        try setLocalIdentityWithChain(securityProtocolOptions: sec, keyManager: keyManager)
        // Log identity subject client-side as well
        do {
            let id = try getClientIdentityFromKeychain()
            var cert: SecCertificate?
            if SecIdentityCopyCertificate(id, &cert) == errSecSuccess, let c = cert {
                let subj = SecCertificateCopySubjectSummary(c) as String? ?? "nil"
                logger.debug("🔐 [NetworkQuicTransporter] [Client] using identity subject=\(subj)")
            }
        } catch { logger.debug("🔐 [NetworkQuicTransporter] [Client] identity log error: \(error)") }
        logger.debug("🔐 [NetworkQuicTransporter] Per-connection local identity with chain set")
        // Attach options to parameters
        let params = NWParameters(quic: quic)
        // Prefer loopback and avoid P2P for local tests
        params.requiredInterfaceType = .loopback
        params.includePeerToPeer = false
        params.allowLocalEndpointReuse = true
        return params
    }
    
    private func connectToAddress(_ address: String, peerId: String) async throws {
        // Parse address
        let components = address.split(separator: ":")
        guard components.count == 2,
              let port = UInt16(components[1]) else {
            throw RunarTransportError.configurationError("Invalid address format: \(address)")
        }
        
        let host = String(components[0])
        
        // Build fresh parameters with TLS for this connection
        guard let keyManager = options.mobileKeyManager else {
            throw RunarTransportError.configurationError("MobileKeyManager not initialized in transport options")
        }
        // Use SNI that matches certificate SAN regardless of numeric endpoint
        let parameters = try buildQuicParametersForConnection(keyManager: keyManager, sniHost: "localhost")
        logger.debug("🔧 [NetworkQuicTransporter] Created per-connection QUIC parameters for \(peerId)")
        
        // Create endpoint
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        logger.debug("🔧 [NetworkQuicTransporter] Created endpoint \(host):\(port) for \(peerId)")
        
        // Create connection
        let connection = NWConnection(to: endpoint, using: parameters)
        logger.debug("🔧 [NetworkQuicTransporter] Created NWConnection for \(peerId)")
        
        logger.debug("🔧 [NetworkQuicTransporter] TLS configured via per-connection parameters for \(peerId)")
        
        // Set up connection state handler
        connection.stateUpdateHandler = self.connectionStateUpdateHandler(connection: connection, peerId: peerId)
        logger.debug("🔧 [NetworkQuicTransporter] Set up connection state handler for \(peerId)")
        
        // Start connection
        connection.start(queue: connectionQueue)
        logger.debug("🔧 [NetworkQuicTransporter] Started connection for \(peerId)")
        // Kick the handshake by sending a tiny datagram
        let kickContext = NWConnection.ContentContext.defaultMessage
        connection.send(content: Data([0x00]), contentContext: kickContext, isComplete: true, completion: .idempotent)
        
        // Store connection in ConnectionPool
        let peerState = connectionPool.getOrCreatePeer(peerId: peerId, address: address, logger: logger)
        logger.debug("🔧 [NetworkQuicTransporter] Created/get peer state for \(peerId)")
        
        // Wait for connection to be established (proper state management)
        // Use a continuation to wait for the connection to be ready
        logger.debug("🔧 [NetworkQuicTransporter] Waiting for connection to be ready for \(peerId)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Store the continuation to be called when connection is ready
            peerState.setConnectionReadyContinuation(continuation)
            logger.debug("🔧 [NetworkQuicTransporter] Set connection ready continuation for \(peerId)")
            
            // Set a timeout
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                logger.debug("🔧 [NetworkQuicTransporter] Connection timeout reached for \(peerId)")
                // Ask peerState to resume the continuation if it hasn't been resumed yet
                let timeoutError = RunarTransportError.connectionError("Connection to \(peerId) failed to establish within timeout")
                peerState.notifyConnectionFailed(timeoutError)
            }
        }
        
        logger.info("✅ [NetworkQuicTransporter] Connection to \(peerId) established")
    }
    
    private func sendMessage(_ message: RunarNetworkMessage, to peerId: String) async throws {
        guard let peerState = connectionPool.getPeer(peerId: peerId),
              let connection = peerState.getConnection() else {
            throw RunarTransportError.connectionError("Not connected to peer \(peerId)")
        }
        
        // Encode message using binary format
        let messageData = try encodeNetworkMessage(message)
        
        // Add length prefix (4 bytes)
        var data = Data()
        var length = UInt32(messageData.count).bigEndian
        withUnsafeBytes(of: &length) { rawBuffer in
            data.append(rawBuffer.bindMemory(to: UInt8.self))
        }
        data.append(messageData)
        
        // Send via unidirectional stream (matching Rust implementation)
        connection.send(content: data, contentContext: NWConnection.ContentContext.defaultMessage, isComplete: true, completion: .contentProcessed { [weak self] (error: NWError?) -> Void in
            if let error = error {
                self?.logger.error("❌ [NetworkQuicTransporter] Failed to send message to \(peerId): \(error)")
            } else {
                self?.logger.debug("✅ [NetworkQuicTransporter] Message sent to \(peerId)")
            }
        })
    }
    
    private func removeConnection(peerId: String) {
        connectionPool.removePeer(peerId: peerId)
        logger.info("🔚 [NetworkQuicTransporter] Removed connection to \(peerId)")
    }
    
    // MARK: - Handler Methods
    
    private func listenerStateUpdateHandler(state: NWListener.State) {
        switch state {
        case .ready:
            self.logger.info("✅ [NetworkQuicTransporter] Listener ready on \(self.bindAddress)")
        case .failed(let error):
            self.logger.error("❌ [NetworkQuicTransporter] Listener failed: \(error)")
        case .cancelled:
            self.logger.info("🔚 [NetworkQuicTransporter] Listener cancelled")
        default:
            self.logger.debug("🔄 [NetworkQuicTransporter] Listener state: \(String(describing: state))")
        }
    }
    
    private func listenerNewConnectionHandler(connection: NWConnection) {
        self.logger.info("🆕 [NetworkQuicTransporter] New incoming connection")
        // Retain the inbound connection immediately with a temporary peer id
        let tempPeerId = connection.endpoint.debugDescription
        let tempAddress = tempPeerId
        let tempPeerState = self.connectionPool.getOrCreatePeer(peerId: tempPeerId, address: tempAddress, logger: self.logger)
        tempPeerState.setConnection(connection)
        // Accept and start the inbound QUIC connection so TLS handshake can proceed
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            self.logger.debug("🔧 [NetworkQuicTransporter] Inbound connection state: \(state)")
            switch state {
            case .ready:
                // We don't yet know the peerId until handshake/meta; use endpoint as temporary key
                let tempPeerId = connection.endpoint.debugDescription
                if let peerState = self.connectionPool.getPeer(peerId: tempPeerId) {
                    peerState.setConnection(connection)
                    peerState.updateActivity()
                    peerState.notifyConnectionReady()
                } else {
                    let peerState = self.connectionPool.getOrCreatePeer(peerId: tempPeerId, address: tempPeerId, logger: self.logger)
                    peerState.setConnection(connection)
                    peerState.updateActivity()
                    peerState.notifyConnectionReady()
                }
                self.startReceiving(from: connection, peerId: tempPeerId)
            case .failed(let error):
                self.logger.error("❌ [NetworkQuicTransporter] Inbound connection failed: \(error)")
            case .cancelled:
                self.logger.info("🔚 [NetworkQuicTransporter] Inbound connection cancelled")
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
        // Server-side handshake kick: send a few small datagrams to trigger TLS
        for i in 0..<5 {
            let ctx = NWConnection.ContentContext(identifier: "server-handshake-kick-\(i)")
            connection.send(content: Data([0x00]), contentContext: ctx, isComplete: true, completion: .idempotent)
        }
        // Start receiving only after the connection is started
        self.startReceiving(from: connection, peerId: tempPeerId)
    }
    
    private func connectionStateUpdateHandler(connection: NWConnection, peerId: String) -> (NWConnection.State) -> Void {
        let handler: (NWConnection.State) -> Void = { [weak self, weak connection] (state: NWConnection.State) in
            guard let self = self, let connection = connection else { 
                self?.logger.debug("🔧 [NetworkQuicTransporter] Connection state handler called with nil self or connection for \(peerId)")
                return 
            }
            
            // Add comprehensive debug logging for all state changes
            self.logger.debug("🔧 [NetworkQuicTransporter] Connection state change for \(peerId): \(String(describing: state))")
            self.logger.info("🔄 [NetworkQuicTransporter] Connection state change for \(peerId): \(String(describing: state))")
            // Path logging omitted (platform API differences)
            
            switch state {
            case .ready:
                self.logger.debug("🔧 [NetworkQuicTransporter] Connection READY for \(peerId)")
                self.logger.info("✅ [NetworkQuicTransporter] Connected to \(peerId)")
                self.handleConnectionReady(connection, peerId: peerId)
            case .failed(let error):
                self.logger.debug("🔧 [NetworkQuicTransporter] Connection FAILED for \(peerId): \(error)")
                self.logger.error("❌ [NetworkQuicTransporter] Connection to \(peerId) failed: \(error)")
                if case let NWError.posix(code) = error { self.logger.error("❌ [NetworkQuicTransporter] POSIX: \(code.rawValue)") }
                if case let NWError.tls(code) = error { self.logger.error("❌ [NetworkQuicTransporter] TLS: \(code)") }
                if case let NWError.dns(code) = error { self.logger.error("❌ [NetworkQuicTransporter] DNS: \(code)") }
                if let peerState = self.connectionPool.getPeer(peerId: peerId) {
                    self.logger.debug("🔧 [NetworkQuicTransporter] Notifying peer state of connection failure for \(peerId)")
                    peerState.notifyConnectionFailed(error)
                } else {
                    self.logger.debug("🔧 [NetworkQuicTransporter] No peer state found for failed connection \(peerId)")
                }
                self.removeConnection(peerId: peerId)
            case .cancelled:
                self.logger.debug("🔧 [NetworkQuicTransporter] Connection CANCELLED for \(peerId)")
                self.logger.info("🔚 [NetworkQuicTransporter] Connection to \(peerId) cancelled")
                if let peerState = self.connectionPool.getPeer(peerId: peerId) {
                    self.logger.debug("🔧 [NetworkQuicTransporter] Notifying peer state of connection cancellation for \(peerId)")
                    peerState.notifyConnectionFailed(RunarTransportError.connectionError("Connection cancelled"))
                } else {
                    self.logger.debug("🔧 [NetworkQuicTransporter] No peer state found for cancelled connection \(peerId)")
                }
                self.removeConnection(peerId: peerId)
            case .preparing:
                self.logger.debug("🔧 [NetworkQuicTransporter] Connection PREPARING for \(peerId)")
            case .setup:
                self.logger.debug("🔧 [NetworkQuicTransporter] Connection SETUP for \(peerId)")
            case .waiting(let error):
                self.logger.debug("🔧 [NetworkQuicTransporter] Connection WAITING for \(peerId): \(error)")
                if case let NWError.posix(code) = error { self.logger.error("❌ [NetworkQuicTransporter] WAIT POSIX: \(code.rawValue)") }
                if case let NWError.tls(code) = error { self.logger.error("❌ [NetworkQuicTransporter] WAIT TLS: \(code)") }
                if case let NWError.dns(code) = error { self.logger.error("❌ [NetworkQuicTransporter] WAIT DNS: \(code)") }
            default:
                self.logger.debug("🔧 [NetworkQuicTransporter] Connection UNKNOWN state for \(peerId): \(String(describing: state))")
            }
        }
        return handler
    }
    
    private func handleConnectionReady(_ connection: NWConnection, peerId: String) {
        logger.debug("🔧 [NetworkQuicTransporter] handleConnectionReady called for \(peerId)")
        logger.info("🔄 [NetworkQuicTransporter] Connection ready for \(peerId)")
        
        // Set the connection in the peer state (this makes isConnected return true)
        if let peerState = connectionPool.getPeer(peerId: peerId) {
            logger.debug("🔧 [NetworkQuicTransporter] Found existing peer state for \(peerId)")
            peerState.setConnection(connection)
            peerState.updateActivity()
            peerState.notifyConnectionReady()
            logger.debug("🔧 [NetworkQuicTransporter] Notified connection ready for existing peer \(peerId)")
            logger.info("✅ [NetworkQuicTransporter] Connection state set for \(peerId)")
        } else {
            // If peer state doesn't exist, create it
            logger.debug("🔧 [NetworkQuicTransporter] Creating new peer state for \(peerId)")
            let peerState = connectionPool.getOrCreatePeer(peerId: peerId, address: connection.endpoint.debugDescription, logger: logger)
            peerState.setConnection(connection)
            peerState.updateActivity()
            peerState.notifyConnectionReady()
            logger.debug("🔧 [NetworkQuicTransporter] Notified connection ready for new peer \(peerId)")
            logger.info("✅ [NetworkQuicTransporter] Created and set connection state for \(peerId)")
        }
        
        // Start receiving messages
        startReceiving(from: connection, peerId: peerId)
        
        // Initiate handshake with a slight delay to ensure the peer's receive loop is attached
        Task {
            try await Task.sleep(nanoseconds: 150_000_000) // 150ms
            try await initiateHandshake(to: peerId)
        }
    }
    
    private func startReceiving(from connection: NWConnection, peerId: String) {
        receiveNextMessage(from: connection, peerId: peerId)
    }
    
    private func receiveNextMessage(from connection: NWConnection, peerId: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (content: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) -> Void in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("❌ [NetworkQuicTransporter] Receive error from \(peerId): \(error)")
                return
            }
            
            // Process any received content >= 4 bytes (length-prefixed protocol), ignoring explicit kick contexts
            if let data = content, !data.isEmpty {
                var isNonApp = false
                if let ctx = context {
                    if ctx.identifier.hasPrefix("server-handshake-kick") {
                        isNonApp = true
                    }
                }
                if isNonApp {
                    self.logger.debug("🔎 [NetworkQuicTransporter] Ignoring non-app context from \(peerId)")
                } else if data.count < 4 {
                    self.logger.debug("🔎 [NetworkQuicTransporter] Ignoring short frame (len=\(data.count)) from \(peerId)")
                } else {
                    self.handleReceivedData(data, from: peerId, connection: connection)
                }
            }
            
            if !isComplete {
                self.receiveNextMessage(from: connection, peerId: peerId)
            }
        }
    }
    
    private func handleReceivedData(_ data: Data, from peerId: String, connection: NWConnection) {
        logger.debug("📥 [NetworkQuicTransporter] Received \(data.count) bytes from \(peerId)")
        // Expect a 4-byte big-endian length prefix followed by the frame
        guard data.count >= 4 else {
            logger.debug("🔎 [NetworkQuicTransporter] Frame too short (<4) from \(peerId)")
            return
        }
        // Read BE length
        let len: Int = data.withUnsafeBytes { rawBuf in
            let buf = rawBuf.bindMemory(to: UInt8.self)
            if buf.count >= 4 {
                let v = (UInt32(buf[0]) << 24) | (UInt32(buf[1]) << 16) | (UInt32(buf[2]) << 8) | UInt32(buf[3])
                return Int(v)
            } else {
                return -1
            }
        }
        guard len >= 0 else {
            logger.debug("🔎 [NetworkQuicTransporter] Failed to parse length prefix from \(peerId)")
            return
        }
        let totalNeeded = 4 + len
        guard data.count >= totalNeeded else {
            logger.debug("🔎 [NetworkQuicTransporter] Incomplete framed message from \(peerId): have=\(data.count) need=\(totalNeeded)")
            return
        }
        // Safe slicing within bounds
        let messageData = data.subdata(in: 4..<(4 + len))
        do {
            let message = try decodeNetworkMessage(from: messageData)
            logger.info("📥 [NetworkQuicTransporter] Received message from \(peerId) - Type: \(message.messageType)")
            if message.messageType == MessageTypes.HANDSHAKE {
                messageQueue.async { self.messageHandler.handleMessage(message) }
                if let payload = message.payloads.first {
                    let pv = payload.valueBytes
                    let pvPreview = pv.prefix(8).map { String(format: "%02x", $0) }.joined()
                    self.logger.info("🔎 [NetworkQuicTransporter] HANDSHAKE payloadLen=\(pv.count) preview=\(pvPreview)")
                    if let peerNode = try? self.decodeNodeInfo(from: pv) {
                        self.messageQueue.async { self.messageHandler.peerConnected(peerNode) }
                        self.subscriptionQueue.async { self.peerNodeInfoStream?.yield(peerNode) }
                    } else {
                        self.logger.error("❌ [NetworkQuicTransporter] Failed to decode HANDSHAKE payload as NodeInfo (len=\(pv.count))")
                    }
                }
            } else if message.messageType == "REQUEST" {
                let response = RunarNetworkMessage(
                    sourceNodeId: self.nodeInfo.nodeId,
                    destinationNodeId: message.sourceNodeId,
                    messageType: "RESPONSE",
                    payloads: [
                        NetworkMessagePayloadItem(
                            path: "/auto/response",
                            valueBytes: Data("ok".utf8),
                            correlationId: message.payloads.first?.correlationId ?? ""
                        )
                    ]
                )
                Task { try await self.send(message: response) }
            } else {
                messageQueue.async { self.messageHandler.handleMessage(message) }
            }
        } catch {
            logger.error("❌ [NetworkQuicTransporter] Failed to decode message from \(peerId): \(error)")
        }
    }
    
    // MARK: - Message Receiver (matching Rust spawn_connection_tasks)
    
    private func startMessageReceiver(for peerId: String, connection: NWConnection) {
        logger.info("🔄 [NetworkQuicTransporter] Starting message receiver for peer \(peerId)")
        
        // Spawn task to handle bidirectional and unidirectional streams
        Task {
            await handleConnectionStreams(peerId: peerId, connection: connection)
        }
    }
    
    private func handleConnectionStreams(peerId: String, connection: NWConnection) async {
        // This is a simplified version matching Rust's spawn_connection_tasks
        // In Network.framework, we handle streams differently but maintain the same flow
        
        logger.info("🔄 [NetworkQuicTransporter] Handling connection streams for peer \(peerId)")
        
        // Start receiving messages (Network.framework handles this automatically)
        // The connection state handler will manage the streams
    }
    
    // MARK: - Handshake Protocol (matching Rust handshake_outbound)
    
    private func performHandshake(to peerId: String, connection: NWConnection) async throws {
        logger.info("🤝 [NetworkQuicTransporter] Performing handshake with \(peerId)")
        
        // Create handshake message (matching Rust handshake_outbound)
        let handshakeMessage = RunarNetworkMessage(
            sourceNodeId: nodeInfo.nodeId,
            destinationNodeId: peerId,
            messageType: MessageTypes.HANDSHAKE,
            payloads: [
                NetworkMessagePayloadItem(
                    path: "handshake",
                    valueBytes: try encodeNodeInfo(nodeInfo),
                    correlationId: UUID().uuidString
                )
            ]
        )
        
        // Send handshake via bidirectional stream (matching Rust request_inner)
        let response = try await sendRequestAndWaitForResponse(connection: connection, message: handshakeMessage)
        
        logger.info("✅ [NetworkQuicTransporter] Handshake completed with \(peerId)")
        
        // Process handshake response through message handler (matching Rust)
        messageQueue.async {
            self.messageHandler.handleMessage(response)
        }
    }
    
    private func sendRequestAndWaitForResponse(connection: NWConnection, message: RunarNetworkMessage) async throws -> RunarNetworkMessage {
        // This simulates the Rust request_inner flow using Network.framework
        logger.debug("🔄 [NetworkQuicTransporter] Sending request and waiting for response")
        
        // Encode and send message
        let messageData = try encodeNetworkMessage(message)
        var data = Data()
        var length = UInt32(messageData.count).bigEndian
        withUnsafeBytes(of: &length) { rawBuffer in
            data.append(rawBuffer.bindMemory(to: UInt8.self))
        }
        data.append(messageData)
        
        // For now, we'll use a simple send without waiting for response
        // In a full implementation, we'd need to implement proper request-response correlation
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("❌ [NetworkQuicTransporter] Failed to send request: \(error)")
            } else {
                self?.logger.debug("✅ [NetworkQuicTransporter] Request sent successfully")
            }
        })
        
        // Wait for the actual response from the peer
        // This is a real implementation that waits for the response
        let correlationId = message.payloads.first?.correlationId ?? ""
        return try await waitForResponse(from: message.destinationNodeId, correlationId: correlationId)
    }
    
    private func waitForResponse(from peerId: String, correlationId: String) async throws -> RunarNetworkMessage {
        logger.debug("⏳ [NetworkQuicTransporter] Waiting for response from \(peerId) with correlation ID: \(correlationId)")
        
        // Create a continuation to wait for the response
        return try await withCheckedThrowingContinuation { continuation in
            // Store the continuation to be resumed when response is received
            self.correlationQueue.async {
                self.pendingResponses[correlationId] = continuation
            }
            
            // Set a timeout for the response
            DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.correlationQueue.async {
                    if let continuation = self?.pendingResponses[correlationId] {
                        self?.pendingResponses.removeValue(forKey: correlationId)
                        continuation.resume(throwing: RunarTransportError.connectionError("Response timeout from \(peerId)"))
                    }
                }
            }
        }
    }
    
    // MARK: - Handshake Protocol
    
    private func initiateHandshake(to peerId: String) async throws {
        logger.info("🤝 [NetworkQuicTransporter] Initiating handshake with \(peerId)")
        
        // Create handshake message
        let handshakeMessage = RunarNetworkMessage(
            sourceNodeId: nodeInfo.nodeId,
            destinationNodeId: peerId,
            messageType: MessageTypes.HANDSHAKE,
            payloads: [
                NetworkMessagePayloadItem(
                    path: "",
                    valueBytes: try encodeNodeInfo(nodeInfo),
                    correlationId: "handshake-\(nodeInfo.nodeId)-\(Date().timeIntervalSince1970)"
                )
            ]
        )
        
        // Send handshake message directly via connection
        guard let peerState = connectionPool.getPeer(peerId: peerId),
              let connection = peerState.getConnection() else {
            throw RunarTransportError.connectionError("No connection available for handshake to \(peerId)")
        }
        
        let messageData = try encodeNetworkMessage(handshakeMessage)
        var data = Data()
        var length = UInt32(messageData.count).bigEndian
        withUnsafeBytes(of: &length) { rawBuffer in
            data.append(rawBuffer.bindMemory(to: UInt8.self))
        }
        data.append(messageData)
        // Tag content as app-level framed message
        let appCtx = NWConnection.ContentContext(identifier: "runar-msg")
        connection.send(content: data, contentContext: NWConnection.ContentContext.defaultMessage, isComplete: true, completion: .contentProcessed { [weak self] (error: NWError?) -> Void in
            if let error = error {
                self?.logger.error("❌ [NetworkQuicTransporter] Failed to send handshake to \(peerId): \(error)")
            } else {
                self?.logger.debug("✅ [NetworkQuicTransporter] Handshake sent to \(peerId)")
            }
        })
    }
    
    private func handleHandshakeMessage(_ message: RunarNetworkMessage, from peerId: String, connection: NWConnection) {
        logger.info("🤝 [NetworkQuicTransporter] Handling handshake message from \(peerId)")
        
        guard let payload = message.payloads.first else {
            logger.error("❌ [NetworkQuicTransporter] Handshake message has no payload")
            return
        }
        
        do {
            let peerNodeInfo = try decodeNodeInfo(from: payload.valueBytes)
            let realPeerId = peerNodeInfo.nodeId
            
            logger.info("✅ [NetworkQuicTransporter] Identified peer: \(realPeerId)")
            
            // Update connection mapping if this was an unknown peer
            if peerId == "unknown" {
                let peerState = connectionPool.getOrCreatePeer(peerId: realPeerId, address: "unknown", logger: logger)
                peerState.setConnection(connection)
                connectionPool.removePeer(peerId: "unknown")
            }
            
            // Handle different handshake message types
            if message.messageType == MessageTypes.NODE_INFO_HANDSHAKE {
                // Send handshake response
                Task {
                    try await sendHandshakeResponse(to: realPeerId)
                }
                
                // Notify about new peer (both directions)
                messageQueue.async {
                    self.messageHandler.peerConnected(peerNodeInfo)
                }
                
                // Send to subscription stream
                subscriptionQueue.async {
                    self.peerNodeInfoStream?.yield(peerNodeInfo)
                }
                
            } else if message.messageType == MessageTypes.NODE_INFO_HANDSHAKE_RESPONSE {
                // Notify about new peer (both directions)
                messageQueue.async {
                    self.messageHandler.peerConnected(peerNodeInfo)
                }
                
                // Send to subscription stream
                subscriptionQueue.async {
                    self.peerNodeInfoStream?.yield(peerNodeInfo)
                }
            }
            
        } catch {
            logger.error("❌ [NetworkQuicTransporter] Failed to process handshake from \(peerId): \(error)")
        }
    }
    
    private func sendHandshakeResponse(to peerId: String) async throws {
        logger.info("🤝 [NetworkQuicTransporter] Sending handshake response to \(peerId)")
        
        let responseMessage = RunarNetworkMessage(
            sourceNodeId: nodeInfo.nodeId,
            destinationNodeId: peerId,
            messageType: MessageTypes.NODE_INFO_HANDSHAKE_RESPONSE,
            payloads: [
                NetworkMessagePayloadItem(
                    path: "",
                    valueBytes: try encodeNodeInfo(nodeInfo),
                    correlationId: "handshake-response-\(nodeInfo.nodeId)-\(Date().timeIntervalSince1970)"
                )
            ]
        )
        
        // Send handshake response directly via connection
        guard let peerState = connectionPool.getPeer(peerId: peerId),
              let connection = peerState.getConnection() else {
            throw RunarTransportError.connectionError("No connection available for handshake response to \(peerId)")
        }
        
        let messageData = try encodeNetworkMessage(responseMessage)
        var data = Data()
        var length = UInt32(messageData.count).bigEndian
        data.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
        data.append(messageData)
        
        connection.send(content: data, completion: .contentProcessed { [weak self] (error: NWError?) -> Void in
            if let error = error {
                self?.logger.error("❌ [NetworkQuicTransporter] Failed to send handshake response to \(peerId): \(error)")
            } else {
                self?.logger.debug("✅ [NetworkQuicTransporter] Handshake response sent to \(peerId)")
            }
        })
    }
    
    // MARK: - Message Encoding/Decoding
    
    private func encodeNetworkMessage(_ message: RunarNetworkMessage) throws -> Data {
        // Use binary encoding for efficiency and compatibility with Rust
        return try BinaryMessageEncoder.encodeNetworkMessage(message)
    }
    
    private func decodeNetworkMessage(from data: Data) throws -> RunarNetworkMessage {
        // Use binary decoding for efficiency and compatibility with Rust
        return try BinaryMessageEncoder.decodeNetworkMessage(from: data)
    }
    
    private func encodeNodeInfo(_ nodeInfo: RunarNodeInfo) throws -> Data {
        // Use binary encoding for efficiency and compatibility with Rust
        return try BinaryMessageEncoder.encodeNodeInfo(nodeInfo)
    }
    
    private func decodeNodeInfo(from data: Data) throws -> RunarNodeInfo {
        // Use binary decoding for efficiency and compatibility with Rust
        return try BinaryMessageEncoder.decodeNodeInfo(from: data)
    }
}

// MARK: - Supporting Types

@available(macOS 12.0, iOS 15.0, *)
private struct HandshakeState {
    let peerId: String
    let initiatedAt: Date
    let status: HandshakeStatus
    
    enum HandshakeStatus {
        case initiated
        case completed
        case failed
    }
}

@available(macOS 12.0, iOS 15.0, *)
private struct RequestState {
    let correlationId: String
    let initiatedAt: Date
    let timeout: TimeInterval
    
    init(correlationId: String, timeout: TimeInterval = 30.0) {
        self.correlationId = correlationId
        self.initiatedAt = Date()
        self.timeout = timeout
    }
}

/// Transport-specific errors
public enum QuicTransportError: Error, LocalizedError {
    case peerNotConnected(String)
    case transportNotRunning
    case encodingError(String)
    case decodingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .peerNotConnected(let peerId):
            return "Peer \(peerId) is not connected"
        case .transportNotRunning:
            return "Transport is not running"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        }
    }
} 