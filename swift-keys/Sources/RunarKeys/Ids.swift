import Foundation
import CryptoKit

public enum Ids {
    public static func compactId(_ publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        let first16 = Data(digest.prefix(16))
        return base32HexLowerNoPad(first16)
    }

    // RFC 4648 Base32hex alphabet (lowercase), without padding. DNS-safe (letters+digits only).
    private static func base32HexLowerNoPad(_ data: Data) -> String {
        if data.isEmpty { return "" }
        let alphabet = Array("0123456789abcdefghijklmnopqrstuv")
        var output: [Character] = []
        var buffer: UInt32 = 0
        var bitsInBuffer: Int = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bitsInBuffer += 8
            while bitsInBuffer >= 5 {
                let index = Int((buffer >> UInt32(bitsInBuffer - 5)) & 0x1F)
                output.append(alphabet[index])
                bitsInBuffer -= 5
            }
        }
        if bitsInBuffer > 0 {
            let index = Int((buffer << UInt32(5 - bitsInBuffer)) & 0x1F)
            output.append(alphabet[index])
        }
        return String(output)
    }
}


