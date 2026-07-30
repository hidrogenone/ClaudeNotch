import Foundation

struct StatusSummary: Decodable {
    struct OverallStatus: Decodable {
        let indicator: String
        let description: String
    }

    struct Component: Decodable {
        let id: String
        let name: String
        let status: String
        let groupId: String?

        enum CodingKeys: String, CodingKey {
            case id, name, status
            case groupId = "group_id"
        }
    }

    struct Incident: Decodable {
        struct Update: Decodable {
            let body: String
        }

        let id: String
        let name: String
        let status: String
        let impact: String
        let shortlink: String?
        let incidentUpdates: [Update]?
        let components: [Component]?

        enum CodingKeys: String, CodingKey {
            case id, name, status, impact, shortlink, components
            case incidentUpdates = "incident_updates"
        }
    }

    let status: OverallStatus
    let components: [Component]
    let incidents: [Incident]
}

struct AlertInfo: Equatable {
    let title: String
    let detail: String
    let impact: String // none | minor | major | critical
    let url: URL

    var key: String { title + "|" + impact }
}

func impactRank(_ impact: String) -> Int {
    switch impact {
    case "critical": return 3
    case "major": return 2
    case "minor": return 1
    default: return 0
    }
}

func humanComponentStatus(_ status: String) -> String {
    switch status {
    case "operational": return "Operational"
    case "degraded_performance": return "Degraded performance"
    case "partial_outage": return "Partial outage"
    case "major_outage": return "Major outage"
    case "under_maintenance": return "Under maintenance"
    default: return status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
