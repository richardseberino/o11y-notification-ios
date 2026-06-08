//
//  Models.swift
//  Dyntrace Problems App
//

import Foundation

/// Vendor de observabilidade ao qual uma instância se conecta. Cada vendor tem
/// seu próprio conjunto de filtros e endpoint de alertas/problemas.
enum Vendor: String, Codable, CaseIterable, Identifiable {
    case dynatrace
    case grafana

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dynatrace: return "Dynatrace"
        case .grafana: return "Grafana"
        }
    }
}

struct DynatraceInstance: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var vendor: Vendor = .dynatrace
    var name: String = ""
    var baseURL: String = ""
    var apiToken: String = ""
    var managementZone: String = ""
    var entitySelector: String = ""
    var problemSelector: String = ""
    var severityLevel: String = ""
    /// Filtros de labels (Grafana): pares "chave=valor" separados por vírgula ou
    /// quebra de linha, ex.: `severity=critical, team=payments`.
    var labelFilters: String = ""
    var pageSize: Int = 25
    var notificationsEnabled: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, vendor, name, baseURL, apiToken, managementZone, entitySelector,
             problemSelector, severityLevel, labelFilters, pageSize, notificationsEnabled
    }

    init(id: UUID = UUID(),
         vendor: Vendor = .dynatrace,
         name: String = "",
         baseURL: String = "",
         apiToken: String = "",
         managementZone: String = "",
         entitySelector: String = "",
         problemSelector: String = "",
         severityLevel: String = "",
         labelFilters: String = "",
         pageSize: Int = 25,
         notificationsEnabled: Bool = false) {
        self.id = id
        self.vendor = vendor
        self.name = name
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.managementZone = managementZone
        self.entitySelector = entitySelector
        self.problemSelector = problemSelector
        self.severityLevel = severityLevel
        self.labelFilters = labelFilters
        self.pageSize = pageSize
        self.notificationsEnabled = notificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        vendor = try c.decodeIfPresent(Vendor.self, forKey: .vendor) ?? .dynatrace
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiToken = try c.decodeIfPresent(String.self, forKey: .apiToken) ?? ""
        managementZone = try c.decodeIfPresent(String.self, forKey: .managementZone) ?? ""
        entitySelector = try c.decodeIfPresent(String.self, forKey: .entitySelector) ?? ""
        problemSelector = try c.decodeIfPresent(String.self, forKey: .problemSelector) ?? ""
        severityLevel = try c.decodeIfPresent(String.self, forKey: .severityLevel) ?? ""
        labelFilters = try c.decodeIfPresent(String.self, forKey: .labelFilters) ?? ""
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize) ?? 25
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
    }
}

/// Representação unificada de um alerta/problema usada pela lista, contagem e
/// notificações — independente do vendor. Guarda o payload original do vendor
/// para permitir a navegação até a tela de detalhe específica.
struct AlertListItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let startDate: Date
    let severityKey: String?
    let displayId: String?
    let externalURL: URL?
    let dynatraceProblem: DynatraceProblem?
    let grafanaAlert: GrafanaAlert?

    init(problem: DynatraceProblem, instance: DynatraceInstance) {
        self.id = problem.problemId
        self.title = problem.title
        self.subtitle = problem.affectedResource
        self.startDate = problem.startDate
        self.severityKey = problem.severityLevel
        self.displayId = problem.displayId
        self.externalURL = DynatraceAPI.problemDetailURL(instance: instance, problemId: problem.problemId)
        self.dynatraceProblem = problem
        self.grafanaAlert = nil
    }

    init(grafanaAlert alert: GrafanaAlert) {
        self.id = alert.stableId
        self.title = alert.title
        self.subtitle = alert.affectedResource
        self.startDate = alert.startDate
        self.severityKey = alert.labels?["severity"]
        self.displayId = nil
        self.externalURL = alert.generatorURL.flatMap { URL(string: $0) }
        self.dynatraceProblem = nil
        self.grafanaAlert = alert
    }
}

