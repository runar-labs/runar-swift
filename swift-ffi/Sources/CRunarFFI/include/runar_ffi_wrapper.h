#pragma once

// Prefer the Rust workspace header when available; otherwise, fall back to bundled copy
#if __has_include("../../../../runar-rust/runar-ffi/include/runar_ffi.h")
#  include "../../../../runar-rust/runar-ffi/include/runar_ffi.h"
#else
#  include "runar_ffi.h"
#endif


