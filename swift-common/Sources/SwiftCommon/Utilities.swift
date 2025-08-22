import Foundation
import CryptoKit

// MARK: - Compact ID Generation (DNS-safe identifiers)

/// Compact ID generation utilities matching Rust's compact_id function
/// From runar-common/src/lib.rs - generates DNS-safe compact IDs from public keys
public enum CompactId {
    /// Generate a DNS-safe compact ID from public key bytes matching Rust's compact_id
    /// - Input: Public key bytes (SEC1/X9.63 uncompressed format)
    /// - Hash: SHA-256 of public key
    /// - Truncate: First 16 bytes of hash
    /// - Encode: Base32hex (no padding), lowercase
    /// - Output: 26 character DNS-safe identifier
    public static func compactId(from publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        let first16 = Data(digest.prefix(16))
        return base32hexNoPadLower(first16)
    }

    /// RFC 4648 Base32hex without padding, lowercase
    /// Matches Rust's BASE32HEX_NOPAD.encode().to_lowercase()
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
