import AppKit

/// Owns one shelf panel's lifecycle: positioning it under the cursor, keeping it on top
/// across every Space, and tearing it (and its temp files) down when the user closes it.
final class ShelfWindowController: NSObject, ShelfViewControllerDelegate {

    private var panel: ShelfPanel!
    private var viewController: ShelfViewController!
    private var spaceChangeObserver: NSObjectProtocol?

    /// Called once the shelf has been closed and fully cleaned up.
    var onClose: (() -> Void)?

    func show(at screenPoint: CGPoint) {
        let controller = ShelfViewController()
        controller.delegate = self
        viewController = controller

        let width = controller.panelWidth
        let height: CGFloat = 320

        let panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height))
        // contentView, not contentViewController: NSWindow ties a contentViewController's
        // view to the window via its contentLayoutGuide, which — like the Auto Layout
        // chain further down — doesn't track an animated setFrame smoothly. Assigning
        // contentView directly uses the older, purely autoresizing-based mechanism, which
        // is guaranteed to stay in lockstep with the window's frame on every single frame
        // of the animation (it's the same code path that's always made interactive corner
        // resizing perfectly smooth).
        panel.contentView = controller.view
        panel.setFrame(frame(for: screenPoint, width: width, height: height), display: true)
        self.panel = panel

        // orderFrontRegardless() skips the fade-in that animationBehavior would otherwise
        // give an ordinary orderFront — closing (below) does get that automatic fade, so
        // without this the shelf used to pop in instantly but fade out smoothly. Doing
        // both explicitly keeps them symmetric regardless of that AppKit quirk.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }

        // canJoinAllSpaces marks the window as belonging to every Space, but the
        // WindowServer doesn't always repaint it into the newly active Space the instant
        // Mission Control finishes switching — re-asserting front-most order on every
        // Space change nudges it to actually redraw there. orderFrontRegardless() only
        // reorders windows, it never activates the app or steals key status.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.panel?.orderFrontRegardless()
        }
    }

    /// Centers the panel a little below the cursor (like a tooltip), clamped to stay fully
    /// on the screen the cursor is currently on.
    private func frame(for point: CGPoint, width: CGFloat, height: CGFloat) -> NSRect {
        var origin = CGPoint(x: point.x - width / 2, y: point.y - height - 16)

        let screen = NSScreen.screens.first { NSPointInRect(point, $0.frame) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - width - 8))
            origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - height - 8))
        }
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    func shelfDidRequestClose(_ controller: ShelfViewController) {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel = nil
            self?.viewController = nil
            self?.onClose?()
        })
    }
}
