//
//  AlertService.swift
//  Dyntrace Problems App
//
//  Fachada que abstrai o vendor (Dynatrace, Grafana, …) e devolve alertas em
//  um formato unificado para a lista, a contagem e as notificações.
//

import Foundation

enum AlertService {

    struct AlertsPage {
        let items: [AlertListItem]
        let nextPageKey: String?
        let totalCount: Int?
    }

    struct AlertsAggregate {
        let items: [AlertListItem]
        let totalCount: Int?
        let truncated: Bool
    }

    /// Busca uma única página. Usado pela paginação da lista. O Grafana não
    /// pagina — devolve todos os alertas de uma vez com `nextPageKey == nil`.
    static func fetchPage(for instance: DynatraceInstance,
                          nextPageKey: String? = nil) async throws -> AlertsPage {
        switch instance.vendor {
        case .dynatrace:
            let page = try await DynatraceAPI.fetchProblemsPage(for: instance, nextPageKey: nextPageKey)
            let items = page.problems.map { AlertListItem(problem: $0, instance: instance) }
            return AlertsPage(items: items, nextPageKey: page.nextPageKey, totalCount: page.totalCount)
        case .grafana:
            // Uma página só; ignora nextPageKey.
            if nextPageKey != nil {
                return AlertsPage(items: [], nextPageKey: nil, totalCount: nil)
            }
            let alerts = try await GrafanaAPI.fetchAlerts(for: instance)
            let items = alerts.map { AlertListItem(grafanaAlert: $0) }
            return AlertsPage(items: items, nextPageKey: nil, totalCount: items.count)
        }
    }

    /// Percorre todas as páginas coletando os alertas + o totalCount. Usado pela
    /// lista de instâncias e pelo background fetch das notificações.
    static func fetchAll(for instance: DynatraceInstance) async throws -> AlertsAggregate {
        switch instance.vendor {
        case .dynatrace:
            let aggregate = try await DynatraceAPI.fetchAllOpenProblems(for: instance)
            let items = aggregate.problems.map { AlertListItem(problem: $0, instance: instance) }
            return AlertsAggregate(items: items,
                                   totalCount: aggregate.totalCount,
                                   truncated: aggregate.truncated)
        case .grafana:
            let alerts = try await GrafanaAPI.fetchAlerts(for: instance)
            let items = alerts.map { AlertListItem(grafanaAlert: $0) }
            return AlertsAggregate(items: items, totalCount: items.count, truncated: false)
        }
    }
}
