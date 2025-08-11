import Foundation

public enum TransportWireCodec {
    public static func encodeBody(from message: RunarNetworkMessage) throws -> Data {
        let rustType = try MessageTypeMapping.swiftStringToRustU32(message.messageType)
        let payloads: [PayloadWithContext] = message.payloads.map { p in
            PayloadWithContext(path: p.path, valueBytes: p.valueBytes, correlationId: p.correlationId, context: nil)
        }
        return try CborMessageEncoder.encodeNetworkMessageRust(
            sourceNodeId: message.sourceNodeId,
            destinationNodeId: message.destinationNodeId,
            messageTypeU32: rustType,
            payloads: payloads
        )
    }

    public static func decodeBody(to messageData: Data) throws -> RunarNetworkMessage {
        let decoded = try CborMessageDecoder.decodeNetworkMessageRust(from: messageData)
        let messageTypeString = try MessageTypeMapping.toSwiftString(fromRustU32: decoded.messageType)
        let payloads: [NetworkMessagePayloadItem] = decoded.payloads.map { dp in
            NetworkMessagePayloadItem(path: dp.path, valueBytes: dp.valueBytes, correlationId: dp.correlationId)
        }
        return RunarNetworkMessage(
            sourceNodeId: decoded.sourceNodeId,
            destinationNodeId: decoded.destinationNodeId,
            messageType: messageTypeString,
            payloads: payloads
        )
    }
}


