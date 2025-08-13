import XCTest
import CryptoKit
import Security
@testable import RunarKeys
import X509

final class KeychainCSRPoCTests: XCTestCase {
    func testKeychainFirstP384CSRPOC() throws {
        let nodeId = "poc-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let keyLabel = "Runar POC Key \(nodeId)"
        let appTag = Data(("com.runar.keys.poc." + nodeId).utf8)

        // Generate EC P-384 key pair in Keychain (software token)
        var secPublicKeyRef: SecKey?
        let privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: appTag,
            kSecAttrLabel as String: keyLabel,
        ]
        let genParams: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 384,
            kSecPrivateKeyAttrs as String: privateAttrs,
        ]
        // Prefer SecKeyCreateRandomKey for private key and derive public via copy attributes
        var genError: Unmanaged<CFError>?
        guard let secPrivateKey = SecKeyCreateRandomKey(genParams as CFDictionary, &genError) else {
            return XCTFail("SecKeyCreateRandomKey failed: \(genError?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        secPublicKeyRef = SecKeyCopyPublicKey(secPrivateKey)
        guard let secPublicKey = secPublicKeyRef else { return XCTFail("Failed to copy public key") }

        // Export public key in x963 (uncompressed) to use as node public key
        var pubErr: Unmanaged<CFError>?
        guard let publicKeyBytes = SecKeyCopyExternalRepresentation(secPublicKey, &pubErr) as Data? else {
            return XCTFail("Export public key failed: \(pubErr?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        XCTAssertEqual(publicKeyBytes.first, 0x04, "Expected uncompressed x963 public key")
        XCTAssertEqual(publicKeyBytes.count, 97, "Expected P-384 uncompressed public key length")

        // Export private key external representation and extract 48-byte scalar
        var privErr: Unmanaged<CFError>?
        guard let privExternal = SecKeyCopyExternalRepresentation(secPrivateKey, &privErr) as Data? else {
            return XCTFail("Export private key failed: \(privErr?.takeRetainedValue().localizedDescription ?? "Unknown")")
        }
        // Debug: inspect header to understand provider format
        let debugHead = privExternal.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        print("privExternal len=\(privExternal.count) head=\(debugHead)")
        let signingScalar: Data
        if privExternal.count >= 48 && privExternal.first != 0x30 {
            signingScalar = Data(privExternal.suffix(48))
        } else if let parsed = extractP384PrivateScalar(fromECPrivateKeyExternal: privExternal) {
            signingScalar = parsed
        } else {
            return XCTFail("Failed to extract P-384 private scalar from SecKey external representation")
        }
        XCTAssertEqual(signingScalar.count, 48)

        // Build CryptoKit signer from scalar and sign/verify a message
        let signer = try P384.Signing.PrivateKey(rawRepresentation: signingScalar)
        let message = Data("hello-runar".utf8)
        let signature = try signer.signature(for: message)
        XCTAssertTrue(signer.publicKey.isValidSignature(signature, for: message))

        // Build CSR using our ECDHKeyPair wrapper (same 48-byte scalar)
        let ecdhKeyForCsr = try ECDHKeyPair(rawRepresentation: signingScalar)
        let subjectCN = dnsSafeName(nodeId)
        let subject = "CN=\(subjectCN),O=Runar,C=US"
        let csrDer = try CertificateRequest.create(keyPair: ecdhKeyForCsr, subject: subject)
        XCTAssertFalse(csrDer.isEmpty)

        // Parse CSR and validate CN constraint
        let csr = try CertificateRequest(derData: csrDer)
        XCTAssertTrue(csr.subject.contains("CN=\(subjectCN)"))

        // Cleanup: delete generated key from keychain
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: keyLabel,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    // MARK: - Helpers (POC-local copy)

    private func dnsSafeName(_ input: String) -> String {
        let lowered = input.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        let filtered = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var result = String(filtered)
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "node" : result
    }

    private func extractP384PrivateScalar(fromECPrivateKeyExternal data: Data) -> Data? {
        if data.count >= 48 && data.count <= 64 && data[0] != 0x30 {
            return Data(data.suffix(48))
        }
        guard data.count > 0, data[0] == 0x30 else { return nil }
        var idx = 1
        func readLen() -> Int? {
            guard idx < data.count else { return nil }
            let first = Int(data[idx]); idx += 1
            if first < 0x80 { return first }
            let num = first & 0x7F
            guard num > 0, idx + num <= data.count else { return nil }
            var val = 0
            for _ in 0..<num { val = (val << 8) | Int(data[idx]); idx += 1 }
            return val
        }
        func readTLV() -> (UInt8, Data)? {
            guard idx < data.count else { return nil }
            let tag = data[idx]; idx += 1
            guard let length = readLen(), idx + length <= data.count else { return nil }
            let val = data[idx..<(idx + length)]
            idx += length
            return (tag, Data(val))
        }
        _ = readLen()
        let savedIdx = idx
        guard let (tag1, v1) = readTLV(), tag1 == 0x02 else { return nil }
        if v1.count == 1, v1[0] == 0x00 {
            guard let (algTag, _) = readTLV(), algTag == 0x30 else { return nil }
            guard let (octTag, octVal) = readTLV(), octTag == 0x04 else { return nil }
            guard octVal.count > 0, octVal[0] == 0x30 else { return nil }
            var jdx = 1
            func rdLen(_ buf: Data, _ pos: inout Int) -> Int? {
                guard pos < buf.count else { return nil }
                let first = Int(buf[pos]); pos += 1
                if first < 0x80 { return first }
                let num = first & 0x7F
                guard num > 0, pos + num <= buf.count else { return nil }
                var val = 0
                for _ in 0..<num { val = (val << 8) | Int(buf[pos]); pos += 1 }
                return val
            }
            _ = rdLen(octVal, &jdx)
            guard jdx < octVal.count, octVal[jdx] == 0x02 else { return nil }
            jdx += 1; _ = rdLen(octVal, &jdx); jdx += 1
            guard jdx < octVal.count, octVal[jdx] == 0x04 else { return nil }
            jdx += 1
            guard let pl = rdLen(octVal, &jdx), jdx + pl <= octVal.count else { return nil }
            let scalar = octVal[jdx..<(jdx + pl)]
            return Data(scalar.count == 48 ? Data(scalar) : Data(scalar.suffix(48)))
        }
        idx = savedIdx
        guard let (tVer, vVer) = readTLV(), tVer == 0x02 else { return nil }
        _ = vVer
        guard let (tOct, vOct) = readTLV(), tOct == 0x04 else { return nil }
        return Data(vOct.count == 48 ? vOct : Data(vOct.suffix(48)))
    }
}


