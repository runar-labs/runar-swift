import Foundation
import CryptoKit
import SwiftCommon

/// Utility functions for cryptographic operations
public struct CryptoUtils {
    
    /// Generate a compact identifier from public key bytes
    /// This matches the Rust implementation's compact_id function
    /// - Parameter publicKey: Public key bytes
    /// - Returns: Compact identifier string
    public static func compactId(_ publicKey: Data) -> String {
        return NodeId.compactId(from: publicKey)
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
        // Deprecated: use NodeId directly for canonical encoding
        return NodeId.compactId(from: data)
    }
} 