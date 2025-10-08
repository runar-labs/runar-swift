GOAL indeitify all issues realate to remove action calls - test swift-node/Tests/SwiftNodeTests/RemoteNetworkTests.swift - testRemoteActionCall()

Process:
 1) INSPECT LOGS IN DETAILS AND COMPARE TO THE RUST LOGS OF THE SAME TEST /Users/rafael/dev/runar-rust/runar-node-tests/src/network/remote_test.rs TO identify where hey diverge.

 2) Every change must be 100% aligned tyo the RUST code.. every time u touch anything in swift,m first find the correponding are in the RUST code and make sure the Swift IMPL is 100% aligned, nothing more nothing less - exact same dataflow, exact same rules, parameters, functions/method body EVERYNG must match.. test setup, test steps, testa assertions.
Consider language differeces which must exist and be kept, and consider that Swift uses FFI to access Key mangers, transporter, discovery from the RUST layer and it does not ahve its own.

 3) keep iterating and fixing swift side to aligne with rust 100% until the test testRemoteActionCall() works properly - DO NOT compromise thet test. the test must be exactly like tyeh rust test at remote_test.rs

 Follow our rules .cursor/rules/code-standards.mdc