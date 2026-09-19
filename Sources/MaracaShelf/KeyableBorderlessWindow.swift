import AppKit

/// A borderless, custom-chrome `NSWindow` that still becomes key/main like an ordinary
/// window. Plain `NSWindow(styleMask: [.borderless, ...])` defaults `canBecomeKey`/
/// `canBecomeMain` to `false` (verified directly against the real AppKit implementation —
/// this isn't a guess) — invisible unless you go looking for it, since this app's own
/// custom controls (`RoundIconButton`, `PillButton`) already override
/// `acceptsFirstMouse(for:)` to cope with `ShelfPanel` never becoming key. But stock AppKit
/// controls that don't override that (the language `NSPopUpButton`, both sensitivity/
/// storage `NSSlider`s) don't get that workaround, so their very first click in a non-key
/// window would just bring the window forward instead of registering — and keyboard
/// navigation (Tab between controls, Return/Escape) silently wouldn't work at all. Used by
/// `SettingsWindowController` and `ArchiveWindowController`, both deliberately ordinary,
/// interactive windows (unlike `ShelfPanel`, which goes the other way on purpose).
final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
