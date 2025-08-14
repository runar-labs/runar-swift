import CryptoKit
import Foundation

public enum NodeId {
    /// Compute compact node ID from a public key matching Rust implementation:
    /// - Hash with SHA-256
    /// - Take first 16 bytes
    /// - Encode Base32hex (no padding), lowercase
    public static func compactId(from publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        let first16 = Data(digest.prefix(16))
        return base32hexNoPadLower(first16)
    }

    /// RFC 4648 Base32hex without padding, lowercase
    private static func base32hexNoPadLower(_ data: Data) -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuv")
        var output = ""
        var buffer: UInt32 = 0
        var bitsLeft = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                let index = Int((buffer >> UInt32(bitsLeft - 5)) & 0x1F)
                output.append(alphabet[index])
                bitsLeft -= 5
            }
        }
        if bitsLeft > 0 {
            let index = Int((buffer << UInt32(5 - bitsLeft)) & 0x1F)
            output.append(alphabet[index])
        }
        return output.lowercased()
    }
}
