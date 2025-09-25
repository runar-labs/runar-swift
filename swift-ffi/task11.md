GOAL Improve the API for QuicTransport

1) CBOR shuold be an internal thing and not exposed in the QuicTransport API at all.

1.1)
public static func create(keys: NodeKeyManager, optionsCbor: Data) async throws -> QuicTransport {

Should be public static func create(keys: NodeKeyManager, options: QuicTransportOptoins) async throws -> QuicTransport {

Instead of passing Data around.. we shuold have a proper type QuicTransportOptoins that is then serialized as Data  so be send in the FFI layer.


1.2)
public func connectPeer(peerInfoCbor: Data) async throws {

shuold be

public func connectPeer(peerInfo: PeerInfo) async throws {

Instead of passing Data around.. we shuold have a proper type PeerInfo that is then serialized as Data  so be send in the FFI layer.

1.3)
public func pollEvent() async throws -> Data? {
    shuold be
public func pollEvent() async throws -> TransportEvent? {

1.4)
 public func updateLocalNodeInfo(nodeInfoCbor: Data) async throws {
    should be
 public func updateLocalNodeInfo(nodeInfo: NodeInfo) async throws {

1.5)
public func request(requestCbor: Data) async throws {

shuold be
public func request(request: RequestParams) async throws {

1.6
public func publish(publishCbor: Data) async throws {

shuold be
public func publish(publish: PublishParams) async throws {

1.7
public func completeRequest(completeCbor: Data) async throws {
shuold be
public func completeRequest(complete: RequestCompleteParams) async throws {

All these public APIS must dea wih ptoper types and CBOR must be dealt as an internal concer.. paramets shuold ben serialize to CBOS internaly and return should be desetialized form CBOR to proper types

NO BACKWARED COMPAT AT ALL> FULL REFACTORY>> ALL TESTS TAHT USE THESE APIS MUST BE UPDATED TO USE THE PROPER NEW API.


ALL new types that uses CBOR must be properly tested against the RUST TYPES 
/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFITypesCrossValidationTests.swift

/Users/rafael/dev/runar-swift/runar-rust/rust-examples/validate_swift_vectors.rs
/Users/rafael/dev/runar-swift/runar-rust/rust-examples/validate_ffi_vectors.rs

