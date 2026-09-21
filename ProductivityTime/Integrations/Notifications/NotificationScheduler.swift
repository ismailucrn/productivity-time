import Foundation
import UserNotifications

struct TimerNotificationRequest: Equatable, Sendable { let identifier: String; let deadline: Date; let title: String }
protocol NotificationCenterClient: Sendable { func requestAuthorization() async throws -> Bool; func add(_ request: TimerNotificationRequest) async throws; func remove(identifiers: [String]) async }
protocol NotificationScheduling: Sendable { func requestAuthorization() async throws -> Bool; func schedule(identifier: String, at deadline: Date, title: String) async throws; func remove(identifier: String) async }
struct SystemNotificationCenterClient: NotificationCenterClient, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func add(_ request: TimerNotificationRequest) async throws { let content = UNMutableNotificationContent(); content.title = request.title; content.body = "Timer completed"; content.sound = .default; let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.deadline.timeIntervalSinceNow), repeats: false); try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)) }
    func remove(identifiers: [String]) async { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
}
struct UserNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let center: any NotificationCenterClient
    init(center: any NotificationCenterClient = SystemNotificationCenterClient()) { self.center = center }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization() }
    func schedule(identifier: String, at deadline: Date, title: String) async throws { try await center.add(TimerNotificationRequest(identifier: identifier, deadline: deadline, title: title)) }
    func remove(identifier: String) async { await center.remove(identifiers: [identifier]) }
}
