//
//  InstanceEditView.swift
//  Dyntrace Problems App
//

import SwiftUI
import UIKit

struct InstanceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var instance: DynatraceInstance
    let onSave: (DynatraceInstance) -> Void

    @ObservedObject private var notificationManager = NotificationManager.shared

    @State private var managementZones: [ManagementZone] = []
    @State private var loadingZones = false
    @State private var zonesError: String?
    @State private var hasFetchedZones = false

    private var canFetchOptions: Bool {
        !instance.baseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !instance.apiToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isValid: Bool {
        !instance.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !instance.baseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !instance.apiToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var urlPlaceholder: String {
        switch instance.vendor {
        case .dynatrace: return "URL (ex: https://abc12345.live.dynatrace.com)"
        case .grafana: return "URL (ex: https://seu-grafana.com)"
        }
    }

    private var tokenPlaceholder: String {
        switch instance.vendor {
        case .dynatrace: return "API Token"
        case .grafana: return "Service Account Token"
        }
    }

    private var tokenFooter: String {
        switch instance.vendor {
        case .dynatrace:
            return "O token precisa do escopo \"Read problems\". Para listar as Management Zones, inclua também \"Read configuration\"."
        case .grafana:
            return "Use um token de Service Account com permissão para ler alertas. Ele é enviado como \"Authorization: Bearer\"."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $instance.vendor) {
                        ForEach(Vendor.allCases) { vendor in
                            Text(vendor.displayName).tag(vendor)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Fonte de observabilidade")
                }

                Section {
                    TextField("Nome", text: $instance.name)
                    TextField(urlPlaceholder, text: $instance.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(tokenPlaceholder, text: $instance.apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Instância")
                } footer: {
                    Text(tokenFooter)
                }

                if instance.vendor == .dynatrace {
                    dynatraceFilterSections
                } else {
                    grafanaFilterSection
                }

                if instance.vendor == .dynatrace {
                    Section {
                        Picker("Itens por página", selection: $instance.pageSize) {
                            ForEach(PageSizeOption.all, id: \.self) { size in
                                Text("\(size)").tag(size)
                            }
                        }
                    } header: {
                        Text("Lista de problems")
                    } footer: {
                        Text("Quantidade de problems carregados por vez na lista desta instância.")
                    }
                }

                Section {
                    Toggle("Notificar novos problems", isOn: $instance.notificationsEnabled)
                        .onChange(of: instance.notificationsEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    let granted = await notificationManager.requestAuthorization()
                                    if !granted {
                                        instance.notificationsEnabled = false
                                    }
                                }
                            }
                        }

                    if instance.notificationsEnabled && !notificationManager.isAuthorized {
                        Button("Abrir Ajustes do iOS") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } header: {
                    Text("Notificações")
                } footer: {
                    Text("Quando ativadas, o iOS verifica esta instância em background e envia uma notificação local para cada novo problem aberto que corresponda aos filtros configurados acima.\n\nO sistema controla a frequência das verificações (geralmente a cada 15 minutos ou mais).")
                }
            }
            .navigationTitle(instance.name.isEmpty ? "Nova Instância" : instance.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        var toSave = instance
                        toSave.name = toSave.name.trimmingCharacters(in: .whitespaces)
                        toSave.baseURL = toSave.baseURL.trimmingCharacters(in: .whitespaces)
                        toSave.apiToken = toSave.apiToken.trimmingCharacters(in: .whitespaces)
                        onSave(toSave)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .task {
                await notificationManager.refreshAuthorizationStatus()
                if instance.vendor == .dynatrace && canFetchOptions && !hasFetchedZones {
                    await reloadOptions()
                }
            }
        }
    }

    @ViewBuilder
    private var dynatraceFilterSections: some View {
        Section {
            managementZonePicker
            Picker("Severidade", selection: $instance.severityLevel) {
                ForEach(SeverityLevel.all, id: \.value) { item in
                    Text(item.label).tag(item.value)
                }
            }
        } header: {
            HStack {
                Text("Filtros")
                Spacer()
                Button {
                    Task { await reloadOptions() }
                } label: {
                    if loadingZones {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!canFetchOptions || loadingZones)
                .accessibilityLabel("Carregar opções da instância")
            }
        } footer: {
            if let zonesError {
                Text(zonesError).foregroundStyle(.orange)
            } else if !hasFetchedZones && canFetchOptions {
                Text("Toque em ↻ para listar as Management Zones desta instância.")
            } else if !canFetchOptions {
                Text("Preencha URL e Token para listar as opções da instância.")
            } else {
                Text("As opções acima vêm da instância configurada.")
            }
        }

        Section {
            TextField("Entity Selector", text: $instance.entitySelector, axis: .vertical)
                .lineLimit(2...5)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("Problem Selector adicional", text: $instance.problemSelector, axis: .vertical)
                .lineLimit(2...5)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Filtros avançados (opcional)")
        } footer: {
            Text("Exemplos:\n• Entity: type(\"HOST\"),tag(\"env:prod\")\n• Problem: impactLevel(\"INFRASTRUCTURE\")\nO status(\"OPEN\") já é aplicado automaticamente.")
        }
    }

    @ViewBuilder
    private var grafanaFilterSection: some View {
        Section {
            TextField("Filtros de labels", text: $instance.labelFilters, axis: .vertical)
                .lineLimit(2...5)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Filtros por labels (opcional)")
        } footer: {
            Text("Um par por linha ou separados por vírgula. Ex.:\n• severity=critical\n• team=payments\n• namespace=~prod-.*\nOperadores: =, !=, =~, !~. Somente alertas que casam com todos os filtros são exibidos.")
        }
    }

    @ViewBuilder
    private var managementZonePicker: some View {
        if !managementZones.isEmpty {
            Picker("Management Zone", selection: $instance.managementZone) {
                Text("Nenhuma").tag("")
                ForEach(managementZones) { zone in
                    Text(zone.name).tag(zone.name)
                }
                if !instance.managementZone.isEmpty
                    && !managementZones.contains(where: { $0.name == instance.managementZone }) {
                    Text("\(instance.managementZone) (não encontrada)").tag(instance.managementZone)
                }
            }
        } else {
            TextField("Management Zone (nome)", text: $instance.managementZone)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private func reloadOptions() async {
        guard instance.vendor == .dynatrace, canFetchOptions else { return }
        loadingZones = true
        zonesError = nil
        do {
            managementZones = try await DynatraceAPI.fetchManagementZones(for: instance)
            hasFetchedZones = true
        } catch {
            zonesError = "Não foi possível carregar as Management Zones: \(error.localizedDescription)"
        }
        loadingZones = false
    }
}
