import AppKit

/// Owns one shelf panel's lifecycle: positioning it under the cursor, keeping it on top
/// across every Space, and tearing it (and its temp files) down when the user closes it.
final class ShelfWindowController: NSObject, ShelfViewControllerDelegate {

    private var panel: ShelfPanel!
    private var viewController: ShelfViewController!
    private var spaceChangeObserver: NSObjectProtocol?
    private var dragMonitor: Any?

    // MARK: - Peek (Picture-in-Picture-style edge hiding)

    private var isPeeked = false
    private var prePeekFrame: NSRect?
    private var mouseDownFrame: NSRect?
    private let peekEdgeThreshold: CGFloat = 40
    private let peekTabSize = NSSize(width: 40, height: 120)
    private lazy var peekTab: PeekTabView = {
        let tab = PeekTabView(frame: NSRect(origin: .zero, size: peekTabSize))
        tab.onActivate = { [weak self] in self?.exitPeek() }
        return tab
    }()
    // A completely separate small content view, swapped in for `controller.view` while
    // peeked, rather than trying to shrink the normal content down to tab size in place.
    // The normal layout has several children with hard minimums that don't shrink that far
    // (dropHintLabel's fixed 180pt width, countPill's intrinsic content size) — `isHidden`
    // doesn't deactivate a view's own constraints outside of NSStackView, so those would
    // keep fighting a 40pt-wide target frame. A separate, unrelated view sidesteps that
    // entirely instead of hunting down and re-tuning every one of them.
    private lazy var peekContentView: NSView = GlassChrome.panel(cornerRadius: 20, content: peekTab)

    /// Called once the shelf has been closed and fully cleaned up.
    var onClose: (() -> Void)?

    func show(at screenPoint: CGPoint) {
        let controller = ShelfViewController()
        controller.delegate = self
        viewController = controller

        let width = controller.panelWidth
        let height = controller.expandedHeight

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

        // Detects "the user dragged the panel to a screen edge and let go" — like Safari's
        // Picture-in-Picture window auto-hiding to a peek tab at the edge. A local monitor
        // (not global) is enough since this only ever needs to see drags of our own panel,
        // unlike ShakeDragMonitor, which must see drags over *other* apps' windows too.
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handlePotentialEdgeDrag(event)
            return event
        }
    }

    private func handlePotentialEdgeDrag(_ event: NSEvent) {
        guard !isPeeked, let panel, event.window === panel else { return }
        switch event.type {
        case .leftMouseDown:
            mouseDownFrame = panel.frame
        case .leftMouseUp:
            defer { mouseDownFrame = nil }
            // Only a real drag (the frame actually changed) counts — a plain click on one
            // of the header buttons, or on a grid item, never moves the window, so this
            // naturally excludes those without needing to inspect what was actually clicked.
            guard let startFrame = mouseDownFrame, startFrame != panel.frame else { return }
            evaluateEdgeSnap()
        default:
            break
        }
    }

    private func evaluateEdgeSnap() {
        guard let panel, let screen = panel.screen else { return }
        let frame = panel.frame
        if frame.minX - screen.frame.minX < peekEdgeThreshold {
            enterPeek(pointingRight: true, on: screen)
        } else if screen.frame.maxX - frame.maxX < peekEdgeThreshold {
            enterPeek(pointingRight: false, on: screen)
        }
    }

    /// Slides the panel to a small tab at the nearest screen edge. Nothing in the shelf
    /// (its files, the temp session directory) is touched — this only repositions the
    /// window and swaps which view it hosts, so everything is exactly as it was once the
    /// shelf is pulled back out. Only closing it (the "×") actually tears anything down.
    private func enterPeek(pointingRight: Bool, on screen: NSScreen) {
        guard let panel else { return }
        // Clamped, not stored as-is: the drag that triggered this may well have carried
        // the panel well past the edge rather than stopping right at it (the edge check
        // below only has an upper bound on how close it must be, not a lower one) —
        // restoring to that unclamped position would reopen the shelf mostly off-screen
        // instead of back where it visually was.
        prePeekFrame = clamped(panel.frame, toVisibleFrameOf: screen)
        isPeeked = true
        peekTab.setDirection(pointingRight: pointingRight)

        let clampedY = max(screen.visibleFrame.minY + 8,
                            min(panel.frame.midY - peekTabSize.height / 2,
                                screen.visibleFrame.maxY - peekTabSize.height - 8))
        let x: CGFloat = pointingRight ? screen.frame.minX : screen.frame.maxX - peekTabSize.width
        let tabFrame = NSRect(x: x, y: clampedY, width: peekTabSize.width, height: peekTabSize.height)

        // Cross-fades through fully transparent rather than animating the content swap or
        // frame change directly. Swapping contentView first would briefly stretch the tiny
        // tab to fill the still-large window (it tracks the window's current size via
        // autoresizing); animating the frame shrink first would do the same lagging-content
        // dance collapsedHeight was tuned to avoid, except worse (the grid/header content
        // isn't built to shrink to 40pt wide at all). Swapping while invisible sidesteps
        // both.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, let panel = self.panel else { return }
            panel.contentView = self.peekContentView
            panel.setFrame(tabFrame, display: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        })
    }

    /// Restores the shelf to exactly where it was before peeking, via the same
    /// fade-through-invisible swap `enterPeek` uses.
    private func exitPeek() {
        guard let panel, let restoreFrame = prePeekFrame else { return }
        isPeeked = false
        prePeekFrame = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, let panel = self.panel, let viewController = self.viewController else { return }
            panel.contentView = viewController.view
            panel.setFrame(restoreFrame, display: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        })
    }

    /// Centers the panel a little below the cursor (like a tooltip), clamped to stay fully
    /// on the screen the cursor is currently on.
    private func frame(for point: CGPoint, width: CGFloat, height: CGFloat) -> NSRect {
        let origin = CGPoint(x: point.x - width / 2, y: point.y - height - 16)
        let screen = NSScreen.screens.first { NSPointInRect(point, $0.frame) } ?? NSScreen.main
        let frame = NSRect(origin: origin, size: NSSize(width: width, height: height))
        return screen.map { clamped(frame, toVisibleFrameOf: $0) } ?? frame
    }

    /// Nudges a frame to fit fully within a screen's visible area (an 8pt margin from the
    /// edges), shrinking neither its width nor height — just repositioning it.
    private func clamped(_ frame: NSRect, toVisibleFrameOf screen: NSScreen) -> NSRect {
        var frame = frame
        let visible = screen.visibleFrame
        frame.origin.x = max(visible.minX + 8, min(frame.origin.x, visible.maxX - frame.width - 8))
        frame.origin.y = max(visible.minY + 8, min(frame.origin.y, visible.maxY - frame.height - 8))
        return frame
    }

    func shelfDidRequestClose(_ controller: ShelfViewController) {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
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
