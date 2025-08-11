import Foundation
import os.log

/// Protocol defining the interface for transport implementations
/// Matches the Rust NetworkTransport trait functionality
@available(macOS 12.0, iOS 15.0, *)
public protocol TransportProtocol: AnyObject {
    /// Start the transport and begin listening for connections
    func start() async throws
    
    /// Stop the transport and clean up resources
    func stop() async
    
    /// Connect to a peer using discovery information
    func connect(to peerInfo: RunarPeerInfo) async throws
    
    /// Send a message to a peer
    func send(message: RunarNetworkMessage) async throws
    
    /// Check if connected to a specific peer
    func isConnected(to peerId: String) async -> Bool
    
    /// Get list of connected peers
    func getConnectedPeers() async -> [String]
    
    /// Update connected peers with new node info
    /// Matches Rust update_peers method
    func updatePeers(nodeInfo: RunarNodeInfo) async throws
    
    /// Get local address where transport is bound
    /// Matches Rust get_local_address method
    func getLocalAddress() -> String
    
    /// Subscribe to peer node info updates
    /// Matches Rust subscribe_to_peer_node_info method
    func subscribeToPeerNodeInfo() -> AsyncStream<RunarNodeInfo>
}

/// Protocol for handling incoming messages and peer events
@available(macOS 12.0, iOS 15.0, *)
public protocol MessageHandlerProtocol: AnyObject {
    /// Handle an incoming network message
    func handleMessage(_ message: RunarNetworkMessage)
    
    /// Handle peer connection event
    func peerConnected(_ peerInfo: RunarNodeInfo)
    
    /// Handle peer disconnection event
    func peerDisconnected(_ peerId: String)
}

/// Default implementation for MessageHandlerProtocol
@available(macOS 12.0, iOS 15.0, *)
public class DefaultMessageHandler: MessageHandlerProtocol {
    private weak var transporter: TransportProtocol?
    private let logger: Logger
    
    public init(transporter: TransportProtocol? = nil, logger: Logger) {
        self.transporter = transporter
        self.logger = logger
    }
    
    public func handleMessage(_ message: RunarNetworkMessage) {
        logger.info("📥 [DefaultMessageHandler] Received message - Type: \(message.messageType), From: \(message.sourceNodeId)")
        // Echo RESPONSE for REQUEST to enable end-to-end correlation tests
        if message.messageType == MessageTypes.REQUEST,
           let corr = message.payloads.first?.correlationId {
            let response = RunarNetworkMessage(
                sourceNodeId: message.destinationNodeId,
                destinationNodeId: message.sourceNodeId,
                messageType: MessageTypes.RESPONSE,
                payloads: [
                    NetworkMessagePayloadItem(
                        path: "echo",
                        valueBytes: message.payloads.first?.valueBytes ?? Data(),
                        correlationId: corr
                    )
                ]
            )
            Task { try? await self.transporter?.send(message: response) }
        }
    }
    
    public func peerConnected(_ peerInfo: RunarNodeInfo) {
        logger.info("🔗 [DefaultMessageHandler] Peer connected: \(peerInfo.nodeId)")
    }
    
    public func peerDisconnected(_ peerId: String) {
        logger.info("🔚 [DefaultMessageHandler] Peer disconnected: \(peerId)")
    }
}