import Foundation

public enum Framing {
    /// Encode payload with 4-byte big-endian length prefix
    public static func encodeFrame(_ payload: Data) -> Data {
        var data = Data()
        var len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &len) { raw in data.append(raw.bindMemory(to: UInt8.self)) }
        data.append(payload)
        return data
    }

    /// Decode as many complete frames from buffer as possible; leaves any partial data in buffer
    public static func decodeFrames(_ buffer: inout Data, maxSize: Int = 1_048_576) -> [Data] {
        var frames: [Data] = []
        while buffer.count >= 4 {
            let lenBytes = Array(buffer.prefix(4))
            let len = (UInt32(lenBytes[0]) << 24) | (UInt32(lenBytes[1]) << 16) | (UInt32(lenBytes[2]) << 8) | UInt32(lenBytes[3])
            let needed = 4 + Int(len)
            if len == 0 || needed > maxSize + 4 { // invalid length; drop 4 bytes and continue
                buffer.removeFirst(4)
                continue
            }
            guard buffer.count >= needed else { break }
            let payload = buffer.subdata(in: 4..<needed)
            frames.append(payload)
            buffer.removeFirst(needed)
        }
        return frames
    }
}


