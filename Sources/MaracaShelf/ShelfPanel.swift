import AppKit

/// A borderless, non-activating panel that floats above every window, follows the user
/// across Spaces/full-screen apps, and never steals focus from whatever app they were
/// dragging into.
final class ShelfPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // No .resizable: every size change (collapse/expand, peek) is done
            // programmatically via setFrame, which works regardless of this style mask bit
            // — it only gates *user-facing* resize affordances. Removing it is also what
            // stops macOS's window-tiling gesture (Sequoia+: drag a window to a screen edge
            // to snap it to half/full screen) from kicking in while dragging this panel by
            // its background — tiling only offers itself to windows the user could actually
            // resize in the first place.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Tried raising this to .statusBar/.screenSaver to chase a "stranded on the old
        // Space" report, but that didn't fix it and broke drag-and-drop instead — very high
        // levels are excluded from the WindowServer's drag-destination hit-testing. Back to
        // .floating; the actual Space-follow fix is nudging the window on Space-change
        // notifications (see ShelfWindowController), not the window level.
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .utilityWindow
    }

    // Never key/main: besides keeping the previously active app frontmost, this also avoids
    // macOS drawing its system key-window focus ring around the panel. Buttons and the
    // collection view still respond to a single click via acceptsFirstMouse(for:) instead.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
