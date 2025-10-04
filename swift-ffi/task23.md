

Lets fix all these issues in the FFI code:

1) public func createTransportHandle(nodeInfo: NodeInfo, options: FFIQuicTransportOptions) async throws -> HandleToken {
    SHUOLDN NOT IN THE NodeKeyManager object.. it shuiood be in the QuicTransport

The method create() already receives the keys: NodeKeyManager , so it can be used internaly to get the nodeKeYmanger handler which is needed to create the transporter.

public static func create(keys: NodeKeyManager, nodeInfo: NodeInfo, options: QuicTransportOptions, callbacks: TransportCallbacks, logger: RunarLogger) async throws -> QuicTransport {


2) public func createDiscoveryHandle(optionsCbor: Data) async throws -> DiscoveryHandle {
SHUOLOD NOT be in the NodeKeyManager object - it shuold be in the DiscoveryHandle

I have chnaged he RUST FFI API where the method rn_discovery_new_with_multicast no longer required the KeyManager as parameter. Not it needs a PeerInfo as parameter.. with the node PK and Address properly populated. taht is how it works in RUST runar-node/src/node.rs -<> method  async fn create_discovery_provider( - check that for referce.. that is how this will also work with the SwfitNode. i will provide a proper PeerInfo when creating the MulticastDiscovery

Another change is what the Discovery oiptoins was being provided using a CBOR map.. taht was wrongl. not it is using the proper DiscoveryOptions struct. MAKE SUYRE WE HAVE THIS struct in Swift also an that is properly tested following the guidelines at  swift-ffi/CBOR.md

FINAL aftar all the previous changes are done and working properly and all tests refacored and working
3) the object DiscoveryHandle shuold be renamed to MulticastDiscovery 

NEW GOAL
A NEW ISSUE WAS FOUND AND FIXED with the rn_transport_new_with_keys
It was using a CBOR map to pass parameters. This is now fixed and it uses a proper struct
pub struct QuicTransportOptionsConfig {

1) Create the SWIFT COUNTERpart for this and test it properly using our CBOR guidelines swift-ffi/CBOR.md

2) update he Swift FFI to align with the latest verison of rn_transport_new_with_keys and pass the proper QuicTransportOptionsConfig struct serialized in CBOR