There are critical issues in the serializer impl in swift that does not match rust.

#1)  KeyStore parameter should be passed in the deserialize method -> AnyValue.deserialize(serializedData) and NOT in the asType method -> deserializedValue.asType(keystore: mobileKeystore) THIS IS WRONG and not how works in rust..

The when calling AnyValue.deserialize(serializedData, mobileKeystore)  itn shuold create an AnyValue with Lazy data with contains the key store.. so when the deserializedValue.asType() is called... it then IF the serialisze data is encrypted.. it can then decrypt it.. that is the pattern in RUST.

The test /Users/rafael/dev/runar-swift/swift-serializer-macros/Tests/RunarSerializerMacrosTests/EndToEndEncryptionTest.swift DOES NTO MATCH the RUST counter part /Users/rafael/dev/runar-swift/runar-rust/runar-serializer/tests/encryption_test.rs 

Specialy yhe test test_encryption_in_arcvalue() which shuood be called testEncryptionInAnyvalue in swift and it tests the capability that we can get an ecnrypted type and the final plain type from a serialized any value:
let node_profile: Arc<TestProfile> = de_node.as_struct_ref()?;
and
let node_profile_encrypted: Arc<EncryptedTestProfile> = de_node.as_struct_ref()?;

THIS IS A CRITICAL FUNCTIONALITY. that seift must micit and do exactly like rust does.

te test shoudl also shows the sme as test test_encryption_basic that we can use the types
created by the macros directly like:
 let encrypted: EncryptedTestProfile =
        original.encrypt_with_keystore(&mobile_ks, resolver.as_ref())?;

The type EncryptedTestProfile was genrated by the Encrypt macro in rust.. ew need the same capability in swift.
And be able to:
let decrypted_mobile = encrypted.decrypt_with_keystore(&mobile_ks)?;

and test eh decruyption with both key stores, mobile and ndoe (which has different keys, and can decryption differen setup of fields:
let decrypted_mobile = encrypted.decrypt_with_keystore(&mobile_ks)?;
    assert_eq!(decrypted_mobile.id, original.id);
    assert_eq!(decrypted_mobile.name, original.name);
    assert_eq!(decrypted_mobile.private, original.private);
    assert_eq!(decrypted_mobile.email, original.email);
    assert!(decrypted_mobile.system_metadata.is_empty()); // Mobile should NOT have access to system_metadata

    // Test decryption with node (should have access to system fields but not user fields)
    let decrypted_node = encrypted.decrypt_with_keystore(&node_ks)?;
    assert_eq!(decrypted_node.id, original.id);
    assert_eq!(decrypted_node.name, original.name);
    assert!(decrypted_node.private.is_empty()); // Should be empty for node
    assert_eq!(decrypted_node.email, original.email);
    assert_eq!(decrypted_node.system_metadata, original.system_metadata); // Node should have access to system_metadata


THIS IS THE CRUCIAL FEATURE OF THE Serializer encryptoin mechanism.. the ablity to encrypt Field Groups Labels and debcrupt them dependneign on what keyus are vailable in the key store presented.