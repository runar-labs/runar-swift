@swift-serializer/ I had to stop work on this package to work on the FFI refactory.. which now is done.. Help find the current state of this package..

Goal #1 - Asses the current state of the seift-serializer package, the code, test and also the md files swift-serializer/improve_async_02.md, swift-serializer/label_resolver_issues.md and swift-serializer/use_ffi_keys.md

See what is relevante, and what is outdate, what was done vs not done in teh code.. Some of it is  old and outdate.. for example the FFI does not have label resolver anymore.. the label resolver must be fully implemented in the swift side now.

The purpose of the /Users/rafael/dev/runar-swift/swift-serializer package is to implement a 100% mirror fo the rust version /Users/rafael/dev/runar-swift/runar-rust/runar-serializer .. it works in conjunctin with /Users/rafael/dev/runar-swift/swift-serializer-macros which is also a mirror of /Users/rafael/dev/runar-swift/runar-rust/runar-serializer-macros  BUT using proper swift semantics and feaures and the swift language best practices..

BUT swift does not have its down keys packge. it will use these features via the FFI intertface /Users/rafael/dev/runar-swift/swift-ffi .. mobiline and node key managers.


Fo the Goal here is to do a complete analisys taking all this into consideration..and provide an md document with current state assesment of the swift-serializer  and swift-serializer-macros  vs its goals.. and these partiaply implements md files I mentioned above. so we can discard them and have a single MD filw with all the remainig works that need sto be done. addresseing fixes, gaps and improvement needed to acheive the goals of these swift package to be 100% aligned to their rust counterpars and using the swift-ffi lib to perform encryption in the seraializer.

The detailed document must be in details, in complex areas even provising code example. So the implementation task should have not doubt or have go guess anything.. we need a detailed and complete design. based on the rust functoinality.