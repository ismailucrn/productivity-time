import Cocoa

actor AppleNotesAdapter: NotesSessionSink {
    static let scriptSource = """
on appendProductivityTimeLine(noteName, htmlLine, markerText)
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
end appendProductivityTimeLine
on verifyProductivityTimeConnection(noteName)
 tell application "Notes"
  if not (exists default account) then error "unavailable"
  return "connected"
 end tell
end verifyProductivityTimeConnection
"""
    private let runner: any AppleScriptRunning
    private let formatter: NotesLineFormatter

    init(runner: any AppleScriptRunning = OsaScriptRunner(), formatter: NotesLineFormatter = NotesLineFormatter()) { self.runner = runner; self.formatter = formatter }
    func deliver(_ session: CompletedSession, to target: NotesTarget) async throws -> DeliveryResult {
        guard !target.noteName.isEmpty else { throw DeliveryError.configuration }
        let line = formatter.format(session)
        do {
            let response = try await runner.run(AppleScriptInvocation(source: Self.scriptSource, handler: "appendProductivityTimeLine", parameters: [target.noteName, line.html, line.marker]))
            return response == "already_exists" ? .alreadyExists : .created
        } catch let error as AppleScriptRunnerError {
            switch error { case .permissionDenied: throw DeliveryError.permissionDenied; case .unavailable: throw DeliveryError.notesUnavailable; case .failed: throw DeliveryError.notesUnavailable }
        } catch { throw DeliveryError.notesUnavailable }
    }
    func testConnection(to target: NotesTarget) async throws {
        guard !target.noteName.isEmpty else { throw DeliveryError.configuration }
        do { _ = try await runner.run(AppleScriptInvocation(source: Self.scriptSource, handler: "verifyProductivityTimeConnection", parameters: [target.noteName])) }
        catch let error as AppleScriptRunnerError { if case .permissionDenied = error { throw DeliveryError.permissionDenied }; throw DeliveryError.notesUnavailable }
        catch { throw DeliveryError.notesUnavailable }
    }
}

struct OsaScriptRunner: AppleScriptRunning, @unchecked Sendable {
    func run(_ invocation: AppleScriptInvocation) async throws -> String {
        guard let script = NSAppleScript(source: invocation.source) else { throw AppleScriptRunnerError.unavailable }
        let parameters = NSAppleEventDescriptor.list()
        for (index, parameter) in invocation.parameters.enumerated() { parameters.insert(NSAppleEventDescriptor(string: parameter), at: index + 1) }
        // Four-character OSA event codes: `ascr` / `psbr` / `snam` / `----`.
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(0x6173_6372), eventID: AEEventID(0x7073_6272), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: invocation.handler), forKeyword: AEKeyword(0x736E_616D))
        event.setParam(parameters, forKeyword: AEKeyword(0x2D2D_2D2D))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let number = error?[NSAppleScript.errorNumber] as? Int { if number == -1743 { throw AppleScriptRunnerError.permissionDenied }; throw AppleScriptRunnerError.failed }
        return result.stringValue ?? "created"
    }
}
