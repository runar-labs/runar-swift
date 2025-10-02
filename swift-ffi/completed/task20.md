GOAL FIX the test @FFIDiscoveryTest.swift  to properly test the discovery mechanis and check all aspected ot eh discovery., the current test has gaps..

## 🔍 **DETAILED ANALYSIS: FFI Discovery Test Issues**

### **What the FFI Discovery Test SHOULD Do:**
1. Create two discovery instances (A and B)
2. Set up discovery callbacks for both
3. Start announcing on both
4. **Generate discovery events when peers are discovered**
5. **Call the discovery callbacks with peer information**

### **What the FFI Discovery Test ACTUALLY Does:**
1. ✅ Creates two discovery instances (A and B)
2. ✅ Sets up discovery callbacks for both
3. ✅ Starts announcing on both
4. ❌ **NEVER generates discovery events**
5. ❌ **NEVER calls the discovery callbacks**

### **Evidence from the Logs:**

#### **1. Multicast Messages ARE Working:**
```
[2025-10-02T06:17:17.279Z DEBUG] [Keys NetworkDiscovery discovery-transport-test iodolrpbjksnv6u5dg6etsmhbc] Received multicast message from 192.168.0.155:46475, size: 184
[2025-10-02T06:17:17.279Z DEBUG] [Keys NetworkDiscovery discovery-transport-test iodolrpbjksnv6u5dg6etsmhbc] Processing announce message from peer
```

#### **2. But NO Discovery Events Are Generated:**
```
[TRACE] DiscoveryHandle internal polling - Polling for discovery events
[TRACE] DiscoveryHandle internal polling - No discovery events available
[TRACE] DiscoveryHandle internal polling - Polling for discovery events
[TRACE] DiscoveryHandle internal polling - No discovery events available
```
