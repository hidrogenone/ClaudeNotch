import Foundation

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let disabledComponents = "disabledComponentIDs"
        static let pollInterval = "pollInterval"
        static let edgeFlashEnabled = "edgeFlashEnabled"
    }

    /// Components the user chose NOT to monitor. Everything is monitored by default.
    var disabledComponentIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.disabledComponents) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.disabledComponents) }
    }

    var pollInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.pollInterval)
            return value >= 15 ? value : 60
        }
        set { defaults.set(newValue, forKey: Key.pollInterval) }
    }

    var edgeFlashEnabled: Bool {
        get { defaults.object(forKey: Key.edgeFlashEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.edgeFlashEnabled) }
    }

    func isMonitored(_ componentID: String) -> Bool {
        !disabledComponentIDs.contains(componentID)
    }

    func toggleMonitored(_ componentID: String) {
        var set = disabledComponentIDs
        if set.contains(componentID) {
            set.remove(componentID)
        } else {
            set.insert(componentID)
        }
        disabledComponentIDs = set
    }
}
