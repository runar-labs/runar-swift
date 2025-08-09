import Foundation
import Network
import SwiftCommon

@available(macOS 12.0, iOS 15.0, *)
public class PeerState {
    public let peerNodeId: String
    public let address: String
    public let logger: RunarLogger
    public let streamPool: StreamPool
    private var connection: NWConnection?
    private var lastActivity: Date
    private var connectionReadyContinuation: CheckedContinuation<Void, Error>?
    private let queue = DispatchQueue(label: "com.runar.peerstate.", attributes: .concurrent)
    
    public init(peerNodeId: String, address: String, logger: RunarLogger) {
        self.peerNodeId = peerNodeId
        self.address = address
        self.logger = logger
        self.streamPool = StreamPool(logger: logger)
        self.lastActivity = Date()
    }
    
    public var isConnected: Bool {
        queue.sync { connection != nil }
    }
    
    public func setConnection(_ conn: NWConnection) {
        queue.async(flags: .barrier) {
            self.connection = conn
            self.lastActivity = Date()
        }
    }
    
    public func getConnection() -> NWConnection? {
        queue.sync { connection }
    }
    
    public func updateActivity() {
        queue.async(flags: .barrier) { self.lastActivity = Date() }
    }
    
    public func closeConnection() {
        queue.async(flags: .barrier) {
            self.connection?.cancel()
            self.connection = nil
        }
    }
    
    public func setConnectionReadyContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        queue.async(flags: .barrier) {
            self.logger.debug("🔧 [PeerState] Setting connection ready continuation for \(self.peerNodeId)")
            self.connectionReadyContinuation = continuation
        }
    }
    
    public func notifyConnectionReady() {
        queue.async(flags: .barrier) {
            self.logger.debug("🔧 [PeerState] notifyConnectionReady called for \(self.peerNodeId)")
            if let continuation = self.connectionReadyContinuation {
                self.logger.debug("🔧 [PeerState] Resuming connection ready continuation for \(self.peerNodeId)")
                continuation.resume()
                self.connectionReadyContinuation = nil
            } else {
                self.logger.debug("🔧 [PeerState] No connection ready continuation found for \(self.peerNodeId)")
            }
        }
    }
    
    public func notifyConnectionFailed(_ error: Error) {
        queue.async(flags: .barrier) {
            self.logger.debug("🔧 [PeerState] notifyConnectionFailed called for \(self.peerNodeId): \(error)")
            if let continuation = self.connectionReadyContinuation {
                self.logger.debug("🔧 [PeerState] Resuming connection failed continuation for \(self.peerNodeId)")
                continuation.resume(throwing: error)
                self.connectionReadyContinuation = nil
            } else {
                self.logger.debug("🔧 [PeerState] No connection ready continuation found for failure \(self.peerNodeId)")
            }
        }
    }
} 