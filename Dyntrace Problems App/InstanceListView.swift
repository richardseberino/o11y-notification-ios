//
//  InstanceListView.swift
//  Dyntrace Problems App
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ProblemCountState {
    case loaded(Int)
    case failed(String)
}

struct InstanceListView: View {
    @EnvironmentObject var store: InstanceStore
    @State private var problemCounts: [UUID: ProblemCountState] = [:]
    @State private var loadingIds: Set<UUID> = []
    @State private var showingAdd = false
    @State private var editingInstance: DynatraceInstance?
    @State private var showingExportConfirmation = false
    @State private var exportFileURL: URL?
    @State private var showingShareSheet = false
    @State private var showingImport = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if store.instances.isEmpty {
                    ContentUnavailableView {
                        Label("Sem instâncias", systemImage: "server.rack")
                    } description: {
                        Text("Adicione uma instância do Dynatrace para começar a monitorar problemas.")
                    } actions: {
                        Button("Adicionar instância") { showingAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.instances) { instance in
                            NavigationLink(value: instance) {
                                row(for: instance)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    store.remove(id: instance.id)
                                    problemCounts.removeValue(forKey: instance.id)
                                } label: {
                                    Label("Excluir", systemImage: "trash")
                                }
                                Button {
                                    editingInstance = instance
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await refreshAll()
                    }
                }
            }
            .navigationTitle("O11y Notification")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingImport = true
                        } label: {
                            Label("Importar instâncias…", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showingExportConfirmation = true
                        } label: {
                            Label("Exportar instâncias…", systemImage: "square.and.arrow.up")
                        }
                        .disabled(store.instances.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Importar ou exportar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: DynatraceInstance.self) { instance in
                ProblemListView(instanceId: instance.id)
            }
            .sheet(isPresented: $showingAdd) {
                InstanceEditView(instance: DynatraceInstance()) { newInstance in
                    store.add(newInstance)
                    Task { await refresh(instance: newInstance) }
                }
            }
            .sheet(item: $editingInstance) { instance in
                InstanceEditView(instance: instance) { updated in
                    store.update(updated)
                    Task { await refresh(instance: updated) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .confirmationDialog("Exportar instâncias",
                                isPresented: $showingExportConfirmation,
                                titleVisibility: .visible) {
                Button("Incluir tokens da API") {
                    exportInstances(includeTokens: true)
                }
                Button("Sem tokens") {
                    exportInstances(includeTokens: false)
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Tokens dão acesso completo à API da sua instância Dynatrace. Inclua somente em arquivos que você for compartilhar com pessoas de confiança.")
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: cleanupExportFile) {
                if let url = exportFileURL {
                    ActivityShareSheet(items: [url])
                }
            }
            .fileImporter(isPresented: $showingImport,
                          allowedContentTypes: [.data, .propertyList],
                          allowsMultipleSelection: false) { result in
                handleImport(result: result)
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .task {
                await refreshAll()
            }
        }
    }

    private func exportInstances(includeTokens: Bool) {
        guard let data = store.exportPayload(includeTokens: includeTokens) else {
            alertTitle = "Erro ao exportar"
            alertMessage = "Não foi possível gerar o arquivo de export."
            showingAlert = true
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let stamp = dateFormatter.string(from: Date())
        let suffix = includeTokens ? "com-tokens" : "sem-tokens"
        let fileName = "dynatrace-instancias-\(stamp)-\(suffix).dypc"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            exportFileURL = url
            showingShareSheet = true
        } catch {
            alertTitle = "Erro ao exportar"
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    private func cleanupExportFile() {
        if let url = exportFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportFileURL = nil
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let count = try store.importPayload(from: data)
                alertTitle = "Importação concluída"
                alertMessage = "\(count) instância\(count == 1 ? "" : "s") adicionada\(count == 1 ? "" : "s")."
                Task { await refreshAll() }
            } catch {
                alertTitle = "Erro ao importar"
                alertMessage = error.localizedDescription
            }
        case .failure(let error):
            alertTitle = "Erro ao importar"
            alertMessage = error.localizedDescription
        }
        showingAlert = true
    }

    private var footer: some View {
        VStack(spacing: 1) {
            Text("Versão \(Self.appVersion) (build \(Self.appBuild))")
            Text("Compilado em \(Self.releaseDateText)")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private static var releaseDateText: String {
        guard let path = Bundle.main.executablePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func row(for instance: DynatraceInstance) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name).font(.headline)
                Text(displayHost(for: instance.baseURL))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let filterSummary = filterSummary(for: instance) {
                    Text(filterSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            problemCountView(for: instance)
        }
        .padding(.vertical, 4)
    }

    private func displayHost(for url: String) -> String {
        if let parsed = URL(string: url), let host = parsed.host {
            return host
        }
        return url
    }

    private func filterSummary(for instance: DynatraceInstance) -> String? {
        var parts: [String] = []
        let mz = instance.managementZone.trimmingCharacters(in: .whitespaces)
        if !mz.isEmpty { parts.append("MZ: \(mz)") }
        let es = instance.entitySelector.trimmingCharacters(in: .whitespaces)
        if !es.isEmpty { parts.append("entity") }
        let ps = instance.problemSelector.trimmingCharacters(in: .whitespaces)
        if !ps.isEmpty { parts.append("problem") }
        return parts.isEmpty ? nil : "Filtros: " + parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func problemCountView(for instance: DynatraceInstance) -> some View {
        if loadingIds.contains(instance.id) {
            ProgressView()
        } else if let result = problemCounts[instance.id] {
            switch result {
            case .loaded(let count):
                Text("\(count)")
                    .font(.title3.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(count > 0 ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                    .foregroundStyle(count > 0 ? Color.red : Color.green)
                    .clipShape(Capsule())
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for instance in store.instances {
                group.addTask { @MainActor in
                    await refresh(instance: instance)
                }
            }
        }
    }

    @MainActor
    private func refresh(instance: DynatraceInstance) async {
        loadingIds.insert(instance.id)
        defer { loadingIds.remove(instance.id) }
        do {
            let aggregate = try await DynatraceAPI.fetchAllOpenProblems(for: instance)
            let displayCount = aggregate.totalCount ?? aggregate.problems.count
            problemCounts[instance.id] = .loaded(displayCount)
            await NotificationManager.shared.processFetchedProblems(
                aggregate.problems, for: instance, triggerNotifications: false)
        } catch {
            problemCounts[instance.id] = .failed(error.localizedDescription)
        }
    }
}
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

