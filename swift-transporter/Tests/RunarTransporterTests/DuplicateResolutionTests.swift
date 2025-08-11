import XCTest
@testable import RunarTransporter

final class DuplicateResolutionTests: XCTestCase {
    func testDesiredLocalRole() {
        XCTAssertEqual(DuplicateResolution.desiredLocalRole(localId: "a", peerId: "b"), .initiator)
        XCTAssertEqual(DuplicateResolution.desiredLocalRole(localId: "z", peerId: "b"), .responder)
        XCTAssertEqual(DuplicateResolution.desiredLocalRole(localId: "abc", peerId: "abc"), .responder)
    }

    func testPlaceholderReplacement() {
        let existing = PeerStateLite(connectionId: 10, initiatorPeerId: "X", initiatorNonce: 0, responderPeerId: "Y", responderNonce: 0)
        let pick = DuplicateResolution.shouldPickCandidate(
            localId: "L",
            peerId: "P",
            existing: existing,
            candidateConnectionId: 5,
            candidateInitiatorPeerId: "L",
            candidateInitiatorNonce: 1,
            candidateResponderPeerId: "P",
            candidateResponderNonce: 2
        )
        XCTAssertTrue(pick)
    }

    func testRoleBasedSelection() {
        let local = "L"
        let peer = "P"
        // desired role depends on string compare; ensure deterministic
        let existing = PeerStateLite(connectionId: 10, initiatorPeerId: peer, initiatorNonce: 7, responderPeerId: local, responderNonce: 9)
        let candidatePick = DuplicateResolution.shouldPickCandidate(
            localId: local,
            peerId: peer,
            existing: existing,
            candidateConnectionId: 9,
            candidateInitiatorPeerId: local,
            candidateInitiatorNonce: 11,
            candidateResponderPeerId: peer,
            candidateResponderNonce: 12
        )
        // If desired local role is initiator, candidate (local as initiator) should be preferred unless existing also matches and has lower id.
        // With equal desired roles, lower connection id wins; here candidate id 9 < 10 so true.
        XCTAssertTrue(candidatePick)
    }

    func testTieBreakerStableId() {
        let local = "a"
        let peer = "zz"
        // desired initiator because a < zz
        let existing = PeerStateLite(connectionId: 100, initiatorPeerId: local, initiatorNonce: 1, responderPeerId: peer, responderNonce: 2)
        // candidate also initiator; lower id loses/ wins? Rust picks lower stable_id to avoid flapping → pick candidate if id < existing
        let pickLower = DuplicateResolution.shouldPickCandidate(
            localId: local,
            peerId: peer,
            existing: existing,
            candidateConnectionId: 50,
            candidateInitiatorPeerId: local,
            candidateInitiatorNonce: 3,
            candidateResponderPeerId: peer,
            candidateResponderNonce: 4
        )
        XCTAssertTrue(pickLower)

        let pickHigher = DuplicateResolution.shouldPickCandidate(
            localId: local,
            peerId: peer,
            existing: existing,
            candidateConnectionId: 150,
            candidateInitiatorPeerId: local,
            candidateInitiatorNonce: 5,
            candidateResponderPeerId: peer,
            candidateResponderNonce: 6
        )
        XCTAssertFalse(pickHigher)
    }
}


