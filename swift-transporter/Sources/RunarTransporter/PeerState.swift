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
    private let activation = ActivationStateMachine()
    private static var idSeq: Int = 0
    private let connectionId: Int
    // Duplicate-resolution metadata (mirrors Rust fields at a high level)
    private(set) var initiatorPeerId: String = ""
    private(set) var initiatorNonce: UInt64 = 0
    private(set) var responderPeerId: String = ""
    private(set) var responderNonce: UInt64 = 0

    public init(peerNodeId: String, address: String, logger: RunarLogger) {
        self.peerNodeId = peerNodeId
        self.address = address
        self.logger = logger
        streamPool = StreamPool(logger: logger)
        lastActivity = Date()
        PeerState.idSeq += 1
        connectionId = PeerState.idSeq
    }

    public var isConnected: Bool {
        queue.sync { activation.active() }
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

    public func hasConnection(_ conn: NWConnection) -> Bool {
        queue.sync { connection === conn }
    }

    public func getConnectionId() -> Int { connectionId }

    public func hasConnectionToEndpoint(_ endpoint: String) -> Bool {
        queue.sync {
            address == endpoint
        }
    }

    public func hasConnectionToIPAddress(_ ipAddress: String) -> Bool {
        queue.sync {
            // Extract IP address from the stored address (which might include port)
            if let colonRange = address.range(of: ":") {
                let storedIP = String(address[..<colonRange.lowerBound])
                return storedIP == ipAddress
            }
            return address == ipAddress
        }
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

    public func activate() {
        activation.activate()
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

    public func setDupMetadata(initiatorPeerId: String, initiatorNonce: UInt64, responderPeerId: String, responderNonce: UInt64) {
        queue.async(flags: .barrier) {
            self.initiatorPeerId = initiatorPeerId
            self.initiatorNonce = initiatorNonce
            self.responderPeerId = responderPeerId
            self.responderNonce = responderNonce
        }
    }
}
