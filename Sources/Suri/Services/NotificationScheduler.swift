import Foundation
import UserNotifications

struct NotificationScheduler {
    func scheduleNotifications(for tasks: [AssistantTask], preferences: SyncPreferences) async throws {
        guard preferences.notificationsEnabled else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }

        let granted = await requestAuthorization()
        guard granted else {
            return
        }

        let candidates = tasks.filter { task in
            task.requiresUserReview || isDueSoon(task, dueSoonHours: preferences.dueSoonHours)
        }

        let identifiers = candidates.map { notificationIdentifier(for: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

        for task in candidates.prefix(20) {
            try await scheduleNotification(for: task, leadTime: preferences.notificationLeadTime)
        }
    }

    private func requestAuthorization() async -> Bool {
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            return false
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func scheduleNotification(for task: AssistantTask, leadTime: NotificationLeadTime) async throws {
        let content = UNMutableNotificationContent()
        content.title = task.requiresUserReview ? "확인이 필요합니다" : "기한이 임박했습니다"
        content.body = "\(task.title) · \(task.source.title)"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: triggerInterval(for: task, leadTime: leadTime),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: task),
            content: content,
            trigger: trigger
        )

        try await add(request)
    }

    private func triggerInterval(for task: AssistantTask, leadTime: NotificationLeadTime) -> TimeInterval {
        guard let dueDate = task.dueDate else {
            return 8
        }

        let notificationDate = dueDate.addingTimeInterval(-leadTime.hours * 60 * 60)
        return max(notificationDate.timeIntervalSinceNow, 8)
    }

    private func isDueSoon(_ task: AssistantTask, dueSoonHours: Double) -> Bool {
        guard let dueDate = task.dueDate else {
            return false
        }

        return dueDate <= Date.hoursFromNow(dueSoonHours) && task.status != .reviewed
    }

    private func notificationIdentifier(for task: AssistantTask) -> String {
        "suri.task.\(task.id.uuidString)"
    }
}
