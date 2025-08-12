import CryptoKit
import Foundation

public enum NodeId {
    /// Compute compact node ID from a public key as base64url(no padding)
    /// of the first 16 bytes of SHA-256(publicKey).
    public static func compactId(from publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        let first16 = Data(digest.prefix(16))
        return base64urlEncode(first16)
    }

    private static func base64urlEncode(_ data: Data) -> String {
        let b64 = data.base64EncodedString()
        let b64url = b64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return b64url
    }
}
