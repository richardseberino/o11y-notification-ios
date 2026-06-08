//
//  Dyntrace_Problems_AppApp.swift
//  Dyntrace Problems App
//
//  Created by Richard Marques on 31/05/26.
//

import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct Dyntrace_Problems_AppApp: App {
    static let refreshTaskId = "com.dyntrace.problems.refresh"

    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskId, using: nil) { task in
            Self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                Self.scheduleAppRefresh()
            case .active:
                Task { await NotificationManager.shared.refreshAuthorizationStatus() }
            default:
                break
            }
        }
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let operation = Task { @MainActor in
            let store = InstanceStore()
            for instance in store.instances where instance.notificationsEnabled {
                if Task.isCancelled { break }
                do {
                    let aggregate = try await AlertService.fetchAll(for: instance)
                    await NotificationManager.shared.processFetchedAlerts(
                        aggregate.items, for: instance, triggerNotifications: true)
                } catch {
                    continue
                }
            }
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        task.expirationHandler = {
            operation.cancel()
        }
    }
}
