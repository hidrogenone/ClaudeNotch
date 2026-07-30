import AppKit

/// Detects "someone else is probably looking at this screen" situations where
/// a surprise notch drop-down would be embarrassing: a mirrored display
/// (projector/AirPlay) or a remote Screen Sharing session. Window captures by
/// apps like Zoom have no public detection API, so those are out of scope.
enum QuietMode {
    static var isActive: Bool {
        guard Settings.shared.quietWhenPresenting else { return false }
        return screenIsMirrored || screenIsShared
    }

    private static var screenIsMirrored: Bool {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &displayCount) == .success else { return false }
        return (0..<Int(displayCount)).contains { CGDisplayIsInMirrorSet(displays[$0]) != 0 }
    }

    private static var screenIsShared: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsShared"] as? Bool) ?? false
    }
}
