import Foundation

/// Minimal activation state machine mirroring Rust's `activation_tx/activation_rx` semantics.
/// Once set active, remains active and notifies observers exactly once.
public final class ActivationStateMachine {
    private var isActive: Bool = false
    private var observers: [(Bool) -> Void] = []
    private let lock = NSLock()

    public init() {}

    /// Subscribe to activation changes. If already active, the callback is invoked immediately with `true`.
    public func subscribe(_ observer: @escaping (Bool) -> Void) {
        lock.lock(); defer { lock.unlock() }
        observers.append(observer)
        if isActive { observer(true) }
    }

    /// Mark connection as active and notify subscribers. Idempotent.
    public func activate() {
        lock.lock(); defer { lock.unlock() }
        if isActive { return }
        isActive = true
        for cb in observers {
            cb(true)
        }
    }

    public func active() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return isActive
    }
}
