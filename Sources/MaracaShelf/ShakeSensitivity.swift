import Foundation

/// How vigorously the user needs to shake a dragged file to open the shelf. `0` means
/// "least sensitive" (needs a bigger, more emphatic shake), `1` means "most sensitive" (a
/// light wiggle is enough). Persisted via UserDefaults so it survives relaunches and can be
/// changed live from the settings window while `ShakeDragMonitor` keeps running.
enum ShakeSensitivity {
    private static let key = "ShakeSensitivity"
    static let defaultValue: Double = 0.5

    static var value: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: key) as? Double ?? defaultValue
            return min(max(stored, 0), 1)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0), 1), forKey: key)
        }
    }
}
