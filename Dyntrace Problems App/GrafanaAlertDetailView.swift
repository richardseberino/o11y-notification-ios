//
//  GrafanaAlertDetailView.swift
//  Dyntrace Problems App
//

import SwiftUI
import UIKit

struct GrafanaAlertDetailView: View {
    let alert: GrafanaAlert
    let instance: DynatraceInstance

    var body: some View {
        List {
            Section("Identificação") {
                detailRow("Name", value: alert.title)
                detailRow("Status", value: statusText)
                detailRow("Severity", value: severityText)
                if let receivers = receiversText {
                    detailRow("Receivers", value: receivers)
                }
            }

            Section("Tempo") {
                detailRow("Started", value: formattedDate(alert.startDate))
                detailRow("Duration", value: durationText)
                if let endDate = alert.endDate {
                    detailRow("Ends", value: formattedDate(endDate))
                }
            }

            if !annotationItems.isEmpty {
                Section("Anotações") {
                    ForEach(annotationItems, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prettyKey(item.key))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(item.value)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !labelItems.isEmpty {
                Section("Labels") {
                    ForEach(labelItems, id: \.key) { item in
                        HStack(alignment: .top) {
                            Text(item.key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(item.value)
                                .font(.caption)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if !silencingItems.isEmpty {
                Section("Silenciamentos e inibições") {
                    ForEach(silencingItems, id: \.label) { item in
                        detailRow(item.label, value: item.value)
                    }
                }
            }

            Section {
                if let url = alert.generatorURL.flatMap({ URL(string: $0) }) {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        HStack {
                            Image(systemName: "safari")
                            Text("Abrir no Grafana")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.tertiary)
                        }
                    }

                    ShareLink(item: url,
                              subject: Text(alert.title)) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Compartilhar link")
                            Spacer()
                        }
                    }
                } else {
                    Text("Este alerta não possui link de origem (generatorURL).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(alert.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Dados derivados

    private struct KeyValue {
        let key: String
        let value: String
    }

    private struct LabeledValue {
        let label: String
        let value: String
    }

    private var statusText: String {
        (alert.status?.state ?? "active").capitalized
    }

    private var severityText: String {
        guard let severity = alert.labels?["severity"], !severity.isEmpty else { return "—" }
        return severity.capitalized
    }

    private var receiversText: String? {
        let names = (alert.receivers ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private var annotationItems: [KeyValue] {
        (alert.annotations ?? [:])
            .filter { !$0.value.isEmpty }
            .sorted { annotationRank($0.key) < annotationRank($1.key) }
            .map { KeyValue(key: $0.key, value: $0.value) }
    }

    private var labelItems: [KeyValue] {
        (alert.labels ?? [:])
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { KeyValue(key: $0.key, value: $0.value) }
    }

    private var silencingItems: [LabeledValue] {
        var items: [LabeledValue] = []
        if let silenced = alert.status?.silencedBy, !silenced.isEmpty {
            items.append(LabeledValue(label: "Silenciado por", value: silenced.joined(separator: ", ")))
        }
        if let inhibited = alert.status?.inhibitedBy, !inhibited.isEmpty {
            items.append(LabeledValue(label: "Inibido por", value: inhibited.joined(separator: ", ")))
        }
        return items
    }

    private var durationText: String {
        let endDate = alert.endDate ?? Date()
        let seconds = max(0, endDate.timeIntervalSince(alert.startDate))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let formatted = formatter.string(from: seconds) ?? "—"
        return alert.endDate == nil ? "\(formatted) (em andamento)" : formatted
    }

    /// Ordena as anotações mais úteis primeiro.
    private func annotationRank(_ key: String) -> Int {
        switch key.lowercased() {
        case "summary": return 0
        case "description": return 1
        case "message": return 2
        case "runbook_url": return 3
        default: return 10
        }
    }

    private func prettyKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale.current
        return formatter.string(from: date)
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
}
