import AppKit

/// Mirrors the Liquid Glass intensity control macOS 26+ exposes in System Settings →
/// Appearance (more see-through vs. more frosted/matte). As of this SDK, Apple hasn't
/// published an AppKit API to read it — but it's a plain, world-readable user default
/// (`defaults read -g NSGlassTintAmount`), so we read that directly instead of hard-coding
/// one fixed look.
enum SystemGlassSettings {
    private static let defaultsKey = "NSGlassTintAmount"

    /// 0 = as transparent as the system allows, 1 = fully frosted/opaque. Falls back to a
    /// neutral middle value if the key is missing (older point release, or Apple renames
    /// it), so the shelf still looks reasonable either way.
    static var tintAmount: CGFloat {
        guard let value = UserDefaults.standard.object(forKey: defaultsKey) as? Double else {
            return 0.5
        }
        return CGFloat(min(max(value, 0), 1))
    }

    /// Linear interpolation helper for scaling a tint's opacity by `tintAmount`.
    static func lerp(_ minValue: CGFloat, _ maxValue: CGFloat, amount: CGFloat) -> CGFloat {
        minValue + (maxValue - minValue) * amount
    }
}
