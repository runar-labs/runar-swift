import XCTest
import CryptoKit
@testable import RunarKeys

final class PrimitivesTests: XCTestCase {
    func testCompactId() {
        let key = P256.KeyAgreement.PrivateKey().publicKey
        let id = Ids.compactId(key.x963Representation)
        XCTAssertFalse(id.isEmpty)
    }

    func testECIESRoundTrip() throws {
        let recipient = P256.KeyAgreement.PrivateKey()
        let msg = Data("hello".utf8)
        let ct = try ECIES.encrypt(data: msg, recipientPublicKey: recipient.publicKey)
        let pt = try ECIES.decrypt(encrypted: ct, recipientPrivateKey: recipient)
        XCTAssertEqual(pt, msg)
    }

    func testUserRootStore() throws {
        let secret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        do {
            try UserRootStore.save(secret)
            let loaded = try UserRootStore.load()
            XCTAssertEqual(loaded, secret)
        } catch {
            throw XCTSkip("Keychain not available in this environment: \(error)")
        }
    }
}


