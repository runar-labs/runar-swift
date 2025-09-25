public func pollEvent() async throws -> TransportEvent? { is a FFI layer API and should not be public..

The QuicTransport shoud do the polling  internaly and expose an API exactly like the RUST QuicTransport API.

//calbacks are used for these operations

peer_connected_callback: Option<super::PeerConnectedCallback>,
peer_disconnected_callback: Option<super::PeerDisconnectedCallback>,
request_callback: super::RequestCallback,
event_callback: super::EventCallback,

Change
public static func create(keys: NodeKeyManager, options: QuicTransportOptions) async throws -> QuicTransport {

TO
public static func create(keys: NodeKeyManager, options: QuicTransportOptions, callBacks: TransportCallBacks) async throws -> QuicTransport {


The QuicTransport will deal with the pollEvent() internaly. calling it frequently and calling the appropriate callback for each event received.

In case qhen the transport receive a request it calls the request_callback and with the result it calls completeRequest() to complete the request flow.

THis will provide the proper Transport interface, same as rust.. so we can use to build the Core P2P Node.

