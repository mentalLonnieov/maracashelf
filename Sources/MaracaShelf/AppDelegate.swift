import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let shakeMonitor = ShakeDragMonitor()
    private var activeShelf: ShelfWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    private var settingsMenuItem: NSMenuItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ShelfStorage.cleanUpOrphanedSessions()
        promptForAccessibilityIfNeeded()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshMenuTitles),
            name: LocalizationManager.languageDidChangeNotification, object: nil
        )

        shakeMonitor.onShake = { [weak self] location in
            self?.handleShake(at: location)
        }
        shakeMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeMonitor.stop()
    }

    private func handleShake(at location: CGPoint) {
        // Only one shelf at a time — a second shake while one is open just leaves it be.
        guard activeShelf == nil else { return }

        let shelf = ShelfWindowController()
        shelf.onClose = { [weak self] in
            self?.activeShelf = nil
        }
        shelf.show(at: location)
        activeShelf = shelf
    }

    private func promptForAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.loadStatusIcon()

        let menu = NSMenu()
        menu.addItem(withTitle: "MaracaShelf", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let settingsItem = menu.addItem(withTitle: "", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        settingsMenuItem = settingsItem

        let accessibilityItem = menu.addItem(withTitle: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        accessibilityMenuItem = accessibilityItem

        menu.addItem(.separator())

        let quitItem = menu.addItem(withTitle: "", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitMenuItem = quitItem

        item.menu = menu
        statusItem = item
        refreshMenuTitles()
    }

    @objc private func refreshMenuTitles() {
        settingsMenuItem?.title = L("menu.settings")
        accessibilityMenuItem?.title = L("menu.accessibility")
        quitMenuItem?.title = L("menu.quit")
    }

    /// Loads the custom maraca menu-bar icon from the app bundle's Resources (both @2x and
    /// @3x representations, so it stays crisp on any display), tagged as a template image
    /// so macOS tints it correctly for light/dark menu bars and the highlighted state.
    /// Falls back to a generic SF Symbol if the bundled files aren't present — e.g. when
    /// running the raw debug binary directly instead of the packaged .app.
    private static func loadStatusIcon() -> NSImage? {
        guard let resourceURL = Bundle.main.resourceURL else { return fallbackIcon() }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        var loadedAny = false
        for suffix in ["@2x", "@3x"] {
            let url = resourceURL.appendingPathComponent("MaracaStatusIcon\(suffix).png")
            if let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) {
                rep.size = NSSize(width: 18, height: 18)
                image.addRepresentation(rep)
                loadedAny = true
            }
        }
        guard loadedAny else { return fallbackIcon() }
        image.isTemplate = true
        return image
    }

    private static func fallbackIcon() -> NSImage? {
        NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "MaracaShelf")
    }

    @objc private func openSettings() {
        let controller = settingsWindowController ?? SettingsWindowController()
        settingsWindowController = controller
        controller.show()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
