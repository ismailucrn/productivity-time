import Foundation
import UserNotifications

protocol NotificationScheduling: Sendable { func requestAuthorization() async throws -> Bool; func schedule(identifier: String, at deadline: Date, title: String) async throws; func remove(identifier: String) }
struct UserNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func schedule(identifier: String, at deadline: Date, title: String) async throws { let content = UNMutableNotificationContent(); content.title = title; content.body = "Timer completed"; content.sound = .default; let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false); try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) }
    func remove(identifier: String) { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
}
