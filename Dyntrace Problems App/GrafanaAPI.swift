//
//  GrafanaAPI.swift
//  Dyntrace Problems App
//
//  Integração com o Alertmanager embutido do Grafana
//  (GET /api/alertmanager/grafana/api/v2/alerts).
//

import Foundation

// MARK: - Modelos

struct GrafanaAlert: Decodable, Hashable {
    let fingerprint: String?
    let labels: [String: String]?
    let annotations: [String: String]?
    let startsAt: String?
    let endsAt: String?
    let updatedAt: String?
    let generatorURL: String?
    let receivers: [GrafanaReceiver]?
    let status: GrafanaAlertStatus?

    /// Identificador estável do alerta. Usa o fingerprint quando disponível e,
    /// como fallback, uma combinação determinística dos labels.
    var stableId: String {
        if let fingerprint, !fingerprint.isEmpty { return fingerprint }
        let sortedLabels = (labels ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return sortedLabels.isEmpty ? UUID().uuidString : sortedLabels
    }

    var title: String {
        if let name = labels?["alertname"], !name.isEmpty { return name }
        if let summary = annotations?["summary"], !summary.isEmpty { return summary }
        if let desc = annotations?["description"], !desc.isEmpty { return desc }
        return "Alerta"
    }

    /// Recurso afetado derivado dos labels mais comuns em setups Prometheus/Grafana.
    var affectedResource: String {
        let preferredKeys = ["instance", "service", "namespace", "pod",
                             "job", "node", "cluster", "container"]
        let parts = preferredKeys.compactMap { key -> String? in
            guard let value = labels?[key], !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        return parts.prefix(3).joined(separator: " · ")
    }

    var startDate: Date {
        GrafanaAPI.parseISODate(startsAt) ?? Date(timeIntervalSince1970: 0)
    }

    var endDate: Date? {
        // O Alertmanager usa uma data "zero" (0001-01-01) quando o alerta segue ativo.
        guard let date = GrafanaAPI.parseISODate(endsAt) else { return nil }
        return date.timeIntervalSince1970 <= 0 ? nil : date
    }
}

struct GrafanaReceiver: Decodable, Hashable {
    let name: String?
}

struct GrafanaAlertStatus: Decodable, Hashable {
    let state: String?
    let silencedBy: [String]?
    let inhibitedBy: [String]?
}

// MARK: - API

enum GrafanaAPI {

    /// Busca os alertas ativos da instância Grafana, aplicando os filtros de
    /// labels configurados.
    static func fetchAlerts(for instance: DynatraceInstance) async throws -> [GrafanaAlert] {
        let trimmedURL = trimmedBaseURL(instance.baseURL)
        guard var components = URLComponents(string: "\(trimmedURL)/api/alertmanager/grafana/api/v2/alerts") else {
            throw DynatraceAPIError.invalidURL
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "active", value: "true"),
            URLQueryItem(name: "silenced", value: "false"),
            URLQueryItem(name: "inhibited", value: "false")
        ]
        for matcher in parseLabelFilters(instance.labelFilters) {
            queryItems.append(URLQueryItem(name: "filter", value: matcher))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw DynatraceAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(instance.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DynatraceAPIError.httpError(httpResponse.statusCode, body)
        }
        do {
            return try JSONDecoder().decode([GrafanaAlert].self, from: data)
        } catch {
            throw DynatraceAPIError.decodingError(error)
        }
    }

    /// Converte a configuração de filtros de labels em matchers do Alertmanager.
    /// Aceita pares separados por vírgula ou quebra de linha. Cada par pode usar
    /// os operadores `=`, `!=`, `=~`, `!~`. Valores sem aspas são automaticamente
    /// envolvidos por aspas (formato esperado pela API v2).
    static func parseLabelFilters(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { normalizeMatcher($0) }
    }

    private static func normalizeMatcher(_ token: String) -> String {
        // Ordem importa: operadores de 2 caracteres antes dos de 1.
        let operators = ["=~", "!~", "!=", "="]
        for op in operators {
            guard let range = token.range(of: op) else { continue }
            let key = String(token[token.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            var value = String(token[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            if !(value.hasPrefix("\"") && value.hasSuffix("\"")) {
                value = "\"\(value)\""
            }
            return "\(key)\(op)\(value)"
        }
        // Sem operador: trata como igualdade exata de alertname.
        return "alertname=\"\(token)\""
    }

    static func parseISODate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = isoFormatterWithFractional.date(from: string) {
            return date
        }
        return isoFormatter.date(from: string)
    }

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func trimmedBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
    }
}
