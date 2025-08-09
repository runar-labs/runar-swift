import Foundation
import CryptoKit

/// Utility functions for cryptographic operations
public struct CryptoUtils {
    
    /// Generate a compact identifier from public key bytes
    /// This matches the Rust implementation's compact_id function
    /// - Parameter publicKey: Public key bytes
    /// - Returns: Compact identifier string
    public static func compactId(_ publicKey: Data) -> String {
        // Create a hash of the public key
        let hash = SHA256.hash(data: publicKey)
        
        // Take the first 8 bytes and encode as base58
        let prefix = Data(hash.prefix(8))
        return base58Encode(prefix)
    }
    
    /// Generate a random identifier
    /// - Parameter prefix: Prefix for the identifier
    /// - Returns: Random identifier string
    public static func generateRandomId(prefix: String = "id") -> String {
        let randomBytes = (0..<8).map { _ in UInt8.random(in: 0...255) }
        let randomData = Data(randomBytes)
        let randomString = randomData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "=", with: "")
            .prefix(12)
        
        return "\(prefix)-\(randomString)"
    }
    
    // MARK: - Private Helper Methods
    
    /// Simple base58 encoding (simplified implementation)
    /// - Parameter data: Data to encode
    /// - Returns: Base58 encoded string
    private static func base58Encode(_ data: Data) -> String {
        let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        var bytes = [UInt8](data)
        var result = ""
        
        while bytes.count > 0 {
            var remainder = 0
            var newBytes: [UInt8] = []
            
            for byte in bytes {
                remainder = remainder * 256 + Int(byte)
                if remainder >= 58 {
                    newBytes.append(UInt8(remainder / 58))
                    remainder %= 58
                } else if !newBytes.isEmpty {
                    newBytes.append(0)
                }
            }
            
            result = String(alphabet[alphabet.index(alphabet.startIndex, offsetBy: remainder)]) + result
            bytes = newBytes
        }
        
        return result
    }
} 