We need to undertand more about te CBOR encoding/decoding appraoch in swift. this is creating a ton of probems every very time we introduce new types in RUST is a pain. in swift and it should not be;

1) Do the current tests /Users/rafael/dev/runar-swift/swift-ffi/Tests/SwiftFFITests/FFITypesCrossValidationTests.swift use/validates this CBORHelper ? is the testing.. actuqaly testint this ? 

2) where are these methods being used createMinimalNodeInfo, createMinimalTransportOptions, createMinimalSwiftTransportOptions ?? These looks lien test helpers.. theyu shouol not be use din the core code and should not be in the core code.. theyu shuold. be moved to a test helper only used and aviaolablen for testing.. 

3) FIND all CBOR typs taht have fallbacks. and list them all.. FALLBACKS ARE NOT ALLOEWD.. e.g. of falabcl  init fn from NdeIndo type.. // Try alternative field name "public_key" (used in PeerDiscovered events). this is not alloed in our rules.. code must be determinitist an ahve a single path.. if CBOR cannot deboce then return an error.. 

4) why CBOR approach is so over the place.. some types like  ServiceMetadata onlyt have enum CodingKeys: String, CodingKey {n to map swfit fields to rust fields.. which make sense since they follow differnece naming conventions.. but other types have public init(from decoder: Decoder) throws { and  public func encode(to encoder: Encoder) throws { ??? with the proper field nam mapping do we need these..?? 

5) IN SHORT CBOR is all over the plance and is a HUGE mess.. we need to mprove this.. we need the same appraoch for ALL TUYPE.. we need the same testing for alltypes.. all types must be tested both ways.. swift to rust and ruwt to swift.. and we need a single test tha we run on both sides that do that..
a) generate RUST bin outut for every type.. sometime multple for the same type.. when we wanto test multpoe data conbimnations. like vec of buytes empty and populated (a common issue) and 
b) a test hat uses this as input and tgest all the decoding in the other side.. we need this in both sides.. both need s to follow same conveitions. .so is eaty to udnerstand and to add new types.. everytime we hav ae new CBORT tyupe.. we add to this test to make sure works properly.. 

GOAL 1: Organiaze CBOR in swift. .create a separte file from swift-ffi/Sources/SwiftFFI/SwiftFFI.swift and mvoe all CBOR types and code there. and add documentat on how ity works.. all lesonss learned. what to do and what NOT to do. so when adding new types we can follow these rules

GOAL2: Organise the CBOR testing in both side.. RUST and Swift.. as I descreibed above. improve tghe existint testing files:
swift-ffi/Tests/SwiftFFITests/FFITypesCrossValidationTests.swift
runar-rust/rust-examples/validate_swift_vectors.rs
runar-rust/rust-examples/validate_ffi_vectors.rs
runar-rust/rust-examples/ffi_types_vectors.rs

WHAT WE NEED IS>. one ach side:
1 File - generate CBOR types outputs
1 File validate CBOR types

that is it.. so we can run the rust  generate CBOR types outputs will generate in a folder a bunch of bin files.. sometimes more than one fo thte same type.. we need a robbuyst naming convention <type_name><-data_variation_name>.bin

then we can run the validate CBOR types in the ogher side and consume all these bin files to decode and validate teh data.. and check CBOR working in that direction.. then we need the same in the other direction..

CONSOLIDATE (DO NOT LECE TRACH BEHIND>> CEHCK ALL FILES RELATE TO CBOR TEST AN REMOVE ALL OF THEM AT THE END SO WE END UPU JUST WITHY THIS STRCUTTURE) FULL REFACTOTY.. proper code orgabniszation