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
        
        // Take the first 16 bytes and encode as base64url without padding
        let prefix = Data(hash.prefix(16))
        return base64URLEncode(prefix)
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
    private static func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
} 