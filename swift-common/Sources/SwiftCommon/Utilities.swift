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

/// Compact ID generator for general-purpose identifiers
/// Note: For public key-based IDs, use CompactId.compactId() instead
public final class CompactIdGenerator: Sendable {
    private static let charset = "0123456789abcdefghijklmnopqrstuvwxyz"
    private static let charsetCount = UInt8(charset.count)

    /// Generate a compact ID of specified length
    /// - Parameter length: Length of the ID (default: 20)
    /// - Returns: DNS-safe alphanumeric string
    public static func generate(length: Int = 20) -> String {
        var result = ""
        for _ in 0 ..< length {
            let randomIndex = UInt8.random(in: 0 ..< charsetCount)
            let character = charset[charset.index(charset.startIndex, offsetBy: Int(randomIndex))]
            result.append(character)
        }
        return result
    }

    /// Generate a compact ID with prefix
    /// - Parameters:
    ///   - prefix: Prefix to add (e.g., "node", "svc")
    ///   - length: Total length including prefix
    /// - Returns: Prefixed DNS-safe identifier
    public static func generateWithPrefix(_ prefix: String, totalLength: Int = 24) -> String {
        let idLength = totalLength - prefix.count - 1 // -1 for separator
        let id = generate(length: max(4, idLength))
        return "\(prefix)\(id)"
    }

    /// Validate if a string is a valid compact ID (DNS-safe alphanumeric)
    public static func isValidCompactId(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return id.allSatisfy { char in
            char.isASCII && (char.isLowercase || char.isNumber)
        }
    }
}
