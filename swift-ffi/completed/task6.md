# Task 6: Swift FFI Package Updates for CA Node API Consistency

## Overview
This task documents all the changes needed in the Swift FFI package to align with the latest Rust FFI changes that fixed the CA Node handle API consistency issues. The Rust layer has been updated to use a unified shared handle approach, eliminating the raw vs shared handle mismatch that was causing crashes.

## 🎯 **Root Cause Analysis**
The original crash was caused by:
- **API Mismatch**: Swift was passing raw `CANode` handles to Rust functions expecting `Arc<RwLock<CANode>>` shared handles
- **Memory Corruption**: This caused `std::sync::RwLock::write()` to operate on invalid memory (address 0x1d1)
- **Undefined Behavior**: The mismatch only manifested in full test suite runs due to memory layout timing

## 🔧 **Rust Changes Summary**
The Rust layer has been updated with these key changes:

### **Removed Functions:**
- `rn_keys_ca_node_new` - No longer creates raw handles
- `rn_keys_ca_node_free` - No longer needed for raw handles
- `rn_keys_ca_node_create_shared` - Renamed to `rn_keys_ca_node_new_shared`

### **Updated Functions:**
- `rn_keys_ca_node_new_shared` - Now the single entry point for CA Node creation
- All CA Node functions now expect `shared_ca_node: *mut c_void` (Arc<RwLock<CANode>>)
- Functions updated: `setup_complete`, `get_root_ca_certificate`, `get_issuing_ca_certificate`, `add_admin_ski`, `handle_enroll`, `handle_renew`, `handle_revoke`, `handle_chain`, `handle_status`, `handle_crl`, `revoke_token`, `generate_crl_lite`
 

## 📋 **Required Swift Changes**

### **Phase 1: Update CANode Class**

#### **1.1 Remove Raw Handle Creation**
**File:** `Sources/SwiftFFI/SwiftFFI.swift`
**Location:** Lines 2028-2050

**Current Code:**
```swift
public nonisolated static func create() throws -> CANode {
    let logger = RunarLogger(component: .custom)
    logger.info("CANode.create() - Starting CA Node creation")
    var handle: UnsafeMutableRawPointer?
    logger.trace("CANode.create() - About to call rn_keys_ca_node_new")
    let (code, err) = withRnErrorCode { errPtr in
        logger.trace("CANode.create() - Inside withRnErrorCode closure")
        let result = rn_keys_ca_node_new(&handle, errPtr)
        logger.debug("CANode.create() - rn_keys_ca_node_new returned: \(result)")
        return result
    }
    // ... rest of function
}
```

**Required Change:**
```swift
public nonisolated static func create() throws -> CANode {
    let logger = RunarLogger(component: .custom)
    logger.info("CANode.create() - Starting CA Node creation")
    var handle: UnsafeMutableRawPointer?
    logger.trace("CANode.create() - About to call rn_keys_ca_node_new_shared")
    let (code, err) = withRnErrorCode { errPtr in
        logger.trace("CANode.create() - Inside withRnErrorCode closure")
        let result = rn_keys_ca_node_new_shared(&handle, errPtr)
        logger.debug("CANode.create() - rn_keys_ca_node_new_shared returned: \(result)")
        return result
    }
    // ... rest of function
}
```

#### **1.2 Update deinit Method**
**File:** `Sources/SwiftFFI/SwiftFFI.swift`
**Location:** Lines 2129-2131

**Current Code:**
```swift
deinit {
    rn_keys_ca_node_free(_ffiHandle)
}
```

**Required Change:**
```swift
deinit {
    rn_keys_ca_node_free_shared(_ffiHandle)
}
```

#### **1.3 Remove createShared Method**
**File:** `Sources/SwiftFFI/SwiftFFI.swift`
**Location:** Lines 2097-2109

**Action:** Remove the entire `createShared()` method since we now create shared handles directly.

#### **1.4 Update setupComplete Method**
**File:** `Sources/SwiftFFI/SwiftFFI.swift`
**Location:** Lines 2052-2080

**Current Code:**
```swift
let (code, err) = withRnErrorCode { errPtr in
    params.rootCaSubject.withCString { cRoot in
        params.issuingCaSubject.withCString { cIssuing in
            params.networkId.withCString { cNetworkId in
                rn_keys_ca_node_setup_complete(
                    caHandle,
                    cRoot,
                    cIssuing,
                    UInt32(params.validityDays),
                    UInt32(params.issuingCaSerial),
                    cNetworkId,
                    params.eaPublicKeys.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! },
                    params.eaPublicKeys.count,
                    errPtr
                )
            }
        }
    }
}
```

**Required Change:** No change needed - the function signature already expects shared handles.

#### **1.5 Update Certificate Retrieval Methods**
**File:** `Sources/SwiftFFI/SwiftFFI.swift`
**Location:** Lines 2082-2108

**Current Code:** Already correct - these methods already use the shared handle.

#### **1.6 Update addAdminSki Method**
**File:** `Sources/SwiftFFI/SwiftFFI.swift`
**Location:** Lines 2116-2127

**Current Code:** Already correct - this method already uses the shared handle.

### **Phase 2: Update SharedCANode Class**

#### **2.1 Update deinit Method**
**File:** `Sources/SwiftFFI/SwiftFFI.swift`
**Location:** Lines 2281-2283

