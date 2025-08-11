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
        map[.utf8String("services")] = .array(nodeInfo.services.map { service in
            var s: [CBOR: CBOR] = [:]
            s[.utf8String("service_path")] = .utf8String(service.servicePath)
            s[.utf8String("network_id")] = .utf8String(service.networkId)
            s[.utf8String("service_name")] = .utf8String(service.serviceName)
            s[.utf8String("description")] = .utf8String(service.description)
            s[.utf8String("actions")] = .array(service.actions.map { action in
                var a: [CBOR: CBOR] = [:]
                a[.utf8String("action_path")] = .utf8String(action.actionPath)
                a[.utf8String("action_name")] = .utf8String(action.actionName)
                a[.utf8String("description")] = .utf8String(action.description)
                if let input = action.inputSchema { a[.utf8String("input_schema")] = .utf8String(input) }
                if let output = action.outputSchema { a[.utf8String("output_schema")] = .utf8String(output) }
                return .map(a)
            })
            s[.utf8String("events")] = .array(service.events.map { event in
                var e: [CBOR: CBOR] = [:]
                e[.utf8String("path")] = .utf8String(event.path)
                e[.utf8String("description")] = .utf8String(event.description)
                if let schema = event.dataSchema { e[.utf8String("data_schema")] = .utf8String(schema) }
                return .map(e)
            })
            return .map(s)
        })
        // version is Int64; encode as CBOR integer
        map[.utf8String("version")] = CBOR(integerLiteral: Int(truncatingIfNeeded: nodeInfo.version))
        map[.utf8String("created_at_ms")] = .unsignedInt(UInt64(nodeInfo.createdAt.timeIntervalSince1970 * 1000))
        return Data(CBOR.map(map).encode())
    }
}


