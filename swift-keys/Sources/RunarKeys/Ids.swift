import Foundation
import CryptoKit

enum Ids {
    static func compactId(_ publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        let first16 = Data(digest.prefix(16))
        return base64url(first16)
    }

    private static func base64url(_ data: Data) -> String {
        let s = data.base64EncodedString()
        return s
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}


