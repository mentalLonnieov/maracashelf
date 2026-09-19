import AppKit

/// Watches global mouse activity while the left button is held down (i.e. while the user
/// is dragging something — a file from Finder, Mail, etc.) and fires a callback when it
/// recognizes a "shake" pattern: several quick direction reversals in a short time window.
final class ShakeDragMonitor {

    /// Called with the current screen-space mouse location when a shake is recognized.
    var onShake: ((CGPoint) -> Void)?

    // Tunables. `requiredReversals` and `minSwing` scale with the user's chosen
    // ShakeSensitivity (read fresh on every check, so a change in Settings takes effect on
    // the very next shake attempt); at the default sensitivity (0.5) they match this
    // detector's original fixed values (3 reversals, 20px).
    private var requiredReversals: Int {
        Int((4.0 - 2.0 * ShakeSensitivity.value).rounded())
    }
    private var minSwing: CGFloat {
        CGFloat(32.0 - 24.0 * ShakeSensitivity.value)
    }
    private let windowDuration: TimeInterval = 0.9   // shake must happen within this time span
    private let cooldown: TimeInterval = 1.1   // minimum time between two triggers

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var isMouseDown = false
    private var samples: [(t: TimeInterval, p: CGPoint)] = []
    private var lastTrigger: TimeInterval = 0

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        // Local monitor lets detection keep working even while the mouse is over our own
        // panel (global monitors only see events destined for *other* applications).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        reset()
    }

    private func reset() {
        isMouseDown = false
        samples.removeAll()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            isMouseDown = true
            samples = [(now(), NSEvent.mouseLocation)]

        case .leftMouseUp:
            reset()

        case .leftMouseDragged:
            guard isMouseDown else { return }
            let t = now()
            samples.append((t, NSEvent.mouseLocation))
            // Keep only samples within the detection window.
            samples.removeAll { t - $0.t > windowDuration }

            if t - lastTrigger < cooldown { return }
            if detectShake() {
                lastTrigger = t
                let location = NSEvent.mouseLocation
                samples.removeAll()
                onShake?(location)
            }

        default:
            break
        }
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func detectShake() -> Bool {
        guard samples.count >= 4 else { return false }
        let xs = samples.map { $0.p.x }
        let ys = samples.map { $0.p.y }
        return countReversals(xs) >= requiredReversals || countReversals(ys) >= requiredReversals
    }

    /// Counts direction reversals in a series of positions, collapsing movements smaller
    /// than `minSwing` so ordinary mouse jitter doesn't count.
    private func countReversals(_ values: [CGFloat]) -> Int {
        guard var lastExtremum = values.first else { return 0 }
        var direction = 0 // -1, 0, 1
        var segments = 0

        for value in values.dropFirst() {
            let diff = value - lastExtremum
            if abs(diff) < minSwing { continue }
            let dir = diff > 0 ? 1 : -1
            if direction == 0 {
                direction = dir
                lastExtremum = value
            } else if dir != direction {
                segments += 1
                direction = dir
                lastExtremum = value
            } else {
                lastExtremum = value
            }
        }
        return segments
    }
}
