import Foundation

struct NotesTarget: Equatable, Sendable { let noteName: String
    init(noteName: String) { self.noteName = noteName.trimmingCharacters(in: .whitespacesAndNewlines) }
}

protocol NotesSessionSink: Sendable {
    func deliver(_ session: CompletedSession, to target: NotesTarget) async throws -> DeliveryResult
    func testConnection(to target: NotesTarget) async throws
}

struct AppleScriptInvocation: Equatable, Sendable { let source: String; let handler: String; let parameters: [String] }
protocol AppleScriptRunning: Sendable { func run(_ invocation: AppleScriptInvocation) async throws -> String }

enum AppleScriptRunnerError: Error, Sendable { case permissionDenied, unavailable, failed }
