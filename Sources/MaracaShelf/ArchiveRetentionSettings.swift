import Foundation

/// How many days a file stays in the persistent archive before `ArchiveStorage` purges it
/// automatically. Persisted via UserDefaults so it survives relaunches, mirroring
/// `ShakeSensitivity`'s storage pattern.
enum ArchiveRetentionSettings {
    private static let key = "ArchiveRetentionDays"
    static let defaultValue = 7
    static let minValue = 1
    static let maxValue = 30

    static var days: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: key) as? Int ?? defaultValue
            return min(max(stored, minValue), maxValue)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, minValue), maxValue), forKey: key)
        }
    }
}
