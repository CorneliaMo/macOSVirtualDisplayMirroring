import Foundation

final class LatestValueMailbox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Value?
    private var drainScheduled = false
    private var accepting = false

    func activate() { lock.withLock { accepting = true } }

    func offer(_ value: Value) -> Bool {
        lock.withLock {
            guard accepting else { return false }
            pending = value
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
    }

    func take() -> Value? { lock.withLock { pending.take() } }

    func finishDrain() -> Bool {
        lock.withLock {
            guard pending != nil else { drainScheduled = false; return false }
            return true
        }
    }

    func deactivateAndClear() {
        lock.withLock {
            accepting = false
            pending = nil
            drainScheduled = false
        }
    }
}

private extension Optional {
    mutating func take() -> Wrapped? {
        let value = self
        self = nil
        return value
    }
}
