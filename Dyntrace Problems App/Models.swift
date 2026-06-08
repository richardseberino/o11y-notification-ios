//
//  Models.swift
//  Dyntrace Problems App
//

import Foundation

struct DynatraceInstance: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var baseURL: String = ""
    var apiToken: String = ""
    var managementZone: String = ""
    var entitySelector: String = ""
    var problemSelector: String = ""
    var severityLevel: String = ""
    var pageSize: Int = 25
    var notificationsEnabled: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiToken, managementZone, entitySelector,
             problemSelector, severityLevel, pageSize, notificationsEnabled
    }

    init(id: UUID = UUID(),
         name: String = "",
         baseURL: String = "",
         apiToken: String = "",
         managementZone: String = "",
         entitySelector: String = "",
         problemSelector: String = "",
         severityLevel: String = "",
         pageSize: Int = 25,
         notificationsEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.managementZone = managementZone
        self.entitySelector = entitySelector
        self.problemSelector = problemSelector
        self.severityLevel = severityLevel
        self.pageSize = pageSize
        self.notificationsEnabled = notificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiToken = try c.decodeIfPresent(String.self, forKey: .apiToken) ?? ""
        managementZone = try c.decodeIfPresent(String.self, forKey: .managementZone) ?? ""
        entitySelector = try c.decodeIfPresent(String.self, forKey: .entitySelector) ?? ""
        problemSelector = try c.decodeIfPresent(String.self, forKey: .problemSelector) ?? ""
        severityLevel = try c.decodeIfPresent(String.self, forKey: .severityLevel) ?? ""
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize) ?? 25
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
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