**Current Code:**
```swift
nonisolated deinit {
    rn_keys_ca_node_free_shared(_handle)
}
```

**Required Change:** No change needed - already correct.

### **Phase 3: Update Test Files**

#### **3.1 Update FFIE2EIntegrationTest.swift**
**File:** `Tests/SwiftFFITests/FFIE2EIntegrationTest.swift`

**Current Code (Lines 83-86):**
```swift
// Create CA Node
logger.debug("🔧 STEP 1: Creating CA Node...")
caNode = try await CANode.create()
logger.debug("   ✅ CA Node created successfully")
```

**Required Change:** No change needed - `CANode.create()` now creates shared handles directly.

**Current Code (Lines 113-115):**
```swift
logger.debug("   🔧 Calling caNode!.setupComplete() - this should trigger Rust FFI logs...")
try await caNode!.setupComplete(params: setupParams)
logger.debug("   ✅ CA Node setup completed successfully")
```

**Required Change:** No change needed - `setupComplete` already works with shared handles.

**Current Code (Lines 326-330):**
```swift
// Add SKI to CA Node's admin allowlist
try await caNode!.addAdminSki(mobileCertSki.data(using: .utf8)!)
logger.debug("   ✅ Mobile cert SKI added to CA Node admin allowlist")
```

**Required Change:** No change needed - `addAdminSki` already works with shared handles.

#### **3.2 Update Other Test Files**
**Files:** All test files in `Tests/SwiftFFITests/`

**Required Changes:**
- Remove any calls to `createShared()` since `CANode.create()` now creates shared handles directly
- Remove any calls to `CANode.freeShared()` since `CANode.deinit` now handles cleanup
- Update any direct FFI calls to use the new function names

### **Phase 4: Update FFI Function Declarations**

#### **4.1 Update Header File**
**File:** `Sources/CRunarFFI/include/runar_ffi_wrapper.h`

**Required Changes:**
- Remove declaration for `rn_keys_ca_node_new`
- Remove declaration for `rn_keys_ca_node_free`
- Remove declaration for `rn_keys_ca_node_create_shared`
- Add declaration for `rn_keys_ca_node_new_shared`

**New Declaration:**
```c
int32_t rn_keys_ca_node_new_shared(void **out_shared_ca_node, struct RnError *err);
```

### **Phase 5: Update Build Configuration**

#### **5.1 Update Module Map**
**File:** `Sources/CRunarFFI/include/module.modulemap`

**Required Change:** No change needed - the module map should already link against the updated Rust library.

#### **5.2 Update Build Scripts**
**File:** `sign_and_run_tests.sh`

**Required Change:** No change needed - the build script should work with the updated Rust library.

## 🧪 **Testing Strategy**

### **Phase 1: Unit Tests**
1. Run individual test files to ensure they pass
2. Verify CA Node creation works with new API
3. Verify all CA Node operations work correctly

### **Phase 2: Integration Tests**
1. Run the full test suite to ensure no crashes
2. Verify memory management is correct
3. Check for any remaining handle type mismatches

### **Phase 3: Performance Tests**
1. Verify no memory leaks
2. Check performance is not degraded
3. Ensure proper cleanup in all scenarios

## 🚨 **Critical Points**

### **Memory Management**
- **CRITICAL**: All CA Node handles are now shared handles (`Arc<RwLock<CANode>>`)
- **CRITICAL**: Use `rn_keys_ca_node_free_shared` for cleanup, not `rn_keys_ca_node_free`
- **CRITICAL**: No more raw handle creation - only shared handles

### **API Consistency**
- **CRITICAL**: All CA Node functions now expect shared handles
- **CRITICAL**: No more `createShared()` calls needed - handles are shared by default
- **CRITICAL**: No more `freeShared()` calls needed - `deinit` handles cleanup

### **Backward Compatibility**
- **BREAKING**: The API is not backward compatible
- **BREAKING**: All existing code using raw handles must be updated
- **BREAKING**: Test code must be updated to use new API

## 📊 **Expected Outcomes**

### **Before (Current State)**
- ❌ Crashes with `signal 11` in full test suite
- ❌ Handle type mismatches between raw and shared
- ❌ Memory corruption in `std::sync::RwLock::write()`
- ❌ Undefined behavior in CA Node operations

### **After (Target State)**
- ✅ No crashes in full test suite
- ✅ Consistent shared handle API throughout
- ✅ Proper memory management with `Arc<RwLock<CANode>>`
- ✅ Deterministic behavior in all CA Node operations

## 🔄 **Implementation Order**

1. **Update FFI Function Declarations** (Phase 4)
2. **Update CANode Class** (Phase 1)
3. **Update SharedCANode Class** (Phase 2)
4. **Update Test Files** (Phase 3)
5. **Update Build Configuration** (Phase 5)
6. **Run Tests** (Testing Strategy)

## 📝 **Notes**

- The Rust layer has already been updated and tested
- All Rust tests pass with the new API
- The Swift layer needs to be updated to match the Rust changes
- This is a breaking change that requires updating all CA Node usage
- The new API is more consistent and eliminates the handle type mismatch issues

## 🎯 **Success Criteria**

- [ ] All Swift tests pass without crashes
- [ ] No `signal 11` errors in full test suite
- [ ] Consistent shared handle API throughout
- [ ] Proper memory management with no leaks
- [ ] All CA Node operations work correctly
- [ ] No handle type mismatches
- [ ] Clean compilation with no warnings
