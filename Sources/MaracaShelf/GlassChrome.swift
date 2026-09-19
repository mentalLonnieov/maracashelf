import AppKit

/// Wraps our UI in real Liquid Glass (`NSGlassEffectView`, macOS 26+) when available,
/// falling back to the older vibrancy material on earlier systems. Callers only ever get
/// back a plain `NSView`, so no call site needs `@available` guards of its own.
enum GlassChrome {

    /// The main shelf body: a heavier, tinted "regular" glass slab.
    static func panel(cornerRadius: CGFloat, content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            let alpha = SystemGlassSettings.lerp(0.16, 0.5, amount: SystemGlassSettings.tintAmount)
            glass.tintColor = NSColor.black.withAlphaComponent(alpha)
            // Deliberately NOT interactive: this is the whole window's background, which
            // the user presses-and-holds to drag it around (isMovableByWindowBackground).
            // Liquid Glass's press feedback (a slight grow/shimmer) is meant for buttons,
            // not something that fires every time you grab the window to move it.
            glass.contentView = content
            pin(content, into: glass)
            return glass
        }
        return legacyMaterial(cornerRadius: cornerRadius, material: .hudWindow, content: content)
    }

    /// Small floating controls (close/collapse buttons, the count pill) that sit on top of
    /// the panel: a lighter "clear" glass with an interactive shimmer on click/hover.
    static func control(cornerRadius: CGFloat, content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .clear
            let alpha = SystemGlassSettings.lerp(0.04, 0.16, amount: SystemGlassSettings.tintAmount)
            glass.tintColor = NSColor.white.withAlphaComponent(alpha)
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = true
            }
            glass.contentView = content
            pin(content, into: glass)
            return glass
        }
        return legacyTranslucentWrapper(cornerRadius: cornerRadius, content: content)
    }

    /// Makes `content` fill `container` exactly. Used after handing a view to
    /// `NSGlassEffectView.contentView` so its size never depends on undocumented internal
    /// behavior — we own the sizing ourselves either way.
    ///
    /// Deliberately uses an autoresizing mask instead of NSLayoutConstraint: when a window
    /// is resized via an animated `setFrame` (see the shelf's collapse/expand), AppKit
    /// tracks the window's contentView smoothly in lockstep every frame, but Auto Layout
    /// constraints on views further down the hierarchy only get resolved once the animation
    /// settles — which showed up as the rounded glass background visibly lagging behind
    /// (a "ghost" of the old size) until the animation finished. Autoresizing masks resize
    /// synchronously with their superview's frame, so the glass tracks the window exactly.
    private static func pin(_ content: NSView, into container: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]
        content.frame = container.bounds
    }

    // MARK: - Pre-macOS 26 fallbacks

    private static func legacyMaterial(cornerRadius: CGFloat, material: NSVisualEffectView.Material, content: NSView) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = material
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true

        effect.addSubview(content)
        pin(content, into: effect)
        return effect
    }

    private static func legacyTranslucentWrapper(cornerRadius: CGFloat, content: NSView) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = cornerRadius
        wrapper.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor

        wrapper.addSubview(content)
        pin(content, into: wrapper)
        return wrapper
    }
}
