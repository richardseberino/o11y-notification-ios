//
//  NotificationManager.swift
//  Dyntrace Problems App
//

import Foundation
import UserNotifications
import Combine
import UIKit

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false

    private static let seenKeyPrefix = "notifications.seenProblems."

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus
        isAuthorized = (status == .authorized || status == .provisional || status == .ephemeral)
    }

    /// Atualiza o baseline de "problems vistos" para a instância e dispara
    /// notificações para IDs novos quando `instance.notificationsEnabled` está
    /// ativo e `triggerNotifications == true`. A primeira sincronização nunca
    /// dispara notificações.
    func processFetchedProblems(_ problems: [DynatraceProblem],
                                for instance: DynatraceInstance,
                                triggerNotifications: Bool) async {
        let key = Self.seenKeyPrefix + instance.id.uuidString
        let storedArray = UserDefaults.standard.stringArray(forKey: key)
        let hadBaseline = storedArray != nil
        let seenIds = Set(storedArray ?? [])
        let currentIds = Set(problems.map { $0.problemId })

        if triggerNotifications,
           instance.notificationsEnabled,
           isAuthorized,
           hadBaseline {
            let newProblems = problems.filter { !seenIds.contains($0.problemId) }
            for problem in newProblems {
                await postLocalNotification(problem: problem, instance: instance)
            }
        }

        UserDefaults.standard.set(Array(currentIds), forKey: key)
    }

    func clearSeen(for instanceId: UUID) {
        UserDefaults.standard.removeObject(forKey: Self.seenKeyPrefix + instanceId.uuidString)
    }

    private func postLocalNotification(problem: DynatraceProblem, instance: DynatraceInstance) async {
        let content = UNMutableNotificationContent()
        content.title = instance.name
        content.body = problem.title
        if !problem.affectedResource.isEmpty {
            content.subtitle = problem.affectedResource
        }
        content.sound = .default
        if let url = DynatraceAPI.problemDetailURL(instance: instance, problemId: problem.problemId) {
            content.userInfo = ["url": url.absoluteString]
        }
        let request = UNNotificationRequest(
            identifier: "problem-\(instance.id.uuidString)-\(problem.problemId)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                  willPresent notification: UNNotification,
                                  withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                  didReceive response: UNNotificationResponse,
                                  withCompletionHandler completionHandler: @escaping () -> Void) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}
