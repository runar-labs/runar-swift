@swift-serializer/ I had to stop work on this package to work on the FFI refactory.. which now is done.. Help find the current state of this package..

Goal #1 - Asses the current state of the seift-serializer package, the code, test and also the md files swift-serializer/improve_async_02.md, swift-serializer/label_resolver_issues.md and swift-serializer/use_ffi_keys.md

See what is relevante, that is outdate, what was done vs not done in teh code.. Some of it is  old and outdate.. for example the FFI does not have label resolver anymore.. the label resolve is all done int eh rust sude.. the seift side just provide the configuration.. the label config , btu the label resovler itself used by the keys for encryptoin is managed in the rust side.. so whne looikg at all these md file.. consider teh latest veriosn fo the FFI /Users/rafael/dev/runar-swift/runar-rust/runar-ffi in terms of what is offering currently.

The purpose of the /Users/rafael/dev/runar-swift/swift-serializer package is to implement a 100% mirror fo the rust version /Users/rafael/dev/runar-swift/runar-rust/runar-serializer .. it works in conjunctin with /Users/rafael/dev/runar-swift/swift-serializer-macros which is also a mirror of /Users/rafael/dev/runar-swift/runar-rust/runar-serializer-macros  BUT using prtoper swsift semantics and feauures and best practices..

BUT swift does not have its down keys packges. it will use these features via the FFI intertface /Users/rafael/dev/runar-swift/swift-ffi ..


Fo the Goal here is to do a complet analisys taking all this into consideration..and provcide a cvurrent state of the swift-serializer  and swift-serializer-macros  vs its goals.. and these partiaply implements md files.. to we can discard them.. and create a single MD filw with all the remainig works that need sto be done.. addresseing fixes, gaps and improvement needed to acheive the goals of these swift package to be 100% aligned to their rust counterpars and using the swift-ffi lib to perform encryption in the seraializer .