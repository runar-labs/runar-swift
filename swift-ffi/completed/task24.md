GOAL FIX logger usage in the SeiftFFI code

Many places do:
let logger = RunarLogger.root(component: .custom("ffi"))

THIS IS WRONG.

A looger should always be passed. never created internaly like this.

IF is an object like 
public class CANode {

    Then when creating this obuject a logger must be passes and kept as a field in the object and this field be used as the logger.. NEVER create internaly.


If is a function like:
func ffi_node_generate_csr(
    _ handle: UnsafeMutableRawPointer
) throws -> Data {

Then is needs to receive the logger as the last parameter
func ffi_node_generate_csr(
    _ handle: UnsafeMutableRawPointer,
    _ logger: RunarLogger,
) throws -> Data {

and use that >> NEVER CREATE ITS OWN INTERNAL LOGGER> >NEVER.


WHEN updating the Tests to pass the logger as parameter use the following pattern:

//CREATE A ROOT LOGER WITH THE NAME OF THE Test Case
 let logger = RunarLogger.root(component: .custom("testBasicDiscoverySetup"))
// Then create a child logger with the target component - in this csae is network - check the enum for a full list of components
let discovery = try await MulticastDiscovery.create(peerInfo: peerInfo, options: discoveryOptions, logger: logger.child(component: .network) )

THIS mimics the actual real usave of the logger