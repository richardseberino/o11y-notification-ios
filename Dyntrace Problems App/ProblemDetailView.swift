//
//  ProblemDetailView.swift
//  Dyntrace Problems App
//

import SwiftUI
import UIKit

struct ProblemDetailView: View {
    let problem: DynatraceProblem
    let instance: DynatraceInstance

    @State private var detail: DynatraceProblemDetail?
    @State private var isLoadingDetail = false
    @State private var detailError: String?
    @State private var loadedEntities: [EntityDetails] = []
    @State private var isLoadingEntities = false
    @State private var entitiesError: String?
    @State private var showDiagnostics = false

    var body: some View {
        List {
            Section("Identificação") {
                detailRow("ID", value: problem.displayId ?? problem.problemId)
                detailRow("Name", value: problem.title)
                detailRow("Status", value: problem.status.capitalized)
                detailRow("Severity", value: severityText)
                detailRow("Category", value: categoryText)
            }

            Section("Tempo") {
                detailRow("Started", value: formattedDate(problem.startDate))
                detailRow("Duration", value: durationText)
            }

            if let context = kubernetesContext {
                Section(header: Label("Kubernetes", systemImage: "shippingbox")) {
                    ForEach(context, id: \.label) { item in
                        detailRow(item.label, value: item.value)
                    }
                }
            }

            if let cloud = cloudContext {
                Section(header: Label(cloud.title, systemImage: "cloud")) {
                    ForEach(cloud.items, id: \.label) { item in
                        detailRow(item.label, value: item.value)
                    }
                }
            }

            if let rootCause = detail?.rootCauseEntity {
                Section("Causa raiz") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rootCause.name ?? "—")
                            .font(.callout)
                        if let type = rootCause.entityId?.type, !type.isEmpty {
                            Text(type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let evidences = detail?.evidenceDetails?.details, !evidences.isEmpty {
                Section(header: evidenceHeader(count: detail?.evidenceDetails?.totalCount ?? evidences.count)) {
                    ForEach(Array(evidences.enumerated()), id: \.offset) { _, evidence in
                        evidenceRow(evidence)
                    }
                }
            }

            if let impacts = detail?.impactAnalysis?.impacts, !impacts.isEmpty {
                Section("Impacto") {
                    ForEach(Array(impacts.enumerated()), id: \.offset) { _, impact in
                        impactRow(impact)
                    }
                }
            }

            Section("Affected entities") {
                let entities = (problem.affectedEntities ?? []) + (problem.impactedEntities ?? [])
                let unique = uniqueEntities(entities)
                if unique.isEmpty {
                    Text("Nenhuma").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(unique.enumerated()), id: \.offset) { _, entity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entity.name ?? "—")
                                .font(.callout)
                            if let type = entity.entityId?.type, !type.isEmpty {
                                Text(type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let comments = detail?.recentComments?.comments, !comments.isEmpty {
                Section("Comentários") {
                    ForEach(Array(comments.enumerated()), id: \.offset) { _, comment in
                        commentRow(comment)
                    }
                }
            }

            if isLoadingDetail {
                Section {
                    HStack {
                        ProgressView()
                        Text("Carregando diagnóstico…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let detailError {
                Section {
                    Label(detailError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Mostrar diagnóstico de entidades", isOn: $showDiagnostics)
                    .font(.footnote)
            }

            if showDiagnostics {
                Section("Entidades carregadas") {
                    if isLoadingEntities {
                        HStack {
                            ProgressView()
                            Text("Carregando entidades K8s…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let entitiesError {
                        Label(entitiesError, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    if loadedEntities.isEmpty && !isLoadingEntities && entitiesError == nil {
                        Text("Nenhuma entidade K8s encontrada nesse problema.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !loadedEntities.isEmpty {
                        ForEach(loadedEntities, id: \.entityId) { entity in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entity.displayName ?? entity.entityId ?? "—")
                                    .font(.callout.bold())
                                Text("\(entity.type ?? "?") · \(entity.entityId ?? "?")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let tags = entity.tags, !tags.isEmpty {
                                    Text("Tags:")
                                        .font(.caption2.bold())
                                        .padding(.top, 4)
                                    ForEach(tags, id: \.self) { tag in
                                        Text(tag.stringRepresentation
                                             ?? "[\(tag.context ?? "?")] \(tag.key ?? "?")=\(tag.value ?? "?")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                } else {
                                    Text("Sem tags retornadas").font(.caption2).foregroundStyle(.tertiary)
                                }
                                if let p = entity.properties {
                                    Text("Properties:")
                                        .font(.caption2.bold())
                                        .padding(.top, 4)
                                    propertyLine("kubernetesClusterName", p.kubernetesClusterName)
                                    propertyLine("namespaceName", p.namespaceName)
                                    propertyLine("kubernetesNamespace", p.kubernetesNamespace)
                                    propertyLine("workloadKind", p.workloadKind)
                                    propertyLine("workloadName", p.workloadName)
                                    propertyLine("podName", p.podName)
                                    propertyLine("nodeName", p.nodeName)
                                    propertyLine("containerName", p.containerName)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Section {
                Button {
                    openInBrowser()
                } label: {
                    HStack {
                        Image(systemName: "safari")
                        Text("Abrir no Dynatrace")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.tertiary)
                    }
                }

                if let url = DynatraceAPI.problemDetailURL(instance: instance, problemId: problem.problemId) {
                    ShareLink(item: url,
                              subject: Text(problem.title),
                              message: Text(problem.displayId ?? problem.problemId)) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Compartilhar link")
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(problem.displayId ?? "Problema")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
        .refreshable { await loadDetail() }
    }

    private var severityText: String {
        guard let severity = problem.severityLevel, !severity.isEmpty else { return "—" }
        return severity.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var categoryText: String {
        guard let impact = problem.impactLevel, !impact.isEmpty else { return "—" }
        return impact.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var durationText: String {
        let endMillis = problem.endTime ?? -1
        let endDate: Date = (endMillis > 0)
            ? Date(timeIntervalSince1970: TimeInterval(endMillis) / 1000.0)
            : Date()
        let seconds = max(0, endDate.timeIntervalSince(problem.startDate))

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let formatted = formatter.string(from: seconds) ?? "—"
        if endMillis > 0 {
            return formatted
        }
        return "\(formatted) (em andamento)"
    }

    @ViewBuilder
    private func evidenceHeader(count: Int) -> some View {
        HStack {
            Text("Evidências")
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func evidenceRow(_ evidence: Evidence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(evidence.displayName ?? "—")
                    .font(.callout)
                Spacer()
                if evidence.rootCauseRelevant == true {
                    Label("Causa", systemImage: "target")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            HStack(spacing: 6) {
                if let type = evidence.evidenceType, !type.isEmpty {
                    Text(prettyEvidenceType(type))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                if let entityName = evidence.entity?.name, !entityName.isEmpty {
                    Text(entityName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func impactRow(_ impact: Impact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(impact.impactedEntity?.name ?? "—")
                .font(.callout)
            HStack(spacing: 6) {
                if let type = impact.impactType, !type.isEmpty {
                    Text(prettyImpactType(type))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                if let users = impact.estimatedAffectedUsers, users > 0 {
                    Text("\(users) usuário(s) afetado(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func commentRow(_ comment: ProblemComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comment.content ?? "—")
                .font(.callout)
            HStack {
                if let author = comment.authorName, !author.isEmpty {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let ts = comment.createdAtTimestamp {
                    Text(formattedDate(Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private struct ContextItem {
        let label: String
        let value: String
    }

    private struct CloudContext {
        let title: String
        let items: [ContextItem]
    }

    private var kubernetesContext: [ContextItem]? {
        let allEntities = (detail?.affectedEntities ?? problem.affectedEntities ?? [])
            + (detail?.impactedEntities ?? problem.impactedEntities ?? [])
            + [detail?.rootCauseEntity].compactMap { $0 }

        // Mapeia tipos de entidade Dynatrace para o rótulo correspondente em K8s.
        let typeToLabel: [(type: String, label: String)] = [
            ("KUBERNETES_CLUSTER", "Cluster"),
            ("CLOUD_APPLICATION_NAMESPACE", "Namespace"),
            ("CLOUD_APPLICATION", "Workload"),
            ("CLOUD_APPLICATION_INSTANCE", "Pod"),
            ("KUBERNETES_SERVICE", "Service"),
            ("KUBERNETES_NODE", "Node"),
            ("CONTAINER_GROUP_INSTANCE", "Container")
        ]

        var items: [ContextItem] = []
        for entry in typeToLabel {
            var names = allEntities
                .filter { ($0.entityId?.type ?? "") == entry.type }
                .compactMap { $0.name }
                .filter { !$0.isEmpty }
            // Inclui também entidades resolvidas via /entities (ex.: cluster
            // obtido a partir das relationships da workload/namespace).
            names += loadedEntities
                .filter { ($0.type ?? "") == entry.type }
                .compactMap { $0.displayName }
                .filter { !$0.isEmpty }
            let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
            if !unique.isEmpty {
                items.append(ContextItem(label: entry.label,
                                         value: unique.joined(separator: ", ")))
            }
        }

        // Extrai das propriedades das entidades carregadas (a forma mais
        // confiável quando o tenant não usa autotagging [Kubernetes]).
        var existingLabels = Set(items.map { $0.label })
        let propertySources: [(label: String, getter: (EntityKubernetesProperties) -> String?)] = [
            ("Cluster", { $0.kubernetesClusterName }),
            ("Namespace", { $0.namespaceName ?? $0.kubernetesNamespace }),
            ("Workload kind", { $0.workloadKind }),
            ("Workload", { $0.workloadName }),
            ("Pod", { $0.podName }),
            ("Node", { $0.nodeName }),
            ("Container", { $0.containerName })
        ]
        for entry in propertySources where !existingLabels.contains(entry.label) {
            let values = loadedEntities
                .compactMap { $0.properties.flatMap(entry.getter) }
                .filter { !$0.isEmpty }
            let unique = Array(NSOrderedSet(array: values)) as? [String] ?? values
            if !unique.isEmpty {
                items.append(ContextItem(label: entry.label,
                                         value: unique.joined(separator: ", ")))
                existingLabels.insert(entry.label)
            }
        }

        // Complementa com tags (cluster/namespace via [Kubernetes]xxx ou
        // kubernetes.xxx, dependendo do tenant).
        let combinedTags = loadedEntities.flatMap { $0.tags ?? [] }
            + (detail?.entityTags ?? [])
        if !combinedTags.isEmpty {
            let tagPriority: [(matcher: (String) -> Bool, label: String)] = [
                ({ $0.contains("cluster") }, "Cluster"),
                ({ $0.contains("namespace") }, "Namespace"),
                ({ $0.contains("workload-kind") || $0.contains("workload.kind") }, "Workload kind"),
                ({ $0.contains("workload") }, "Workload"),
                ({ $0.contains("pod") }, "Pod"),
                ({ $0.contains("node") }, "Node")
            ]
            for entry in tagPriority where !existingLabels.contains(entry.label) {
                let matches = combinedTags
                    .filter { tag in
                        let key = (tag.key ?? "").lowercased()
                        guard key.contains("kubernetes") else { return false }
                        return entry.matcher(key)
                    }
                    .compactMap { $0.value }
                    .filter { !$0.isEmpty }
                let unique = Array(NSOrderedSet(array: matches)) as? [String] ?? matches
                if !unique.isEmpty {
                    items.append(ContextItem(label: entry.label,
                                             value: unique.joined(separator: ", ")))
                    existingLabels.insert(entry.label)
                }
            }
        }

        return items.isEmpty ? nil : items
    }

    private var cloudContext: CloudContext? {
        guard let tags = detail?.entityTags else { return nil }
        let mapping: [(context: String, title: String)] = [
            ("AWS", "AWS"),
            ("AZURE", "Azure"),
            ("GOOGLE_CLOUD", "Google Cloud"),
            ("GCP", "Google Cloud")
        ]
        for entry in mapping {
            let filtered = tags.filter { $0.context?.uppercased() == entry.context }
            guard !filtered.isEmpty else { continue }
            var items: [ContextItem] = []
            let grouped = Dictionary(grouping: filtered, by: { $0.key?.lowercased() ?? "" })
            for (key, group) in grouped.sorted(by: { $0.key < $1.key }) where !key.isEmpty {
                let values = group.compactMap { $0.value }.filter { !$0.isEmpty }
                let unique = Array(NSOrderedSet(array: values)) as? [String] ?? values
                guard !unique.isEmpty else { continue }
                items.append(ContextItem(label: key.replacingOccurrences(of: "-", with: " ").capitalized,
                                         value: unique.joined(separator: ", ")))
            }
            if !items.isEmpty {
                return CloudContext(title: entry.title, items: items)
            }
        }
        return nil
    }

    private func prettyEvidenceType(_ raw: String) -> String {
        switch raw.uppercased() {
        case "EVENT": return "Evento"
        case "METRIC": return "Métrica"
        case "MAINTENANCE_WINDOW", "MAINTENANCE": return "Manutenção"
        case "TRANSACTIONAL": return "Transacional"
        case "AVAILABILITY": return "Disponibilidade"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func prettyImpactType(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func uniqueEntities(_ entities: [AffectedEntity]) -> [AffectedEntity] {
        var seen = Set<String>()
        var result: [AffectedEntity] = []
        for entity in entities {
            let key = entity.entityId?.id ?? entity.name ?? UUID().uuidString
            if !seen.contains(key) {
                seen.insert(key)
                result.append(entity)
            }
        }
        return result
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func propertyLine(_ key: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(key).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).font(.caption2).textSelection(.enabled)
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func openInBrowser() {
        guard let url = DynatraceAPI.problemDetailURL(instance: instance, problemId: problem.problemId) else { return }
        UIApplication.shared.open(url)
    }

    private func loadDetail() async {
        isLoadingDetail = true
        do {
            let loadedDetail = try await DynatraceAPI.fetchProblemDetails(
                problemId: problem.problemId, for: instance)
            detail = loadedDetail
            detailError = nil
            isLoadingDetail = false
            // Carrega entidades K8s em background — não bloqueia a UI mesmo se
            // a chamada de entidades estourar timeout.
            Task { await loadEntityTags(for: loadedDetail) }
        } catch {
            detailError = error.localizedDescription
            isLoadingDetail = false
        }
    }

    private func loadEntityTags(for detail: DynatraceProblemDetail) async {
        let allEntities = (detail.affectedEntities ?? [])
            + (detail.impactedEntities ?? [])
            + [detail.rootCauseEntity].compactMap { $0 }

        let interestingTypes: Set<String> = [
            "CLOUD_APPLICATION",
            "CLOUD_APPLICATION_INSTANCE",
            "CLOUD_APPLICATION_NAMESPACE",
            "KUBERNETES_NODE",
            "KUBERNETES_CLUSTER",
            "KUBERNETES_SERVICE",
            "CONTAINER_GROUP_INSTANCE"
        ]

        let ids = allEntities
            .filter { interestingTypes.contains($0.entityId?.type ?? "") }
            .compactMap { $0.entityId?.id }
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty else {
            loadedEntities = []
            return
        }

        isLoadingEntities = true
        defer { isLoadingEntities = false }
        do {
            let initial = try await DynatraceAPI.fetchEntitiesWithTags(
                entityIds: uniqueIds, for: instance)
            loadedEntities = initial
            entitiesError = nil
            await loadRelatedClusters(from: initial)
        } catch {
            loadedEntities = []
            entitiesError = error.localizedDescription
        }
    }

    private func loadRelatedClusters(from entities: [EntityDetails]) async {
        // Prioriza namespace (hop barato), depois workload, depois pod.
        let candidatesByType: [String] = [
            "CLOUD_APPLICATION_NAMESPACE",
            "CLOUD_APPLICATION",
            "CLOUD_APPLICATION_INSTANCE"
        ]
        var pivotIds: [String] = []
        for type in candidatesByType {
            let ids = entities
                .filter { $0.type == type }
                .compactMap { $0.entityId }
            pivotIds.append(contentsOf: ids)
            if !pivotIds.isEmpty { break }
        }
        // Limita pra no máximo 1 pivot — evita explodir requests.
        guard let pivotId = pivotIds.first else { return }

        let pivotWithRels: EntityDetails
        do {
            pivotWithRels = try await DynatraceAPI.fetchSingleEntityRelationships(
                entityId: pivotId, for: instance)
        } catch {
            return
        }

        let from = pivotWithRels.fromRelationships?.values.flatMap { $0 } ?? []
        let to = pivotWithRels.toRelationships?.values.flatMap { $0 } ?? []
        let clusterIds = (from + to)
            .filter { $0.type == "KUBERNETES_CLUSTER" }
            .compactMap { $0.id }
        let unique = Array(Set(clusterIds))
        guard !unique.isEmpty else { return }

        do {
            let clusters = try await DynatraceAPI.fetchEntitiesWithTags(
                entityIds: unique, for: instance)
            loadedEntities.append(contentsOf: clusters)
        } catch {
            // Ignora — o resto do contexto já está disponível.
        }
    }
}
