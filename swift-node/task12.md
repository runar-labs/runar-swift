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
