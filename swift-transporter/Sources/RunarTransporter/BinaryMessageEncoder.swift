import Foundation
import SwiftProtobuf

/// Binary message encoder/decoder for Runar network messages
/// Matches the Rust protobuf implementation for compatibility
@available(macOS 12.0, iOS 15.0, *)
public struct BinaryMessageEncoder {
    // MARK: - Low-level helpers

    private static func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { rawBuffer in
            data.append(rawBuffer.bindMemory(to: UInt8.self))
        }
    }

    private static func appendUInt64BE(_ value: UInt64, to data: inout Data) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { rawBuffer in
            data.append(rawBuffer.bindMemory(to: UInt8.self))
        }
    }

    private static func appendInt64BE(_ value: Int64, to data: inout Data) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { rawBuffer in
            data.append(rawBuffer.bindMemory(to: UInt8.self))
        }
    }
    
    // Safely read a 4-byte big-endian unsigned integer and advance offset
    private static func readUInt32BE(data: Data, offset: inout Int, context: String) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw RunarTransportError.serializationError("Insufficient data for UInt32 in \(context)")
        }
        let value: UInt32 = data.withUnsafeBytes { rawBuf in
            let buf = rawBuf.bindMemory(to: UInt8.self)
            let i = offset
            return (UInt32(buf[i]) << 24) | (UInt32(buf[i + 1]) << 16) | (UInt32(buf[i + 2]) << 8) | UInt32(buf[i + 3])
        }
        offset += 4
        return value
    }
    
    // Safely read an 8-byte big-endian unsigned integer and advance offset
    private static func readUInt64BE(data: Data, offset: inout Int, context: String) throws -> UInt64 {
        guard offset + 8 <= data.count else {
            throw RunarTransportError.serializationError("Insufficient data for UInt64 in \(context)")
        }
        let value: UInt64 = data.withUnsafeBytes { rawBuf in
            let buf = rawBuf.bindMemory(to: UInt8.self)
            let i = offset
            let b0 = UInt64(buf[i])
            let b1 = UInt64(buf[i + 1])
            let b2 = UInt64(buf[i + 2])
            let b3 = UInt64(buf[i + 3])
            let b4 = UInt64(buf[i + 4])
            let b5 = UInt64(buf[i + 5])
            let b6 = UInt64(buf[i + 6])
            let b7 = UInt64(buf[i + 7])
            return (b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) | (b4 << 24) | (b5 << 16) | (b6 << 8) | b7
        }
        offset += 8
        return value
    }
    
    // Safely read an 8-byte big-endian signed integer and advance offset
    private static func readInt64BE(data: Data, offset: inout Int, context: String) throws -> Int64 {
        let u = try readUInt64BE(data: data, offset: &offset, context: context)
        return Int64(bitPattern: u)
    }
    
    // MARK: - Message Encoding
    
    /// Encode a network message to binary format
    /// Matches the Rust NetworkMessage protobuf encoding
    public static func encodeNetworkMessage(_ message: RunarNetworkMessage) throws -> Data {
        // Create a simple binary format that matches the Rust implementation
        // Format: [length:4][source_node_id_length:4][source_node_id][dest_node_id_length:4][dest_node_id][message_type_length:4][message_type][payloads_count:4][payloads...]
        
        var data = Data()
        
        // Helper function to append string with length prefix
        func appendString(_ string: String) {
            let stringData = string.data(using: .utf8) ?? Data()
            BinaryMessageEncoder.appendUInt32BE(UInt32(stringData.count), to: &data)
            data.append(stringData)
        }
        
        // Append source node ID
        appendString(message.sourceNodeId)
        
        // Append destination node ID
        appendString(message.destinationNodeId)
        
        // Append message type
        appendString(message.messageType)
        
        // Append timestamp (as milliseconds since epoch)
        let timestamp = UInt64(message.timestamp.timeIntervalSince1970 * 1000)
        Self.appendUInt64BE(timestamp, to: &data)
        
        // Append payloads count
        Self.appendUInt32BE(UInt32(message.payloads.count), to: &data)
        
        // Append each payload
        for payload in message.payloads {
            try appendPayload(payload, to: &data)
        }
        
        return data
    }
    
    /// Encode a node info to binary format
    /// Matches the Rust NodeInfo protobuf encoding
    public static func encodeNodeInfo(_ nodeInfo: RunarNodeInfo) throws -> Data {
        // Create a simple binary format that matches the Rust implementation
        // Format: [public_key_length:4][public_key][network_ids_count:4][network_ids...][addresses_count:4][addresses...][services_count:4][services...][version:8][created_at:8]
        
        var data = Data()
        
        // Helper function to append string with length prefix
        func appendString(_ string: String) {
            let stringData = string.data(using: .utf8) ?? Data()
            BinaryMessageEncoder.appendUInt32BE(UInt32(stringData.count), to: &data)
            data.append(stringData)
        }
        
        // Helper function to append string array
        func appendStringArray(_ strings: [String]) {
            BinaryMessageEncoder.appendUInt32BE(UInt32(strings.count), to: &data)
            for string in strings { appendString(string) }
        }
        
        // Append public key
        Self.appendUInt32BE(UInt32(nodeInfo.nodePublicKey.count), to: &data)
        data.append(nodeInfo.nodePublicKey)
        
        // Append network IDs
        appendStringArray(nodeInfo.networkIds)
        
        // Append addresses
        appendStringArray(nodeInfo.addresses)
        
        // Append services count
        Self.appendUInt32BE(UInt32(nodeInfo.services.count), to: &data)
        
        // Append each service
        for service in nodeInfo.services {
            try appendServiceMetadata(service, to: &data)
        }
        
        // Append version
        Self.appendInt64BE(Int64(nodeInfo.version), to: &data)
        
        // Append created at timestamp (as milliseconds since epoch)
        let createdAt = UInt64(nodeInfo.createdAt.timeIntervalSince1970 * 1000)
        Self.appendUInt64BE(createdAt, to: &data)
        
        return data
    }
    
    // MARK: - Message Decoding
    
    /// Decode a network message from binary format
    /// Matches the Rust NetworkMessage protobuf decoding
    public static func decodeNetworkMessage(from data: Data) throws -> RunarNetworkMessage {
        var offset = 0
        
        // Helper function to read string with length prefix (bounds-safe, no slicing)
        func readString() throws -> String {
            let length = try readUInt32BE(data: data, offset: &offset, context: "string length")
            if length > 1_000_000 { // sanity guard
                throw RunarTransportError.serializationError("Unreasonable string length: \(length)")
            }
            guard offset + Int(length) <= data.count else {
                throw RunarTransportError.serializationError("Insufficient data for string (need=\(length) have=\(data.count - offset))")
            }
            let start = offset
            let end = offset + Int(length)
            var bytes = Data(count: Int(length))
            bytes.withUnsafeMutableBytes { (mutableBuffer: UnsafeMutableRawBufferPointer) in
                data.copyBytes(to: mutableBuffer, from: start..<end)
            }
            offset = end
            return String(data: bytes, encoding: .utf8) ?? ""
        }
        
        // Read source node ID
        let sourceNodeId = try readString()
        
        // Read destination node ID
        let destinationNodeId = try readString()
        
        // Read message type
        let messageType = try readString()
        
        // Read timestamp (8 bytes, BE)
        let timestampMs = try readUInt64BE(data: data, offset: &offset, context: "timestamp")
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
        
        // Read payloads count
        let payloadsCount = try readUInt32BE(data: data, offset: &offset, context: "payloads count")
        
        // Read payloads
        var payloads: [NetworkMessagePayloadItem] = []
        for _ in 0..<payloadsCount {
            let payload = try readPayload(from: data, offset: &offset)
            payloads.append(payload)
        }
        
        return RunarNetworkMessage(
            sourceNodeId: sourceNodeId,
            destinationNodeId: destinationNodeId,
            messageType: messageType,
            payloads: payloads,
            timestamp: timestamp
        )
    }
    
    /// Decode a node info from binary format
    /// Matches the Rust NodeInfo protobuf decoding
    public static func decodeNodeInfo(from data: Data) throws -> RunarNodeInfo {
        var offset = 0
        
        // Helper function to read string with length prefix (safe, no slicing)
        func readString() throws -> String {
            let length = try readUInt32BE(data: data, offset: &offset, context: "node string length")
            if length > 1_000_000 {
                throw RunarTransportError.serializationError("Unreasonable string length: \(length)")
            }
            guard offset + Int(length) <= data.count else {
                throw RunarTransportError.serializationError("Insufficient data for string (need=\(length) have=\(data.count - offset))")
            }
            let start = offset
            let end = offset + Int(length)
            var bytes = Data(count: Int(length))
            bytes.withUnsafeMutableBytes { destRaw in
                let dest = destRaw.bindMemory(to: UInt8.self)
                data.withUnsafeBytes { srcRaw in
                    let src = srcRaw.bindMemory(to: UInt8.self)
                    if let d = dest.baseAddress, let s = src.baseAddress {
                        memcpy(d, s.advanced(by: start), Int(length))
                    }
                }
            }
            offset = end
            guard let string = String(data: bytes, encoding: .utf8) else {
                throw RunarTransportError.serializationError("Invalid UTF-8 string")
            }
            return string
        }
        
        // Helper function to read string array
        func readStringArray() throws -> [String] {
            let count = try readUInt32BE(data: data, offset: &offset, context: "array count")
            if count > 10_000 { throw RunarTransportError.serializationError("Unreasonable string array count: \(count)") }
            var strings: [String] = []
            strings.reserveCapacity(Int(count))
            for _ in 0..<count {
                let s = try readString()
                strings.append(s)
            }
            return strings
        }
        
        // Read public key
        let keyLength = try readUInt32BE(data: data, offset: &offset, context: "node public key length")
        // Sanity check key length to avoid pathological values
        if keyLength == 0 || keyLength > 10_000 {
            print("[BINDEC] Unreasonable node public key length=\(keyLength), data.count=\(data.count), offset(before slice)=\(offset)")
            throw RunarTransportError.serializationError("Unreasonable node public key length: \(keyLength)")
        }
        
        guard offset + Int(keyLength) <= data.count else {
            print("[BINDEC] Insufficient data for public key: need=\(Int(keyLength)) have=\(data.count - offset) offset=\(offset) data.count=\(data.count)")
            throw RunarTransportError.serializationError("Insufficient data for public key")
        }
        let sliceStart = offset
        let sliceEnd = offset + Int(keyLength)
        print("[BINDEC] Slicing publicKey: start=\(sliceStart) end=\(sliceEnd) total=\(data.count)")
        // Copy bytes explicitly to avoid any potential slicing issues
        var publicKey = Data(count: Int(keyLength))
        publicKey.withUnsafeMutableBytes { destRaw in
            let dest = destRaw.bindMemory(to: UInt8.self)
            data.withUnsafeBytes { srcRaw in
                let src = srcRaw.bindMemory(to: UInt8.self)
                if let d = dest.baseAddress, let s = src.baseAddress {
                    memcpy(d, s.advanced(by: sliceStart), Int(keyLength))
                }
            }
        }
        // Emit a short hex preview for diagnostics
        let previewCount = min(8, publicKey.count)
        let preview = publicKey.prefix(previewCount).map { String(format: "%02x", $0) }.joined()
        print("[BINDEC] publicKey.len=\(publicKey.count) preview=\(preview)")
        offset += Int(keyLength)
        
        // Read network IDs
        _ = offset // silence unused warnings for debug breadcrumbs
        let networkIds = try readStringArray()
        
        // Read addresses
        _ = offset
        let addresses = try readStringArray()
        
        // Read services count
        let servicesCount = try readUInt32BE(data: data, offset: &offset, context: "services count")
        
        // Read services
        var services: [ServiceMetadata] = []
        for _ in 0..<servicesCount {
            let service = try readServiceMetadata(from: data, offset: &offset)
            services.append(service)
        }
        
        // Read version (8 bytes, BE)
        let version = try readInt64BE(data: data, offset: &offset, context: "version")
        
        // Read created at timestamp (8 bytes, BE)
        let createdAtMs = try readUInt64BE(data: data, offset: &offset, context: "created at timestamp")
        let createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1000.0)
        
        return RunarNodeInfo(
            nodePublicKey: publicKey,
            networkIds: networkIds,
            addresses: addresses,
            services: services,
            version: version,
            createdAt: createdAt
        )
    }
    
    // MARK: - Private Helper Methods
    
    private static func appendPayload(_ payload: NetworkMessagePayloadItem, to data: inout Data) throws {
        // Helper function to append string with length prefix
        func appendString(_ string: String) {
            let stringData = string.data(using: .utf8) ?? Data()
            BinaryMessageEncoder.appendUInt32BE(UInt32(stringData.count), to: &data)
            data.append(stringData)
        }
        
        // Append path
        appendString(payload.path)
        
        // Append value bytes
        Self.appendUInt32BE(UInt32(payload.valueBytes.count), to: &data)
        data.append(payload.valueBytes)
        
        // Append correlation ID
        appendString(payload.correlationId)
    }
    
    private static func readPayload(from data: Data, offset: inout Int) throws -> NetworkMessagePayloadItem {
        // Helper function to read string with length prefix (safe)
        func readString() throws -> String {
            let length = try readUInt32BE(data: data, offset: &offset, context: "string length")
            guard offset + Int(length) <= data.count else {
                throw RunarTransportError.serializationError("Insufficient data for string")
            }
            let start = offset
            let end = offset + Int(length)
            var bytes = Data(count: Int(length))
            bytes.withUnsafeMutableBytes { destRaw in
                let dest = destRaw.bindMemory(to: UInt8.self)
                data.copyBytes(to: dest, from: start..<end)
            }
            offset = end
            guard let string = String(data: bytes, encoding: .utf8) else {
                throw RunarTransportError.serializationError("Invalid UTF-8 string")
            }
            return string
        }
        
        // Read path
        let path = try readString()
        
        // Read value bytes
        let valueLength = try readUInt32BE(data: data, offset: &offset, context: "value bytes length")
        
        guard offset + Int(valueLength) <= data.count else {
            throw RunarTransportError.serializationError("Insufficient data for value bytes")
        }
        let valueBytes = data[offset..<(offset + Int(valueLength))]
        offset += Int(valueLength)
        
        // Read correlation ID
        let correlationId = try readString()
        
        return NetworkMessagePayloadItem(
            path: path,
            valueBytes: valueBytes,
            correlationId: correlationId
        )
    }
    
    private static func appendServiceMetadata(_ service: ServiceMetadata, to data: inout Data) throws {
        // Helper function to append string with length prefix
        func appendString(_ string: String) {
            let stringData = string.data(using: .utf8) ?? Data()
            BinaryMessageEncoder.appendUInt32BE(UInt32(stringData.count), to: &data)
            data.append(stringData)
        }
        
        // Helper function to append optional string
        func appendOptionalString(_ string: String?) {
            if let string = string {
                appendString(string)
            } else {
                // Write empty string for nil
                appendString("")
            }
        }
        
        // Helper function to append array
        func appendActionArray(_ actions: [ActionMetadata]) {
            BinaryMessageEncoder.appendUInt32BE(UInt32(actions.count), to: &data)
            for action in actions {
                appendString(action.actionPath)
                appendString(action.actionName)
                appendString(action.description)
                appendOptionalString(action.inputSchema)
                appendOptionalString(action.outputSchema)
            }
        }
        
        func appendEventArray(_ events: [EventMetadata]) {
            BinaryMessageEncoder.appendUInt32BE(UInt32(events.count), to: &data)
            for event in events {
                appendString(event.path)
                appendString(event.description)
                appendOptionalString(event.dataSchema)
            }
        }
        
        // Append service fields
        appendString(service.servicePath)
        appendString(service.networkId)
        appendString(service.serviceName)
        appendString(service.description)
        appendActionArray(service.actions)
        appendEventArray(service.events)
    }
    
    private static func readServiceMetadata(from data: Data, offset: inout Int) throws -> ServiceMetadata {
        // Helper function to read string with length prefix (safe)
        func readString() throws -> String {
            let length = try readUInt32BE(data: data, offset: &offset, context: "string length")
            guard offset + Int(length) <= data.count else {
                throw RunarTransportError.serializationError("Insufficient data for string")
            }
            let start = offset
            let end = offset + Int(length)
            var bytes = Data(count: Int(length))
            bytes.withUnsafeMutableBytes { destRaw in
                let dest = destRaw.bindMemory(to: UInt8.self)
                data.copyBytes(to: dest, from: start..<end)
            }
            offset = end
            guard let string = String(data: bytes, encoding: .utf8) else {
                throw RunarTransportError.serializationError("Invalid UTF-8 string")
            }
            return string
        }
        
        // Helper function to read optional string
        func readOptionalString() throws -> String? {
            let string = try readString()
            return string.isEmpty ? nil : string
        }
        
        // Helper function to read action array
        func readActionArray() throws -> [ActionMetadata] {
            let count = try readUInt32BE(data: data, offset: &offset, context: "actions count")
            
            var actions: [ActionMetadata] = []
            for _ in 0..<count {
                let actionPath = try readString()
                let actionName = try readString()
                let description = try readString()
                let inputSchema = try readOptionalString()
                let outputSchema = try readOptionalString()
                
                actions.append(ActionMetadata(
                    actionPath: actionPath,
                    actionName: actionName,
                    description: description,
                    inputSchema: inputSchema,
                    outputSchema: outputSchema
                ))
            }
            
            return actions
        }
        
        // Helper function to read event array
        func readEventArray() throws -> [EventMetadata] {
            let count = try readUInt32BE(data: data, offset: &offset, context: "events count")
            
            var events: [EventMetadata] = []
            for _ in 0..<count {
                let path = try readString()
                let description = try readString()
                let dataSchema = try readOptionalString()
                
                events.append(EventMetadata(
                    path: path,
                    description: description,
                    dataSchema: dataSchema
                ))
            }
            
            return events
        }
        
        // Read service fields
        let servicePath = try readString()
        let networkId = try readString()
        let serviceName = try readString()
        let description = try readString()
        let actions = try readActionArray()
        let events = try readEventArray()
        
        return ServiceMetadata(
            servicePath: servicePath,
            networkId: networkId,
            serviceName: serviceName,
            description: description,
            actions: actions,
            events: events
        )
    }
} 