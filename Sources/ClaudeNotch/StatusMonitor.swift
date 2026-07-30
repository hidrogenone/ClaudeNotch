import Foundation

final class StatusMonitor {
    static let summaryURL = URL(string: "https://status.claude.com/api/v2/summary.json")!
    static let statusPageURL = URL(string: "https://status.claude.com")!

    /// Called on the main thread after every poll with the latest summary and
    /// the alert derived from it (nil when everything monitored is healthy).
    var onUpdate: ((StatusSummary?, AlertInfo?) -> Void)?

    private(set) var lastSummary: StatusSummary?
    private var timer: Timer?

    func start() {
        poll()
        reschedule()
    }

    func reschedule() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Settings.shared.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-evaluates the last summary without a network round-trip,
    /// e.g. after the user changes which components are monitored.
    func reevaluate() {
        guard let summary = lastSummary else { return }
        onUpdate?(summary, Self.evaluate(summary))
    }

    func poll() {
        var request = URLRequest(url: Self.summaryURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let summary = data.flatMap { try? JSONDecoder().decode(StatusSummary.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                if let summary {
                    self.lastSummary = summary
                    self.onUpdate?(summary, Self.evaluate(summary))
                }
                // A failed fetch keeps the previous state; we never alarm on our own network errors.
            }
        }.resume()
    }

    static func evaluate(_ summary: StatusSummary) -> AlertInfo? {
        let settings = Settings.shared

        let troubled = summary.components.filter {
            $0.status != "operational" && settings.isMonitored($0.id)
        }
        // An incident with no component list is shown regardless of filters.
        let incidents = summary.incidents.filter { incident in
            guard let components = incident.components, !components.isEmpty else { return true }
            return components.contains { settings.isMonitored($0.id) }
        }

        if troubled.isEmpty && incidents.isEmpty { return nil }

        if let incident = incidents.max(by: { impactRank($0.impact) < impactRank($1.impact) }) {
            let affected = (incident.components ?? [])
                .filter { settings.isMonitored($0.id) }
                .map(\.name)
            let fallback = troubled.map(\.name)
            let names = (affected.isEmpty ? fallback : affected).joined(separator: " · ")
            let detail = names.isEmpty
                ? (incident.incidentUpdates?.first?.body ?? "See status page for details")
                : names
            let url = incident.shortlink.flatMap(URL.init(string:)) ?? statusPageURL
            return AlertInfo(title: incident.name, detail: detail, impact: incident.impact, url: url)
        }

        let names = troubled.map { "\($0.name): \(humanComponentStatus($0.status))" }
            .joined(separator: " · ")
        let isMajor = troubled.contains { $0.status == "major_outage" || $0.status == "partial_outage" }
        return AlertInfo(
            title: "Claude service disruption",
            detail: names,
            impact: isMajor ? "major" : "minor",
            url: statusPageURL
        )
    }
}
