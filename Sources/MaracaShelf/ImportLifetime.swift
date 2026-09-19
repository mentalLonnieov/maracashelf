import Foundation

/// One ticket per file, held from accepting a drop through archive completion.
/// Unlike queue ordering, this also accounts for callbacks scheduled in the future.
final class ImportLifetime {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var closed = false

    @discardableResult
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }
        group.enter()
        return true
    }

    func finish() { group.leave() }

    func close(cleanup: @escaping () -> Void) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        lock.unlock()
        group.notify(queue: .global(qos: .utility), execute: cleanup)
    }
}
