I have Updated rn_transport_new_with_keys signature to require NodeInfo CBOR and initialize local_node_info with it. 

I have already run swift-ffi/build_rust_ffi.sh so lates Rust FFI is build anbd the header file copied to the swift side alrady.


Step 1: make sure NodeInfo  has tests to verify its CBOR works both ways swift to rust and rust to swift 
/Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFITypesCrossValidationTests.swift
and
/Users/rafael/dev/runar-swift/runar-rust/rust-examples

Step 2: change teh swift ffi transporter to also requirea node info at creation (PROPER TYPE.. CBOR bytes should never be exposed i teh API.. CBOR is an internal thing) and the pass tha to the FFI API to fully aligne the swift FFI to the rust FFI API.

Step 3: update all tests usign the transporter to use the new API and prvoide a node info instance.