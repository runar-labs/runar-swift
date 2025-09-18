based on swift-ffi/code_review_01.md  ther are a few items I want further investigation and detailed analisys before we proceed with changes and implementations:

1) Error handling
Consistent “withRnError” wrapper and typed FFIError. Good.
Message extraction frees rn_string_free reliably. Good.
One inconsistency: only setLocalNodeInfo tries rn_last_error on failure; everything else relies on RNAPIRnError. This is fine; RNAPIRnError is the primary channel. Keep rn_last_error only for legacy code paths that do not use error structs (which you’ve already done).

What is the issue here ? is taht the FFI API in rust for setLocalNodeInfo does nto follow the same pattern as the other APIS.. it is usign something called rn_last_error ?? is taht only this API.?? ANy other Rust FFI does that ?


If that is the case.. I think we need to fix this at the rust level.. so ALL APIS follow the sme patternf or error habndling.. and so we can also do he same at the swift level..