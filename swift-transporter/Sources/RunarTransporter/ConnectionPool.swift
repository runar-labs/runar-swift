import Foundation
import SwiftCommon

/// Thread-safe connection pool for managing active peer connections
@available(macOS 12.0, iOS 15.0, *)
public class ConnectionPool {
    private let queue = DispatchQueue(label: "com.runar.connectionpool", attributes: .concurrent)
    private var peers: [String: PeerState] = [:]
    
    public init() {}
    
    public func getOrCreatePeer(peerId: String, address: String, logger: RunarLogger) -> PeerState {
        return queue.sync(flags: .barrier) {
            if let existing = peers[peerId] {
                return existing
            } else {
                let peer = PeerState(peerNodeId: peerId, address: address, logger: logger)
                peers[peerId] = peer
                return peer
            }
        }
    }
    
    public func getPeer(peerId: String) -> PeerState? {
        return queue.sync { peers[peerId] }
    }
    
    public func removePeer(peerId: String) {
        queue.async(flags: .barrier) { self.peers.removeValue(forKey: peerId) }
    }
    
    public func isPeerConnected(peerId: String) -> Bool {
        return queue.sync { peers[peerId]?.isConnected ?? false }
    }
    
    public func getConnectedPeers() -> [String] {
        return queue.sync { Array(peers.keys) }
    }
} 