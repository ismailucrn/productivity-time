import Foundation
import XCTest
@testable import ProductivityTime

final class IntegrationAdapterTests: XCTestCase {
    func testAppleNotesUsesConstantSourceAndPassesHostileValuesAsArguments() async throws {
        let runner = RecordingScriptRunner(response: "already_exists")
        let adapter = AppleNotesAdapter(runner: runner)
        let session = makeSession(title: "\" </script> \\n 📚")
        let result = try await adapter.deliver(session, to: NotesTarget(noteName: "My <note>"))
        let invocation = await runner.invocation
        XCTAssertEqual(result, .alreadyExists)
        XCTAssertEqual(invocation?.source, AppleNotesAdapter.scriptSource)
        XCTAssertFalse(invocation?.source.contains(session.titleSnapshot) ?? true)
        XCTAssertEqual(invocation?.arguments.first, "My <note>")
        XCTAssertTrue(invocation?.arguments.dropFirst().joined().contains("PT:\(session.id.uuidString.lowercased())") ?? false)
    }

    func testNotionQueriesUUIDBeforeCreatingAndSkipsExistingPage() async throws {
        let http = RecordingHTTPClient(responses: [schemaResponse(), queryResponse(results: [["id": "page"]])])
        let client = NotionAPIClient(credentials: MemoryCredentials(token: Data("secret".utf8)), http: http)
        let result = try await client.deliver(makeSession(), configuration: NotionConfiguration(dataSourceID: "source"))
        let paths = await http.paths
        XCTAssertEqual(result, .alreadyExists)
        XCTAssertEqual(paths, ["/v1/data_sources/source", "/v1/data_sources/source/query"])
        XCTAssertFalse(paths.contains("/v1/pages"))
    }

    func testNotionCreatesOnePageAfterUUIDQueryFindsNoExistingPage() async throws {
        let http = RecordingHTTPClient(responses: [schemaResponse(), queryResponse(results: []), emptyResponse(status: 200)])
        let session = makeSession()
        let client = NotionAPIClient(credentials: MemoryCredentials(token: Data("secret".utf8)), http: http)
        _ = try await client.deliver(session, configuration: NotionConfiguration(dataSourceID: "source"))
        let captured = await http.requests
        XCTAssertEqual(captured.map { $0.url?.path }, ["/v1/data_sources/source", "/v1/data_sources/source/query", "/v1/pages"])
        let body = String(decoding: try XCTUnwrap(captured.last?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains(session.id.uuidString.lowercased()))
    }

    private func makeSession(title: String = "Writing") -> CompletedSession { CompletedSession(id: UUID(uuidString: "A0B1C2D3-E4F5-4678-9ABC-DEF012345678")!, activityID: UUID(), titleSnapshot: title, mode: .timer, duration: .seconds(60), completedAt: Date(timeIntervalSince1970: 1_704_067_200), deliveryState: .pending) }
    private func schemaResponse() -> FakeResponse { let properties = NotionConfiguration.expectedProperties.mapValues { ["type": $0] }; return jsonResponse(["properties": properties]) }
    private func queryResponse(results: [Any]) -> FakeResponse { jsonResponse(["results": results]) }
    private func jsonResponse(_ value: [String: Any]) -> FakeResponse { FakeResponse(data: try! JSONSerialization.data(withJSONObject: value), status: 200) }
    private func emptyResponse(status: Int) -> FakeResponse { FakeResponse(data: Data("{}".utf8), status: status) }
}

private actor RecordingScriptRunner: AppleScriptRunning {
    let response: String; private(set) var invocation: AppleScriptInvocation?
    init(response: String) { self.response = response }
    func run(_ invocation: AppleScriptInvocation) async throws -> String { self.invocation = invocation; return response }
}
private struct MemoryCredentials: NotionCredentialStore { let token: Data?; func readToken() throws -> Data? { token }; func writeToken(_ token: Data) throws {}; func removeToken() throws {} }
private struct FakeResponse { let data: Data; let status: Int }
private actor RecordingHTTPClient: NotionHTTPClient {
    private var responses: [FakeResponse]; private(set) var requests = [URLRequest]()
    init(responses: [FakeResponse]) { self.responses = responses }
    var paths: [String] { requests.compactMap { $0.url?.path } }
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { requests.append(request); let next = responses.removeFirst(); return (next.data, HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!) }
}
