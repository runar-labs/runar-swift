import Foundation

/// Stream correlation tracking for request-response pairs
@available(macOS 12.0, iOS 15.0, *)
public struct StreamCorrelation {
    public let peerNodeId: String
    public let streamId: UInt64
    public let correlationId: String
    public let createdAt: Date

    public init(peerNodeId: String, streamId: UInt64, correlationId: String) {
        self.peerNodeId = peerNodeId
        self.streamId = streamId
        self.correlationId = correlationId
        createdAt = Date()
    }
}
