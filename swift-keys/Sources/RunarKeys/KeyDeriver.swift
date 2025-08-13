import Foundation
import CryptoKit

enum KeyDeriver {
    private static let salt = Data("RunarKeyDerivationSalt/v1".utf8)

    static func deriveScalar(master: Data, scope: String, purpose: String, label: String, counterStart: UInt32 = 0) throws -> Data {
        var counter = counterStart
        while true {
            let info = "runar-v1:\(scope):\(purpose):\(label)\(counter == 0 ? "" : ":\(counter)")"
            let infoData = Data(info.utf8)
            let ikm = SymmetricKey(data: master)
            let out = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: infoData, outputByteCount: 32)
            let bytes = out.withUnsafeBytes { Data($0) }
            // P-256 scalar is 32 bytes; accept as-is. If needed, add rejection sampling here.
            return bytes
        }
    }
}


