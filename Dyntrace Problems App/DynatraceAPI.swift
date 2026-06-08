//
//  DynatraceAPI.swift
//  Dyntrace Problems App
//

import Foundation

enum DynatraceAPIError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL inválida"
        case .httpError(let code, let body):
            let snippet = body.prefix(300)
            return "Erro HTTP \(code): \(snippet)"
        case .decodingError(let error):
            return "Erro ao decodificar resposta: \(error.localizedDescription)"
        }
    }
}

enum DynatraceAPI {

    private static let maxPagesForFullSync = 50

    struct ProblemsPage {
        let problems: [DynatraceProblem]
        let nextPageKey: String?
        let totalCount: Int?
    }

    struct ProblemsAggregate {
        let problems: [DynatraceProblem]
        let totalCount: Int?
        let truncated: Bool
    }

    /// Busca uma única página da API. Use para paginação na UI.
    static func fetchProblemsPage(for instance: DynatraceInstance,
                                  nextPageKey: String? = nil) async throws -> ProblemsPage {
        let trimmedURL = trimmedBaseURL(instance.baseURL)
        guard var components = URLComponents(string: "\(trimmedURL)/api/v2/problems") else {
            throw DynatraceAPIError.invalidURL
        }
        components.queryItems = buildQueryItems(for: instance, nextPageKey: nextPageKey)
        guard let url = components.url else { throw DynatraceAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Api-Token \(instance.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DynatraceAPIError.httpError(httpResponse.statusCode, body)
        }
        do {
            let decoded = try JSONDecoder().decode(ProblemsResponse.self, from: data)
            return ProblemsPage(
                problems: decoded.problems,
                nextPageKey: decoded.nextPageKey,
                totalCount: decoded.totalCount
            )
        } catch {
            throw DynatraceAPIError.decodingError(error)
        }
    }

    /// Caminha todas as páginas (até `maxPagesForFullSync`) coletando os
    /// problemas + o totalCount. Usado pela lista de instâncias e pelo
    /// background fetch que mantém o baseline das notificações.
    static func fetchAllOpenProblems(for instance: DynatraceInstance) async throws -> ProblemsAggregate {
        var allProblems: [DynatraceProblem] = []
        var nextKey: String? = nil
        var totalCount: Int? = nil
        var pagesFetched = 0

        repeat {
            let page = try await fetchProblemsPage(for: instance, nextPageKey: nextKey)
            allProblems.append(contentsOf: page.problems)
            if totalCount == nil { totalCount = page.totalCount }
            nextKey = page.nextPageKey
            pagesFetched += 1
        } while nextKey != nil && pagesFetched < maxPagesForFullSync

        return ProblemsAggregate(
            problems: allProblems,
            totalCount: totalCount,
            truncated: nextKey != nil
        )
    }

    private static func buildQueryItems(for instance: DynatraceInstance, nextPageKey: String?) -> [URLQueryItem] {
        // Em paginação a API v2 só aceita o nextPageKey.
        if let nextPageKey {
            return [URLQueryItem(name: "nextPageKey", value: nextPageKey)]
        }

        var problemSelectorParts: [String] = ["status(\"OPEN\")"]

        let extraProblemSelector = instance.problemSelector.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extraProblemSelector.isEmpty {
            problemSelectorParts.append(extraProblemSelector)
        }

        let mz = instance.managementZone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mz.isEmpty {
            problemSelectorParts.append("managementZones(\"\(mz)\")")
        }

        let severity = instance.severityLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !severity.isEmpty {
            problemSelectorParts.append("severityLevel(\"\(severity)\")")
        }

        let combinedProblemSelector = problemSelectorParts.joined(separator: ",")

        // pageSize fixo em 10 porque a API v2 não aceita valores maiores quando
        // o parâmetro "fields" está presente.
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "from", value: "now-7d"),
            URLQueryItem(name: "problemSelector", value: combinedProblemSelector),
            URLQueryItem(name: "fields", value: "+affectedEntities,+impactedEntities,+severityLevel,+impactLevel"),
            URLQueryItem(name: "pageSize", value: "10"),
            URLQueryItem(name: "sort", value: "-startTime")
        ]

