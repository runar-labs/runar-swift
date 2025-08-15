import Foundation
import Network
import SwiftCommon

/// Thread-safe connection pool for managing active peer connections
@available(macOS 12.0, iOS 15.0, *)
public class ConnectionPool {
    private let queue = DispatchQueue(label: "com.runar.connectionpool", attributes: .concurrent)
    private var peers: [String: PeerState] = [:]

    public init() {}

    public func getOrCreatePeer(peerId: String, address: String, logger: RunarLogger) -> PeerState {
        queue.sync(flags: .barrier) {
            if let existing = peers[peerId] {
                logger.debug("🔍 [ConnectionPool] Found existing peer \(peerId)")
                return existing
            } else {
                logger.info("➕ [ConnectionPool] Creating new peer \(peerId) at \(address)")
                let peer = PeerState(peerNodeId: peerId, address: address, logger: logger)
                peers[peerId] = peer
                return peer
            }
        }
    }

    public func getPeer(peerId: String) -> PeerState? {
        queue.sync { peers[peerId] }
    }

    public func removePeer(peerId: String) {
        queue.async(flags: .barrier) {
            if let removed = self.peers.removeValue(forKey: peerId) {
                // Remove any aliases pointing to the same PeerState instance
                let keysToRemove = self.peers.compactMap { (key: String, value: PeerState) in
                    value === removed ? key : nil
                }
                for key in keysToRemove {
                    self.peers.removeValue(forKey: key)
                }
            }
        }
    }

    public func isPeerConnected(peerId: String) -> Bool {
        queue.sync { peers[peerId]?.isConnected ?? false }
    }

    public func getConnectedPeers() -> [String] {
        queue.sync { Array(peers.keys) }
    }

    /// Create an alias mapping so that another identifier points to the same peer state
    public func aliasPeer(existingId: String, aliasId: String) {
        queue.async(flags: .barrier) {
            if let state = self.peers[existingId] {
                self.peers[aliasId] = state
            }
        }
    }

    /// Get all peer states for iteration
    public func getAllPeers() -> [String: PeerState] {
        queue.sync { peers }
    }

    /// Check if we have a connection to a specific endpoint
    public func hasConnectionToEndpoint(_ endpoint: String) -> Bool {
        queue.sync {
            for (_, peerState) in peers {
                if peerState.hasConnectionToEndpoint(endpoint) {
                    return true
                }
            }
            return false
        }
    }

    public func hasConnectionToIPAddress(_ ipAddress: String) -> Bool {
        queue.sync {
            for (_, peerState) in peers {
                if peerState.hasConnectionToIPAddress(ipAddress) {
                    return true
                }
            }
            return false
        }
    }

    /// Check if any peer has a specific connection
    public func hasPeerWithConnection(_ connection: NWConnection) -> Bool {
        queue.sync {
            for (_, peerState) in peers {
                if peerState.hasConnection(connection) {
                    return true
                }
            }
            return false
        }
    }
    
    /// Check if we have a connection to a specific peer ID
    public func hasConnection(to peerId: String) -> Bool {
        queue.sync { peers[peerId]?.isConnected ?? false }
    }
}
