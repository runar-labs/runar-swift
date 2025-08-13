import XCTest
import CryptoKit
@testable import RunarKeys

final class ProfileNetworkTests: XCTestCase {
    func testProfileDerivationAndEnvelope() throws {
        let root = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let priv = try ProfileKeys.deriveAgreementPrivateKey(userRoot: root, label: "personal")
        let pub = priv.publicKey
        let msg = Data("secret".utf8)
        let ct = try ECIES.encrypt(data: msg, recipientPublicKey: pub)
        let pt = try ECIES.decrypt(encrypted: ct, recipientPrivateKey: priv)
        XCTAssertEqual(pt, msg)
    }

    func testNetworkExportImport() throws {
        let root = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let networkPriv = try NetworkKeys.deriveAgreementPrivateKey(userRoot: root, label: "netA")
        let nodePriv = P256.KeyAgreement.PrivateKey()
        let wrapped = try NetworkKeys.exportWrappedPrivateScalar(networkPriv, to: nodePriv.publicKey)
        let imported = try NetworkKeys.importWrappedPrivateScalar(wrapped, for: nodePriv)
        XCTAssertEqual(imported.rawRepresentation, networkPriv.rawRepresentation)
    }
}


