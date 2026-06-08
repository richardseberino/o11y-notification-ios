//
//  InstanceStore.swift
//  Dyntrace Problems App
//

import Foundation
import SwiftUI
import Combine

struct InstanceExportPayload: Codable {
    var version: Int
    var includesTokens: Bool
    var instances: [DynatraceInstance]
}

enum InstanceImportError: LocalizedError {
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "O arquivo selecionado não é um export válido de instâncias."
        }
    }
}

@MainActor
final class InstanceStore: ObservableObject {
    @Published var instances: [DynatraceInstance] = []

    private let storageKey = "dynatrace.instances.v1"

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DynatraceInstance].self, from: data) else {
            return
        }

        var needsMigration = false
        instances = decoded.map { stored -> DynatraceInstance in
            var copy = stored
            let keychainToken = KeychainHelper.loadToken(for: stored.id)
            if !keychainToken.isEmpty {
                copy.apiToken = keychainToken
            } else if !stored.apiToken.isEmpty {
                KeychainHelper.save(token: stored.apiToken, for: stored.id)
                needsMigration = true
            } else {
                copy.apiToken = ""
            }
            return copy
        }

        if needsMigration {
            save()
        }
    }

    func save() {
        for instance in instances {
            KeychainHelper.save(token: instance.apiToken, for: instance.id)
        }
        let sanitized = instances.map { instance -> DynatraceInstance in
            var copy = instance
            copy.apiToken = ""
            return copy
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func add(_ instance: DynatraceInstance) {
        instances.append(instance)
        save()
    }

    func update(_ instance: DynatraceInstance) {
        if let idx = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[idx] = instance
            save()
        }
    }

    func move(from offsets: IndexSet, to destination: Int) {
        instances.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func remove(at offsets: IndexSet) {
        let ids = offsets.map { instances[$0].id }
        ids.forEach {
            KeychainHelper.deleteToken(for: $0)
            NotificationManager.shared.clearSeen(for: $0)
        }
        instances.remove(atOffsets: offsets)
        save()
    }

    func remove(id: UUID) {
        KeychainHelper.deleteToken(for: id)
        NotificationManager.shared.clearSeen(for: id)
        instances.removeAll { $0.id == id }
        save()
    }

    // MARK: - Export / Import

    func exportPayload(includeTokens: Bool) -> Data? {
        let toExport: [DynatraceInstance] = instances.map { instance in
            var copy = instance
            if !includeTokens {
                copy.apiToken = ""
            }
            return copy
        }
        let payload = InstanceExportPayload(
            version: 1,
            includesTokens: includeTokens,
            instances: toExport
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(payload)
    }

    @discardableResult
    func importPayload(from data: Data) throws -> Int {
        let payload: InstanceExportPayload
        do {
            payload = try PropertyListDecoder().decode(InstanceExportPayload.self, from: data)
        } catch {
            throw InstanceImportError.invalidFile
        }
        // Gera novos UUIDs para evitar colisão com instâncias existentes e
        // garantir que os tokens (se vierem) sejam salvos sob uma chave nova
        // no Keychain.
        let newInstances = payload.instances.map { incoming -> DynatraceInstance in
            var copy = incoming
            copy.id = UUID()
            return copy
        }
        instances.append(contentsOf: newInstances)
        save()
        return newInstances.count
    }
}
