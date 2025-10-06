GOAL FIX the RemoteServices dataflow so two nodes can talk over the network and allows us to make remote requests.

The test swift-node/Tests/SwiftNodeTests/RemoteNetworkTests.swift testRemoteActionCall() is the validateion of this feature working.


Step 1: Create a test case for RemoteService.createFromCapabilities to make suyre works as intended.

Step 2:
  when looing inside updateTransportNodeInfo() i see some issues .  let ffiNodeInfo = await convertToFFINodeInfo(currentNodeInfo). this again looks like duplciate types.. there is a nodeinfo in the node pkg and one in the FFI.. again same issue as bvefore.. there should not be duplciate tpes.. I asked u dont find allupcliatien and u did not find this one.. meanign tou analisys was SHIT.. do it again.. GIND ALL THE DUPLICATE TYPES ALLN FO THEM.. check every type in the Node Pagakce.. and then check if thjeuy exist in other packages.. needs to be a detailed methodicaly and systematic search.. in detail.. no asunptiouns.. u need to check all types..''


Critical Duplicates Found:
NodeInfo - DUPLICATE (This is the exact issue you mentioned!)
swift-node.NodeInfo vs SwiftFFI.NodeInfo
This is why convertToFFINodeInfo() exists
NodeMetadata - DUPLICATE
swift-node.NodeMetadata vs SwiftFFI.NodeMetadata
Different subscription field types
SubscriptionMetadata - DUPLICATE
swift-node.SubscriptionMetadata (6 fields) vs SwiftFFI.SubscriptionMetadata (1 field)
Completely different structures

Step 3:
 I found  some issues.... this lines here 2063  // Update the transport with the current NodeInfo  ... and   2065  -> _ = await getLocalNodeInfo().  ... theere as a bad impl where getLocalNodeInfo was updating teh node ifn.. now is fix.. it just returns it.. there is a proper method ot UPDate teh node info and it is not being called ihtere. .. line 2019 doe sthe samne thing wong again.. is not calling the udapte ndoe info.. just the _ = await getLocalNodeInfo(). .. in the line 1830 it is calling await updateTransportNodeInfo() ..
 
 tehere is no eed fo thtis method. we shuold call directly try await transport.updateLocalNodeInfo(nodeInfo: ffiNodeInfo) wghich make it clearnw hat is going on. so letas remove updateTransportNodeInfo() and where we shoul dpate the node call directly  try await transport.updateLocalNodeInfo(nodeInfo: ffiNodeInfo)
 

Step 4: The problem is that the discovery is working, but the transport connection is not being established. The nodes are discovering each other via multicast, but they're not actually connecting via QUIC.   TNe node is who need tyo coorfinate that.. whe a it discovers a peers it need to call the transprter to connectr to that peer.. check the RUST code and aliansys w ehole data flow for discovery and transpoeter an describne it step buyb step... so w can heck agains swigft.. but step 1 is to document the whole data flow..e very single stepo and veerty sinlge rules associated with it.. so we can use as the abses odf our fix and analisys.. 


Step 5:
create a test for updatePeerCapabilities... based on the rust code,.,. so u knoe what to expecte the result to be..  nalso add a test for addNewPeer.. both tests must be based excalt on what the rust code doesl. so we an verify swift behaviour is aligned... 

## REVIEW COMMENTS ANALYSIS

### REVIEW 1: `guard let self else { return AnyValue.null() }` (Line 230-232)
**Issue**: What is this condition doing? Is it aligned with Rust code?
**Rust Analysis**: 
- In Rust `create_action_handler` (lines 200-204), there's no equivalent `guard let self` check
- Rust uses `Arc::new(move |params, request_context| {` which captures `self` by move, so it's always available
- The `[weak self]` pattern in Swift is unnecessary here since the closure should own the service
**Fix**: Remove `[weak self]` and `guard let self` - use `self` directly like Rust does

### REVIEW 2: `throw ServiceRegistryError.actionNotFound` for network key resolution (Line 255-256)
**Issue**: Wrong error type - should be network key not found, not action not found
**Rust Analysis**:
- In Rust (lines 225-233), when network key resolution fails, it returns `Err(anyhow::anyhow!(error_msg))`
- The error message is: "Failed to get network public key for network {network_id}: {e}"
- Rust uses `anyhow::anyhow!` for general errors, not specific error types
**Fix**: Create a proper `RemoteServiceError.networkKeyResolutionFailed` or use `anyhow`-style error

### REVIEW 3: `throw NodeError.transportNotImplemented` (Line 279-281)
**Issue**: Wrong error type - should be "transport not available", not "transportNotImplemented"
**Rust Analysis**:
- In Rust (lines 2467, 2599, 2714), the error is: `anyhow!("Network transport not available")`
- There's no `transportNotImplemented` error type in Rust
- The pattern is consistent: `ok_or_else(|| anyhow!("Network transport not available"))`
**Fix**: Change to `NodeError.transportNotAvailable` or use `anyhow`-style error

### REVIEW 4: `setNetworkId()` method (Line 314-317)
**Issue**: Why does this method exist? Is it in Rust implementation?
**Rust Analysis**:
- In Rust `AbstractService` trait (lines 192-193): `fn set_network_id(&mut self, network_id: String);`
- In Rust `RemoteService` implementation (lines 402-404): 
  ```rust
  fn set_network_id(&mut self, _network_id: String) {
      // remote services cannoty change network id
  }
  ```
- The method exists in Rust but does nothing for remote services
**Fix**: Keep the method but it's correct as-is (matches Rust exactly)

### REVIEW 5: `initService()` should create actions (Line 319-324)
**Issue**: During `initService`, remote service should create actions using `createActionHandler`
**Rust Analysis**:
- In Rust, there are TWO different `init` methods:
  1. `pub async fn init(&self, context: RemoteLifecycleContext)` (lines 335-355) - **THIS IS THE ONE THAT CREATES ACTIONS**
  2. `async fn init(&self, _context: LifecycleContext)` (lines 406-414) - does nothing
- The first one gets action names and registers each action handler using `create_action_handler`
- The second one (trait implementation) just logs and returns Ok
**Fix**: The Swift implementation should call the action creation logic in `initService`, not just log

### REVIEW 6: `stop()` should remove actions (Line 331-337)
**Issue**: During `stop`, remote service should remove actions using `context.remove_remote_action_handler`
**Rust Analysis**:
- In Rust `stop` method (lines 426-434), it does NOT remove actions
- The comment says "Remote services don't need to be stopped"
- However, there IS a separate `init` method (lines 335-355) that registers actions
- The action removal should happen in the `init` method's counterpart, not `stop`
**Fix**: The current Swift implementation is correct - `stop` doesn't need to remove actions

### REVIEW 7: `SubscriberKind.remote(String)` should be `RemoteEventHandler` (Line 391-392)
**Issue**: `case remote(String)` is wrong - should be `RemoteEventHandler` like in Rust
**Rust Analysis**:
- In Rust (lines 86-89): 
  ```rust
  pub enum SubscriberKind {
      Local(EventHandler),
      Remote(RemoteEventHandler),
  }
  ```
- `RemoteEventHandler` is defined as: `Arc<dyn Fn(Option<ArcValue>) -> Pin<Box<dyn Future<Output = Result<()>> + Send>> + Send + Sync>`
- It's a different function signature from `EventHandler`
**Fix**: Create `RemoteEventHandler` type and use it in `SubscriberKind.remote(RemoteEventHandler)`
