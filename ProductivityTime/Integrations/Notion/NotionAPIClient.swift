import Foundation

protocol NotionHTTPClient: Sendable { func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }
struct URLSessionNotionHTTPClient: NotionHTTPClient, @unchecked Sendable {
    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse else { throw DeliveryError.network }; return (data, http) }
}

actor NotionAPIClient: NotionSessionSink {
    private let credentials: any NotionCredentialStore; private let http: any NotionHTTPClient; private let baseURL: URL; private let now: @Sendable () -> Date
    init(credentials: any NotionCredentialStore = KeychainNotionCredentialStore(), http: any NotionHTTPClient = URLSessionNotionHTTPClient(), baseURL: URL = URL(string: "https://api.notion.com")!, now: @escaping @Sendable () -> Date = Date.init) { self.credentials = credentials; self.http = http; self.baseURL = baseURL; self.now = now }
    func testConnection(configuration: NotionConfiguration) async throws { _ = try await schema(configuration) }
    func deliver(_ session: CompletedSession, configuration: NotionConfiguration) async throws -> DeliveryResult {
        _ = try await schema(configuration)
        if try await sessionExists(session.id, configuration: configuration) { return .alreadyExists }
        let response = try await request(path: "/v1/pages", method: "POST", body: pageBody(session, configuration: configuration))
        guard (200..<300).contains(response.1.statusCode) else { try throwStatus(response.1) }
        return .created
    }
    private func schema(_ configuration: NotionConfiguration) async throws -> [String: Any] {
        guard !configuration.dataSourceID.isEmpty else { throw DeliveryError.configuration }
        let response = try await request(path: "/v1/data_sources/\(configuration.dataSourceID)", method: "GET", body: nil)
        guard (200..<300).contains(response.1.statusCode) else { try throwStatus(response.1) }
        guard let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any], let properties = json["properties"] as? [String: Any] else { throw DeliveryError.schema }
        for (name, type) in NotionConfiguration.expectedProperties { guard let value = properties[name] as? [String: Any], value["type"] as? String == type else { throw DeliveryError.schema } }
        return properties
    }
    private func sessionExists(_ id: UUID, configuration: NotionConfiguration) async throws -> Bool {
        let query: [String: Any] = ["filter": ["property": "Session ID", "rich_text": ["equals": id.uuidString.lowercased()]]]
        let response = try await request(path: "/v1/data_sources/\(configuration.dataSourceID)/query", method: "POST", body: query)
        guard (200..<300).contains(response.1.statusCode) else { try throwStatus(response.1) }
        guard let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any], let results = json["results"] as? [Any] else { throw DeliveryError.unknown }
        return !results.isEmpty
    }
    private func request(path: String, method: String, body: [String: Any]?) async throws -> (Data, HTTPURLResponse) {
        let token: Data
        do {
            guard let value = try credentials.readToken(), !value.isEmpty else { throw DeliveryError.configuration }
            token = value
        } catch is DeliveryError { throw DeliveryError.configuration }
        catch { throw DeliveryError.configuration }
        guard let text = String(data: token, encoding: .utf8), let url = URL(string: path, relativeTo: baseURL) else { throw DeliveryError.configuration }
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue("Bearer \(text)", forHTTPHeaderField: "Authorization"); request.setValue("2026-03-11", forHTTPHeaderField: "Notion-Version")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        do { return try await http.execute(request) } catch let error as DeliveryError { throw error } catch { throw DeliveryError.network }
    }
    private func pageBody(_ session: CompletedSession, configuration: NotionConfiguration) -> [String: Any] {
        func text(_ value: String) -> [String: Any] { ["rich_text": [["type": "text", "text": ["content": value]]]] }
        func title(_ value: String) -> [String: Any] { ["title": [["type": "text", "text": ["content": value]]]] }
        let seconds = max(0, Int(session.duration.timeInterval.rounded(.down))); let duration = String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        let iso = ISO8601DateFormatter().string(from: session.completedAt)
        return ["parent": ["type": "data_source_id", "data_source_id": configuration.dataSourceID], "properties": ["Name": title(session.titleSnapshot), "Mode": text(session.mode.rawValue), "Duration": text(duration), "Date": ["date": ["start": iso]], "Session ID": text(session.id.uuidString.lowercased())]]
    }
    private func throwStatus(_ response: HTTPURLResponse) throws -> Never {
        switch response.statusCode {
        case 401, 403: throw DeliveryError.authorization
        case 404: throw DeliveryError.configuration
        case 429, 529:
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init).map { now().addingTimeInterval($0) }
            throw DeliveryError.rateLimited(retryNotBefore: delay)
        case 500...599: throw DeliveryError.network
        default: throw DeliveryError.unknown
        }
    }
}
