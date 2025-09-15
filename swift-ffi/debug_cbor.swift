import Foundation
import SwiftCBOR

struct NodeMetadata: Codable {
    var services: [Empty]
    var subscriptions: [Empty]
}

struct Empty: Codable {
}

struct NodeInfo: Codable {
    var nodePublicKey: Data
    var networkIds: [String]
    var addresses: [String]
    var nodeMetadata: NodeMetadata
    var version: Int64
}

let nodeInfo = NodeInfo(
    nodePublicKey: Data(),
    networkIds: [],
    addresses: [],
    nodeMetadata: NodeMetadata(services: [], subscriptions: []),
    version: 0
)

do {
    let nodeInfoData = try CodableCBOREncoder().encode(nodeInfo)
    print("CBOR data length: \(nodeInfoData.count)")
    print("CBOR data: \(nodeInfoData.map { String(format: "%02x", $0) }.joined(separator: " "))")
    
    // Try to decode it back
    let decoded = try CodableCBORDecoder().decode(NodeInfo.self, from: nodeInfoData)
    print("Decoded successfully: \(decoded)")
} catch {
    print("Error: \(error)")
}




