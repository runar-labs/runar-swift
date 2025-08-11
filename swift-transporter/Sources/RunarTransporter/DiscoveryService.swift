import Foundation
import Network
import os.log
import Crypto
import Darwin

/// Discovery service for finding peers on the network
/// Implements multicast-based discovery that matches the Rust implementation exactly
@available(macOS 12.0, iOS 15.0, *)
public class DiscoveryService: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let nodeInfo: RunarNodeInfo
    private let multicastGroup: String
    private let multicastPort: UInt16
    private let logger: Logger
    
    // Raw UDP socket for multicast (matching Rust implementation)
    private var udpSocket: Int32 = -1
    private let socketQueue = DispatchQueue(label: "com.runar.discovery.socket", qos: .userInitiated)
    
    // State management
    private var isRunning = false
    private let stateQueue = DispatchQueue(label: "com.runar.discovery.state", qos: .userInitiated)
    
    // Callbacks
    private var peerDiscoveredCallback: ((RunarPeerInfo) -> Void)?
    private var peerLostCallback: ((String) -> Void)?
    
    // Discovered peers tracking (matches Rust HashMap<String, PeerInfo>)
    private var discoveredPeers: [String: DiscoveryPeerInfo] = [:]
    private let peersQueue = DispatchQueue(label: "com.runar.discovery.peers", qos: .userInitiated)
    
    // Task management
    private var receiveTask: Task<Void, Never>?
    private var announceTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(
        nodeInfo: RunarNodeInfo,
        multicastGroup: String = "224.0.0.1",
        multicastPort: UInt16 = 45678, // Match Rust DEFAULT_MULTICAST_PORT
        logger: Logger
    ) {
        self.nodeInfo = nodeInfo
        self.multicastGroup = multicastGroup
        self.multicastPort = multicastPort
        self.logger = logger
        
        logger.info("🔍 [DiscoveryService] Initialized - Node: \(nodeInfo.nodeId), Group: \(multicastGroup):\(multicastPort)")
    }
    
    // MARK: - Public Methods
    
    /// Start the discovery service
    public func start() async throws {
        logger.info("🔄 [DiscoveryService] Starting discovery service...")
        
        stateQueue.sync {
            guard !isRunning else {
                logger.warning("⚠️ [DiscoveryService] Already running")
                return
            }
            isRunning = true
        }
        
        // Start with timeout to prevent hanging
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.createMulticastSocket()
                try await self.startReceiveTask()
                try await self.startAnnounceTask()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout
                throw RunarTransportError.transportError("Discovery service start timeout")
            }
            
            try await group.next()!
            group.cancelAll()
        }
        
        logger.info("✅ [DiscoveryService] Started successfully")
    }
    
    /// Stop the discovery service
    public func stop() async {
        logger.info("🔄 [DiscoveryService] Stopping discovery service...")
        
        stateQueue.sync {
            guard isRunning else {
                logger.warning("⚠️ [DiscoveryService] Not running")
                return
            }
            isRunning = false
        }
        
        // Cancel tasks first
        receiveTask?.cancel()
        announceTask?.cancel()
        
        // Wait for tasks to finish (with timeout)
        if let receiveTask = receiveTask {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await receiveTask.value
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second timeout
                }
            }
        }
        
        if let announceTask = announceTask {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await announceTask.value
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second timeout
                }
            }
        }
        
        // Send goodbye
        await sendGoodbye()
        
        // Close socket
        await closeSocket()
        
        logger.info("✅ [DiscoveryService] Stopped successfully")
    }
    
    /// Set callback for when a peer is discovered
    public func onPeerDiscovered(_ callback: @escaping (RunarPeerInfo) -> Void) {
        peerDiscoveredCallback = callback
    }
    
    /// Set callback for when a peer is lost
    public func onPeerLost(_ callback: @escaping (String) -> Void) {
        peerLostCallback = callback
    }
    
    /// Get currently discovered peers
    public func getDiscoveredPeers() -> [RunarPeerInfo] {
        peersQueue.sync {
            return discoveredPeers.values.map { peerInfo in
                RunarPeerInfo(
                    publicKey: peerInfo.publicKey,
                    addresses: peerInfo.addresses,
                    name: "Runar Node",
                    metadata: [:]
                )
            }
        }
    }
    
    /// Manually announce this node to the network
    public func announce() async throws {
        guard isRunning else {
            throw RunarTransportError.transportError("Discovery service not running")
        }
        
        try await sendAnnouncement()
    }
    
    // MARK: - Private Methods
    
    /// Create and configure multicast socket (matches Rust create_multicast_socket)
    private func createMulticastSocket() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            socketQueue.async {
                do {
                    // Create UDP socket
                    let socket = socket(AF_INET, SOCK_DGRAM, 0)
                    guard socket >= 0 else {
                        continuation.resume(throwing: RunarTransportError.transportError("Failed to create socket"))
                        return
                    }
                    
                    // Set socket options
                    var reuseAddr: Int32 = 1
                    setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
                    
                    // Set reuse port if available (macOS/iOS)
                    #if os(macOS) || os(iOS)
                    setsockopt(socket, SOL_SOCKET, SO_REUSEPORT, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
                    #endif
                    
                    // Set multicast TTL
                    var ttl: UInt8 = 2
                    setsockopt(socket, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
                    
                    // Enable multicast loopback
                    var loopback: UInt8 = 1
                    setsockopt(socket, IPPROTO_IP, IP_MULTICAST_LOOP, &loopback, socklen_t(MemoryLayout<UInt8>.size))
                    
                    // Bind to port
                    var addr = sockaddr_in()
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = self.multicastPort.bigEndian
                    addr.sin_addr.s_addr = INADDR_ANY
                    
                    let bindResult = withUnsafePointer(to: &addr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                            bind(socket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                    
                    guard bindResult == 0 else {
                        let errorCode = errno
                        close(socket)
                        continuation.resume(throwing: RunarTransportError.transportError("Failed to bind socket: error \(errorCode)"))
                        return
                    }
                    
                    // Join multicast group
                    var mreq = ip_mreq()
                    inet_pton(AF_INET, self.multicastGroup, &mreq.imr_multiaddr)
                    mreq.imr_interface.s_addr = INADDR_ANY
                    
                    let joinResult = setsockopt(socket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))
                    
                    guard joinResult == 0 else {
                        close(socket)
                        continuation.resume(throwing: RunarTransportError.transportError("Failed to join multicast group"))
                        return
                    }
                    
                    self.udpSocket = socket
                    self.logger.info("✅ [DiscoveryService] Created multicast socket bound to 0.0.0.0:\(self.multicastPort) and joined group \(self.multicastGroup)")
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Close the socket
    private func closeSocket() async {
        socketQueue.async {
            if self.udpSocket >= 0 {
                close(self.udpSocket)
                self.udpSocket = -1
            }
        }
    }
    
    /// Start receive task (matches Rust start_listener_task)
    private func startReceiveTask() async throws {
        receiveTask = Task {
            let socket = self.udpSocket
            var buffer = [UInt8](repeating: 0, count: 4096)
            
            while !Task.isCancelled && socket >= 0 {
                do {
                    // Use non-blocking socket operations with timeout
                    let (data, _) = try await withCheckedThrowingContinuation { continuation in
                        socketQueue.async {
                            // Set socket to non-blocking mode
                            var flags = fcntl(socket, F_GETFL, 0)
                            fcntl(socket, F_SETFL, flags | O_NONBLOCK)
                            
                            var addr = sockaddr_in()
                            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                            
                            // Try to receive data with a short timeout
                            let bytesRead = withUnsafeMutablePointer(to: &addr) { addrPtr in
                                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                                    recvfrom(socket, &buffer, buffer.count, MSG_DONTWAIT, sockaddrPtr, &addrLen)
                                }
                            }
                            
                            if bytesRead > 0 {
                                let data = Data(buffer.prefix(bytesRead))
                                continuation.resume(returning: (data, addr))
                            } else if bytesRead == -1 && errno == EAGAIN {
                                // No data available, continue
                                continuation.resume(throwing: RunarTransportError.transportError("No data available"))
                            } else if bytesRead == 0 {
                                continuation.resume(throwing: RunarTransportError.transportError("Socket closed"))
                            } else {
                                continuation.resume(throwing: RunarTransportError.transportError("Receive error"))
                            }
                        }
                    }
                    
                    self.handleReceivedData(data)
                    
                } catch {
                    if !Task.isCancelled {
                        // Only log actual errors, not "no data available"
                        if !error.localizedDescription.contains("No data available") {
                            self.logger.error("❌ [DiscoveryService] Receive error: \(error)")
                        }
                        // Short delay to prevent busy waiting
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
                    }
                }
            }
        }
    }
    
    /// Start announce task (matches Rust start_announce_task)
    private func startAnnounceTask() async throws {
        announceTask = Task {
            while !Task.isCancelled {
                do {
                    try await self.sendAnnouncement()
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                } catch {
                    if !Task.isCancelled {
                        self.logger.error("❌ [DiscoveryService] Failed to send announcement: \(error)")
                    }
                }
            }
        }
    }
    
    /// Handle received data (matches Rust process_message)
    private func handleReceivedData(_ data: Data) {
        Task {
            do {
                // Decode protobuf message
                var message = try DiscoveryMulticastMessage(serializedData: data)
                
                // Get sender ID
                guard let senderId = message.senderId() else {
                    logger.warning("⚠️ [DiscoveryService] Received message with no sender ID")
                    return
                }
                
                // Skip messages from self
                let localNodeId = nodeInfo.nodeId
                if senderId == localNodeId {
                    logger.debug("🔄 [DiscoveryService] Skipping message from self")
                    return
                }
                
                // Process message based on type
                if let peerInfo = message.announce {
                    await handleAnnouncement(peerInfo, senderId: senderId)
                } else if !message.goodbye.isEmpty {
                    await handleGoodbye(senderId: message.goodbye)
                } else {
                    logger.warning("⚠️ [DiscoveryService] Received message with no content")
                }
                
            } catch {
                logger.error("❌ [DiscoveryService] Failed to decode discovery message: \(error)")
            }
        }
    }
    
    /// Handle announcement (matches Rust announce handling)
    private func handleAnnouncement(_ peerInfo: DiscoveryPeerInfo, senderId: String) async {
        logger.debug("📥 [DiscoveryService] Processing announcement from \(senderId)")
        
        // Check if this is a new peer
        let isNewPeer = peersQueue.sync {
            !discoveredPeers.keys.contains(senderId)
        }
        
        // Store the peer info
        peersQueue.sync {
            discoveredPeers[senderId] = peerInfo
        }
        
        // Notify listeners
        let runarPeerInfo = RunarPeerInfo(
            publicKey: peerInfo.publicKey,
            addresses: peerInfo.addresses,
            name: "Runar Node",
            metadata: [:]
        )
        peerDiscoveredCallback?(runarPeerInfo)
        
        // Auto-respond to new peers (matches Rust behavior)
        if isNewPeer {
            logger.debug("🔄 [DiscoveryService] Auto-responding to new peer: \(senderId)")
            try? await sendAnnouncement()
        }
    }
    
    /// Handle goodbye (matches Rust goodbye handling)
    private func handleGoodbye(senderId: String) async {
        logger.debug("👋 [DiscoveryService] Processing goodbye from \(senderId)")
        
        let wasRemoved = peersQueue.sync {
            discoveredPeers.removeValue(forKey: senderId) != nil
        }
        
        if wasRemoved {
            peerLostCallback?(senderId)
        }
    }
    
    /// Send announcement (matches Rust announcement)
    private func sendAnnouncement() async throws {
        let peerInfo = DiscoveryPeerInfo(
            publicKey: nodeInfo.nodePublicKey,
            addresses: nodeInfo.addresses
        )
        
        let message = DiscoveryMulticastMessage(announce: peerInfo)
        let data = try message.serializedData()
        
        try await sendMulticastData(data)
        logger.debug("📢 [DiscoveryService] Sent announcement")
    }
    
    /// Send goodbye
    private func sendGoodbye() async {
        let message = DiscoveryMulticastMessage(goodbye: nodeInfo.nodeId)
        
        do {
            let data = try message.serializedData()
            try await sendMulticastData(data)
            logger.debug("👋 [DiscoveryService] Sent goodbye")
        } catch {
            logger.error("❌ [DiscoveryService] Failed to send goodbye: \(error)")
        }
    }
    
    /// Send data to multicast group
    private func sendMulticastData(_ data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            socketQueue.async {
                let socket = self.udpSocket
                guard socket >= 0 else {
                    continuation.resume(throwing: RunarTransportError.transportError("Socket not available"))
                    return
                }
                
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = self.multicastPort.bigEndian
                inet_pton(AF_INET, self.multicastGroup, &addr.sin_addr)
                
                let sendResult = data.withUnsafeBytes { bytes in
                    withUnsafePointer(to: &addr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                            sendto(socket, bytes.baseAddress, bytes.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                
                if sendResult >= 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: RunarTransportError.transportError("Failed to send multicast data"))
                }
            }
        }
    }
}