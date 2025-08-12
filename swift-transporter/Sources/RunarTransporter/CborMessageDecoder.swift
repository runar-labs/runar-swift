import Foundation
import SwiftCBOR

@available(macOS 12.0, iOS 15.0, *)
public enum CborMessageDecoder {
    public static func decodeNodeInfo(from data: Data) throws -> RunarNodeInfo {
        let itemOpt = try CBORDecoder(input: [UInt8](data)).decodeItem()
        guard let item = itemOpt, case let CBOR.map(map) = item else {
            throw RunarTransportError.serializationError("Invalid CBOR for node_info")
        }
        func str(_ k: String) -> CBOR { .utf8String(k) }

        guard case let CBOR.byteString(keyBytes)? = map[str("node_public_key")] else {
            throw RunarTransportError.serializationError("Missing node_public_key")
        }
        let nodePublicKey = Data(keyBytes)

        let networkIds: [String] = if case let CBOR.array(ids)? = map[str("network_ids")] {
            ids.compactMap { if case let CBOR.utf8String(s) = $0 { s } else { nil } }
        } else { [] }

        let addresses: [String] = if case let CBOR.array(addrs)? = map[str("addresses")] {
            addrs.compactMap { if case let CBOR.utf8String(s) = $0 { s } else { nil } }
        } else { [] }

        var services: [ServiceMetadata] = []
        if case let CBOR.array(svcs)? = map[str("services")] {
            for svc in svcs {
                guard case let CBOR.map(sm) = svc else { continue }
                let servicePath = (sm[str("service_path")]?.asString) ?? ""
                let networkId = (sm[str("network_id")]?.asString) ?? ""
                let serviceName = (sm[str("service_name")]?.asString) ?? ""
                let description = (sm[str("description")]?.asString) ?? ""
                let actions: [ActionMetadata] = if case let CBOR.array(act)? = sm[str("actions")] {
                    act.compactMap { a in
                        guard case let CBOR.map(am) = a else { return nil }
                        let ap = (am[str("action_path")]?.asString) ?? ""
                        let an = (am[str("action_name")]?.asString) ?? ""
                        let ad = (am[str("description")]?.asString) ?? ""
                        let ins = am[str("input_schema")]?.asString
                        let outs = am[str("output_schema")]?.asString
                        return ActionMetadata(actionPath: ap, actionName: an, description: ad, inputSchema: ins, outputSchema: outs)
                    }
                } else { [] }
                let events: [EventMetadata] = if case let CBOR.array(ev)? = sm[str("events")] {
                    ev.compactMap { e in
                        guard case let CBOR.map(em) = e else { return nil }
                        let p = (em[str("path")]?.asString) ?? ""
                        let d = (em[str("description")]?.asString) ?? ""
                        let ds = em[str("data_schema")]?.asString
                        return EventMetadata(path: p, description: d, dataSchema: ds)
                    }
                } else { [] }
                services.append(ServiceMetadata(servicePath: servicePath, networkId: networkId, serviceName: serviceName, description: description, actions: actions, events: events))
            }
        }

        let version: Int64 = if let v = map[str("version")]?.asInt64 { v } else { 0 }
        let createdAtMs = map[str("created_at_ms")]?.asUInt64 ?? 0
        let createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1000.0)

        return RunarNodeInfo(
            nodePublicKey: nodePublicKey,
            networkIds: networkIds,
            addresses: addresses,
            services: services,
            version: version,
            createdAt: createdAt
        )
    }

    public static func decodeHandshake(from data: Data) throws -> HandshakeData {
        let itemOpt = try CBORDecoder(input: [UInt8](data)).decodeItem()
        guard let item = itemOpt, case let CBOR.map(map) = item else {
            throw RunarTransportError.serializationError("Invalid CBOR for handshake")
        }
        func str(_ k: String) -> CBOR { .utf8String(k) }

        guard let nodeItem = map[str("node_info")], case .map = nodeItem else {
            throw RunarTransportError.serializationError("Missing node_info")
        }
        let nodeInfo = try decodeNodeInfo(from: Data(CBOR.encode(nodeItem)))
        let nonce = map[str("nonce")]?.asUInt64 ?? 0
        // Rust serializes role as enum string using serde default ("Initiator"/"Responder")
        let roleStr = map[str("role")]?.asString ?? "Responder"
        let role = roleStr == "Initiator" ? HandshakeRole.initiator : HandshakeRole.responder
        return HandshakeData(nodeInfo: nodeInfo, nonce: nonce, role: role)
    }

    public struct DecodedPayloadWithContext: Equatable {
        public let path: String
        public let valueBytes: Data
        public let correlationId: String
        public let context: MessageContextSwift?
    }

    public struct DecodedNetworkMessageRust: Equatable {
        public let sourceNodeId: String
        public let destinationNodeId: String
        public let messageType: UInt32
        public let payloads: [DecodedPayloadWithContext]
    }

    public static func decodeNetworkMessageRust(from data: Data) throws -> DecodedNetworkMessageRust {
        let itemOpt = try CBORDecoder(input: [UInt8](data)).decodeItem()
        guard let item = itemOpt, case let CBOR.map(map) = item else {
            throw RunarTransportError.serializationError("Invalid CBOR for NetworkMessage")
        }
        func str(_ k: String) -> CBOR { .utf8String(k) }
        let src = map[str("source_node_id")]?.asString ?? ""
        let dst = map[str("destination_node_id")]?.asString ?? ""
        let msgType = UInt32(map[str("message_type")]?.asUInt64 ?? 0)
        var payloads: [DecodedPayloadWithContext] = []
        if case let CBOR.array(arr)? = map[str("payloads")] {
            for it in arr {
                guard case let CBOR.map(pm) = it else { continue }
                let path = pm[str("path")]?.asString ?? ""
                let valueBytes = if case let CBOR.byteString(vb)? = pm[str("value_bytes")] { Data(vb) } else { Data() }
                let correlationId = pm[str("correlation_id")]?.asString ?? ""
                var ctx: MessageContextSwift? = nil
                if case let CBOR.map(cm)? = pm[str("context")] {
                    if case let CBOR.byteString(pk)? = cm[str("profile_public_key")] {
                        ctx = MessageContextSwift(profilePublicKey: Data(pk))
                    }
                }
                payloads.append(DecodedPayloadWithContext(path: path, valueBytes: valueBytes, correlationId: correlationId, context: ctx))
            }
        }
        return DecodedNetworkMessageRust(sourceNodeId: src, destinationNodeId: dst, messageType: msgType, payloads: payloads)
    }
}

private extension CBOR {
    var asString: String? { if case let .utf8String(s) = self { s } else { nil } }
    var asUInt64: UInt64? { if case let .unsignedInt(u) = self { u } else { nil } }
    var asInt64: Int64? {
        switch self {
        case let .negativeInt(n): -Int64(bitPattern: n + 1)
        case let .unsignedInt(u): Int64(bitPattern: u)
        default: nil
        }
    }
}