        let entitySel = instance.entitySelector.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entitySel.isEmpty {
            queryItems.append(URLQueryItem(name: "entitySelector", value: entitySel))
        }

        return queryItems
    }

    static func fetchProblemDetails(problemId: String,
                                    for instance: DynatraceInstance) async throws -> DynatraceProblemDetail {
        let trimmedURL = trimmedBaseURL(instance.baseURL)
        let encoded = problemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? problemId
        guard var components = URLComponents(string: "\(trimmedURL)/api/v2/problems/\(encoded)") else {
            throw DynatraceAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "fields",
                         value: "+evidenceDetails,+impactAnalysis,+recentComments")
        ]
        guard let url = components.url else { throw DynatraceAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Api-Token \(instance.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DynatraceAPIError.httpError(httpResponse.statusCode, body)
        }
        do {
            return try JSONDecoder().decode(DynatraceProblemDetail.self, from: data)
        } catch {
            throw DynatraceAPIError.decodingError(error)
        }
    }

    static func fetchEntitiesWithTags(entityIds: [String],
                                      for instance: DynatraceInstance) async throws -> [EntityDetails] {
        guard !entityIds.isEmpty else { return [] }
        let trimmedURL = trimmedBaseURL(instance.baseURL)
        let quoted = entityIds.map { "\"\($0)\"" }.joined(separator: ",")
        let selector = "entityId(\(quoted))"

        guard var components = URLComponents(string: "\(trimmedURL)/api/v2/entities") else {
            throw DynatraceAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "entitySelector", value: selector),
            URLQueryItem(name: "fields", value: "+tags,+properties"),
            URLQueryItem(name: "from", value: "now-2h"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        guard let url = components.url else { throw DynatraceAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Api-Token \(instance.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DynatraceAPIError.httpError(httpResponse.statusCode, body)
        }
        do {
            let decoded = try JSONDecoder().decode(EntitiesResponse.self, from: data)
            return decoded.entities ?? []
        } catch {
            throw DynatraceAPIError.decodingError(error)
        }
    }

    /// Busca uma única entidade com relationships. Use para descobrir
    /// relacionamentos (ex.: namespace -> cluster). Mais leve que pedir
    /// `+fromRelationships` num batched, que pode estourar timeout.
    static func fetchSingleEntityRelationships(entityId: String,
                                               for instance: DynatraceInstance) async throws -> EntityDetails {
        let trimmedURL = trimmedBaseURL(instance.baseURL)
        let encoded = entityId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entityId
        guard var components = URLComponents(string: "\(trimmedURL)/api/v2/entities/\(encoded)") else {
            throw DynatraceAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "fields",
                         value: "+fromRelationships,+toRelationships"),
            URLQueryItem(name: "from", value: "now-2h")
        ]
        guard let url = components.url else { throw DynatraceAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Api-Token \(instance.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DynatraceAPIError.httpError(httpResponse.statusCode, body)
        }
        do {
            return try JSONDecoder().decode(EntityDetails.self, from: data)
        } catch {
            throw DynatraceAPIError.decodingError(error)
        }
    }

    static func fetchManagementZones(for instance: DynatraceInstance) async throws -> [ManagementZone] {
        let trimmedURL = trimmedBaseURL(instance.baseURL)
        guard let url = URL(string: "\(trimmedURL)/api/config/v1/managementZones") else {
            throw DynatraceAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Api-Token \(instance.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DynatraceAPIError.httpError(httpResponse.statusCode, body)
        }
        do {
            let decoded = try JSONDecoder().decode(ManagementZonesResponse.self, from: data)
            return decoded.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            throw DynatraceAPIError.decodingError(error)
        }
    }

    static func problemDetailURL(instance: DynatraceInstance, problemId: String) -> URL? {
        let trimmed = trimmedBaseURL(instance.baseURL).replacingOccurrences(of: "live", with: "apps")
        
        let encodedId = problemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? problemId
        //if trimmed.contains(".apps.dynatrace.com") {
        //    return URL(string: "\(trimmed)/ui/apps/dynatrace.classic.problems/#problems/problemdetails;pid=\(encodedId)")
        //}
        
        return URL(string: "\(trimmed)/ui/apps/dynatrace.davis.problems/problem/\(encodedId)")
    }

    private static func trimmedBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
    }
}
