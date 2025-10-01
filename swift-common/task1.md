# Logger Design - Complete Replacement

## Requirements Analysis

### 1. Hierarchical Logger Structure
- Start with a root logger and create child loggers
- Child loggers inherit context from parent loggers
- Log output shows full hierarchy: `[root_component parent_component current_logger_component root_context]`

`[root_component childA_component childB_(current)_logger_component root_context childA_context childB_context]`

### 2. Global Configuration System
- LoggerConfig can be set globally using lock-free atomics
- All loggers affected by global config (unless using specific config)
- Per-logger config overrides global config
- Single atomic read for consistency and performance

### 3. Rust-style Log Format
- Format: `[timestamp level] [root_component parent_component current_logger_component root_context] <message>`
- Example: `[2025-10-01T08:04:31.089Z TRACE] [ffi Network ca-tests] FFI client creation - creating CaClientBuilder with config`

### 4. Efficient Parameter Evaluation
- Parameters only evaluated if log level is enabled
- Avoid expensive operations when logging is disabled
- One-liner syntax similar to Rust's `log_trace!()`

## Design Solution

### Core Components

#### LoggerConfig
- `level: LogLevel` - Global log level
- `includeTimestamp: Bool` - Include timestamp in output
- `includeComponent: Bool` - Include component hierarchy
- `includeContext: Bool` - Include context information

#### LoggerConfigManager
- `shared` singleton instance
- `globalConfig: LoggerConfig` - Lock-free atomic global configuration
- Uses `ManagedAtomic<UInt64>` for single-read consistency
- All loggers inherit from global config unless overridden

#### Logger (Main Class)
- `parent: Logger?` - Parent logger reference
- `component: Component` - Current logger component
- `context: String?` - Current logger context
- `config: LoggerConfig` - Logger-specific config (inherits from global)

### Hierarchical Structure

#### Factory Methods
- `Logger.root(component:context:config:)` - Create root logger
- `logger.child(component:context:)` - Create child logger

#### Context Inheritance
- Child loggers inherit parent's context chain
- Full hierarchy built by traversing up to root
- Context displayed as: `[root_component parent_component current_component root_context parent_context current_context]`

### Efficient Logging with @autoclosure

#### Logging Methods
- `logger.trace(_ message: @autoclosure () -> String)`
- `logger.debug(_ message: @autoclosure () -> String)`
- `logger.info(_ message: @autoclosure () -> String)`
- `logger.warning(_ message: @autoclosure () -> String)`
- `logger.error(_ message: @autoclosure () -> String)`

#### Lazy Evaluation
- `@autoclosure` wraps string interpolation in closure
- Closure only executed if `shouldLog(level:)` returns true
- Expensive operations skipped when logging disabled
- Zero-cost when logging is disabled

### Log Formatting

#### Output Format
```
[timestamp] [level] [component_hierarchy context_hierarchy] message
```

#### Example Output
```
[2025-01-15T08:04:31.089Z TRACE] [ffi Network Custom main tls handshake] Starting TLS handshake with peer: peer123
```

#### Hierarchy Building
- Traverse from current logger to root
- Collect components and contexts
- Display in order: root → parent → current
- Separate components and contexts with spaces

### Usage Patterns

#### Basic Usage
```swift
let logger = Logger.root(component: .ffi, context: "main")
logger.info("Node started successfully")
```

#### Hierarchical Usage
```swift
let rootLogger = Logger.root(component: .ffi, context: "main")
let networkLogger = rootLogger.child(component: .network, context: "tls")
let handshakeLogger = networkLogger.child(component: .custom, context: "handshake")
handshakeLogger.trace("Starting handshake with peer: \(getPeerId())")
```

#### Global Configuration
```swift
LoggerConfigManager.shared.globalConfig = LoggerConfig(level: .info)
let logger = Logger.root(component: .service) // Uses global config
```

### Performance Benefits

#### Without @autoclosure (Current)
- Parameters always evaluated
- Expensive operations run even when logging disabled
- Performance impact in production

#### With @autoclosure (New Design)
- Parameters only evaluated if log level enabled
- Expensive operations skipped when logging disabled
- Zero-cost when logging is disabled
- Same performance as Rust macros

### Key Features

✅ **Hierarchical Structure**: Parent-child relationships with context inheritance
✅ **Global Configuration**: Lock-free atomic configuration with per-logger overrides
✅ **Rust-style Format**: Exact format matching Rust logger
✅ **Lazy Evaluation**: Parameters only evaluated if log level is enabled
✅ **Clean API**: Simple factory methods and intuitive usage
✅ **Performance**: Zero-cost when logging is disabled, single atomic read for config
✅ **Thread Safety**: All operations are thread-safe using Swift Atomics

### Implementation Strategy

1. **Replace Existing Logger**: Complete replacement of `RunarLogger` with new `Logger`
2. **No Legacy Code**: Clean implementation without backward compatibility
3. **@autoclosure Approach**: Use Swift's built-in lazy evaluation instead of macros
4. **Hierarchical Context**: Implement parent-child relationship with context inheritance
5. **Atomic Global Config**: Lock-free configuration using `ManagedAtomic<UInt64>`
6. **Rust Parity**: Match exact format and behavior of Rust logger

### Atomic Configuration Implementation

#### UInt64 Bit Layout
```
Bits 0-2:   LogLevel (0=trace, 1=debug, 2=info, 3=warning, 4=error)
Bit 3:      includeTimestamp (1=enabled, 0=disabled)
Bit 4:      includeComponent (1=enabled, 0=disabled)  
Bit 5:      includeContext (1=enabled, 0=disabled)
Bits 6-63:  Reserved (future use)
```

#### LoggerConfigManager Implementation
- `private static let _globalConfig = ManagedAtomic<UInt64>(0)`
- `globalConfig` getter: Decode atomic value to `LoggerConfig`
- `globalConfig` setter: Encode `LoggerConfig` to atomic value
- No `Sendable` conformance needed (just a facade over atomics)

#### RunarLogger Behavior
- If explicit config provided: use it directly
- Otherwise: read atomic config on each log call
- `shouldLog`: Compare level ordinals from atomic read
- Formatting: Use flags from atomic read for timestamp/component/context

This design achieves all requirements from the Rust logger while leveraging Swift's `@autoclosure` for optimal performance and Swift Atomics for lock-free global configuration.