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

        // Accept byteString or an array of unsigned ints as bytes
        let nodePublicKey: Data = {
            if case let CBOR.byteString(keyBytes)? = map[str("node_public_key")] {
                return Data(keyBytes)
            }
            if case let CBOR.array(arr)? = map[str("node_public_key")] {
                let bytes = arr.compactMap { item -> UInt8? in
                    if case let CBOR.unsignedInt(u) = item, u <= 0xFF { return UInt8(u) }
                    return nil
                }
                return Data(bytes)
            }
            if case let CBOR.utf8String(s)? = map[str("node_public_key")] {
                return Data(s.utf8)
            }
            return Data()
        }()
        if nodePublicKey.isEmpty {
            throw RunarTransportError.serializationError("Missing node_public_key")
        }

        let networkIds: [String] = if case let CBOR.array(ids)? = map[str("network_ids")] {
            ids.compactMap { if case let CBOR.utf8String(s) = $0 { s } else { nil } }
        } else { [] }

        let addresses: [String] = if case let CBOR.array(addrs)? = map[str("addresses")] {
            addrs.compactMap { if case let CBOR.utf8String(s) = $0 { s } else { nil } }
        } else { [] }

        var services: [ServiceMetadata] = []
        // Rust schema: node_metadata { services: [...], subscriptions: [...] }
        if case let CBOR.map(meta)? = map[str("node_metadata")], case let CBOR.array(svcs)? = meta[str("services")] {
            for svc in svcs {
                guard case let CBOR.map(sm) = svc else { continue }
                let servicePath = (sm[str("service_path")]?.asString) ?? ""
                let networkId = (sm[str("network_id")]?.asString) ?? ""
                let serviceName = (sm[str("name")]?.asString) ?? ""
                let description = (sm[str("description")]?.asString) ?? ""
                let actions: [ActionMetadata] = if case let CBOR.array(act)? = sm[str("actions")] {
                    act.compactMap { a in
                        guard case let CBOR.map(am) = a else { return nil }
                        let ap = (sm[str("service_path")]?.asString) ?? ""
                        let an = (am[str("name")]?.asString) ?? ""
                        let ad = (am[str("description")]?.asString) ?? ""
                        let ins = am[str("input_schema")]?.asString
                        let outs = am[str("output_schema")]?.asString
                        return ActionMetadata(actionPath: ap, actionName: an, description: ad, inputSchema: ins, outputSchema: outs)
                    }
                } else { [] }
                let events: [EventMetadata] = []
                services.append(ServiceMetadata(servicePath: servicePath, networkId: networkId, serviceName: serviceName, description: description, actions: actions, events: events))
            }
        }

        let version: Int64 = if let v = map[str("version")]?.asInt64 { v } else { 0 }
        let createdAt = Date(timeIntervalSince1970: 0)

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
        // Debug: list node_info keys
        if case let CBOR.map(nm) = nodeItem {
            let keys = nm.keys.compactMap { if case let .utf8String(s) = $0 { s } else { nil } }.joined(separator: ",")
            print("[Handshake decode] node_info keys=\(keys)")
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
