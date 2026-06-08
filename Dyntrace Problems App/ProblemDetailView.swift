//
//  ProblemDetailView.swift
//  Dyntrace Problems App
//

import SwiftUI
import UIKit

struct ProblemDetailView: View {
    let problem: DynatraceProblem
    let instance: DynatraceInstance

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
}
