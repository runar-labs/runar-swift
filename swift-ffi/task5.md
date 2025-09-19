implement all changes in /Users/rafael/dev/runar-swift/swift-ffi/KEY_MANAGER_UNIFIED_DESIGN.md

follow our code standards rules /Users/rafael/dev/runar-swift/.cursor/rules/code-standards.mdc

Goal is completely remove and replace KeysHandle with the current design. this will impact a lot of tests.. the tests must be chanbges to use this new design.. either a mobile or a node key manager.. be careful when changing and choosing it.

U can leave teh removal of KeysHandle to the end.. after u havce changed the tests nd theuy are 100% working iwth the new types.

DO NOT CHANGE ANYTHIGN ELSE in the tests.. do not compromise or break them.. they are currentl all workign properly.. so make sure the cotinue after all your changes.. 