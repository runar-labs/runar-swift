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


NEW FEEBACK

Feeback 04:
@FFIQuicTransportTest.swift is only testing request reponse.. there is no publish call. 
I have now improved the rust test  so it has the publish/event data flow also.
Lets also improve the @FFIQuicTransportTest.swift test to mimic that, so we can test this works properly in the swift layer. 


Feedback 05:
try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds timeout

All timeouts needs to be config driven. not hardcoded. just like in the rust layer
we need tranport options where we can pass these config options. We nee dot keep this separte form the FFI
options, to acvoid confutions and CBOR issues.. so we need the FFITransportOptions (the current options we alrady have) and we need the QuicTranport optoins which is all the optoins (the seift layer optoins like this tiimetount + the ffi options all in ont type.. and internalty we grab the FFI otpoins and pass jus that to the FFI layer). so u nee to do this carefulty and step by step.. first rename the exisit tyupe QuicTransportOptions to FFIQuicTransportOptions  and keep sme strucure.. sice this is alreaduy validate dot woirk for the FFI layter.. then u create a new QuicTransportOptions with container the FFIQuicTransportOptions items + the seift layer items.. like this timeout.. 


Feedback 06:
Lets improve the QuicTransportOptions
instead of this:
public struct QuicTransportOptions: Sendable {
    public let ffiOptions: FFIQuicTransportOptions
    public let requestTimeoutSeconds: UInt64
    
    public init(
        ffiOptions: FFIQuicTransportOptions = FFIQuicTransportOptions(),
        requestTimeoutSeconds: UInt64 = 30
    ) {
        self.ffiOptions = ffiOptions
        self.requestTimeoutSeconds = requestTimeoutSeconds
    }

Lets normalize and have all teh ffi optoins direclty in the QuicTransportOptions:
public struct QuicTransportOptions: Sendable {
    public let requestTimeoutSeconds: UInt64
public let bindAddr: String?
    public let handshakeTimeoutMs: UInt64?
    public let openStreamTimeoutMs: UInt64?
    public let maxMessageSize: UInt64?
    public let responseCacheTtlMs: UInt64?
    public let maxRequestRetries: UInt32?

and in the method :
 public static func create(keys: NodeKeyManager, options: QuicTransportOptions, callbacks: TransportCallbacks, logger: RunarLogger) async throws -> QuicTransport {
we create a FFIQuicTransportOptions and copy the parameters from the QuicTransportOptions and then we serialize FFIQuicTransportOptions to CBOR and use it to creat the handle.

TEH FFI BEHAVIOUR and CBOR behavioour DO NOT CHAHGE>> it continue using FFIQuicTransportOptions.

The only diference is that we dont have a   public let ffiOptions: FFIQuicTransportOptions FIELD but we have all the fields normalized in the  QuicTransportOptions type and we then COPY each field.. field by fieldl to create a FFIQuicTransportOptions amnd the serialize with CBOR

This propvide a better API for the QuicTransportOptions object..
from the outsite there should not be any jknowled to of FFI.. .. FFI is an internal thing..





## ISSUE IDENTIFIED - Publish/Event Not Working

**Problem**: The `publish()` method is calling the FFI function successfully (logs show "Event published successfully"), but no `EventReceived` events are being generated by the FFI layer. This causes the test to timeout waiting for the event.

**Analysis**: 
- The Rust side properly calls the event callback when `MESSAGE_TYPE_EVENT` messages are received
- The FFI layer should generate `EventReceived` events when the event callback is called
- The issue appears to be in the FFI layer not properly calling the event callback or generating the events

**Status**: This is a complex FFI issue that requires deep investigation of the Rust FFI layer. The Swift implementation is correct, but the underlying FFI layer is not generating the expected events.

**Next Steps**: This issue needs to be investigated in the Rust FFI layer to understand why `EventReceived` events are not being generated when `publish()` is called.