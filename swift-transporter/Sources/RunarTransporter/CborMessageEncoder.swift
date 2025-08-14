import Foundation
import SwiftCBOR

@available(macOS 12.0, iOS 15.0, *)
public enum CborMessageEncoder {
    // MARK: - Encoding

    public static func encodeNetworkMessage(_ message: RunarNetworkMessage) throws -> Data {
        // Map to CBOR structure matching Rust: a CBOR map with specific keys
        // Keys follow snake_case to align with Rust field names
        var cborMap: [CBOR: CBOR] = [:]
        cborMap[.utf8String("source_node_id")] = .utf8String(message.sourceNodeId)
        cborMap[.utf8String("destination_node_id")] = .utf8String(message.destinationNodeId)
        // messageType in current Swift is String; Rust expects u32. Try to parse numeric, fallback to 0
        let mt = UInt64(message.messageType) ?? 0
        cborMap[.utf8String("message_type")] = .unsignedInt(mt)
        cborMap[.utf8String("timestamp_ms")] = .unsignedInt(UInt64(message.timestamp.timeIntervalSince1970 * 1000))
        cborMap[.utf8String("payloads")] = .array(message.payloads.map { payload in
            var item: [CBOR: CBOR] = [:]
            item[.utf8String("path")] = .utf8String(payload.path)
            item[.utf8String("value_bytes")] = .byteString([UInt8](payload.valueBytes))
            item[.utf8String("correlation_id")] = .utf8String(payload.correlationId)
            return .map(item)
        })

        let cbor = CBOR.map(cborMap)
        return Data(cbor.encode())
    }

    public static func encodeNodeInfo(_ nodeInfo: RunarNodeInfo) throws -> Data {
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("node_public_key")] = .byteString([UInt8](nodeInfo.nodePublicKey))
        map[.utf8String("network_ids")] = .array(nodeInfo.networkIds.map { .utf8String($0) })
        map[.utf8String("addresses")] = .array(nodeInfo.addresses.map { .utf8String($0) })
        // Rust expects node_metadata { services: [], subscriptions: [] }
        var nodeMeta: [CBOR: CBOR] = [:]
        // Map our services into Rust ServiceMetadata shape minimally
        let services = nodeInfo.services.map { service -> CBOR in
            var s: [CBOR: CBOR] = [:]
            s[.utf8String("network_id")] = .utf8String(service.networkId)
            s[.utf8String("service_path")] = .utf8String(service.servicePath)
            s[.utf8String("name")] = .utf8String(service.serviceName)
            s[.utf8String("version")] = .utf8String("1.0.0")
            s[.utf8String("description")] = .utf8String(service.description)
            s[.utf8String("actions")] = .array(service.actions.map { action in
                var a: [CBOR: CBOR] = [:]
                a[.utf8String("name")] = .utf8String(action.actionName)
                a[.utf8String("description")] = .utf8String(action.description)
                if let input = action.inputSchema { a[.utf8String("input_schema")] = .utf8String(input) }
                if let output = action.outputSchema { a[.utf8String("output_schema")] = .utf8String(output) }
                return .map(a)
            })
            s[.utf8String("registration_time")] = .unsignedInt(UInt64(nodeInfo.createdAt.timeIntervalSince1970))
            s[.utf8String("last_start_time")] = .null
            return .map(s)
        }
        nodeMeta[.utf8String("services")] = .array(services)
        nodeMeta[.utf8String("subscriptions")] = .array([])
        map[.utf8String("node_metadata")] = .map(nodeMeta)
        map[.utf8String("version")] = CBOR(integerLiteral: Int(truncatingIfNeeded: nodeInfo.version))
        return Data(CBOR.map(map).encode())
    }

    public static func encodeHandshake(_ hs: HandshakeData) throws -> Data {
        var map: [CBOR: CBOR] = [:]
        // Build node_info map inline to avoid accidental wrapping
        var nodeMap: [CBOR: CBOR] = [:]
        nodeMap[.utf8String("node_public_key")] = .byteString([UInt8](hs.nodeInfo.nodePublicKey))
        nodeMap[.utf8String("network_ids")] = .array(hs.nodeInfo.networkIds.map { .utf8String($0) })
        nodeMap[.utf8String("addresses")] = .array(hs.nodeInfo.addresses.map { .utf8String($0) })
        var nodeMeta: [CBOR: CBOR] = [:]
        nodeMeta[.utf8String("services")] = .array([])
        nodeMeta[.utf8String("subscriptions")] = .array([])
        nodeMap[.utf8String("node_metadata")] = .map(nodeMeta)
        nodeMap[.utf8String("version")] = CBOR(integerLiteral: Int(truncatingIfNeeded: hs.nodeInfo.version))
        map[.utf8String("node_info")] = .map(nodeMap)
        map[.utf8String("nonce")] = .unsignedInt(hs.nonce)
        let roleStr = hs.role == .initiator ? "Initiator" : "Responder"
        map[.utf8String("role")] = .utf8String(roleStr)
        return Data(CBOR.map(map).encode())
    }

    public static func encodePayloadWithContext(_ p: PayloadWithContext) throws -> Data {
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("path")] = .utf8String(p.path)
        map[.utf8String("value_bytes")] = .byteString([UInt8](p.valueBytes))
        if let ctx = p.context {
            map[.utf8String("context")] = .map([.utf8String("profile_public_key"): .byteString([UInt8](ctx.profilePublicKey))])
        }
        map[.utf8String("correlation_id")] = .utf8String(p.correlationId)
        return Data(CBOR.map(map).encode())
    }

    // Encode full NetworkMessage aligned with Rust schema
    public static func encodeNetworkMessageRust(
        sourceNodeId: String,
        destinationNodeId: String,
        messageTypeU32: UInt32,
        payloads: [PayloadWithContext]
    ) throws -> Data {
        var map: [CBOR: CBOR] = [:]
        map[.utf8String("source_node_id")] = .utf8String(sourceNodeId)
        map[.utf8String("destination_node_id")] = .utf8String(destinationNodeId)
        map[.utf8String("message_type")] = .unsignedInt(UInt64(messageTypeU32))
        map[.utf8String("payloads")] = .array(payloads.map { p in
            var pm: [CBOR: CBOR] = [:]
            pm[.utf8String("path")] = .utf8String(p.path)
            pm[.utf8String("value_bytes")] = .byteString([UInt8](p.valueBytes))
            if let ctx = p.context {
                pm[.utf8String("context")] = .map([
                    .utf8String("profile_public_key"): .byteString([UInt8](ctx.profilePublicKey)),
                ])
            }
            pm[.utf8String("correlation_id")] = .utf8String(p.correlationId)
            return .map(pm)
        })
        return Data(CBOR.map(map).encode())
    }
}
