import XCTest
import CryptoKit
@testable import RunarKeys

final class MultiRecipientEnvelopeTests: XCTestCase {
    func testMultiRecipientRoundTrip() throws {
        let profile = P256.KeyAgreement.PrivateKey()
        let node = P256.KeyAgreement.PrivateKey()
        let message = Data("hello multi".utf8)

        let env = try MultiRecipientEnvelope.encrypt(data: message, recipients: [
            "profile": profile.publicKey,
            "network": node.publicKey,
        ])

        let nodePT = try MultiRecipientEnvelope.decrypt(env, recipientLabel: "network", recipientPrivateKey: node)
        XCTAssertEqual(nodePT, message)

        let mobilePT = try MultiRecipientEnvelope.decrypt(env, recipientLabel: "profile", recipientPrivateKey: profile)
        XCTAssertEqual(mobilePT, message)
    }

    func testMissingRecipientFails() throws {
        let onlyOne = P256.KeyAgreement.PrivateKey()
        let message = Data("x".utf8)
        let env = try MultiRecipientEnvelope.encrypt(data: message, recipients: [
            "only": onlyOne.publicKey
        ])
        XCTAssertThrowsError(try MultiRecipientEnvelope.decrypt(env, recipientLabel: "missing", recipientPrivateKey: onlyOne))
    }
}


