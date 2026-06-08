//
//  ProblemListView.swift
//  Dyntrace Problems App
//

import SwiftUI
import UIKit

struct ProblemListView: View {
    @EnvironmentObject var store: InstanceStore
    let instanceId: UUID

    @State private var problems: [AlertListItem] = []
    @State private var nextPageKey: String? = nil
    @State private var totalCount: Int? = nil
    @State private var isInitialLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var showingEdit = false
    @State private var hasLoaded = false
    @State private var searchText: String = ""

    private var filteredProblems: [AlertListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return problems }
        return problems.filter { problem in
            problem.title.lowercased().contains(query) ||
            problem.subtitle.lowercased().contains(query)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var instance: DynatraceInstance? {
        store.instances.first(where: { $0.id == instanceId })
    }

    private var pageSize: Int {
        instance?.pageSize ?? 25
    }

    var body: some View {
        Group {
            if let instance {
                content(for: instance)
            } else {
                ContentUnavailableView("Instância não encontrada",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Esta instância foi removida."))
            }
        }
        .navigationTitle(instance?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if instance != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEdit = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Editar filtros")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await initialLoad() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Atualizar")
                    .disabled(isInitialLoading || isLoadingMore)
                }
                ToolbarItem(placement: .bottomBar) {
                    if let instance, let filterDescription = filterDescription(for: instance) {
                        Text(filterDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let instance {
                InstanceEditView(instance: instance) { updated in
                    store.update(updated)
                    Task { await initialLoad() }
                }
            }
        }
        .task(id: instanceId) {
            if !hasLoaded {
                await initialLoad()
                hasLoaded = true
            }
        }
    }

    @ViewBuilder
    private func content(for instance: DynatraceInstance) -> some View {
        List {
            if let errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Erro ao carregar problemas", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if problems.isEmpty && !isInitialLoading && errorMessage == nil {
                Section {
                    ContentUnavailableView("Nenhum problema aberto",
                        systemImage: "checkmark.seal.fill",
                        description: Text("Não há problemas abertos para o filtro atual."))
                        .listRowBackground(Color.clear)
                }
            } else if !problems.isEmpty && filteredProblems.isEmpty && isSearching {
                Section {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                }
            }

            if !problems.isEmpty {
                Section {
                    ForEach(filteredProblems) { item in
                        NavigationLink {
                            destination(for: item, instance: instance)
                        } label: {
                            problemRow(item)
                        }
                    }

                    if nextPageKey != nil {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack(spacing: 6) {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                    Text("Carregando...").foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Carregar mais \(pageSize)")
                                }
                                Spacer()
                            }
                            .font(.callout)
                            .padding(.vertical, 6)
                        }
                        .disabled(isLoadingMore)
                    }
                } header: {
                    Text(headerText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Buscar por título ou recurso")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .overlay {
            if isInitialLoading && problems.isEmpty {
                ProgressView().controlSize(.large)
            }
        }
        .refreshable { await initialLoad() }
    }

    private var headerText: String {
        if isSearching {
            let matched = filteredProblems.count
            let plural = matched == 1 ? "" : "s"
            return "\(matched) resultado\(plural) (de \(problems.count) carregado\(problems.count == 1 ? "" : "s"))"
        }
        if let totalCount {
            return "Mostrando \(problems.count) de \(totalCount)"
        }
        let plural = problems.count == 1 ? "" : "s"
        return "\(problems.count) problema\(plural) carregado\(plural)"
    }

    @ViewBuilder
    private func destination(for item: AlertListItem, instance: DynatraceInstance) -> some View {
        if let problem = item.dynatraceProblem {
            ProblemDetailView(problem: problem, instance: instance)
        } else if let alert = item.grafanaAlert {
            GrafanaAlertDetailView(alert: alert, instance: instance)
        } else {
            ContentUnavailableView("Detalhe indisponível",
                systemImage: "questionmark.circle",
                description: Text("Não foi possível abrir este alerta."))
        }
    }

    @ViewBuilder
    private func problemRow(_ item: AlertListItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(severityColor(item.severityKey))
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(formattedDate(item.startDate))
                    if let displayId = item.displayId {
                        Text("·")
                        Text(displayId)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !item.subtitle.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "cube")
                        Text(item.subtitle)
                            .lineLimit(3)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func severityColor(_ severity: String?) -> Color {
        switch severity?.uppercased() {
        case "AVAILABILITY", "ERROR", "CRITICAL": return .red
        case "PERFORMANCE", "RESOURCE_CONTENTION", "RESOURCE", "WARNING": return .orange
        case "CUSTOM_ALERT", "MONITORING_UNAVAILABLE": return .yellow
        case "INFO", "INFORMATION", "NONE": return .blue
        default: return .red
        }
    }

    private func filterDescription(for instance: DynatraceInstance) -> String? {
        var parts: [String] = []
        switch instance.vendor {
        case .dynatrace:
            let mz = instance.managementZone.trimmingCharacters(in: .whitespaces)
            if !mz.isEmpty { parts.append("MZ: \(mz)") }
            let sev = instance.severityLevel.trimmingCharacters(in: .whitespaces)
            if !sev.isEmpty { parts.append("severidade: \(sev)") }
            let es = instance.entitySelector.trimmingCharacters(in: .whitespaces)
            if !es.isEmpty { parts.append("entity: \(es)") }
            let ps = instance.problemSelector.trimmingCharacters(in: .whitespaces)
            if !ps.isEmpty { parts.append("problem: \(ps)") }
        case .grafana:
            let matchers = GrafanaAPI.parseLabelFilters(instance.labelFilters)
            if !matchers.isEmpty { parts.append("labels: " + matchers.joined(separator: ", ")) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    private func initialLoad() async {
        problems = []
        nextPageKey = nil
        totalCount = nil
        errorMessage = nil
        isInitialLoading = true
        await fetchMore()
        isInitialLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        await fetchMore()
        isLoadingMore = false
    }

    private func fetchMore() async {
        guard let instance else { return }
        var key: String? = nextPageKey
        var collected: [AlertListItem] = []

        do {
            while collected.count < pageSize {
                let page = try await AlertService.fetchPage(for: instance, nextPageKey: key)
                collected.append(contentsOf: page.items)
                if totalCount == nil { totalCount = page.totalCount }
                if let next = page.nextPageKey {
                    key = next
                } else {
                    key = nil
                    break
                }
            }
            problems.append(contentsOf: collected)
            nextPageKey = key
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