struct ProblemsResponse: Decodable {
    let problems: [DynatraceProblem]
    let totalCount: Int?
    let nextPageKey: String?
    let pageSize: Int?
}

struct DynatraceProblem: Identifiable, Decodable, Hashable {
    let problemId: String
    let displayId: String?
    let title: String
    let status: String
    let startTime: Int64
    let endTime: Int64?
    let affectedEntities: [AffectedEntity]?
    let impactedEntities: [AffectedEntity]?
    let severityLevel: String?
    let impactLevel: String?

    var id: String { problemId }

    var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startTime) / 1000.0)
    }

    var affectedResource: String {
        let combined = (affectedEntities ?? []) + (impactedEntities ?? [])
        let names = combined.compactMap { $0.name }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return "" }
        let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
        return unique.joined(separator: ", ")
    }
}

struct AffectedEntity: Decodable, Hashable {
    let entityId: EntityId?
    let name: String?
}

struct DynatraceProblemDetail: Decodable {
    let problemId: String
    let displayId: String?
    let title: String
    let status: String
    let startTime: Int64
    let endTime: Int64?
    let severityLevel: String?
    let impactLevel: String?
    let affectedEntities: [AffectedEntity]?
    let impactedEntities: [AffectedEntity]?
    let rootCauseEntity: AffectedEntity?
    let recentComments: RecentCommentsResult?
    let evidenceDetails: EvidenceDetailsResult?
    let impactAnalysis: ImpactAnalysisResult?
    let entityTags: [EntityTag]?
}

struct EntityTag: Decodable, Hashable {
    let context: String?
    let key: String?
    let value: String?
    let stringRepresentation: String?
}

struct EntitiesResponse: Decodable {
    let entities: [EntityDetails]?
}

struct EntityDetails: Decodable, Hashable {
    let entityId: String?
    let type: String?
    let displayName: String?
    let tags: [EntityTag]?
    let properties: EntityKubernetesProperties?
    let fromRelationships: [String: [EntityReference]]?
    let toRelationships: [String: [EntityReference]]?
}

struct EntityReference: Decodable, Hashable {
    let id: String?
    let type: String?
}

struct EntityKubernetesProperties: Decodable, Hashable {
    let kubernetesClusterName: String?
    let namespaceName: String?
    let kubernetesNamespace: String?
    let workloadKind: String?
    let workloadName: String?
    let podName: String?
    let containerName: String?
    let nodeName: String?
}

struct RecentCommentsResult: Decodable {
    let totalCount: Int?
    let comments: [ProblemComment]?
}

struct ProblemComment: Decodable, Hashable {
    let id: String?
    let content: String?
    let authorName: String?
    let createdAtTimestamp: Int64?
}

struct EvidenceDetailsResult: Decodable {
    let totalCount: Int?
    let details: [Evidence]?
}

struct Evidence: Decodable, Hashable {
    let displayName: String?
    let entity: AffectedEntity?
    let evidenceType: String?
    let rootCauseRelevant: Bool?
    let startTime: Int64?
}

struct ImpactAnalysisResult: Decodable {
    let impacts: [Impact]?
}

struct Impact: Decodable, Hashable {
    let impactType: String?
    let impactedEntity: AffectedEntity?
    let estimatedAffectedUsers: Int?
}

struct EntityId: Decodable, Hashable {
    let id: String?
    let type: String?
}

struct ManagementZone: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct ManagementZonesResponse: Decodable {
    let values: [ManagementZone]
}

enum SeverityLevel {
    static let all: [(label: String, value: String)] = [
        ("Qualquer", ""),
        ("Availability", "AVAILABILITY"),
        ("Error", "ERROR"),
        ("Performance", "PERFORMANCE"),
        ("Resource", "RESOURCE_CONTENTION"),
        ("Custom alert", "CUSTOM_ALERT"),
        ("Monitoring unavailable", "MONITORING_UNAVAILABLE"),
        ("Info", "INFO")
    ]
}

enum PageSizeOption {
    static let all: [Int] = [10, 25, 50, 100]
}
