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

Change this TEST 
/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFIQuicTransportTest.swift

To use this new API.
Add a comment that this test use the improved Transporter API but still matches the RUST test. in all the rules, steps.. setup and asserts. DO NO COMPROMISE THE TEST. it shold not deviate  from the rust test. just in these API chagnes.




FEED BACK 01 - Logging:
Teh usage odf the loggoe ris incorrect:
 do {
    if let event = try await self.pollEvent() {
        await self.handleEvent(event)
    }
} catch {
    // Log error but continue polling
    let logger = RunarLogger(component: .custom)
    logger.error("QuicTransport internal polling error: \(error)")
}

You cant creat eh logger everytime u need to use it..

The logger shuold be passed as parameter in the 
 public static func create(keys: NodeKeyManager, options: QuicTransportOptions, callbacks: TransportCallbacks) async throws -> QuicTransport {

    should be
 public static func create(keys: NodeKeyManager, options: QuicTransportOptions, callbacks: TransportCallbacks, logger:RunarLogger) async throws -> QuicTransport {


The code creaing teh transporter is reponsible to pass the logger

and then the same logger shold be used everythere in the QuicTransport actor.

self.logger.trace() ...

also logs ot places u are using logger.debug whre u should actualy be using logger.trace  thse frequente detailed logs are tgrce logs.. debug shuoldn show once or maximumt wice in a funtions.. info is very reate.. just important events likst start stop etc..

Change all tests using the tranport to pass the logger

Feeback 02 -  RequestReceived:

Seems the handling of this is imcomplete
We need to send the request result back.. so the result of  callbacks.requestCallback(requestId, path, Data(payload), sourcePeerId, correlationId).. must be sent back to the peer using completeRequest()


Feeback 03 -  eventCallback():

default:
    // Call general event callback for other events
    callbacks.eventCallback?(event)
}

THI IS WRONG way to handle this
1) every know event should have a proper case .. u are missign teh case for EventReceived  and default shoud log an error for (unkown FFI event received)

YOU ARE MIXING THE CONCEPT OFN THE FFI EVENT with the P2P Event. These are two difference things.

2) eventCallback is not for the FFI EVENT/generic any type of event.. this for the specific P2P event message.. just like the reqeust message which is request/response pattern. we also have the event which is fire and forget message (no response). The event callbaback has the same paramter as the reqeut call back but not return.

You have conflated the "Transport FFI Event" with the message event.. Two difference thgings.. 

Check the rust code I have reference event_callback: super::EventCallback,  and u will see that the EventCallback here takeas parmetarmers.. in seift must be the same..


Correct Architecture (matching Rust):
request() method:
Sends request via FFI
Waits internally for ResponseReceived event
Returns the response data directly
publish() method:
Sends fire-and-forget event via FFI
No response expected
RequestCallback:
Handles incoming requests
Returns a response (which gets sent back via completeRequest())
EventCallback:
Handles incoming publish events (fire-and-forget)
No return value
ResponseReceived events:
NOT handled by eventCallback
Handled internally by the request() method
This matches the Rust implementation exactly where:
request() waits for the response internally and returns it
publish() sends fire-and-forget events
RequestCallback returns responses
EventCallback handles publish events (no response)