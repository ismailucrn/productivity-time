import Foundation

actor AppleNotesAdapter: NotesSessionSink {
    static let scriptSource = """
on run argv
 set noteName to item 1 of argv
 set htmlLine to item 2 of argv
 set markerText to item 3 of argv
 tell application "Notes"
  if not (exists default account) then error "unavailable"
  set accountRef to default account
  set folderRef to default folder of accountRef
  set noteRef to missing value
  repeat with candidate in notes of folderRef
   if name of candidate is noteName then set noteRef to candidate
  end repeat
  if noteRef is missing value then set noteRef to make new note at folderRef with properties {name:noteName, body:""}
  if body of noteRef contains markerText then return "already_exists"
  set body of noteRef to (body of noteRef) & "<br>" & htmlLine
 end tell
 return "created"
end run
"""
    private let runner: any AppleScriptRunning
    private let formatter: NotesLineFormatter

    init(runner: any AppleScriptRunning = OsaScriptRunner(), formatter: NotesLineFormatter = NotesLineFormatter()) { self.runner = runner; self.formatter = formatter }
    func deliver(_ session: CompletedSession, to target: NotesTarget) async throws -> DeliveryResult {
        guard !target.noteName.isEmpty else { throw DeliveryError.configuration }
        let line = formatter.format(session)
        do {
            let response = try await runner.run(AppleScriptInvocation(source: Self.scriptSource, arguments: [target.noteName, line.html, line.marker]))
            return response == "already_exists" ? .alreadyExists : .created
        } catch let error as AppleScriptRunnerError {
            switch error { case .permissionDenied: throw DeliveryError.permissionDenied; case .unavailable: throw DeliveryError.unavailable; case .failed: throw DeliveryError.unknown }
        } catch { throw DeliveryError.unknown }
    }
    func testConnection(to target: NotesTarget) async throws { guard !target.noteName.isEmpty else { throw DeliveryError.configuration } }
}

struct OsaScriptRunner: AppleScriptRunning, @unchecked Sendable {
    func run(_ invocation: AppleScriptInvocation) async throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", invocation.source, "--"] + invocation.arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { throw AppleScriptRunnerError.unavailable }
        guard process.terminationStatus == 0 else { throw AppleScriptRunnerError.failed }
        let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value
    }
}
