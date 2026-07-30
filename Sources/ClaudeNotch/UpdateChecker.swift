import Foundation

/// Compares the running version against the newest GitHub release.
/// No auto-update machinery — just a menu item that opens the release page.
final class UpdateChecker {
    static let latestReleaseURL = URL(string: "https://github.com/hidrogenone/ClaudeNotch/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/hidrogenone/ClaudeNotch/releases/latest")!

    /// Set on the main thread when a newer version exists, e.g. "1.2.0".
    private(set) var availableVersion: String?

    private var timer: Timer?

    func start() {
        check()
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func check() {
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return // running via `swift run`; nothing to compare against
        }
        var request = URLRequest(url: Self.apiURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                self?.availableVersion = Self.isNewer(latest, than: current) ? latest : nil
            }
        }.resume()
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
