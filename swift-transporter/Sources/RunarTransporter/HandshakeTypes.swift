import Foundation

public enum HandshakeRole: Int, Equatable, Hashable {
    case initiator = 0
    case responder = 1
}

public struct HandshakeData: Equatable, Hashable {
    public let nodeInfo: RunarNodeInfo
    public let nonce: UInt64
    public let role: HandshakeRole

    public init(nodeInfo: RunarNodeInfo, nonce: UInt64, role: HandshakeRole) {
        self.nodeInfo = nodeInfo
        self.nonce = nonce
        self.role = role
    }
}
