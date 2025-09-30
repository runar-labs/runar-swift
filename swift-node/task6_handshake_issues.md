### 🔄 **Current Issue:**

The **handshake service announcement is not working**. The nodes are discovering each other (`PeerDiscovered` events), but the handshake is not completing successfully because:

- `PeerDiscovered` events are missing both `peerNodeId` and `nodeInfo`
- Without proper NodeInfo exchange, remote service handlers are never registered
- This means remote service calls fail because no remote handlers exist

WHY are PeerDiscovered events are missing both peerNodeId and nodeInfo ?? we have fixed the set and udpate node info.. ... the Node should call tehse method properly.. to set the ndoe info the transport layer.. so the RUST FFI layer can use it for proper handshake and exchange peer node info... check if we have trace logs in this data flow.. at the RUST FFI code.. if not lets add.. so we can debug and see what is going on in detail.. also check in tyour side.. in the swift node where do we set and udapte teh ndoe info.. at which stages ??