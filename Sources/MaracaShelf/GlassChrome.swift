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
            pinTrackingAnimatedResize(content, into: glass)
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
            pinStatic(content, into: glass)
            return glass
        }
        return legacyTranslucentWrapper(cornerRadius: cornerRadius, content: content)
    }

    /// Makes `content` fill `container` exactly, for chrome whose *container* itself gets
    /// resized by an animated `setFrame` (only the shelf's main panel, via its collapse/
    /// expand animation). Deliberately uses an autoresizing mask instead of
    /// NSLayoutConstraint: AppKit tracks the window's contentView smoothly in lockstep
    /// every frame of an animated resize, but Auto Layout constraints on views further down
    /// the hierarchy only get resolved once the animation settles — which showed up as the
    /// rounded glass background visibly lagging behind (a "ghost" of the old size) until
    /// the animation finished. Autoresizing masks resize synchronously with their
    /// superview's frame, so the glass tracks the window exactly.
    ///
    /// Don't reuse this for content that never gets resized by an outside animation (i.e.
    /// `control`'s small fixed-size buttons) — `NSGlassEffectView.contentView` already adds
    /// its own internal Auto Layout constraints pinning the content's edges, and forcing
    /// autoresizing on top of that fights those constraints instead of just being
    /// redundant, producing a real "Conflicting constraints detected" warning at runtime
    /// (only visible via Xcode's build log, not a plain `swift build`). Use `pinStatic`
    /// there instead, which cooperates with those constraints instead of overriding them.
    private static func pinTrackingAnimatedResize(_ content: NSView, into container: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]
        content.frame = container.bounds
    }

    /// Makes `content` fill `container` exactly, for chrome that's never itself resized by
    /// an outside animation (the small close/collapse/remove buttons). Plain Auto Layout
    /// constraints, which is what `NSGlassEffectView.contentView` already expects/manages
    /// internally — see `pinTrackingAnimatedResize` for why the two aren't interchangeable.
    private static func pinStatic(_ content: NSView, into container: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
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
        pinTrackingAnimatedResize(content, into: effect)
        return effect
    }

    private static func legacyTranslucentWrapper(cornerRadius: CGFloat, content: NSView) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = cornerRadius
        wrapper.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor

        wrapper.addSubview(content)
        pinStatic(content, into: wrapper)
        return wrapper
    }
}
