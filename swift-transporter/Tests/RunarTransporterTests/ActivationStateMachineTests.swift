@testable import RunarTransporter
import XCTest

final class ActivationStateMachineTests: XCTestCase {
    func testActivationNotifiesOnceAndIsIdempotent() {
        let sm = ActivationStateMachine()
        var calls: [Bool] = []
        sm.subscribe { calls.append($0) }
        XCTAssertTrue(calls.isEmpty)
        sm.activate()
        XCTAssertEqual(calls, [true])
        sm.activate()
        XCTAssertEqual(calls, [true]) // still one call
        XCTAssertTrue(sm.active())
    }

    func testLateSubscriberReceivesImmediateTrue() {
        let sm = ActivationStateMachine()
        sm.activate()
        var received: Bool?
        sm.subscribe { received = $0 }
        XCTAssertEqual(received, true)
    }
}
